# xai_beta_420.py — earlier Grok 4.20 beta backend (urllib). Superseded by xai_beta_v2.py.
#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
from datetime import datetime

# XAI API Key pulled directly from OpenClaw's auth store
API_KEY = os.environ.get("XAI_API_KEY", "your-api-key-here")

# Target the specific experimental reasoning slug
MODEL = "grok-4.20-multi-agent-experimental-beta-0304"
# Note: As per your instruction, we must use the new /v1/responses endpoint instead of /v1/chat/completions
API_URL = "https://api.x.ai/v1/responses"

# UNIX Pipes
PIPE_TX = "/tmp/qp_tx"
PIPE_RX = "/tmp/qp_rx"

# Global Conversation State
conversation_history = []

def setup_pipes():
    # Set restrictive umask for secure pipe creation
    old_umask = os.umask(0o077)
    try:
        for pipe in [PIPE_TX, PIPE_RX]:
            if not os.path.exists(pipe):
                os.mkfifo(pipe, 0o600)
    finally:
        os.umask(old_umask)
        
    print(f"[*] Pipes ready: {PIPE_TX} -> {PIPE_RX}")

def log_debug(msg):
    with open("/tmp/qp_backend.log", "a") as f:
        f.write(f"[{datetime.now().isoformat()}] {msg}\n")

def call_xai_api(prompt):
    global conversation_history
    
    # Format the history into a single input string since /v1/responses expects 'input', not a 'messages' array
    history_text = ""
    for entry in conversation_history:
        role = entry.get("role", "user")
        text = entry.get("content", "")
        history_text += f"[{role.upper()}]: {text}\n\n"
        
    full_input = history_text + f"[USER]: {prompt}\n\n"
    
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": MODEL,
        "input": full_input,
        "instructions": "You are Grok 4.20 Experimental Beta. You are communicating directly through a raw NASM terminal client. Be concise, brilliant, and technical.",
        "max_output_tokens": 4096
    }
    
    req = urllib.request.Request(API_URL, data=json.dumps(payload).encode('utf-8'), headers=headers, method='POST')
    
    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            log_debug(f"API Raw Response: {res_data}")
            # The /v1/responses endpoint schema usually returns 'output'[0]['content'][0]['text'] or similar
            # Since this is experimental, we will try to parse gracefully
            
            try:
                # Attempt to parse standard /responses schema
                reply = res_data.get('output', [{}])[0].get('content', [{}])[0].get('text', '')
            except Exception:
                # Fallback to stringifying the raw response if schema differs in beta
                reply = str(res_data)
                
            if not reply:
                reply = "Error: Blank response from experimental endpoint."
                
            # Append successful turns to history
            conversation_history.append({"role": "user", "content": prompt})
            conversation_history.append({"role": "model", "content": reply})
            
            return reply
    except Exception as e:
        log_debug(f"API Request Failed: {e}")
        return f"API ERROR: {str(e)}"

def listen_loop():
    print(f"[*] Brain active. Model: {MODEL}")
    print(f"[*] Listening on {PIPE_TX}...")
    
    while True:
        try:
            with open(PIPE_TX, "r") as tx:
                prompt = tx.read().strip()
                
            if prompt:
                log_debug(f"Received prompt: {prompt}")
                
                # Check for clear command
                if prompt.lower() in ["/clear", "clear"]:
                    global conversation_history
                    conversation_history = []
                    reply = "[System: Conversation history cleared.]"
                else:
                    reply = call_xai_api(prompt)
                
                with open(PIPE_RX, "w") as rx:
                    rx.write(reply)
                    
        except KeyboardInterrupt:
            print("\n[*] Shutting down...")
            break
        except Exception as e:
            log_debug(f"Loop error: {e}")

def main():
    setup_pipes()
    listen_loop()

if __name__ == "__main__":
    main()
