# Portal Forge v5: The TUI Overhaul 🛰️

> **Date:** 2026-02-23
> **Objective:** Upgrade `quantum_portal` from a static, scrolling-everything layout to a resilient, scrolling-chat-only TUI with live resize capabilities and box-drawing aesthetics.

## 🛠️ Key Architectural Changes

### 1. The Scroll Engine
We moved from a simple "print and pray" approach to a structured terminal layout:
- **Header:** Rows 1–3 (Fixed). Locked-in title and separator.
- **Scroll Region:** Rows 4 to (Rows-2). Defined via `ESC[{start};{end}r`.
- **Status Bar:** Bottom 2 rows (Fixed). Displays dimensions, model, and system status.

### 2. Live Resizing (Signal Handling)
Implemented the `sys_rt_sigaction` syscall to register a handler for `SIGWINCH` (Signal 28). 
- **The Handler:** Inside the binary, the handler re-invokes `TIOCGWINSZ`, re-renders the fixed chrome (header/footer), and resets the scroll region bounds. 
- **Cursor Persistence:** Used `ESC[s` and `ESC[u` (save/restore) to ensure the user's active prompt doesn't jump during a resize event.

### 3. Environment Inheritance (The curl Fix)
Identified a critical bug: shell children launched via `fork` + `execve` were receiving a NULL environment, breaking `$HOME` resolution.
- **The Fix:** At `_start`, we now crawl the stack to find the `envp` pointer and store it in the stack frame (`OFF_ENVP`). This pointer is passed through to every shell invocation.

### 4. Interactive Command Extension
Extended the `choose_or_prompt` input loop to recognize the `m` command. This triggers a jump back to the model selection branch (`.no_saved_model`), allowing for mid-session model hot-swapping.

## 📊 Syscall Inventory (The v2 Stack)

| Syscall | Hex | Usage | Reason |
|---------|-----|-------|--------|
| `write` | 0x01 | stdout | Core TUI rendering & streaming responses |
| `read` | 0x00 | stdin | User prompt input |
| `ioctl` | 0x10 | TIOCGWINSZ | Fetch physical terminal columns/rows |
| `rt_sigaction` | 0x0d | signal handler | Registering for SIGWINCH window changes |
| `fork` | 0x39 | subprocess | Creating child for `curl` calls |
| `execve` | 0x3b | launch shell | Running bash commands for API calls |
| `wait4` | 0x3d | process sync | Waiting for shells to finish writing JSON |
| `openat` | 0x101 | file creation | Writing `/tmp/qp_req.json` for API data |

## 🏗️ Binary Snapshot (v2)
- **Size:** 6,530 bytes
- **Language:** Pure x86-64 NASM Assembly
- **Dependencies:** `curl` (via syscall fork/exec)
- **Borders:** Unicode UTF-8 (`E2 94 80` through `E2 94 9C`)

## 🚀 Usage Note
Type `m` at any time to switch models. The fixed header and footer will persist through all chat history.
