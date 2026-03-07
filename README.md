# 🔨 Binary Forge

> *Hand-forged x86-64 Linux binaries. No compiler. No libc. Just raw ELF, direct syscalls, and machine code elegance.*

---

## What Is This?

This project builds **raw ELF executables** from scratch — every byte of the ELF header, every opcode, every syscall written by hand in NASM assembly. No C runtime. No dynamic linker. No standard library. Programs are tiny, self-contained, and talk directly to the Linux kernel.

It's a collaboration between a human and AI — brainstorming, iterating, and forging binaries that do real work with radical minimalism. The latest milestone: **an AI autonomously controlling a 3D printer through a 3.3KB NASM binary** for under $1.20 in API costs.

---

## The Stack

### `quantum_portal` — "Glass & Brain" AI Terminal (3.3KB)

A hyper-optimized TUI for interacting with AI models. The architecture is split:

- **The Glass (NASM):** A 3.3KB bare-metal UI handling screen rendering and non-blocking `sys_poll` I/O. Zero libc. Zero dependencies. Talks to backends via **AF_UNIX abstract socket** (`\0grok_socket`).
- **The Brain (Python):** A swappable backend handling TLS, JSON, API routing, and conversation history. Plug in any model.

**Why abstract sockets over FIFOs?** No filesystem races, no SIGPIPE, no mkfifo setup. The socket is created in kernel memory and disappears with the process.

**Why this architecture?** It strips all orchestrator preamble from model prompts — critical for fine-tuned and beta models that break when invisible system text is injected ahead of your input.

```bash
cd projects/quantum_portal

# Build the glass
nasm -f bin quantum_portal.asm -o quantum_portal
chmod +x quantum_portal

# Start a backend (e.g. Grok 4.20 multi-agent)
export XAI_API_KEY=your_key_here
python3 backends/xai_beta_v2.py &

# Launch
./quantum_portal
```

---

### `serial` — NASM Serial Console (11KB)

A bare-metal serial terminal for direct hardware communication. Zero libc. Built with `ld -nostdlib -static`.

Implemented syscalls: `open`, `ioctl` (TCGETS/TCSETS for raw 115200 8N1), `read`, `write`, `poll`.

Validated against a **Creality CR-10S Pro** running Marlin 1.70.1 over `/dev/ttyUSB0`. First contact returned a full M115 firmware capabilities dump.

```bash
cd projects/quantum_portal

# Build
nasm -f elf64 serial.asm -o serial.o
ld -nostdlib -static serial.o -o serial

# Use (requires dialout group membership)
./serial
```

---

### `backends/printer_brain.py` — Grok → Serial Bridge

The Python backend that connects **Grok 4.20 multi-agent** to the serial port. It:

- Serves the AF_UNIX abstract socket (`\0grok_socket`) for quantum_portal
- Forwards prompts to the Grok 4.20 `/v1/responses` API with full conversation history
- Parses `[GCODE: ...]` blocks from Grok responses and executes them over pyserial
- Returns Marlin's response back to Grok for the next turn

This is the bridge that makes **autonomous AI printer control** possible.

```bash
export XAI_API_KEY=your_key_here
python3 backends/printer_brain.py
# [Printer] Connected to /dev/ttyUSB0
# [Brain] Printer Brain online. Listening on \0grok_socket
```

---

### `backends/xai_beta_v2.py` — Grok 4.20 Backend

Grok 4.20 multi-agent backend with hardware trace logger. Logs latency, reasoning tokens, and raw JSON to `memory/hardware_trace.log` for benchmarking.

Uses `/v1/responses` endpoint (not `/v1/chat/completions` — the multi-agent model requires the responses API). Maintains full string-based conversation history across turns.

---

## Milestone: Autonomous AI Hardware Control

On March 6, 2026, Grok 4.20 multi-agent autonomously:

1. Homed a CR-10S Pro 3D printer (G28)
2. Detected and disabled bed mesh compensation (M420 S0)
3. Set PLA temperatures and waited for thermal stabilization (M190/M109)
4. Generated multi-layer G-code from a natural language description
5. Self-corrected mid-print when Z drift was detected (re-triggered G28)
6. Named and printed **"Grok's Embarrassing Singularity Maw"** — a 5-layer organic horror flower with jagged spiraling teeth petals — entirely unprompted

**Total API cost: ~$1.20.** NASM binary stable throughout. No segfaults. No socket deadlocks.

The full session log is in `memory/grok_printer_session.md`.

---

## Build Pattern

Every binary follows the same forge pattern:

```bash
# Flat binary (quantum_portal style — ELF header hand-written in ASM)
nasm -f bin <name>.asm -o <name>
chmod +x <name>

# Static ELF (serial style — standard sections, no libc)
nasm -f elf64 <name>.asm -o <name>.o
ld -nostdlib -static <name>.o -o <name>
```

Inspect:
```bash
readelf -h <binary>
objdump -d <binary>
strace ./<binary>
wc -c <binary>   # how small is it?
```

---

## The Forge Philosophy

**Constraints breed creativity.**

- **User-space x86-64 Linux only**
- **Pure machine code** — hand-crafted ELF headers, no linker scripts (for flat binaries)
- **Direct syscalls only** — `syscall` instruction, not libc wrappers
- **Minimal and complete** — every byte earns its place
- **Glass & Brain split** — NASM owns the UI, Python owns the network

The result is programs that boot in microseconds, have zero dependencies, and can drive physical hardware through a cloud AI for less than the cost of a coffee.

---

## Requirements

- Linux x86-64
- NASM (`apt install nasm`)
- Python 3 + pyserial (`pip3 install pyserial`) for printer_brain
- xAI API key with Grok 4.20 multi-agent access
- For serial: user must be in `dialout` group (`sudo usermod -aG dialout $USER`)

---

## License

MIT
