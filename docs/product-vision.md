# Zimaclaw Product Vision

Zimaclaw is a single Zig binary that acts as a local orchestration service on a headless NixOS machine. It receives task prompts over XMPP, uses `emacsclient --eval` to run controlled Emacs Lisp operations for file-system and editor-aware actions, and drives the Pi coding agent over JSON-RPC (JSONL over stdin/stdout) to execute multi-step programming tasks.

The system is designed to be reproducible and recoverable: OS configuration, services, packages, and dotfiles are declared in a version-controlled Nix flake so the full environment can be rebuilt or rolled back with standard NixOS generation workflows.

## Architectural Direction (Validated)

- **Orchestrator**: Zig is the core runtime and process supervisor.
- **XMPP transport**: implemented via `libstrophe` C bindings from Zig.
- **Steer interface**: Emacs daemon controlled through `emacsclient --eval`.
- **Drive interface**: Pi RPC over newline-delimited JSON on stdin/stdout.
- **Concurrency model**: simple event loop (or `std.Thread` + queues), **not** an external actor framework.
- **Packaging/deployment**: NixOS + flake-based declarations for reproducibility.

## Reliability Constraints and Guardrails

- Emacs calls are treated as **sequential** operations (daemon is single-threaded).
- Large Emacs return payloads should use chunking or file handoff when needed.
- Pi protocol compatibility is protected by **pinning Pi to a fixed version/commit** in Nix.
- JSONL framing is strictly LF-delimited (`\n`) at the Zig boundary.
- Process-level failures (daemon missing, socket issues, hung subprocesses) are explicit error paths with timeout/restart handling.

## Outcome

Zimaclaw provides a private, reproducible, and rollback-safe coding appliance where XMPP is the ingress channel, Zig is the coordinator, Emacs is the steerable workspace interface, and Pi is the execution engine for iterative coding work.
