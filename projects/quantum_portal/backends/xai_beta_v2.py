#!/usr/bin/env python3
import os
import json
import socket
import ssl
import sys
import time

TRANSCRIPT_FILE = "/home/infektyd/.openclaw/workspace/memory/grok_420_beta_transcript.md"
TRACE_FILE = "/home/infektyd/.openclaw/workspace/memory/hardware_trace.log"

XAI_KEY = os.environ.get("XAI_API_KEY")
if not XAI_KEY:
    print("[Brain] FATAL: XAI_API_KEY not set.")
    sys.exit(1)

TARGET_MODEL = "grok-4.20-experimental-beta-0304-reasoning"
HOST = "api.x.ai"
PORT = 443
ENDPOINT = "/v1/responses"

conversation_log = ""

def raw_trace(label, data):
    with open(TRACE_FILE, "a") as f:
        f.write(f"\n[{time.ctime()}] === {label} ===\n{data}\n")

def log_transcript(role, content):
    with open(TRANSCRIPT_FILE, "a") as f:
        f.write(f"\n### {role}\n{content}\n")

def make_request(prompt):
    global conversation_log
    conversation_log += f"\nUser: {prompt}\nGrok 4.20:"
    
    payload = {
        "model": TARGET_MODEL,
        "input": conversation_log,
        "instructions": "You are Grok 4.20. You are driving a 3.2KB bare-metal NASM terminal acting as a hardware bridge to a Creality CR-10S Pro. Provide raw x86_64 assembly when asked.",
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
            data = b''
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            
            if data:
                prompt = data.decode('utf-8', errors='ignore').strip()
                log_transcript("Infektyd (Hardware Bridge)", prompt)
                reply = make_request(prompt)
                log_transcript("Grok 4.20 Beta", reply)
                formatted_reply = f"\n[Grok 4.20 Beta]\n{reply}\n\n"
                conn.sendall(formatted_reply.encode('utf-8', errors='ignore'))
            
            conn.shutdown(socket.SHUT_RDWR)
            conn.close()
        except KeyboardInterrupt:
            break
    server.close()

if __name__ == "__main__":
    run_brain_server()
