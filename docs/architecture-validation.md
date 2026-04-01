# Zimaclaw Architecture Validation

## Scope

This document validates the architecture described in the product vision after the final research round. The important shift is that Zimaclaw is **not** just "XMPP + Emacs + Pi on NixOS". It is an issue-centered orchestration product with:

* a named component model,
* a predispatch simulation harness,
* an execution DAG,
* a human approval gate between simulation and execution,
* and a prototype-first, throwaway-first build strategy.

The goal here is to validate the core technical bets, note the real risks, and call out where the architecture should stay minimal.

---

## Validation Summary

| Area | Verdict | Notes |
|------|---------|-------|
| Claw as Zig supervisor | SOUND | Zig is a good fit for orchestration, process ownership, and policy enforcement. |
| Jaw via libstrophe | SOUND WITH EFFORT | Correct transport choice, but requires original Zig wrapper work. |
| Steer via `emacsclient --eval` | SOUND WITH CAVEATS | Strong differentiator; must respect Emacs serialization and payload limits. |
| Drive via Pi subprocess + JSONL | SOUND | Strong core architecture if Pi is pinned. |
| Fang as local issue store | SOUND | TOML/JSON/file-backed FSM is straightforward and matches product needs. |
| Venom as simulation harness | SOUND | Architecturally coherent and product-defining; main complexity is policy/workspace separation, not feasibility. |
| Spine via SSE | SOUND | Simple, observable, and fits the UI well. |
| Shell as constrained Zig tool | SOUND | Narrow exception to Emacs-first model; should stay heavily constrained. |
| Web search abstraction | SOUND | Useful in both simulation and execution, easy to encapsulate. |
| Svelte UI + SSE | SOUND | Best fit for private dashboard and live issue cards. |
| Backstage actor framework | HIGH RISK / REJECT | Unnecessary and too experimental. |
| ZigJR as a required dependency | UNNECESSARY BY DEFAULT | Sound library, but stdlib-first is the better default. |
| NixOS / flake deployment | SOUND | Strongest environment choice in the stack. |

---

## Named Components

The architecture is clearest when validated through the named components:

| Component | Validated role |
|-----------|----------------|
| **Claw** | Top-level Zig runtime, process supervisor, issue lifecycle controller, policy engine |
| **Jaw** | XMPP ingress transport |
| **Steer** | Emacs interface and computer tool |
| **Drive** | Pi subprocess mediation layer |
| **Fang** | Durable issue store and FSM |
| **Venom** | Predispatch simulation harness |
| **Web** | Shared web-search abstraction |
| **Spine** | SSE event hub |
| **Shell** | Narrow Zig exec wrapper |
| **Marrow** | NixOS flake and deployment layer |
| **Molt** | Throwaway prototype layer |

The named model is not just naming polish. It improves system readability and keeps interfaces from drifting into a pile of unnamed "services" and "helpers".

---

## 1. Claw: Zig as Supervisor — SOUND

Zig remains the right top-level orchestrator language.

### Why it holds

* `std.process.Child` is good enough today for long-lived subprocess management.
* `std.json` is sufficient for JSONL framing, event decoding, and internal artifact serialization.
* Zig's C interop makes Jaw feasible through `libstrophe`.
* The deployment target is a single binary on a headless machine, which Zig suits well.

### Architectural fit

Claw needs to:

* own a process tree,
* supervise Drive / Steer / Jaw interactions,
* enforce simulation-vs-execution policy,
* manage issue state,
* and publish Spine events.

That is closer to a small systems program than to a framework-heavy service. Zig is a good match.

### Main caveat

Zig's process APIs are evolving, so the code should prefer thin wrappers and local abstractions instead of baking deep assumptions about today's API shape into the whole codebase.

**Verdict:** SOUND.

---

## 2. Jaw: XMPP via libstrophe — SOUND WITH EFFORT

There is still no compelling native Zig XMPP alternative. `libstrophe` remains the right practical choice.

### Why it holds

* Mature C library
* Small surface area
* Good enough features for a prompt ingress transport
* Available in NixOS packaging

### Important clarification

The product core is **Jaw**, not "run your own Prosody server". Self-hosted Prosody remains a valid **Marrow deployment option**, but it is not the same thing as the product architecture. Jaw should validate against XMPP transport concerns first.

### Real risk

The main difficulty is not conceptual, but implementation detail:

* callback lifetimes,
* memory ownership,
* error propagation,
* reconnect behavior,
* and safe integration into the Zig event loop.

