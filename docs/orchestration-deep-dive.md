# Zimaclaw Orchestration Layer: Mapping Real Orchestrator Patterns to Zig + Emacs

> **Status note (2026-04-01):** This document describes the target orchestration architecture. For the currently shipped Molt slice, see `README.md` (`issue create/show`, local `molt run`, `inbox -> executing -> review|failed`, JSONL run trail). Items such as Jaw/XMPP ingress, Venom simulation flow, Shell/Web abstractions, and UI/SSE streaming are still deferred.
>
> **Maintenance note:** `docs/orchestration-deep-dive.md` is the canonical deep-dive source. `docs/architecture-deep-dive.md` is an alias entry point only. When shipped-vs-deferred boundaries change, update this file and `README.md` in the same PR.

## Overview

Zimaclaw's architecture — Zig as the process supervisor, Emacs as the steerable workspace (computer), and Pi as the execution engine — maps cleanly onto patterns already proven in production orchestrators. Nullboiler (the Zig-native orchestrator under the NullClaw project) is the most directly transferable reference: it implements worker dispatch, subprocess lifecycle, async correlation, and SSE event streaming entirely in Zig without any external actor framework. Perplexity Computer's multi-agent routing model and CopilotKit's AG-UI event protocol provide the conceptual model for how Zimaclaw should think about the Emacs interface as a "computer tool" and how to structure observable streaming for the UI layer. This document maps all three reference systems to concrete Zimaclaw design decisions.

***

## The Core Insight: Emacs as a Routed Computer Tool

The most useful reframing comes from Perplexity Computer's architecture: it is described as "a routed multi-agent system where the orchestration layer decides who does what, so we don't have to glue models together manually." The orchestrator routes tasks to specialized engines (vision, code, reasoning) as needed. In Zimaclaw, this maps as follows:[^1]

| Perplexity Computer | Zimaclaw |
|---|---|
| Planner deconstructs request into steps[^2] | Zig event loop parses XMPP prompt, decides dispatch |
| Specialized model engines | Pi process pool (coding) + Emacs (file/editor state) |
| Tool routing layer | `dispatch.zig`-style tag-based worker selection |
| Persistent cloud workers with checkpointing[^2] | `SubprocessInfo` + stall detection in `subprocess.zig` |
| Modular internal APIs between engines[^2] | JSONL over stdin/stdout (Pi) + emacsclient eval (Emacs) |

Critically, Perplexity Computer treats **computer interaction** as just another routed tool endpoint — not a separate architectural tier. Zimaclaw should adopt the same posture: Emacs is a tool worker with a known interface (`emacsclient --eval`) that the Zig orchestrator calls when a task step requires file-system or editor-state operations, exactly as it would dispatch an HTTP request to a webhook worker in nullboiler's model.[^3]

***

## Nullboiler: The Most Directly Transferable Reference

