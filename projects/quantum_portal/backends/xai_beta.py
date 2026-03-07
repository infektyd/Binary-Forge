# xai_beta.py — earlier Grok backend (raw TLS socket). Superseded by xai_beta_v2.py.
#!/usr/bin/env python3
import os
import json
import socket
import ssl
import sys
import errno
import time

PIPE_TX = "/tmp/qp_tx"
PIPE_RX = "/tmp/qp_rx"
TRANSCRIPT_FILE = "/home/infektyd/.openclaw/workspace/memory/grok_420_beta_transcript.md"

XAI_KEY = os.environ.get("XAI_API_KEY", "your-api-key-here")
if not XAI_KEY:
    print("[Brain] FATAL: XAI_API_KEY not set.")
    sys.exit(1)

TARGET_MODEL = "grok-4.20-experimental-beta-0304-reasoning"
HOST = "api.x.ai"
PORT = 443
ENDPOINT = "/v1/responses"

# ADDED: Manually track the conversation string in python memory
conversation_log = ""

def log_transcript(role, content):
    with open(TRANSCRIPT_FILE, "a") as f:
        f.write(f"\n### {role}\n{content}\n")

def make_request(prompt):
    global conversation_log
    
    # Append the new user prompt into the running text log
    conversation_log += f"\nUser: {prompt}\nGrok 4.20:"
    
    payload = {
        "model": TARGET_MODEL,
        "input": conversation_log,
        "instructions": "You are Grok 4.20. You are being accessed via a 3.1KB bare-metal NASM terminal (Quantum Portal). You will respond plainly and confidently to the latest query.",
        "max_output_tokens": 4096
    }
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
                ssock.sendall(headers + body)
                response = b""
                while True:
                    chunk = ssock.recv(4096)
                    if not chunk:
                        break
                    response += chunk

        header_data, _, body_data = response.partition(b"\r\n\r\n")
        
        if b"200 OK" not in header_data:
            return f"[API Error]\n{header_data.decode('utf-8', errors='ignore')}"

        resp_json = json.loads(body_data.decode('utf-8'))
        
        # Absolute final strict parse for the deeply nested 4.20 schema
        try:
            if 'output' in resp_json and isinstance(resp_json['output'], list):
                if len(resp_json['output']) > 0 and 'content' in resp_json['output'][0]:
                    content_blocks = resp_json['output'][0]['content']
                    for block in content_blocks:
                        if block.get('type') == 'output_text':
                            # Successfully extracted text
                            extracted = block['text']
                            # Append the AI's reply to the log so it remembers it next time
                            conversation_log += f" {extracted}\n"
                            return extracted
                            
            if 'choices' in resp_json:
                 extracted = resp_json['choices'][0]['message']['content']
                 conversation_log += f" {extracted}\n"
                 return extracted
                 
            return "[Failed to extract text from Beta payload, check logs.]"
            
        except Exception as parse_e:
            return f"[Parse Error] {str(parse_e)}"

    except Exception as e:
        return f"[Connection Error] {str(e)}"

def start_daemon():
    print(f"[Brain-Beta] Dialing api.x.ai...")
    print(f"[Brain-Beta] Wiretap active: Logging to {TRANSCRIPT_FILE}")
    print(f"[Brain-Beta] Waiting for NASM Glass at {PIPE_TX}...")
    
    with open(TRANSCRIPT_FILE, "a") as f:
        f.write(f"\n\n--- NEW SESSION: {time.ctime()} ---\n")

    while True:
        try:
            with open(PIPE_TX, "r") as f_in:
                user_msg = f_in.read().strip()
                if user_msg:
                    print(f"\n[Glass] {user_msg}")
                    log_transcript("Infektyd", user_msg)
                    
                    reply = make_request(user_msg)
                    log_transcript("Grok 4.20 Beta", reply)
                    
                    with open(PIPE_RX, "w") as f_out:
                        f_out.write(f"\n[Grok 4.20 Beta] {reply}\n")
                        
        except IOError as e:
            if e.errno == errno.EINTR:
                continue
            raise
        time.sleep(0.1)

if __name__ == "__main__":
    start_daemon()
