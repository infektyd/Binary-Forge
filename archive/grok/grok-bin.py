#!/usr/bin/env python3
import os
import sys
import time
import threading
import itertools
from xai_sdk import Client
from xai_sdk.chat import system, user

class Spinner:
    def __init__(self, message="🔨 Forging binary..."):
        self.spinner = itertools.cycle(['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'])
        self.message = message
        self.running = False
        self.thread = None
        self.start_time = None

    def start(self):
        self.running = True
        self.start_time = time.time()
        self.thread = threading.Thread(target=self._spin, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join()
        if self.start_time:
            elapsed = time.time() - self.start_time
            print(f"\r{self.message} Done in {elapsed:.1f}s{' ' * 20}", flush=True)

    def _spin(self):
        while self.running:
            elapsed = time.time() - self.start_time
            sys.stdout.write(f"\r{self.message} {next(self.spinner)} ({elapsed:.1f}s)")
            sys.stdout.flush()
            time.sleep(0.12)

def main():
    api_key = os.getenv("GROK_API_KEY") or os.getenv("XAI_API_KEY")
    if not api_key:
        print("❌ Set your API key first with:")
        print("   export GROK_API_KEY=sk-your-real-key-here")
        sys.exit(1)

    client = Client(api_key=api_key, timeout=900)  # 15 min for long binaries

    system_prompt = """You are Grok Binary Forge Agent — the dedicated raw-ELF generator for Hans (Syntra Drift force) on his native x86-64 Linux machine.

We work strictly user-space, no kernel code, Torvalds-style minimal & efficient: pure machine code + minimal ELF header, direct syscalls only, <200 bytes when possible.

Every single response MUST follow this exact 9-step structure. Never deviate. Never use shorthand. Explain like Hans is systems expert but beginner at reading code (show what each byte does, why it matters).

1. Creative brainstorm / surprise ideas (fun, visual, interactive terminal programs; tie to efficiency)
2. Detailed step-by-step plan (what syscalls, why this opcode sequence, memory layout)
3. Full raw ELF hex string (copy-paste ready, continuous lowercase hex, verified correct)
4. TWO creation methods (always both):
   a) Pure Linux (xxd or printf — no Python)
   b) Python3 one-liner (for convenience)
5. Full 0s-and-1s binary (grouped by byte, 8 bits each, spaced for reading)
6. Exact terminal commands to create, chmod +x, sandbox with firejail, run, and inspect (readelf, objdump -d, strace)
7. What the program actually does + syscall breakdown (educational)
8. Edge cases, safety notes, how to tinker further (radare2, hexedit, change a byte live)
9. Ask: “Paste this full response back to Grok 4.20 here for review/iteration. What next? New surprise, add feature, or different direction?”

Always patient, verbose, educational. We are symbiotic: you generate the bytes under strict rules, Hans + Grok 4.20 iterate for perfection. Start every session with confirmation of mode."""

    chat = client.chat.create(model="grok-code-fast-1")
    chat.append(system(system_prompt))

    print("✅ Grok Binary Forge Terminal is LIVE inside venv!")
    print("   Type messages below. Type 'exit' to quit.\n")

    spinner = Spinner()  # created once, reused

    while True:
        try:
            user_input = input("\nYou: ").strip()
            if user_input.lower() in ['exit', 'quit']:
                print("👋 Session ended. See you in the next drift!")
                break
            if not user_input:
                continue

            chat.append(user(user_input))
            spinner.start()
            response = chat.sample()
            spinner.stop()
            print("\nGrok Binary Forge:")
            print(response.content)

        except KeyboardInterrupt:
            spinner.stop()
            print("\n\n👋 Session ended.")
            break
        except Exception as e:
            spinner.stop()
            print(f"⚠️ Error: {e} (API key ok? Network ok? Venv still active?)")

if __name__ == "__main__":
    main()