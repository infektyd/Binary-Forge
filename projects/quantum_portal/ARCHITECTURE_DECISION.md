# Architectural Decision: The "Glass & Brain" Split (NASM + Pluggable Backend)

## Context & Constraints
- **Hardware:** 2010 MacBook Pro, Pop!_OS, 4GB RAM. System resources are tightly constrained; OOM killer is a constant threat.
- **The Application:** `quantum_portal`, a multiplexed-tab Terminal UI (TUI) meant for interfacing with AI agents (Vertex fine-tunes, Minimax, Grok, etc.).
- **The Problem:** Implementing TLS 1.3 handshakes, JSON serialization, and HTTP REST logic purely in x86_64 NASM introduces extreme bloat, security vulnerabilities (extreme technical debt), and risks blocking the UI thread during high-latency network calls.

## The Decision
We are officially decoupling the application into two distinct processes communicating via Unix Named Pipes (FIFOs). 

1. **The Glass (Frontend) -> `quantum_portal.asm`**
   - Pure, lean NASM binary (3.1KB). 
   - Responsibilities: Draw UI tabs, capture keyboard input, multiplex the screen, read/write to Unix pipes.
   - It is ignorant of the internet, JSON, or AI models. It never blocks.

2. **The Brain (Backend) -> `backends/openrouter_generic.py`**
   - A swappable, lightweight Python (or Bash/Rust/Go) daemon.
   - Responsibilities: Listen to the input pipe, manage API keys, negotiate TLS networking, parse JSON tool-calls, and execute local OS operations (`mkdir`, `sed`, `git`).
   - Translates network responses back into raw text and pipes them to the NASM frontend.

## Engineering Justifications

### 1. Separation of Concerns (Thread Safety & UI Snappiness)
If the AI API takes 8 seconds to stream a response, a monolithic NASM binary doing synchronous blocking network I/O will freeze the terminal. By separating the network logic into a Python daemon, the NASM binary remains blistering fast. The user can switch tabs, type ahead, and scroll while the Python backend waits on the internet.

### 2. Absolute Prompt Control (Preserving Vertex Fine-Tuning)
Monolith orchestrators (like OpenClaw or IDEs like Cursor) inject massive, hidden system preambles (2,000+ tokens) defining the AI's identity. If we use our $1,000 GCP Warchest to fine-tune a bespoke "Syntra" model in Vertex AI, these preambles will override the model's baked-in weights (Identity Clash). 
A custom Python backend allows us to strip the context window to the bare metal: bypassing predefined preambles and sending *only* the user's input, environment state, and tool schemas.

### 3. "Bring Your Own Brain" (BYOB) Extensibility
The "Hourglass Architecture" (Text In -> Text Out) turns this tool from a personal toy into a flexible open-source framework:
- The community can write 200MB Python backends incorporating RAG setups, vector databases, and multi-agent swarms. 
- The NASM frontend *never needs to be updated or recompiled* to support new AI models or local features, because all complexity lives in the swappable backend scripts.
- The base repository will ship with lightweight, >50-line Python REST templates (e.g., `openrouter_basic.py`) to remain lean on 4GB hardware.

## IPC (Inter-Process Communication) Implementation Plan
- **Setup:** Create `/tmp/qp_tx` and `/tmp/qp_rx`.
- **NASM:** Non-blocking `sys_read` and `sys_write` on the pipes.
- **Python:** Standard file object reading in a `while True` loop.
