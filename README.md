# 🔨 Binary-Forge

> *Hand-forged x86-64 Linux binaries. No compiler. No libc. Just raw ELF, direct syscalls, and machine code elegance.*

---

## What Is This?

This project builds **raw ELF executables** from scratch — every byte of the ELF header, every opcode, every syscall invocation is written by hand in NASM assembly. No C runtime, no dynamic linker, no standard library. Programs are tiny (often under 500 bytes), self-contained, and talk directly to the Linux kernel.

It's a collaboration between a human and AI agents — brainstorming, iterating, and forging binaries that do real work with radical minimalism. Think Torvalds-grade efficiency meets sci-fi terminal aesthetics.

---

## Tools

### `grokdoc` — Markdown Document Generator
**509 bytes.** Takes a topic, creates a markdown file, prints an ANSI-colored preview.

```bash
# From command-line argument
./tools/grokdoc "Quantum Computing"
# → creates grok-Quantum Computing.md, prints green preview

# From stdin
echo "Linux Kernel" | ./tools/grokdoc
```

**Syscalls:** `read` → `openat` → `write` → `close` → `write` (stdout) → `exit`

---

## Projects

### `quantum_portal` — Terminal Chat Client for xAI API
**6530 bytes.** A heavy-duty terminal UI chat client featuring a custom scrolling engine, live model switching, and terminal resize awareness — all in raw assembly with zero dependencies beyond `curl`.

- **Scrolling Engine:** Fixed header and footer with a central scrolling chat region.
- **TUI Overhaul:** Unicode box-drawing character borders (`┌─┐`, `│`, `└─┘`) for a premium terminal aesthetic.
- **Adaptive Layout:** Handles `SIGWINCH` signals for live terminal resizing.
- **Feature Rich:** Fetches available models from `api.x.ai`, persists selections, supports canned prompts, and allows live model switching via the `/model` (m) command.
- **Diagnostic System:** Real-time logging to `/tmp/qp_diag.log` and error reporting via `grokdoc`.

**Requires:** `~/.xai-key` containing your xAI API key.

---

## How Binaries Are Built

Every binary follows the same forge pattern:

1. **Write NASM assembly** with embedded ELF header + program header (flat binary, `org 0x400000`)
2. **Assemble:** `nasm -f bin <name>.asm -o <name>`
3. **Make executable:** `chmod +x <name>`
4. **Test in sandbox:** `firejail --noprofile ./<name>`
5. **Inspect:** `readelf -h`, `objdump -d`, `strace`, `xxd -p`

The hex dump and binary representation are also stored alongside the source for portability — you can recreate any binary from the hex alone:

```bash
# From hex dump
xxd -r -p tools/grokdoc.hex > tools/grokdoc && chmod +x tools/grokdoc

# Python one-liner
python3 -c "
h = open('tools/grokdoc.hex').read().strip()
open('tools/grokdoc','wb').write(bytes.fromhex(h))
import os; os.chmod('tools/grokdoc', 0o755)
"
```

---

## Project Structure

```
grok-binary-collab/
├── tools/grokdoc/                  # Shipped tools (canonical sources + artifacts)
│   ├── grokdoc.asm                 # NASM source
│   └── grokdoc.hex                 # Hex dump for portable recreation
│
├── projects/quantum_portal/        # Larger standalone projects
│   ├── quantum_portal.asm          # NASM source (1740+ lines, v2 TUI)
│   ├── quantum_portal.hex          # Hex dump
│   └── snapshots/                  # Version history snapshots
│
├── archive/                        # Historical iterations & forge documents
│   ├── grokdoc/                    # Past grokdoc versions & forge docs
│   ├── portal/                     # Past portal versions & forge docs
│   └── grok/                       # Predecessor "grok" binary & Python CLI
│
├── output/                         # Generated files from tool runs (gitignored)
├── docs/                           # Documentation
├── AGENTS.md                       # Detailed codebase reference for AI agents
├── CLAUDE.md                       # Quick-start cheat sheet for Claude Code
└── README.md                       # This file
```

---

## The Forge Philosophy

**Constraints breed creativity.** Every binary in this project follows these rules:

- **User-space x86-64 Linux only** — no kernel modules, no other platforms
- **Pure machine code** — hand-crafted ELF headers, no linker scripts
- **Direct syscalls only** — `syscall` instruction, not libc wrappers
- **Minimal and complete** — every byte earns its place (<450 bytes target)
- **Efficient and elegant** — Torvalds-style: if it can be simpler, it should be

The result is programs that boot in microseconds, have zero dependencies, and fit in a tweet.

---

## Requirements

- **Linux x86-64** (native or VM)
- **NASM** — `sudo apt install nasm` / `sudo pacman -S nasm`
- **firejail** (recommended for sandboxed testing) — `sudo apt install firejail`
- **binutils** (readelf, objdump) — usually pre-installed
- For quantum_portal: **curl** and an **xAI API key** in `~/.xai-key`

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/infektyd/binary-forge.git
cd binary forge

# Build grokdoc from source
nasm -f bin tools/grokdoc/grokdoc.asm -o tools/grokdoc/grokdoc
chmod +x tools/grokdoc/grokdoc

# Run it
./tools/grokdoc/grokdoc "Hello World"
cat grok-Hello\ World.md

# Build quantum_portal
nasm -f bin projects/quantum_portal/quantum_portal.asm -o projects/quantum_portal/quantum_portal
chmod +x projects/quantum_portal/quantum_portal

# Run it (needs ~/.xai-key)
./projects/quantum_portal/quantum_portal
```

---

## Inspect a Binary

```bash
# ELF header
readelf -h tools/grokdoc/grokdoc

# Disassembly
objdump -d -b binary -m i386:x86-64 tools/grokdoc/grokdoc

# Syscall trace
strace ./tools/grokdoc/grokdoc "test"

# Raw hex view
xxd tools/grokdoc/grokdoc | head -20
```

---

## Contributing

This is an experimental forge. If you're into raw ELF hacking, tiny binaries, or systems-level art — PRs welcome. Follow the forge rules: keep it raw, keep it minimal, keep it elegant.

---

## License

MIT
