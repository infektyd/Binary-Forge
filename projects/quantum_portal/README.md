# Quantum Portal

A hyper-optimized, 3.1KB x86_64 raw NASM Terminal User Interface (TUI) acting as an instant "Glass" layer for AI models, backed by a modular Python daemon via UNIX pipes.

## The "Glass & Brain" Architecture

Large Language Models often suffer from "Prompt Override" when orchestrators inject thousands of tokens of invisible system preamble. To fix this, Quantum Portal physically decouples the Terminal UI from the Networking/API layer using a classic Hourglass IPC model:

1. **The Glass (`quantum_portal`):** A 3.1KB hand-crafted ELF NASM executable. It uses pure Linux syscalls (no libc). It paints the screen, captures keystrokes, and reads/writes to UNIX pipes (`/tmp/qp_tx` and `/tmp/qp_rx`).
2. **The Brain (`backends/openrouter_generic.py`):** A lightweight Python daemon that waits silently (0% CPU). When the TUI pipe fires, Python handles the TLS 1.3 handshake, routes the JSON to the AI API, appends conversation history, and pipes the raw text back.

The AI receives *exactly* what you type. Zero preamble.

## Build Requirements
- `nasm`
- Linux x86_64 (Tested on Pop!_OS)

## Quick Start

1. **Start the Brain (Terminal 1)**
```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
python3 backends/openrouter_generic.py
```
*(The daemon will create the `/tmp/qp_tx` and `/tmp/qp_rx` named pipes and wait)*

2. **Compile and Run the Glass (Terminal 2)**
```bash
nasm -f bin quantum_portal.asm -o quantum_portal
chmod +x quantum_portal
./quantum_portal
```

## Customization (Bring Your Own Brain)
Because the NASM binary uses non-blocking Unix Pipes, you can replace the Python backend with anything. You can write a Go router, a Rust daemon, or a local RAG vector-database pipeline. As long as your backend reads from `/tmp/qp_tx` and writes text to `/tmp/qp_rx`, the 3KB NASM UI will render it instantly. 

See `ARCHITECTURE_DECISION.md` for low-level IPC implementation details.
