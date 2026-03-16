# Quantum Portal

Quantum Portal is a 3.1KB x86_64 NASM executable providing a lightweight TUI interface for AI models. It employs a decoupled "Glass & Brain" architecture using abstract UNIX sockets for communication, ensuring zero libc dependencies in the frontend.

## Architecture

The system consists of two components:

- **Glass (`quantum_portal`)**: A hand-crafted NASM binary using only Linux syscalls. It manages the terminal UI, keyboard input, screen rendering, and bidirectional communication over an abstract UNIX socket (`\0grok_socket`).
- **Brain (Python backend)**: A pluggable daemon that handles API authentication, network requests, JSON processing, and response streaming. The backend connects to the socket and exchanges raw text with the Glass component.

This separation ensures UI responsiveness during network operations and provides complete control over prompts sent to the model.

## Features

- Zero libc frontend (pure syscalls)
- Abstract UNIX socket IPC (no filesystem artifacts)
- Modular backends for multiple AI providers (xAI, OpenRouter, etc.)
- Tabbed TUI interface
- Efficient prompt handling without injected system preambles

## Requirements

- nasm
- Linux x86_64

## Quick Start

1. Start the backend:
   ```bash
   cd /path/to/quantum_portal
   export XAI_API_KEY="xai-..."
   python3 backends/xai_beta_v2.py
   ```

2. Build and run the frontend (in another terminal):
   ```bash
   nasm -f bin quantum_portal.asm -o quantum_portal
   chmod +x quantum_portal
   ./quantum_portal
   ```

## Backend Customization

The socket-based interface allows any compatible backend (Python, Rust, Go) to be substituted. The backend must bind to the abstract socket and implement read/write handling for prompts and responses.

See `ARCHITECTURE_DECISION.md` for detailed technical specifications.
