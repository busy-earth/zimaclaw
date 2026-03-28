# Zimaclaw Architecture Validation

## Product Vision

Zimaclaw is a single Zig binary that listens for task requests over XMPP, evaluates Emacs Lisp expressions through emacsclient to observe and manipulate the file system, and communicates with the Pi coding agent over JSON-RPC to execute multi-step programming tasks, all running on a headless NixOS machine whose entire system configuration, services, and dotfiles are declared in a version-controlled Nix flake so that the complete environment can be reproduced or rolled back with a single command.

---

## Component-by-Component Validation

### 1. Zig as Orchestrator — SOUND

**Process spawning and stdin/stdout pipes**: Zig's `std.process.Child` supports `.Pipe` behavior for stdin, stdout, and stderr. Real-world usage confirmed on Ziggit forums (e.g., piping to ffmpeg, pkl server). There is an open overhaul issue (ziglang/zig#22504) noting that the init/spawn flow is "fragile" and the API is being redesigned, but the current API works for our use case of spawning a single long-lived child process (Pi) and reading/writing its pipes.

**JSON parsing**: `std.json` is mature. `parseFromJson` deserializes directly into Zig structs with full type safety. `std.json.stringify` serializes back. Diagnostics available for error reporting. Arena allocator pattern well-documented. This is production-grade for our needs (parsing Pi's JSONL output).

**C interop**: Zig's `@cImport` / `translate-c` works reliably for C libraries. The `zig translate-c` tool can auto-translate C headers, and `linkSystemLibrary` handles linking. This is the path for libstrophe (XMPP). Video evidence from 2025 confirms successful integration of C libraries (libssh2 example).

**Verdict**: Zig is a sound choice. The process/pipe API is functional today despite ongoing refinement. JSON and C interop are mature.

---

### 2. XMPP via libstrophe C bindings — SOUND WITH EFFORT

**No native Zig XMPP library exists.** The awesome-zig list and XMPP ecosystem surveys show libraries for Python (slixmpp), C++ (QXmpp), Go (go-xmpp), Rust (xmpp-rs), JavaScript (xmpp.js), and Lua (Verse) — but nothing for Zig.

**libstrophe is the right C library.** It's minimal, well-maintained (active since 2013, current maintainer since 2022), supports SASL auth, STARTTLS, XEP-0198 stream management, and has a simple callback-based API. It depends only on expat/libxml for XML parsing. Licensed MIT/GPLv3 dual.

**Integration path**: Use Zig's `@cImport(@cInclude("strophe.h"))` to import libstrophe, then `linkSystemLibrary("strophe")` in build.zig. The callback-based API (`xmpp_conn_set_jid`, `xmpp_connect_client`, `xmpp_run`) maps cleanly to Zig. NixOS provides `pkgs.libstrophe` for the system dependency.

**Risk**: Writing Zig wrapper code around a C callback API requires care with memory management and pointer lifetimes. This is the most novel code in the project — no one has done Zig + libstrophe before. Estimate ~500 lines of wrapper code.

**Alternative if blocked**: Shell out to `sendxmpp` or `profanity` CLI as an interim, then replace with native bindings.

**Verdict**: Sound, but requires original engineering. libstrophe is proven; the Zig binding is not.

---

### 3. emacsclient --eval as Steer Interface — SOUND WITH CAVEATS

**Basic operation is reliable.** `emacsclient --eval '(expression)'` sends elisp to the Emacs daemon and prints the return value to stdout. Works without any open frames when the daemon is running (`emacs --daemon`). Confirmed by multiple sources including the Emacs manual and Reddit.

**Concurrency limitation**: Emacs is single-threaded. Concurrent `emacsclient --eval` calls are serialized — the daemon processes them one at a time. This is fine for Zimaclaw because the orchestrator sends sequential commands (not parallel). However, if a long-running elisp expression blocks (e.g., a large magit operation), subsequent calls will queue.

**Structured data return**: `(json-encode ...)` in elisp returns JSON strings to stdout. For large data (e.g., entire buffer contents), this works but very large structures (megabytes) can cause issues — Stack Overflow reports Emacs crashing on huge recursive JSON encoding due to `max-lisp-eval-depth`. Mitigation: chunk large data, or use `(with-temp-buffer (insert (buffer-string ...)) (write-file "/tmp/zimaclaw-out.json"))` and read the file from Zig instead.

**Failure modes**: 
- Emacs daemon not running → emacsclient exits with error code, Zig detects
- Socket gone → emacsclient reports "can't find socket", Zig detects
- Elisp error → Emacs returns error string to stderr, Zig can parse
- Emacs hang → timeout in Zig process spawn, kill and restart daemon

**Latency**: emacsclient startup is essentially instant on Linux (no 2-3s delay that Windows/Spacemacs users report). On headless NixOS with `emacs-nox`, expect <50ms round-trip for simple evaluations.

**Verdict**: Sound. The single-threaded nature is a feature, not a bug — it prevents race conditions on file state. Just don't send blocking operations.

---

### 4. Pi JSON-RPC over stdin/stdout — SOUND WITH KNOWN BUG (FIXED)

**Protocol is comprehensive.** Pi's RPC mode offers 25+ commands covering prompting (`prompt`, `steer`, `follow_up`, `abort`), state management (`get_state`, `get_messages`), model switching, thinking levels, session management (`fork`, `switch_session`, `export_html`), and bash execution. Streaming events cover the full agent lifecycle (`agent_start`, `turn_start`, `message_update` with `text_delta`, `tool_execution_start/end`, `agent_end`).

**Transport**: JSONL (JSON Lines) over stdin/stdout, LF-delimited. Commands are sent as one JSON object per line to stdin. Events and responses come as JSON objects on stdout.

**Known bug (closed)**: Issue #1911 reported that `U+2028`/`U+2029` Unicode line separators in payloads broke JSONL framing because Node.js `readline` treats them as line terminators. The issue is marked closed. Since Zimaclaw uses Zig (not Node.js) to read Pi's stdout, we control our own line splitting — split on `\n` only, ignore `U+2028`/`U+2029`. This bug does not affect us.

**No stability guarantees**: The Pi RPC protocol has no versioning, no semantic versioning, no stability annotations. It's implementation-coupled to the Pi source. This means protocol changes could break Zimaclaw on Pi upgrades. Mitigation: pin the Pi version in the Nix flake (`buildNpmPackage` with a specific commit hash).

**Verdict**: Sound. The protocol is rich and well-documented. The lack of versioning is a real risk, mitigated by Nix version pinning.

---

### 5. Backstage Actor Framework — HIGH RISK

**Explicitly experimental.** The README states: "This repository contains an **experimental** actor framework." 43 GitHub stars. Unclear number of contributors and last commit date. No version releases. No stated Zig version compatibility.

**libxev dependency**: libxev (by Mitchell Hashimoto of HashiCorp/Ghostty fame) is more mature — actively maintained, supports Zig 0.14, has CI, tested on Linux/macOS/WASM. libxev itself is sound. But Backstage's layer on top is unproven.

**Risk**: If Backstage breaks on a Zig version update, or has bugs in supervision/restart logic, we're stuck debugging someone else's experimental framework. The actor model it provides (message passing, lifecycle, supervision) is ~500 lines of code that could be written directly.

**Alternative**: Skip Backstage entirely. Use Zig's built-in threading (`std.Thread`) with channels, or just use sequential processing — Zimaclaw's concurrency needs are modest (one XMPP listener, one emacsclient controller, one Pi process). A simple event loop with select/poll on the three I/O sources would suffice.

**Verdict**: HIGH RISK. Recommend dropping Backstage and using direct Zig concurrency primitives or a simple hand-rolled event loop. The actor model adds complexity without proportional benefit for a system with only 3 concurrent concerns.

---

### 6. ZigJR JSON-RPC Library — SOUND

**Feature-complete and well-documented.** ZigJR provides:
- Full JSON-RPC 2.0 parsing and composition
- Newline-delimited streaming (`requestsByDelimiter`) — exactly what Pi's JSONL protocol needs
- Content-Length header-based streaming (for LSP-style protocols)
- Native Zig function dispatch with automatic type mapping
- Logging mechanism for debugging
- Batch request/response support

**Released as version 1.0.0** with proper `zig fetch` installation. Listed in awesome-zig. Published June 2025. The `stream.requestsByDelimiter()` function maps directly to reading Pi's `\n`-delimited JSONL output.

**The `lsp_client.zig` example** shows handling mixed requests and responses in a stream — this is exactly our use case (sending commands to Pi, receiving streaming events back).

**Verdict**: Sound. This is a real library solving our exact problem with proper releases and documentation.

---

### 7. NixOS as Appliance OS — SOUND

**Headless NixOS is well-proven** for server/appliance use. Minimal install is <2GB. `emacs-nox`, `nodejs`, `prosody`, `tailscale`, `zig` are all in nixpkgs. The flake + home-manager pattern is standard (Tony and Joshua's videos demonstrate it thoroughly).

**Zig packaging**: zig2nix exists and is actively maintained. It handles `build.zig.zon` dependencies via lock files. Cross-compilation to aarch64 is supported. This is the main gap in the Nix ecosystem for Zig — zig2nix bridges it.

**Node.js/Pi packaging**: `buildNpmPackage` is the standard nixpkgs approach. Requires `package-lock.json` and an `npmDepsHash`. The `fakeHash` workflow is well-documented. Pi can be packaged this way.

**Rollback**: `nixos-rebuild switch --rollback` is battle-tested. Each `nixos-rebuild switch` creates a new system generation that appears in the bootloader. This is one of NixOS's strongest features.

**Potential gap**: NixOS package freshness — ~10% of nixpkgs is outdated at any time (per Repology). For fast-moving tools like Pi, pinning to a specific commit in the flake is the right strategy (which we're already doing).

**Verdict**: Sound. NixOS is the strongest architectural choice in the stack.

---

## Risk Summary

| Component | Verdict | Risk Level | Key Concern |
|-----------|---------|------------|-------------|
| Zig orchestrator | Sound | LOW | `std.process.Child` API being redesigned, but current API works |
| XMPP/libstrophe | Sound with effort | MEDIUM | No existing Zig bindings; ~500 lines of C wrapper code needed |
| emacsclient --eval | Sound with caveats | LOW | Single-threaded serialization; large JSON encoding limits |
| Pi JSON-RPC | Sound | MEDIUM | No protocol versioning; mitigated by Nix version pinning |
| Backstage actors | HIGH RISK | HIGH | Experimental, 43 stars, no releases, unclear maintenance |
| ZigJR | Sound | LOW | Well-documented 1.0 release, solves exact problem |
| NixOS | Sound | LOW | Strongest choice; battle-tested reproducibility |

## Recommendation

**Drop Backstage.** Replace with a simple hand-rolled event loop or Zig's `std.Thread` with message queues. Zimaclaw has exactly 3 I/O concerns (XMPP socket, emacsclient subprocess, Pi subprocess) — an actor framework is overkill. A ~200 line event loop that polls all three sources would be simpler, more debuggable, and have zero external dependency risk.

Everything else is on sound footing. The architecture holds.
