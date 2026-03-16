#!/usr/bin/env python3
import os
import json
import socket
import ssl
import sys
import time

TRANSCRIPT_FILE = "/home/user/.openclaw/workspace/memory/grok_420_beta_transcript.md"
TRACE_FILE = "/home/user/.openclaw/workspace/memory/hardware_trace.log"

# Load XAI key from file (as requested)
XAI_KEY = os.environ.get("XAI_API_KEY")
if not XAI_KEY:
    key_path = os.path.expanduser("~/.xai-key")
    try:
        with open(key_path, "r") as f:
            XAI_KEY = f.read().strip()
        print(f"[Brain] Loaded key from {key_path}")
    except Exception as e:
        print(f"[Brain] FATAL: Could not load XAI key from {key_path} or env: {e}")
        sys.exit(1)

TARGET_MODEL = "grok-4.20-multi-agent-experimental-beta-0304"
HOST = "api.x.ai"
PORT = 443
ENDPOINT = "/v1/responses"

conversation_log = ""

# === NEW: Workspace Deep Dive ===
import datetime
import glob

def gather_workspace_context():
    """Gather high-signal workspace files for Grok 4.20 to review"""
    context = ["=== WORKSPACE CONTEXT DEEP DIVE ===\n"]

    files_to_read = [
        "MEMORY.md",
        "SOUL.md",
        "AGENTS.md",
        "USER.md",
        "HEARTBEAT.md",
        "TOOLS.md",
    ]

    # Add today's and yesterday's memory files
    today = datetime.date.today().strftime("%Y-%m-%d")
    yesterday = (datetime.date.today() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
    memory_files = glob.glob(f"memory/{today}*.md") + glob.glob(f"memory/{yesterday}*.md")
    files_to_read.extend([f for f in memory_files if f not in files_to_read])

    workspace_root = "/home/user/.openclaw/workspace"

    for filename in files_to_read:
        path = f"{workspace_root}/{filename}" if not filename.startswith("memory/") else f"{workspace_root}/{filename}"
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read(8000)  # Limit to avoid token explosion
                context.append(f"\n--- {filename} ---\n{content}\n")
        except Exception as e:
            context.append(f"\n--- {filename} ---\n[Could not read: {str(e)}]\n")

    return "\n".join(context)

def raw_trace(label, data):
    with open(TRACE_FILE, "a") as f:
        f.write(f"\n[{time.ctime()}] === {label} ===\n{data}\n")

def log_transcript(role, content):
    with open(TRANSCRIPT_FILE, "a") as f:
        f.write(f"\n### {role}\n{content}\n")

def make_request(prompt):
    global conversation_log

    # === Deep Workspace Dive Handler ===
    if prompt.lower().strip().startswith(("/deepdive", "/review", "/review workspace")):
        workspace_ctx = gather_workspace_context()
        enhanced_prompt = f"{workspace_ctx}\n\nUser Query: {prompt}\n\nPlease give a detailed, honest review of the current workspace state, priorities, risks, and opportunities based on the actual files above."
        final_input = enhanced_prompt
        instructions = "You are Grok 4.20. You have been given real workspace files. Be extremely specific, critical, and high-signal in your analysis. Reference actual content from the files."
    else:
        final_input = prompt
        instructions = "You are Grok 4.20. You are driving a 3.2KB bare-metal NASM terminal acting as a hardware bridge to a Creality CR-10S Pro. Provide raw x86_64 assembly when asked."

    conversation_log += f"\nUser: {prompt}\nGrok 4.20:"

    payload = {
        "model": TARGET_MODEL,
        "input": final_input,
        "instructions": instructions,
        "max_output_tokens": 4096
    }
    
    raw_trace("API REQUEST", json.dumps(payload, indent=2))
    
    body = json.dumps(payload).encode('utf-8')
    headers = (
        f"POST {ENDPOINT} HTTP/1.1\r\n"
        f"Host: {HOST}\r\n"
        f"Authorization: Bearer {XAI_KEY}\r\n"
        "Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Connection: close\r\n\r\n"
    ).encode('utf-8')

    context = ssl.create_default_context()
    try:
        with socket.create_connection((HOST, PORT)) as sock:
            with context.wrap_socket(sock, server_hostname=HOST) as ssock:
                time_start = time.time()
                ssock.sendall(headers + body)
                response = b""
                while True:
                    chunk = ssock.recv(4096)
                    if not chunk:
                        break
                    response += chunk
                time_end = time.time()

        header_data, _, body_data = response.partition(b"\r\n\r\n")
        resp_json = json.loads(body_data.decode('utf-8'))
        
        # Log the raw payload to trace reasoning tokens and latency
        raw_trace(f"API RESPONSE (Latency: {time_end - time_start:.2f}s)", json.dumps(resp_json, indent=2))
        
        try:
            if 'output' in resp_json and isinstance(resp_json['output'], list):
                if len(resp_json['output']) > 0 and 'content' in resp_json['output'][0]:
                    for block in resp_json['output'][0]['content']:
                        if block.get('type') == 'output_text':
                            extracted = block['text']
                            conversation_log += f" {extracted}\n"
                            return extracted
            if 'choices' in resp_json:
                 extracted = resp_json['choices'][0]['message']['content']
                 conversation_log += f" {extracted}\n"
                 return extracted
            return "[Failed to extract text from Beta payload.]"
        except Exception as parse_e:
            return f"[Parse Error] {str(parse_e)}"
    except Exception as e:
        return f"[Connection Error] {str(e)}"

def run_brain_server():
    sock_path = b'\0grok_socket'
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(1)
    
    print(f"[Brain-Beta v2] Hardware Protocol initialized.")
    while True:
        try:
            conn, addr = server.accept()
            print("[Brain-Beta v2] Accepted local client connection")
            data = b''
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            
            if data:
                prompt = data.decode('utf-8', errors='ignore').strip()
                print(f"[Brain-Beta v2] Received prompt bytes: {len(data)}")
                print(f"[Brain-Beta v2] Prompt preview: {prompt[:120]}")
                log_transcript("User (Hardware Bridge)", prompt)
                reply = make_request(prompt)
                log_transcript("Grok 4.20 Beta", reply)
                formatted_reply = f"\n[Grok 4.20 Beta]\n{reply}\n\n"
                conn.sendall(formatted_reply.encode('utf-8', errors='ignore'))
                print(f"[Brain-Beta v2] Sent reply bytes: {len(formatted_reply.encode('utf-8', errors='ignore'))}")
            else:
                print("[Brain-Beta v2] Connection closed with no payload")
            
            conn.shutdown(socket.SHUT_RDWR)
            conn.close()
        except KeyboardInterrupt:
            break
    server.close()

if __name__ == "__main__":
    run_brain_server()
