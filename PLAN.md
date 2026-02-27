# PLAN.md - Building Quantum Portal Binary

## Overview
Build a raw ELF binary (NASM asm) for a secure, creative TUI chat tool with multi-AI support, session organization, and quantum-themed effects. Iterate until successful: No bugs, full features, lean size (<10KB).

## Architecture
- ELF header + program header (org 0x400000).
- Sections: .text for code, .data for strings/buffers, .bss for dynamics.
- Syscalls only: Socket for network, write/read for TUI, gettimeofday for timers.

## Feature Breakdown & Agents
1. **Multi-AI & Loader** (FeatureExpander): Syscall fetches with TLS, parse responses.
2. **TUI with Collapsibles** (TUIDesigner): ANSI-based, pulsing effects, sidebars for sessions/docs/canvas.
3. **Organization** (OrganizerRefiner): Monthly summaries via Grok 4.1, compress to archives/memory.
4. **Security** (SecurityAuditor): Whitelists, consents, zeroing.
5. **Coordination** (BuilderCoordinator): Merge code, test, iterate.

## Creative Touches
- Pulsing borders: Timed color alternations.
- Canvas: Interactive particle sim (random '.*' with movement).
- Summaries: Gradient text fade-ins.

## Build/Test Cycle
- Write asm sections.
- Assemble: nasm -f bin quantum_portal.asm -o quantum_portal
- Test: firejail --noprofile ./quantum_portal (strace for traces).
- Fix regressions via agent steers.

## Success
- Runs stably, features work, creative elements shine, security holds.