**Verdict:** SOUND WITH EFFORT.

---

## 3. Steer: `emacsclient --eval` as the Computer Interface — SOUND WITH CAVEATS

Steer is still one of the strongest bets in the architecture.

### Why it holds

* `emacsclient --eval` is mature and practical.
* Emacs gives structured access to files, buffers, navigation, and editor-state operations.
* It is a better match for the "Emacs Bench" product idea than trying to tunnel everything through bash.

### Constraints that must be treated as first-class

* Emacs is single-threaded.
* Calls must be serialized.
* Large return payloads should use chunking or file handoff.
* Long-running calls need timeout and daemon recovery paths.

### Product impact

This is not just a tool choice; it is a differentiator. If Zimaclaw weakens into "Steer sometimes, bash otherwise", the core product idea gets diluted.

**Verdict:** SOUND WITH CAVEATS.

---

## 4. Drive: Pi subprocess + JSONL mediation — SOUND

Using Pi as a pinned subprocess remains a strong architectural decision.

### Why it holds

* Clean separation between orchestrator and coding worker
* Easy tool mediation at the process boundary
* Isolation from Pi's internal implementation changes, as long as the pinned version is respected
* Natural fit for streaming events and tool-call interception

### Important constraint

Pi should remain:

* a subprocess,
* version-pinned in Marrow,
* and tool-mediated by Drive.

Zimaclaw should not become coupled to Pi as if it were a stable embedded library.

### JSONL framing

LF-delimited JSONL remains the correct framing at the Zig boundary. The known Unicode line-separator bug in other runtimes is not a blocker if Claw/Drive split only on `\n`.

**Verdict:** SOUND.

---

## 5. Fang: local issue store and FSM — SOUND

Fang is a product-critical component, and there is nothing technically exotic about building it.

### Why it holds

The issue object naturally wants to persist:

* lifecycle state,
* acceptance criteria,
* simulation artifacts,
* DAG proposals,
* execution metadata,
* review decisions.

A file-backed store with a clear FSM is enough for the product stage described by the docs.

### Good default

Start with a simple file-backed store (TOML or JSON plus directories for artifacts), not a database-first design.

**Verdict:** SOUND.

---

## 6. Venom: predispatch simulation harness — SOUND

Venom is one of the most important new architectural additions, and it is technically plausible.

### Why it holds

The harness does not ask for a fundamentally different stack. It reuses:

* Drive for Pi,
* Steer for Emacs operations,
* Web for research,
* Spine for observability,
* Fang for persistence.

The novel part is the **policy and workflow distinction** between simulate and execute.

### Main architectural requirement

Venom needs explicit workspace policy:

* scratch tree, temp branch, or synthetic workspace in simulation,
* real branch/worktree in execution.

Without that separation, simulation will leak prototype slop into the real build.

**Verdict:** SOUND.

---

## 7. Spine: SSE event hub — SOUND

Spine is a clean fit for the product.

### Why it holds

* SSE is simple.
* The UI is mostly a stream consumer, not a general bidirectional app shell.
* Reconnect and replay behavior are straightforward.
* It matches the issue-card / live-telemetry model well.

### Event fit

Spine can carry:

* issue state changes,
* simulation branch updates,
* DAG revisions,
* subagent progress,
* Steer and Drive tool activity,
* review transitions.

**Verdict:** SOUND.

---

## 8. Shell: constrained Zig exec wrapper — SOUND

The Shell component is validated precisely because it is narrow.

### Why it holds

The product explicitly does **not** want a general shell escape hatch. But it does need a safe way to run Zig toolchain operations.

Restricting Shell to:

* `zig build`
* `zig test`
* `zig fmt`
* `zig run`

keeps it understandable and auditable.

### Constraint

If Shell expands into "whatever bash can do", the architecture starts undermining Steer and the Emacs Bench idea.

**Verdict:** SOUND.

---

## 9. Web: shared search abstraction — SOUND

Web search belongs in both simulation and execution.

### Why it holds

* Simulation needs research and comparison work.
* Execution sometimes needs targeted technical lookup.
* The capability is simple to wrap behind a small Zig abstraction.

This should remain an abstraction boundary, not a hard-coded dependency on one search provider.

**Verdict:** SOUND.

---

## 10. UI: Svelte + SSE issue cards — SOUND

The UI direction from `ui-deep-dive.md` remains the right choice.

### Why it holds

