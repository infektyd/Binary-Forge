# CLAUDE.md — Grok Binary Forge

This is the reference file for Claude Code (and other local AI agents) working in this repo.

## Project Overview

Hand-crafted x86-64 Linux raw ELF binaries. No compiler, no libc, no linker. Pure NASM assembly → flat binary → direct syscalls. Target size: <450 bytes per tool.

This is a dual-agent collaboration project: **Grok** (xAI, online) handles brainstorming and 9-step forge documents; **local agents** (Claude Code, opencode/Antigravity) handle implementation, debugging, and file management.

---

## Hard Rules — Never Break These

1. **x86-64 Linux user-space only.** No kernel modules, no 32-bit, no other OS.
2. **Flat binary format** — `nasm -f bin`, `bits 64`, `org 0x400000`. No `.text`/`.data` sections.
3. **Embedded ELF structure** — 64-byte `ehdr` + 56-byte `phdr` + flat code. Single `PT_LOAD` segment, `PF_R|PF_X` (flags=5).
4. **Direct syscalls only** — `syscall` instruction. No libc wrappers.
5. **RIP-relative addressing** — always `lea rsi, [rel label]`, never `mov rsi, label`.
6. **Build command:** `nasm -f bin <name>.asm -o <name> && chmod +x <name>`
7. **Test in sandbox:** `firejail --noprofile ./<binary>`
8. **Inspect with:** `readelf -h`, `objdump -d -b binary -m i386:x86-64`, `strace`, `xxd`

---

## Project Structure

```
grok-binary-collab/
├── CLAUDE.md                          ← This file
├── AGENTS.md                          ← Full reference (read for deep context)
├── README.md                          ← Public-facing description
├── tools/grokdoc/
│   ├── grokdoc                        ← 509-byte ELF binary (gitignored)
│   ├── grokdoc.asm                    ← CANONICAL NASM source
│   └── grokdoc.hex                    ← Hex dump (gitignored)
├── projects/quantum_portal/
│   ├── quantum_portal                 ← 6530-byte ELF binary, v2 TUI (gitignored)
│   ├── quantum_portal.asm             ← CANONICAL NASM source (1740+ lines)
│   ├── quantum_portal.hex             ← Hex dump (gitignored)
│   └── snapshots/                     ← Version snapshots (gitignored)
├── archive/
│   ├── grokdoc/                       ← grokdoc history (forge docs, old sources, binaries)
│   ├── portal/                        ← portal history (forge docs, old sources, binaries)
│   ├── grok/                          ← Predecessor "grok" binary + Python CLI
│   ├── ehdr.bin                       ← ELF header blob
│   └── phdr.bin                       ← Program header blob
├── output/                            ← Generated .md files from grokdoc runs (gitignored)
├── docs/                              ← Currently empty
└── build/                             ← Build artifacts (gitignored)
```

**Key:** `tools/grokdoc/` and `projects/quantum_portal/` hold canonical sources. `archive/` is organized by tool.

---

## Current Tools

### `grokdoc` (`tools/grokdoc.asm`)
509-byte ELF. Takes a topic string (argv[1] or stdin), creates `grok-<topic>.md`, prints ANSI green preview.

- Register conventions: `r13`=topic ptr, `r14`=filename buf, `r15`=markdown buf, `r12`=markdown length
- Stack carve: `sub rsp, 0x700` (0x000=stdin buf, 0x100=filename buf, 0x200=markdown buf)
- String helper: `append_z` (copies null-terminated string, backs up past NUL for chaining)
- Length calc: pointer arithmetic `r12 = rdi - r15` (no separate strlen)
- File create: `openat(AT_FDCWD, path, O_CREAT|O_WRONLY|O_TRUNC, 0644)` — flags=`0x241`, mode=`0x1a4`

### `quantum_portal` (`projects/quantum_portal/quantum_portal.asm`)
6530-byte ELF. Full TUI chat client for xAI API. Requires `~/.xai-key` and `curl`.

