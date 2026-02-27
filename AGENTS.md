# AGENTS.md — Grok Binary Forge (Quick Reference for Antigravity)

> **Last updated:** 2026-02-23 (v2 TUI Overhaul)
> **Project owner:** infektyd (Hans)
> **Repo status:** Local only — preparing for GitHub (v2 TUI complete)

---

## 1. What This Project Is

A **raw ELF binary forge** — hand-crafted x86-64 Linux executables built at the machine-code level. No compilers, no libc, no linkers. Pure NASM assembly → flat binary → direct syscalls. The goal is minimal, elegant, Torvalds-style programs that do real work in <500 bytes.

This is a **human-AI collaboration project**. Hans iterates with **Grok** (xAI, online) for brainstorming and review, and uses **local agents** (Antigravity / opencode) for hands-on implementation, debugging, and file management. The two sides are symbiotic — Grok generates forge responses in a strict 9-step format, and local agents translate those into working code and iterate on correctness.

---

## 2. Hard Rules (Never Break These)

1. **Strictly user-space x86-64 Linux raw-ELF only.** No kernel modules. No 32-bit. No other OS.
2. **Forge-style:** minimal/complete & efficient/elegant. Pure machine code + minimal ELF header. Direct syscalls only (no libc). Target <450 bytes when possible.
3. **ELF structure:** Hand-crafted `ehdr` (64-byte ELF header) + single `phdr` (56-byte program header) + flat code + data. `org 0x400000`. Single `PT_LOAD` segment, `PF_R|PF_X` (flags=5). `filesize equ $ - ehdr`.
4. **Assembler:** NASM with `bits 64`, `org 0x400000`, `-f bin` output format. No sections (`.text`/`.data`) in the final ELF — everything is flat.
5. **Build command:** `nasm -f bin <name>.asm -o <name> && chmod +x <name>`
6. **Sandbox:** Always test with `firejail --noprofile ./<binary>`
7. **Inspect:** `readelf -h`, `objdump -d`, `strace`, `xxd -p`, `radare2 -A`

---

## 3. Project Structure

```
grok-binary-collab/
├── AGENTS.md              ← THIS FILE (codebase reference for local agents)
├── CLAUDE.md              ← Quick-start reference for Claude Code sessions
├── README.md              ← Public-facing project description (GitHub-ready)
├── .gitignore             ← Ignores build artifacts, .venv, .grok, generated .md outputs
├── .gitattributes         ← LF line endings for .asm/.hex/.md; binary blobs for ELF executables
├── .grok-model            ← Persisted model selection (used by quantum_portal)
│
├── tools/                 ← CANONICAL location for shipped tools
│   └── grokdoc/
│       ├── grokdoc            ← 509-byte raw ELF binary (gitignored)
│       ├── grokdoc.asm        ← NASM source — THE authoritative source
│       ├── grokdoc.hex        ← Continuous hex dump (gitignored)
│       └── grokdoc.bits.txt   ← Full binary representation (gitignored)
│
├── projects/              ← Larger standalone projects
│   └── quantum_portal/
│       ├── quantum_portal      ← 6530-byte raw ELF binary (v2 TUI, gitignored)
│       ├── quantum_portal.asm  ← NASM source (1740+ lines) — v2 TUI chat client
│       ├── quantum_portal.hex  ← Continuous hex dump (gitignored)
│       ├── quantum_portal.bits.txt (gitignored)
│       └── snapshots/          ← Version snapshots (gitignored)
│           ├── quantum_portal_v1        ← v1 binary snapshot
│           ├── quantum_portal_v1.asm    ← v1 source snapshot
│           ├── quantum_portal_v1_tui    ← v1 TUI binary snapshot
│           └── ...
│
├── archive/               ← Historical iterations, forge documents, dev artifacts
│   ├── grokdoc/           ← All grokdoc history
│   │   ├── grokdoc_forge_v5.md         ← Full 9-step forge document for grokdoc v5
│   │   ├── grokdoc_v5.asm              ← v5 source (has strlen_z, 172 lines)
│   │   ├── grokdoc_fixed.asm           ← Early iteration (uses sections, pop-based argc)
│   │   ├── grokdoc_pre_v5_broken.asm   ← Known-broken earlier attempt
│   │   ├── grokdoc_raw                 ← Early flat binary (no ELF header)
│   │   ├── grokdoc_v5                  ← v5 built binary
│   │   ├── grokdoc_v5.hex.txt          ← v5 hex dump
│   │   ├── grokdoc_v5.bits.txt         ← v5 binary dump
│   │   ├── grokdoc_v5.bits_wrapped.txt ← v5 binary dump (line-wrapped)
│   │   ├── grokdoc.lst                 ← NASM listing file from debug build
│   │   └── grokdoc.o                   ← NASM object file from debug build
│   │
│   ├── portal/            ← All quantum_portal history
│   │   ├── portal_forge_v3.md          ← Portal v3 forge document
│   │   ├── portal_forge_v4.md          ← Portal v4 forge document (pseudocode-style asm)
│   │   ├── portal_forge_v5_tui_overhaul.md ← Portal v5 (v2 TUI) design notes
│   │   ├── portal_flat.asm             ← Portal v4, flat binary (113 lines, no ELF header)
│   │   ├── portal_v3_binary            ← Portal v3 built binary
│   │   ├── portal.hex                  ← Portal v3 hex dump
│   │   └── portal_header.bin           ← Extracted ELF+PHDR header blob
│   │
│   ├── grok/              ← Predecessor "grok" message formatter (pre-grokdoc)
│   │   ├── grok_v0_binary              ← Original grok binary
│   │   ├── grok.asm                    ← grok source
│   │   ├── grok.hex                    ← grok hex dump
│   │   ├── grok-bin.py                 ← Python CLI client using xai_sdk
│   │   ├── grok_output.md              ← First forge output (quantum whisper portal concept)
│   │   ├── grok_new                    ← Experimental grok variant binary
│   │   ├── grok_temp.asm               ← Scratch assembly from dev iteration
│   │   └── grok-                       ← grokdoc output with empty topic (artifact)
│   │
│   ├── ehdr.bin           ← Extracted ELF header blob
│   └── phdr.bin           ← Extracted program header blob
│
├── output/                ← Generated markdown files from grokdoc runs (gitignored)
├── docs/                  ← Documentation (available for future use)
└── build/                 ← Build directory (gitignored)
```