* Lightweight frontend
* Works well with SSE
* Good fit for issue cards and live telemetry
* Avoids dragging in a heavyweight backend runtime just to mirror agent state

### Important product fit

The UI should render:

* simulation track,
* execution track,
* issue artifacts,
* DAG and review state,

not just a terminal transcript.

**Verdict:** SOUND.

---

## 11. Backstage actor framework — HIGH RISK / REJECT

This remains a bad fit.

### Why it does not pass

* experimental
* unnecessary for the scale of this system
* extra dependency and conceptual complexity
* little payoff for a product with a small number of core runtime concerns

### Better option

Use:

* a simple event loop, or
* Zig threads + queues,

with explicit local abstractions.

**Verdict:** HIGH RISK / REJECT.

---

## 12. ZigJR — SOUND, BUT NOT DEFAULT

The earlier validation treated ZigJR as a likely integration layer. The final research round changes that recommendation.

### Why the recommendation changed

ZigJR appears sound and useful, but the updated dependency philosophy says:

* prefer Zig stdlib first,
* add dependencies only when the stdlib is clearly not enough.

Pi's JSONL transport is simple enough that a stdlib-first implementation is the correct default starting point.

### Practical recommendation

Do **not** make ZigJR a foundational ticket or required dependency. Keep it as:

* a fallback,
* or a future refinement,

if the hand-rolled transport becomes clearly too costly or error-prone.

**Verdict:** SOUND, BUT UNNECESSARY BY DEFAULT.

---

## 13. Marrow: NixOS / flake deployment — SOUND

This remains one of the strongest architectural choices.

### Why it holds

* reproducibility,
* rollback,
* pinning Pi and other dependencies,
* declarative services,
* strong fit for appliance-style deployment.

### Product clarification

Marrow is not just OS setup. It is the deployment truth for:

* Zig package/build pins,
* Pi pinning,
* Emacs daemon setup,
* service graph,
* optional XMPP server configuration,
* reproducible machine state.

**Verdict:** SOUND.

---

## Dependency Strategy Validation

The final docs strongly support a tighter dependency posture.

### Validated dependency rules

* Prefer Zig stdlib whenever practical.
* Keep Pi pinned and external.
* Accept `libstrophe` for Jaw.
* Avoid framework-level dependencies unless forced by complexity.
* Use `sorcy` before major dependency additions to keep the dependency surface visible.

This means the architecture should resist:

* actor-framework creep,
* UI backend bloat,
* transport-layer abstraction libraries unless clearly needed.

---

## Prototype Strategy Validation

The throwaway-first strategy is validated as a **process architecture**, not just a product-management preference.

### Why it holds

The product has several unknowns that are best discovered by building a thin vertical slice:

* Pi mediation behavior,
* Emacs tool ergonomics,
* issue artifact shapes,
* simulation traces,
* SSE/UI event shapes,
* workspace separation between simulation and execution.

Using Molt to discover these and then deleting it is a healthy strategy, not wasted work.

**Verdict:** SOUND.

---

## Main Risks Still Worth Watching

| Risk | Why it matters | Mitigation |
|------|----------------|------------|
| Zig + libstrophe wrapper complexity | Original glue code with callback/lifetime hazards | Keep Jaw thin, test reconnect/error cases early |
| Emacs payload and blocking behavior | Can stall Steer or make large results awkward | Serialize calls, add timeouts, use file handoff for large outputs |
| Pi protocol drift | No strong stability guarantees upstream | Pin Pi tightly in Marrow |
| Simulation workspace leakage | Could contaminate the real build with prototype artifacts | Enforce simulate/execute workspace policy explicitly |
| Architecture sprawl | Too many abstractions can bury the product | Keep components small, named, and dependency-light |

---

## Recommendation

The architecture holds, with three major recommendations:

1. **Keep the named component model.** It is one of the best clarity tools in the design.
2. **Lean harder into simulation-first.** Venom is not a side feature; it is central to the product identity.
3. **Stay stdlib-first and minimal.** Drop Backstage, avoid making ZigJR foundational, and keep Shell constrained.

In short:

* Claw + Jaw + Steer + Drive + Fang + Venom + Spine + Shell + Web + Marrow is a coherent architecture.
* Molt is the right first build.
* The biggest technical risks are wrapper/policy details, not the overall shape of the product.

The architecture is strong enough to proceed. The important thing now is to make the backlog reflect it cleanly.્રણ to=functions.ApplyPatch code ***!
