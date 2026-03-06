import os
import json
import urllib.request
import time

# IPC Pipes: NASM uses these to talk to this Python Daemon
# TX = Transmit (from NASM to Python), RX = Receive (from Python to NASM)
PIPE_TX = "/tmp/qp_tx" 
PIPE_RX = "/tmp/qp_rx" 

# Hardcoded OpenRouter API Key for testing
API_KEY = os.environ.get("OPENROUTER_API_KEY", "your-api-key-here")
MODEL = "x-ai/grok-4.1-fast" # Using Grok by default for fast, cheap testing

def setup_pipes():
    # Set restrictive umask for secure pipe creation
    old_umask = os.umask(0o077)
    try:
        for pipe in [PIPE_TX, PIPE_RX]:
            if not os.path.exists(pipe):
                os.mkfifo(pipe, 0o600)
    finally:
        os.umask(old_umask)

# Global Conversation History State
conversation_history = []

def query_llm(prompt):
    global conversation_history
    
    url = "https://openrouter.ai/api/v1/chat/completions"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/yourusername/quantum_portal",
        "X-Title": "Quantum Portal"
    }
    
    # Append new user prompt to history
    conversation_history.append({"role": "user", "content": prompt})
    
    # Notice: ZERO preamble. Just the raw history going to the model.
    data = {
        "model": MODEL,
        "messages": conversation_history
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req) as response:
            res = json.loads(response.read().decode('utf-8'))
            return res['choices'][0]['message']['content']
    except Exception as e:
        return f"API ERROR: {str(e)}"

def main():
    if API_KEY == "your-api-key-here" or not API_KEY:
        print("[!] ERROR: OPENROUTER_API_KEY environment variable not set.")
        print("    Run: export OPENROUTER_API_KEY='sk-...'")
        return
        
    setup_pipes()
    print(f"[*] Quantum Portal Backend ticking. Listening on {PIPE_TX}...")
    
    while True:
        # Opening a FIFO for reading in Python blocks until a writer connects.
        # This means 0% CPU usage while waiting for you to type in the NASM UI.
        with open(PIPE_TX, 'r') as rx_pipe:
            data = rx_pipe.read().strip()
            
        if data:
            if data.lower() in ['exit', 'quit']:
                print("[*] Shutting down backend.")
                break
                
            print(f"[>] Input received: {data[:50]}...")
            response = query_llm(data)
            
            # Append AI response to history so it remembers what it said
            conversation_history.append({"role": "assistant", "content": response})
            
            # Write the API response back to the NASM UI
            with open(PIPE_RX, 'w') as tx_pipe:
                tx_pipe.write(response + "\n\0")
            print("[<] Response sent to NASM.")

if __name__ == "__main__":
    main()