**Key insight:** `tools/grokdoc/` and `projects/quantum_portal/` hold canonical sources. `archive/` is organized into per-tool subdirs. Nothing in `archive/` needs to be tracked for builds.

---

## 4. Current Tools & Projects

### 4.1 `grokdoc` (tools/grokdoc)
- **What:** A 509-byte raw ELF that creates a markdown file from a topic name.
- **Usage:** `./grokdoc "Linux"` → creates `grok-Linux.md`, prints green ANSI preview to stdout.
- **Also supports stdin:** `echo "Quantum Computing" | ./grokdoc`
- **Syscalls used:** `read` (stdin mode), `openat` (create file), `write` (file + stdout), `close`, `exit`
- **Stack layout:**
  - `rsp + 0x000` — stdin topic buffer (if no argv)
  - `rsp + 0x100` — filename buffer (`grok-<topic>.md`)
  - `rsp + 0x200` — markdown content buffer
  - Total stack carve: `0x700` bytes
- **String helpers:** `append_z` (copy null-terminated string, back up past NUL for chaining)
- **Key details:**
  - `r13` = pointer to topic string (argv[1] or stdin buffer)
  - `r14` = filename buffer, `r15` = markdown buffer
  - `r12` = computed markdown length (pointer arithmetic: `rdi - r15`)
  - File created with `openat(AT_FDCWD, -, O_CREAT|O_WRONLY|O_TRUNC, 0644)`
  - ANSI green: `\x1b[1;32m`, reset: `\x1b[0m\n`

### 4.2 `quantum_portal` (projects/quantum_portal/)
- **What:** A 6.5KB raw ELF — a **heavy-duty TUI chat client** for the xAI API.
- **v2 Features:**
  - **Overhauled TUI:** Fixed 3-row header, fixed 2-row status bar, and a dynamic scrolling chat region.
  - **Resilient Layout:** Uses Unicode box-drawing characters (`┌─┐`, `│`, `└─┘`) for a "database terminal" aesthetic.
  - **Live Resize:** Implemented `SIGWINCH` signal handler (signal 28) to re-render the TUI chrome on terminal resize.
  - **Interactive Commands:** Type `m` at the chat prompt to switch models mid-session.
  - **Env Inheritance:** Fixed parent-to-child environment passing (`envp` saved from entry stack) to ensure `curl` finds `~/.xai-key`.
  - **JSON Parsing:** Robust hand-written parser for both model lists and streaming chat responses.
  - **Diagnostic logging:** Full trace to `/tmp/qp_diag.log`.
- **Syscalls used:** `rt_sigaction` (resize handler), `ioctl` (TIOCGWINSZ), `fork`, `execve` (envp-aware), `wait4`, `read`, `write`, `openat`, `close`, `exit`.
- **Architectural Details:**
  - **Stack Layout:** `0xa000` bytes total. Offsets for window size, envp, and various JSON/text buffers.
  - **Cursor Safety:** Uses ANSI `ESC[s` and `ESC[u` (save/restore) extensively during TUI updates to prevent jumping.
  - **Scrolling Region:** Defined via `ESC[4;{N}r` where N = `rows - 2`.
