# 🔨 Grok Binary Forge

> *Hand-forged x86-64 Linux binaries. No compiler. No libc. Just raw ELF, direct syscalls, and machine code elegance.*

---

## What Is This?

This project builds **raw ELF executables** from scratch — every byte of the ELF header, every opcode, every syscall invocation is written by hand in NASM assembly. No C runtime, no dynamic linker, no standard library. Programs are tiny (often under 500 bytes), self-contained, and talk directly to the Linux kernel.

It's a collaboration between a human and AI agents — brainstorming, iterating, and forging binaries that do real work with radical minimalism. Think Torvalds-grade efficiency meets sci-fi terminal aesthetics.

---

## The Binaries

### `quantum_portal` — Terminal Chat Client for xAI API
**6530 bytes.** A heavy-duty terminal UI chat client featuring a custom scrolling engine, live model switching, and terminal resize awareness — all in raw assembly with zero dependencies beyond `curl`.

- **Scrolling Engine:** Fixed header and footer with a central scrolling chat region.
- **TUI Overhaul:** Unicode box-drawing character borders (`┌─┐`, `│`, `└─┘`) for a premium terminal aesthetic.
- **Adaptive Layout:** Handles `SIGWINCH` signals for live terminal resizing.
- **Feature Rich:** Fetches available models from `api.x.ai`, persists selections, supports canned prompts, and allows live model switching via the `/model` (m) command.
- **Diagnostic System:** Real-time logging to `/tmp/qp_diag.log` and error reporting via `grokdoc`.

**Requires:** `~/.xai-key` containing your xAI API key.

### `grokdoc` — Markdown Document Generator
**509 bytes.** Takes a topic, creates a markdown file, prints an ANSI-colored preview.

```bash
# From command-line argument
./tools/grokdoc/grokdoc "Quantum Computing"
# → creates grok-Quantum Computing.md, prints green preview

# From stdin
echo "Linux Kernel" | ./tools/grokdoc/grokdoc
```

**Syscalls:** `read` → `openat` → `write` → `close` → `write` (stdout) → `exit`

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
xxd -r -p tools/grokdoc/grokdoc.hex > tools/grokdoc/grokdoc && chmod +x tools/grokdoc/grokdoc

# Python one-liner
python3 -c "
h = open('tools/grokdoc/grokdoc.hex').read().strip()
open('tools/grokdoc/grokdoc','wb').write(bytes.fromhex(h))
import os; os.chmod('tools/grokdoc/grokdoc', 0o755)
"
```

---

## The Forge Philosophy

**Constraints breed creativity.** Every binary in this project follows these rules:

- **User-space x86-64 Linux only** — no kernel modules, no other platforms
- **Pure machine code** — hand-crafted ELF headers, no linker scripts
- **Direct syscalls only** — `syscall` instruction, not libc wrappers
- **Minimal and complete** — every byte earns its place (<450 bytes target for simple tools)
- **Efficient and elegant** — Torvalds-style: if it can be simpler, it should be

The result is programs that boot in microseconds, have zero dependencies, and fit in a tweet.

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/infektyd/Binary-Forge.git
cd Binary-Forge

# Setup your API key
echo "your_xai_api_key_here" > ~/.xai-key

# Build quantum_portal
cd projects/quantum_portal
nasm -f bin quantum_portal.asm -o quantum_portal
chmod +x quantum_portal

# Run the TUI
./quantum_portal
```

---

## License

MIT