- v2 features: 3-row fixed header, 2-row status bar, dynamic scrolling chat region, live resize via `SIGWINCH`, model switching with `m`
- Primary data register: `r14` (points to base of stack frame)
- Stack: `0xa000` bytes total
- Temp files: `/tmp/qp_*.json`, `/tmp/qp_diag.log`
- Calls `curl` via `fork`+`execve` with inherited `envp` from entry stack

---

## ELF Header Template

```nasm
bits 64
org 0x400000

ehdr:
    db 0x7f, 'E', 'L', 'F', 2, 1, 1, 0
    times 8 db 0
    dw 2, 62                ; ET_EXEC, EM_X86_64
    dd 1                    ; e_version
    dq _start               ; e_entry
    dq phdr - $$            ; e_phoff = 64
    dq 0                    ; e_shoff
    dd 0                    ; e_flags
    dw 64, 56, 1, 0, 0, 0   ; ehsize, phentsize, phnum, shentsize, shnum, shstrndx

phdr:
    dd 1, 5                 ; PT_LOAD, PF_R|PF_X
    dq 0, $$, $$            ; offset, vaddr, paddr
    dq filesize, filesize   ; filesz, memsz
    dq 0x1000               ; align

_start:                     ; entry at 0x400078
    ; ... code ...

filesize equ $ - ehdr
```

---

## Syscall Quick Reference

| Syscall   | RAX | RDI          | RSI      | RDX   | R10    |
|-----------|-----|--------------|----------|-------|--------|
| read      | 0   | fd           | buf      | count | —      |
| write     | 1   | fd           | buf      | count | —      |
| close     | 3   | fd           | —        | —     | —      |
| ioctl     | 16  | fd           | request  | argp  | —      |
| fork      | 57  | —            | —        | —     | —      |
| execve    | 59  | filename     | argv     | envp  | —      |
| exit      | 60  | status       | —        | —     | —      |
| wait4     | 61  | pid          | wstatus  | opts  | rusage |
| openat    | 257 | dirfd (-100) | pathname | flags | mode   |

`openat` flags for create: `O_CREAT|O_WRONLY|O_TRUNC` = `0x241`, mode `0644` = `0x1a4`

---

## Build & Inspect Cheat Sheet

```bash
# Build
nasm -f bin tools/grokdoc.asm -o tools/grokdoc && chmod +x tools/grokdoc

# Test (sandboxed)
firejail --noprofile ./tools/grokdoc "TestTopic"

# Inspect
readelf -h tools/grokdoc
objdump -d -b binary -m i386:x86-64 tools/grokdoc
strace ./tools/grokdoc "TestTopic"
xxd tools/grokdoc | head -20

# Recreate from hex
xxd -r -p tools/grokdoc.hex > tools/grokdoc && chmod +x tools/grokdoc

# Generate hex dump
xxd -p tools/grokdoc | tr -d '\n' > tools/grokdoc.hex
```

---

## Dual-Agent Workflow

- **Grok** (online, xAI): brainstorming, 9-step forge documents, hex review
- **Claude Code / Antigravity** (local): file I/O, builds, debugging, implementing forge docs

When picking up a task, check `archive/` for the latest forge document (e.g. `portal_forge_v4.md`) to understand design decisions. Hans pastes forge output between agents.

---

## Git Notes

- No `.git` yet — preparing for first `git init` + GitHub push
- **Tracked:** `.asm` sources, forge docs, AGENTS.md, README.md, CLAUDE.md, `.gitignore`, `.gitattributes`
- **Not tracked:** built binaries, hex/bits dumps, output markdown, `.venv`, snapshots, logs

---

## Common Pitfalls

- Always use `lea rsi, [rel label]` not `mov rsi, label` (position-independent)
- No `.text`/`.data` sections — flat binary only
- `sub rsp, N` before any branching that uses the stack
- After `append_z`, the pointer sits one byte past the NUL — use pointer arithmetic for length, don't call strlen separately
- `openat` uses `AT_FDCWD` = `-100` (0xFFFFFFFFFFFFFF9C) in `rdi`