- **Key details:**
  - `r14` points to the base of the stack frame (the primary data register).
  - Execve in `run_shell` now passes a valid `envp` pointer retrieved from the entry stack at `_start`.
- **API key:** Read from `~/.xai-key` (hex-encoded for security).
- **Temp files:** `/tmp/qp_models.json`, `/tmp/qp_req.json`, `/tmp/qp_resp.json`, `/tmp/qp_model.tmp`, `/tmp/qp_diag.log`.

---

## 5. The 9-Step Forge Format

When collaborating with Grok, every response follows this exact structure:

1. **Creative brainstorm / surprise ideas** — fun, visual, interactive terminal programs; tie to efficiency
2. **Detailed step-by-step plan** — syscalls, opcode sequence, memory layout
3. **Full raw ELF hex string** — continuous lowercase, verified correct, even length
4. **TWO creation methods:** a) Pure Linux (xxd/printf), b) Python3 one-liner
5. **Full 0s-and-1s binary** — grouped by byte, spaced
6. **Exact terminal commands** — create, chmod +x, firejail sandbox, readelf, objdump -d, strace
7. **What the program does + syscall breakdown** — educational
8. **Edge cases, safety notes, how to tinker** — radare2, hexedit, change bytes live
9. **Ask:** "Paste this full response back to Grok 4.20 here for review/iteration. What next?"

This format is for Grok's responses, not necessarily what Antigravity needs to produce. But understanding the format helps when parsing forge documents in `archive/`.

---

## 6. Dual-Agent Workflow

```
Hans (user)
  ├── Grok (xAI, online, via web/API)
  │     • Brainstorming & creative direction
  │     • Generates 9-step forge documents
  │     • Reviews hex dumps and assembly
  │     • Iterates on design
  │
  └── Antigravity / Local Agent (this agent)
        • Reads and writes files on disk
        • Builds binaries (nasm -f bin)
        • Debugs with strace/objdump/readelf
        • Manages project structure and git
        • Implements changes from forge docs
        • Provides detailed explanations
```

**Important:** Hans pastes Grok's forge output back and forth between agents. The archive contains these forge documents. When working on a tool or project, check `archive/` for the latest forge doc to understand design decisions and iteration history.

---

## 7. ELF Binary Anatomy (Reference)

Every binary in this project follows this structure:

```nasm
bits 64
org 0x400000

ehdr:                           ; 64-byte ELF header
    db 0x7f, 'E', 'L', 'F'     ; magic
    db 2, 1, 1, 0               ; class=64, data=LSB, version=1, OS/ABI=SYSV
    times 8 db 0                ; padding
    dw 2                        ; e_type = ET_EXEC
    dw 62                       ; e_machine = EM_X86_64
    dd 1                        ; e_version
    dq _start                   ; e_entry
    dq phdr - $$                ; e_phoff (always 64 = right after ehdr)
    dq 0                        ; e_shoff (no sections)
    dd 0                        ; e_flags
    dw 64                       ; e_ehsize
    dw 56                       ; e_phentsize
    dw 1                        ; e_phnum (single segment)
    dw 0, 0, 0                  ; e_shentsize, e_shnum, e_shstrndx

phdr:                           ; 56-byte program header
    dd 1                        ; p_type = PT_LOAD
    dd 5                        ; p_flags = PF_R|PF_X
    dq 0                        ; p_offset
    dq $$                       ; p_vaddr = 0x400000
    dq $$                       ; p_paddr = 0x400000
    dq filesize                 ; p_filesz
    dq filesize                 ; p_memsz
    dq 0x1000                   ; p_align

_start:                         ; code begins at offset 120 (0x78)
    ; ... your code ...

filesize equ $ - ehdr           ; total binary size
```

**Entry point** is always at `0x400078` (64 + 56 = 120 bytes of headers).

---

## 8. Common Syscall Reference (x86-64 Linux)

| Syscall     | RAX | RDI         | RSI        | RDX        | R10       |
|-------------|-----|-------------|------------|------------|-----------|
| `read`      | 0   | fd          | buf        | count      | —         |
| `write`     | 1   | fd          | buf        | count      | —         |
| `close`     | 3   | fd          | —          | —          | —         |
| `ioctl`     | 16  | fd          | request    | argp       | —         |
| `fork`      | 57  | —           | —          | —          | —         |
| `execve`    | 59  | filename    | argv       | envp       | —         |
| `exit`      | 60  | status      | —          | —          | —         |
| `wait4`     | 61  | pid         | wstatus    | options    | rusage    |
| `openat`    | 257 | dirfd (-100)| pathname   | flags      | mode      |

