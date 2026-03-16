#!/usr/bin/env python3
"""
printer_brain.py — Grok 4.20 controls a Creality CR-10S Pro via Marlin serial.

Architecture:
  quantum_portal (NASM Glass) ←→ \0grok_socket (AF_UNIX) ←→ printer_brain.py
                                                                    ↕
                                                          api.x.ai (Grok 4.20)
                                                                    ↕
                                                          /dev/ttyUSB0 (Marlin)

Grok receives:
  - User prompt
  - Live printer state (temps, position, last response)
  - Tool calls: send_gcode(cmd), read_response(), get_temps()

Grok responds with natural language + optional [GCODE: <cmd>] blocks which
this brain extracts and executes automatically.
"""
import os, json, ssl, socket, time, serial as pyserial, re, threading

XAI_KEY   = os.environ.get("XAI_API_KEY")
MODEL     = "grok-4.20-experimental-beta-0304-reasoning"
URL_HOST  = "api.x.ai"
URL_PATH  = "/v1/responses"
SERIAL_PORT = "/dev/ttyUSB0"
BAUD      = 115200
TRANSCRIPT = "/home/user/.openclaw/workspace/memory/grok_printer_session.md"

if not XAI_KEY:
    raise SystemExit("FATAL: XAI_API_KEY not set")

# ── Printer serial ──────────────────────────────────────────────────────────

printer = None
printer_lock = threading.Lock()

def open_printer():
    global printer
    printer = pyserial.Serial(SERIAL_PORT, BAUD, timeout=3)
    time.sleep(2)  # wait for Marlin reset after DTR toggle
    # flush boot chatter
    printer.read_all()
    print(f"[Printer] Connected to {SERIAL_PORT}")

def send_gcode(cmd: str) -> str:
    """Send a G-code command, return full response up to 'ok'."""
    with printer_lock:
        cmd = cmd.strip()
        if not cmd.endswith('\n'):
            cmd += '\n'
        printer.write(cmd.encode())
        printer.flush()
        lines = []
        while True:
            line = printer.readline().decode('utf-8', errors='ignore').strip()
            if line:
                lines.append(line)
            if 'ok' in line or not line:
                break
        return '\n'.join(lines)

def get_temps() -> str:
    return send_gcode("M105")

# ── Grok API ────────────────────────────────────────────────────────────────

conversation_log = ""

SYSTEM = (
    "You are Grok 4.20, a hardware-aware AI familiar controlling a Creality CR-10S Pro "
    "3D printer via Marlin firmware over serial. You have direct printer control.\n\n"
    "To send a G-code command to the printer, include it in your response as:\n"
    "  [GCODE: M105]\n"
    "or multiple:\n"
    "  [GCODE: G28]\n"
    "  [GCODE: G29]\n\n"
    "The brain will execute each [GCODE: ...] block automatically and append the printer's "
    "raw response to your next turn so you can reason about the results.\n\n"
    "Current printer: Marlin 1.70.1, CR-10S Pro, caps: AUTOREPORT_TEMP, AUTOLEVEL, Z_PROBE.\n"
    "Be decisive. You are the operator. No disclaimers."
)

def ask_grok(user_prompt: str, printer_feedback: str = "") -> str:
    global conversation_log

    if printer_feedback:
        conversation_log += f"\n[Printer feedback from last commands]\n{printer_feedback}\n"

    conversation_log += f"\nUser: {user_prompt}\nGrok 4.20:"

    payload = {
        "model": MODEL,
        "input": conversation_log,
        "instructions": SYSTEM,
        "max_output_tokens": 2048,
    }

    body = json.dumps(payload).encode()
    headers = (
        f"POST {URL_PATH} HTTP/1.1\r\n"
        f"Host: {URL_HOST}\r\n"
        f"Authorization: Bearer {XAI_KEY}\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        "User-Agent: Mozilla/5.0 (X11; Linux x86_64)\r\n"
        "Connection: close\r\n\r\n"
    ).encode()

    ctx = ssl.create_default_context()
    with socket.create_connection((URL_HOST, 443)) as sock:
        with ctx.wrap_socket(sock, server_hostname=URL_HOST) as s:
            s.sendall(headers + body)
            resp = b""
            while True:
                chunk = s.recv(8192)
                if not chunk: break
                resp += chunk

    _, _, body_raw = resp.partition(b"\r\n\r\n")
    data = json.loads(body_raw)

    text = "[no response]"
    for block in data.get("output", []):
        for c in block.get("content", []):
            if c.get("type") == "output_text":
                text = c["text"]
                break

    conversation_log += f" {text}\n"

    # Log to transcript
    with open(TRANSCRIPT, "a") as f:
        f.write(f"\n### User\n{user_prompt}\n")
        if printer_feedback:
            f.write(f"\n### Printer Feedback\n{printer_feedback}\n")
        f.write(f"\n### Grok 4.20\n{text}\n")

    return text

def extract_and_run_gcodes(reply: str) -> str:
    """Extract [GCODE: ...] blocks from reply, execute them, return combined output."""
    pattern = re.compile(r'\[GCODE:\s*([^\]]+)\]', re.IGNORECASE)
    cmds = pattern.findall(reply)
    if not cmds:
        return ""
    results = []
    for cmd in cmds:
        cmd = cmd.strip()
        print(f"[Printer ←] {cmd}")
        resp = send_gcode(cmd)
        print(f"[Printer →] {resp}")
        results.append(f"{cmd} → {resp}")
    return '\n'.join(results)

# ── Socket server (AF_UNIX abstract \0grok_socket) ──────────────────────────

def run_server():
    sock_path = b'\0grok_socket'
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(1)
    print(f"[Brain] Printer Brain online. Listening on \\0grok_socket")
    print(f"[Brain] Printer: {SERIAL_PORT} @ {BAUD} baud")

    while True:
        conn, _ = server.accept()
        conn.settimeout(1.0)   # don't wait forever for NASM to close write side
        data = b''
        while True:
            try:
                chunk = conn.recv(4096)
                if not chunk: break
                data += chunk
            except socket.timeout:
                break  # NASM sent data but kept socket open; process what we have

        prompt = data.decode('utf-8', errors='ignore').strip()
        if not prompt:
            conn.close()
            continue

        print(f"[User] {prompt}")

        # First pass: ask Grok
        reply = ask_grok(prompt)
        print(f"[Grok] {reply[:200]}...")

        # Execute any G-code Grok emitted
        printer_fb = extract_and_run_gcodes(reply)

        # If Grok ran commands, give it the results for a follow-up synthesis
        if printer_fb:
            synthesis = ask_grok("Here are the printer results. Summarize status for the user.", printer_fb)
            final_reply = f"{reply}\n\n[Printer executed:]\n{printer_fb}\n\n[Grok analysis:]\n{synthesis}"
        else:
            final_reply = reply

        out = f"\n[Grok 4.20 + Printer]\n{final_reply}\n\n"
        conn.sendall(out.encode('utf-8', errors='ignore'))
        conn.shutdown(socket.SHUT_RDWR)
        conn.close()

    server.close()

if __name__ == "__main__":
    try:
        import serial as pyserial
    except ImportError:
        raise SystemExit("Run: pip3 install pyserial")

    open_printer()
    run_server()
