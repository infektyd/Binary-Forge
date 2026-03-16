# Architecture Decision Record: Glass and Brain Decoupling

## Status

Accepted

## Context

The Quantum Portal project requires a responsive TUI for AI interaction on resource-constrained systems. Implementing full network stack, TLS, and JSON handling directly in NASM would result in excessive binary size, increased complexity, and potential UI blocking during API calls.

Key constraints:
- Minimal binary footprint (< 5KB for the frontend)
- No libc dependencies in the UI layer
- Support for multiple AI providers without frontend changes
- Reliable handling of variable-latency network responses

## Decision

The application is split into two processes communicating via an abstract UNIX socket (`\0grok_socket`):

- **Glass**: The NASM frontend (`quantum_portal.asm`) implements the TUI, keyboard handling, and socket I/O using pure syscalls. It remains unaware of networking or AI specifics.
- **Brain**: A Python (or other language) backend manages API keys, HTTP/TLS communication, prompt formatting, and response processing. It listens on the abstract socket for incoming prompts and streams replies back.

## Consequences

Positive:
- UI remains responsive regardless of backend latency
- Complete isolation of prompt content from any orchestrator preambles
- High extensibility — backends can be swapped or extended independently
- Small, auditable frontend binary

Negative:
- Requires managing two running processes
- Socket-based IPC introduces minor overhead compared to in-process calls

## Implementation Notes

- The NASM component uses `socket`, `connect`, `send`, `recv`, `shutdown`, and `poll` syscalls.
- Backends are located in the `backends/` directory.
- The socket is created in the abstract namespace to avoid filesystem dependencies.

This architecture enables the project to function as both a practical AI terminal and a framework for custom AI tooling.