Nullboiler ([github.com/nullclaw/nullboiler](https://github.com/nullclaw/nullboiler)) is a Zig orchestration engine written to manage NullClaw coding agent subprocesses. Its source is the highest-fidelity template for Zimaclaw because it solves the same class of problems in the same language.

### Worker Selection Pattern

`dispatch.zig` implements tag-based, load-aware worker selection:

```zig
pub fn selectWorker(
    allocator: std.mem.Allocator,
    workers: []const WorkerInfo,
    required_tags: []const []const u8,
) !?WorkerInfo
```

The selection criteria are: `status == "active"`, `current_tasks < max_concurrent`, and at least one tag in `tags_json` intersects `required_tags`. Among eligible workers it returns the least-loaded one. **For Zimaclaw**, the `WorkerInfo` pool would contain two worker types: Pi process slots (tagged `["coder"]`) and a single Emacs worker (tagged `["editor", "filesystem"]`, `max_concurrent = 1` to enforce serialization).

### Subprocess Lifecycle

`subprocess.zig` defines the full Pi process management contract that Zimaclaw needs:

```zig
pub const SubprocessState = enum { starting, running, done, failed, stalled };

pub const SubprocessInfo = struct {
    task_id: []const u8,
    port: u16,
    child: ?std.process.Child,
    current_turn: u32,
    max_turns: u32,
    last_activity_ms: i64,
    state: SubprocessState,
    ...
};
```

Key functions:
- `spawnNullClaw` — spawns child process with `--port` and `--workdir` args, stdout/stderr piped
- `waitForHealth` — polls `/health` with retries (500ms between) before accepting tasks
- `sendPrompt` — POSTs `{"message": prompt}` to the child's `/webhook` endpoint
- `killSubprocess` — kills and waits on the child
- `isStalled` — returns `true` if `(now - last_activity_ms) > stall_timeout_ms`

**Direct adaptation for Pi**: Zimaclaw's Pi workers use JSONL over stdin/stdout rather than HTTP, so `sendPrompt` becomes a `write(stdin_fd, jsonl_line ++ "\n")` + `read(stdout_fd)` pair. The health check becomes reading a `{"type":"ready"}` JSONL event from Pi's startup output. Everything else — state tracking, stall detection, kill — ports verbatim.

### Async Correlation Queue

`async_dispatch.zig` provides the pattern for correlating responses when workers run concurrently:

```zig
pub const ResponseQueue = struct {
    map: std.StringArrayHashMapUnmanaged(AsyncResponse),
    mutex: std.Thread.Mutex,

    pub fn put(self: *ResponseQueue, response: AsyncResponse) void { ... }
    pub fn take(self: *ResponseQueue, correlation_id: []const u8) ?AsyncResponse { ... }
};
```

Each dispatched task gets a `correlation_id` (e.g., `"run_{run_id}_step_{step_id}"`). Results are placed into the queue by whichever thread reads the Pi stdout, and the XMPP reply thread calls `take(correlation_id)` to retrieve them. This is the correct concurrency primitive for Zimaclaw's Pi fan-out: no shared mutable state between task threads, just a mutex-protected map keyed by correlation ID.

### SSE Event Hub

`sse.zig` implements the observable streaming layer that feeds the UI:

```zig
pub const SseEvent = struct {
    seq: u64,
    event_type: []const u8,  // "step_started", "state_update", etc.
    data: []const u8,        // JSON payload
    mode: StreamMode,        // values | updates | tasks | debug
};

pub const RunEventQueue = struct { ... };   // per-run buffer, mutex-protected
pub const SseHub = struct { ... };          // keyed map of RunEventQueues
```

The hub supports `broadcast(run_id, event)` from any Zig thread, and `snapshotSince(after_seq)` for reconnecting SSE consumers without missed events (up to 2048 buffered events per run). This is the exact primitive needed for the Svelte UI card streams discussed in the previous session.

***

## CopilotKit AG-UI: The Event Schema to Adopt

CopilotKit's AG-UI protocol defines the **wire format** that the Svelte UI should consume. Rather than inventing a custom event vocabulary, Zimaclaw should emit AG-UI-compatible events from its SSE hub. The full AG-UI event taxonomy is:[^4][^5]

| Event Type | Trigger | Zimaclaw Source |
|---|---|---|
| `RUN_STARTED` | XMPP message received, task dispatched | Zig XMPP handler |
| `TEXT_MESSAGE_START` / `_CONTENT` / `_END` | Pi streaming output token | Pi stdout reader thread |
| `TOOL_CALL_START` | Emacs eval dispatched | Zig before `emacsclient` spawn |
| `TOOL_CALL_ARGS` | Elisp expression being sent | Zig before `emacsclient` spawn |
| `TOOL_CALL_END` | `emacsclient` returned | Zig after `emacsclient` exit |
| `STATE_SNAPSHOT` | Pi task completed with result | Zig after `take(correlation_id)` |
| `STATE_DELTA` | Intermediate Pi turn output | Pi stdout reader thread |
| `RUN_FINISHED` | All subagents done, XMPP reply sent | Zig XMPP reply handler |

One important caveat from CopilotKit's own bug tracker: `TOOL_CALL_START` must never be emitted while another tool call is in progress — the protocol enforces strict serialization at the event level. This aligns perfectly with Zimaclaw's Emacs serialization constraint: since Emacs is single-threaded, Zig must never emit a `TOOL_CALL_START` for an Emacs operation while one is still running. The UI layer's single-tool-at-a-time constraint enforces the Emacs daemon's real-world constraint.[^6]

***

## OpenClaw: What to Borrow Conceptually

OpenClaw's (and its documented architecture's) contribution to this analysis is the **SOUL.md / TOOLS.md persona and capability declaration** pattern. Perplexity Computer's comparison reviewers note that OpenClaw requires manual wiring of tools and capability manifests per agent. For Zimaclaw, this translates into a declaration layer in the Nix flake: each Pi subprocess gets a workspace with a `TOOLS.md` and `SOUL.md` that constrains its capabilities (e.g., "you have access to emacsclient for file reads, git for version control, and the NixOS build system"). This is more relevant for Pi's prompt construction than for Zig's dispatch logic, but it establishes the pattern for how the orchestrator should frame tool availability to each subagent.[^3][^1]

***

## Translating to Zimaclaw's Concrete Architecture

### Worker Registry

Zimaclaw should maintain a static registry of available tool workers, analogous to nullboiler's `workers: []const WorkerInfo`:

```zig
const ZimaWorker = struct {
    id: []const u8,
    kind: enum { pi_subprocess, emacs_client },
    tags: []const []const u8,
    max_concurrent: u32,   // 1 for emacs, N for pi pool
    current_tasks: std.atomic.Value(u32),
    state: enum { active, stalled, dead },
};
```

The `selectWorker` logic from nullboiler ports verbatim with the enum substitution.

### Emacs as a Tool Worker (Not a Peer Orchestrator)

The critical architectural decision: Emacs should **not** be modeled as a peer orchestrator with its own task queue. It is a synchronous tool call with a known interface and a mutex constraint. The Zig dispatch layer should treat `emacsclient --eval '(expression)'` exactly like `sendPrompt(port, prompt)` in nullboiler — a blocking HTTP call that returns a result or an error. The "mutex" is enforced by setting `max_concurrent = 1` on the Emacs worker entry and having `selectWorker` return `null` when it is busy.

```zig
// Pseudo-code for Emacs tool dispatch
fn dispatchEmacsEval(
    allocator: Allocator,
    expression: []const u8,
    timeout_ms: u64,
) !EmacsResult {
    var child = try std.process.Child.init(
        &[_][]const u8{ "emacsclient", "--eval", expression },
        allocator,
    );
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    // Read stdout (return value) and stderr (error string) with timeout
    // kill + restart daemon on timeout
    ...
}
```

This means the `TOOL_CALL_START` → `TOOL_CALL_END` SSE pair wraps `dispatchEmacsEval`, giving the UI full visibility into Emacs operations as tool calls in the AG-UI sense.

### Pi Subprocess as a Computer-Use Endpoint

The "give Pi a computer" framing resolves when Emacs tools are surfaced to Pi as a tool manifest. When Zig dispatches to a Pi subprocess, it sends a JSONL prompt that includes an available tools declaration:

```json
{
  "type": "task",
  "task_id": "...",
  "prompt": "...",
  "tools": [
    {"name": "emacs_eval", "description": "Evaluate elisp in the Emacs daemon", "input_schema": {"expression": "string"}},
    {"name": "emacs_find_file", "description": "Open a file in the Emacs daemon", "input_schema": {"path": "string"}},
    {"name": "shell", "description": "Run a shell command in the workspace", "input_schema": {"cmd": "string"}}
  ]
}
```

When Pi emits a tool call in its JSONL output, Zig intercepts it, dispatches to the appropriate backend (Emacs or shell), and sends the result back to Pi as a tool result JSONL line before Pi continues. This is the "agentic loop" pattern: Pi reasons, Zig executes tools, Pi gets results, Pi continues. Nullboiler's `max_turns` and `isStalled` fields track this loop and terminate hung agents.

### SSE Event Vocabulary for Zimaclaw

Adapting nullboiler's `SseEvent` with AG-UI event types:

```zig
// Emit on XMPP message received
hub.broadcast(run_id, .{ .event_type = "RUN_STARTED", .data = xmpp_payload_json });

// Emit when Pi produces a streaming token
hub.broadcast(run_id, .{ .event_type = "TEXT_MESSAGE_CONTENT", .data = token_json });

// Emit before/after emacsclient dispatch
hub.broadcast(run_id, .{ .event_type = "TOOL_CALL_START", .data = eval_args_json });
hub.broadcast(run_id, .{ .event_type = "TOOL_CALL_END", .data = eval_result_json });

// Emit when all Pi workers done and XMPP reply sent
hub.broadcast(run_id, .{ .event_type = "RUN_FINISHED", .data = summary_json });
```

The Svelte UI subscribes to `GET /runs/{run_id}/events` (an SSE endpoint) and reconstructs each subagent card from this stream. The `snapshotSince(after_seq)` mechanism in nullboiler's `RunEventQueue` handles reconnection transparently — the browser can supply `Last-Event-ID` and replay missed events up to the 2048-event buffer limit.

***

## Protocol Support Tiers

Nullboiler supports multiple dispatch protocols (`webhook`, `api_chat`, `openai_chat`, `a2a`, `mqtt`, `redis_stream`). For Zimaclaw's initial implementation, only two are needed:

| Protocol | Use Case | Implementation |
|---|---|---|
| `pi_jsonl` (custom) | Pi subprocess over stdin/stdout | `write`/`read` on anonymous pipes |
| `emacs_eval` (custom) | Emacs daemon over emacsclient | `spawn emacsclient --eval`, parse stdout |

A2A (Agent-to-Agent, Google's JSON-RPC 2.0 multi-agent protocol) is worth noting as a future upgrade path. Nullboiler already implements A2A dispatch (`tasks/send` JSON-RPC 2.0 with `contextId` for session persistence) — if Pi gains an A2A-compatible HTTP interface in a future version, Zimaclaw could replace the stdin/stdout pipe with an A2A HTTP call and get standardized session management for free.

***

## Reliability and Observability Alignment

The constraints in Zimaclaw's validated architecture map directly to nullboiler's implementation patterns:

| Zimaclaw Constraint | Nullboiler Pattern |
|---|---|
| Emacs calls are sequential | `max_concurrent = 1` + `selectWorker` returning null when busy |
| Large Emacs return payloads → file handoff | Not in nullboiler; implement as: emit file path in `TOOL_CALL_END` payload, Zig reads file |
| Pi pinned to fixed version | NixOS flake pin; `subprocess.zig`'s `command` field points to pinned binary path |
| JSONL strictly LF-delimited | Enforce in Pi stdout reader: split on `\n`, reject malformed frames |
| Process-level failures explicit | `SubprocessState.failed` + `stalled`, `killSubprocess`, daemon restart |
| Timeout/restart on Emacs hang | Zig process spawn with timeout; kill on expiry, restart `emacs --daemon` |

The stall detection pattern (`isStalled` comparing `last_activity_ms` to `nowMs()`) should be applied to both Pi workers and Emacs tool calls. A hung `emacsclient` call with no stdout/stderr output for N seconds is an Emacs hang — Zig kills the child, restarts the daemon, and emits a `TOOL_CALL_END` with `{"error": "emacs_daemon_restarted"}` to the SSE hub so the UI card shows the failure.

***

## Recommended Implementation Sequence

1. **Port `subprocess.zig`** to Zimaclaw's Pi process manager, replacing the HTTP webhook with JSONL pipe I/O. Retain `SubprocessState`, `isStalled`, `killSubprocess` verbatim.
2. **Port `async_dispatch.zig`** (`ResponseQueue`) as the correlation map between Pi task dispatches and XMPP replies.
3. **Port `sse.zig`** (`SseHub`, `RunEventQueue`) as the observable event layer, emitting AG-UI-compatible event type strings.
4. **Add `emacs_worker.zig`**: wraps `emacsclient --eval` as a synchronous tool dispatch, emits `TOOL_CALL_START`/`END` events to the SSE hub, enforces serialization via `max_concurrent = 1`.
5. **Add `pi_tool_loop.zig`**: reads Pi JSONL output, intercepts tool call lines, dispatches to Emacs or shell workers, writes tool results back to Pi stdin, emits streaming tokens to the SSE hub.
6. **Wire Tailscale SSE endpoint** in `api.zig`: serve `GET /runs/{run_id}/events` as a streaming HTTP response, using `snapshotSince` for reconnection support.

---

## References

1. [Perplexity Computer: What I Built in One Night (Review, Examples ...](https://karozieminski.substack.com/p/perplexity-computer-review-examples-guide) - Perplexity Computer explained: 19+ frontier models, unified with files, tools, and multi-agent workf...

2. [Why The Perplexity Computer Max Plan Runs Circles Around Single ...](https://www.reddit.com/r/AISEOInsider/comments/1rk0puo/why_the_perplexity_computer_max_plan_runs_circles/) - It runs tasks using a full multi-model orchestration layer instead of a single LLM. It builds apps, ...

3. [Perplexity Computer Review: What It Gets Right (and Wrong)](https://www.builder.io/blog/perplexity-computer) - It's a "use the right tool for the job" argument. Perplexity Computer for generalist agent work. Spe...

4. [How to add a Frontend to any AG2 Agent using AG-UI Protocol | Blog](https://www.copilotkit.ai/blog/how-to-add-a-frontend-to-any-ag2-agent-using-ag-ui-protocol) - ... TOOL_CALL_START ) or “Here's the weather data” ( TOOL_CALL_END ). State management events: These...

5. [AG-UI CopilotKit Quick Start: Tutorial & Integration Guide](https://zediot.com/blog/ag-ui-copilotkit-quick-start/) - Tool call events like TOOL_CALL_START / TOOL_CALL_ARGS / TOOL_CALL_END; State updates like STATE_SNA...

6. [Bug: CopilotKitError: Cannot send 'TOOL_CALL_START' event - tool ...](https://github.com/CopilotKit/CopilotKit/issues/2587) - A CopilotKitError is thrown: "Cannot send 'TOOL_CALL_START' event: A tool call is already in progres...