`openat` flags: `O_CREAT|O_WRONLY|O_TRUNC` = `0x241`, mode `0644` = `0x1a4`

---

## 9. Build & Test Cheat Sheet

```bash
# Build from source
nasm -f bin tools/grokdoc.asm -o tools/grokdoc && chmod +x tools/grokdoc

# Generate hex dump
xxd -p tools/grokdoc | tr -d '\n' > tools/grokdoc.hex

# Test (sandboxed)
firejail --noprofile ./tools/grokdoc "TestTopic"
cat grok-TestTopic.md

# Inspect
readelf -h tools/grokdoc
objdump -d -b binary -m i386:x86-64 tools/grokdoc
strace ./tools/grokdoc "TestTopic"
xxd tools/grokdoc | head -20

# Create from hex
xxd -r -p tools/grokdoc.hex > tools/grokdoc && chmod +x tools/grokdoc

# Python one-liner equivalent
python3 -c "open('tools/grokdoc','wb').write(bytes.fromhex(open('tools/grokdoc.hex').read().strip())); import os; os.chmod('tools/grokdoc',0o755)"
```

---

## 10. Git Status & Conventions

- **No `.git` directory yet** — repo is being prepared for first `git init` + push to GitHub.
- `.gitignore` covers: `.venv/`, `.grok/`, `.grok-model`, `build/`, `snapshots/`, `tools/grokdoc/grokdoc`, `tools/grokdoc/grokdoc.hex`, `tools/grokdoc/grokdoc.bits.txt`, `projects/quantum_portal/quantum_portal`, `projects/quantum_portal/quantum_portal.hex`, `projects/quantum_portal/quantum_portal.bits.txt`, `output/grok-*.md`, `*.log`, `*.tmp`, OS noise.
- `.gitattributes` enforces LF for `.asm`/`.hex`/`.md`, marks ELF binaries as `binary`.
- **What gets tracked:** `.asm` sources, forge docs (`.md` in archive), AGENTS.md, CLAUDE.md, README.md, project structure, `.gitignore`, `.gitattributes`.
- **What doesn't get tracked:** Built binaries, hex dumps, bit dumps, output markdown, venv, local tooling state.

---

## 11. Key Files to Check First

When starting a new session or picking up work:

| What you need                     | Where to look                              |
|-----------------------------------|--------------------------------------------|
| Current grokdoc source            | `tools/grokdoc/grokdoc.asm`                |
| Current quantum_portal source     | `projects/quantum_portal/quantum_portal.asm` |
| Project rules & this reference    | `AGENTS.md` (this file)                    |
| Quick-start / cheat sheet         | `CLAUDE.md`                                |
| Latest grokdoc forge doc          | `archive/grokdoc/grokdoc_forge_v5.md`      |
| Latest portal forge doc           | `archive/portal/portal_forge_v5_tui_overhaul.md` |
| Python CLI client (archived)      | `archive/grok/grok-bin.py`                 |
| Earlier broken/fixed iterations   | `archive/grokdoc/grokdoc_fixed.asm`, `archive/grokdoc/grokdoc_pre_v5_broken.asm` |
| Generated output examples         | `output/grok-*.md`                         |

---

## 12. Naming Conventions

- **Tools:** lowercase, no extension for binaries. Source is `<name>.asm`, hex is `<name>.hex`.
- **Output files:** `grok-<Topic>.md` (generated by grokdoc, topic can have spaces).
- **Forge docs:** `<tool>_forge_v<N>.md` in archive.
- **Versions:** Tracked informally in forge doc names (v3, v4, v5). The current grokdoc in `tools/` evolved from v5 with a bug fix (the `inc rdi` after `append_z` was removed in favor of pointer arithmetic for length calc).

---

## 13. Evolution Notes

The grokdoc source has gone through several iterations:
1. **Early attempts** (`archive/grokdoc_fixed.asm`) — used `.text`/`.data` sections, `pop`-based argc parsing, hardcoded write length of 50 bytes.
2. **Portal v4** (`archive/portal_forge_v4.md`) — pseudocode-ish, didn't have proper ELF header embedded, used `mov rsi, label` (absolute addressing, not `lea rsi, [rel ...]`).
3. **v5** (`archive/grokdoc_v5.asm`) — proper flat binary with embedded ELF header, RIP-relative addressing, `strlen_z` for length calculation, `inc rdi` after `append_z`.
4. **Current** (`tools/grokdoc.asm`) — cleaned up from v5: removed `strlen_z` dependency for markdown length (uses `r12 = rdi - r15` pointer arithmetic instead), moved `sub rsp, 0x700` before the branch, reordered argv/stdin logic.

Quantum Portal evolved from the simple "grok" message formatter → portal v3/v4 → full TUI chat client with API integration, model selection, JSON parsing, and diagnostic logging.
