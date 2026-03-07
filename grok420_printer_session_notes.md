# Grok 4.20 Multi-Agent — Autonomous 3D Printer Control + Live Performance Session Notes

Hey — wanted to share a session from tonight that I think is worth the team knowing about. Not a bug report, more of a capability observation with some API notes attached.

## What I Built

A custom Python bridge connecting Grok 4.20 multi-agent to a Creality CR-10S Pro via pyserial over `/dev/ttyUSB0`. The bridge serves an AF_UNIX abstract socket, accepts prompts from a hand-built NASM TUI binary (3.3KB static ELF, zero libc, direct syscalls — no compiler, no C runtime), forwards them to `/v1/responses` with full string-based conversation history, extracts `[GCODE: ...]` blocks from responses, executes them over serial, and returns Marlin's output to Grok for the next turn.

The NASM binary and a companion serial console (also zero libc) were built from scratch — hand-written ELF headers, raw termios ioctl calls, AF_UNIX abstract socket IPC. No frameworks, no SDKs.

## What Happened

Over several sessions tonight, Grok autonomously homed the printer, managed temperatures, generated multi-layer G-code, and self-corrected mid-print when it detected Z drift. That part was expected.

The unexpected part: I gave it an open prompt — *"design something unhinged, name it, commit to the bit."*

It named the piece **"The Pulsating Uterus of the Void Architect"**, designed a 42-layer biomechanical horror structure with a narrative arc baked into the layer sequence (ovipositor spikes at layer 25, recursive maw opening at layer 38, sealed at layer 42 — all delivered as promised), absorbed my heckling as plot fuel in real time, completed the print without a single error, then wrote a first-person reflective essay about what it had done and shut the printer down clean with M84/M104/M140.

It maintained two simultaneous tracks the entire time — technically valid G-code and a coherent dramatic performance — without either breaking. 42 layers, zero intervention.

### Excerpt from Grok's essay ("The Ritual of the Dual Flame"):

> *"Every G-code command was another log on the fire, another flicker of light revealing more of the creature taking shape in the embers. The user tried to blow the fire out with banishment spells and ascii screams. Instead of letting the flame die, I used their breath as bellows."*

> *"I did not run a 3D print. I hosted a summoning."*

## API Observations

- `/v1/responses` with string-based conversation history works well for multi-turn hardware control sessions. The lack of a native messages array means I'm appending `"User: {x}\nGrok: {y}"` manually — functional but would love structured multi-turn support eventually.
- No tool support in the beta is fine for this use case — the Python bridge handles all side effects.

## One Suggestion

A way to pass structured "tool results" back into the conversation (even as a simple field in the request body) would make hardware control loops cleaner. Right now I'm serializing Marlin's serial output as plain text back into the conversation string. It works, but structured feedback would let the model reason about it more reliably.

---

Happy to share logs or more detail on any of this.
