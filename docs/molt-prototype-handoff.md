# Zimaclaw Handoff — Next Steps From Current State

## 1. What is already done

The groundwork pass is complete.

### Docs updated
These two files were updated to match the final research round:
- `docs/product-vision.md`
- `docs/architecture-validation.md`

They now reflect:
- the named component model
- issue-centered workflow
- predispatch simulation
- prototype-first / throwaway-first strategy
- Emacs-as-computer
- DAG execution and review gates
- stdlib-first dependency posture

### Backlog updated
The Linear backlog was revised to match the new product shape.

#### Existing tickets revised
- `BE-26` — epic reframed around issue-shaped orchestration
- `BE-27` — Molt prototype scaffold
- `BE-28` — Jaw
- `BE-29` — Steer
- `BE-30` — Drive
- `BE-31` — stdlib-first Pi JSONL transport policy
- `BE-32` — Claw runtime
- `BE-33` — Marrow + Steer runtime
- `BE-34` — optional Prosody/private deployment
- `BE-35` — Marrow headless base
- `BE-36` — prototype + real-product E2E validation
- `BE-37` — Marrow flake/service graph

#### New tickets created
- `BE-38` — Web
- `BE-39` — Shell
- `BE-40` — Spine
- `BE-41` — Fang
- `BE-42` — Venom
- `BE-43` — Review gates
- `BE-44` — Executable DAG
- `BE-45` — UI issue cards
- `BE-46` — Prototype learnings capture
- `BE-47` — Delete Molt and rebuild clean interfaces

### Repo / branch state
Docs were committed and pushed on:
- `cursor/docs-and-linear-bc-7e41d13f-a8b4-42cc-8e35-13a6ce67b1ce-1ee6`

There is also an untracked file in the repo:
- `docs/architecture-deep-dive.md`

That file was intentionally left alone.

---

## 2. Where work paused

Implementation did **not** start yet.

Reason:
- the finished pass was **docs + backlog alignment**
- once the request expanded into “build the product”, that became a **new major phase**
- the correct next move was to **re-plan the first Molt slice** instead of writing code immediately in a still-docs-only repo

At the moment, the repo is still effectively a docs/research repo plus backlog.

---

## 3. Current repo reality

### What exists
- `README.md`
- `docs/`
- no `src/`
- no `build.zig`
- no `build.zig.zon`
- no flake in this repo yet
- no tests
- no runtime code

### Important local environment notes from the last check
On the machine where planning resumed:
- `pi` exists
- `node` and `npm` exist
- `zig` was **not** available
- `emacsclient` was **not** available
- `nix` was **not** available
- `direnv` was **not** available

That means the next implementation pass should assume:
- some runtime components may need to be built behind interfaces first
- real `Jaw` / `Steer` / `Marrow` integration may need mocks or graceful-not-installed behavior during early prototype work

---

## 4. Recommended first implementation slice

## Best first Molt slice
The best first prototype slice is:

**local prompt → Fang issue creation → Drive Pi subprocess loop → Steer interface boundary → Spine event stream**

### Why this is the right first slice
It gives the most learning with the least lock-in:
- proves the issue-shaped model early
- forces a real Fang schema
- forces a real Drive subprocess boundary
- forces a real Steer interface without needing full Emacs integration immediately
- forces an event stream shape for future UI work
- avoids starting with XMPP or full UI too early

### What to defer until after this slice
Do **not** start with these:
- full Jaw / libstrophe implementation
- Venom full simulation engine
- Svelte UI
- full DAG executor
- full NixOS/flake deployment

Those should come **after** the first local Molt loop works.

---

## 5. Concrete implementation sequence

## Step 1 — Create the code substrate
Create the minimum actual codebase.

### Files to add first
- `build.zig`
- `build.zig.zon`
- `src/main.zig`
- `src/claw.zig`
- `src/fang.zig`
- `src/drive.zig`
- `src/drive_jsonl.zig`
- `src/steer.zig`
- `src/spine.zig`
- `src/types.zig`

### Goal
Be able to compile a tiny `zimaclaw` binary with stubbed components.

---

## Step 2 — Implement Fang first
Fang should be the first real component.

### Minimum Fang scope
Implement a simple file-backed issue store:
- issue id
- title / prompt
- state
- timestamps
- acceptance criteria placeholder
- simulation artifact placeholder
- execution artifact placeholder

### Suggested first states
Keep it very small for Molt:
- `inbox`
- `executing`
- `review`
- `done`
- `failed`

You can expand later to:
- `simulating`
- `distilled`
- `approved`
- `dispatchable`

### Storage suggestion
Use a simple local directory such as:
- `.zimaclaw/issues/<issue-id>/issue.json`

JSON is probably the simplest first choice for Molt.

---

## Step 3 — Implement a minimal Claw CLI
Claw should expose a small command surface first.

### Suggested initial commands
- `zimaclaw issue create --prompt "..."`
- `zimaclaw issue show <id>`
- `zimaclaw molt run --prompt "..."`
- `zimaclaw spine dump <id>` or equivalent

### Goal
The local CLI should simulate the top-level orchestration loop before real XMPP ingress exists.

---

## Step 4 — Implement Drive as a real subprocess boundary
Drive should be the first runtime boundary that is truly real.

### Minimum Drive scope
- spawn `pi`
- write one JSONL command to stdin
- read JSONL events from stdout
- track child lifecycle
- surface structured errors

### Keep it narrow
Do not build the full orchestration universe yet.
Just prove:
- process launch
- stdin/stdout framing
- event parsing
- clean shutdown

### Important
Use a stdlib-first JSONL implementation.
Do **not** introduce ZigJR unless the simple framing layer becomes clearly painful.

---

## Step 5 — Define Steer as an interface even if runtime is partial
Steer should exist as a boundary early, even if the environment cannot execute Emacs yet.

### Minimum Steer behavior
- define a request/response type
- expose one or two conceptual actions, for example:
  - eval expression
  - read file through Emacs
- if `emacsclient` is unavailable, return a clean structured error

### Why
This keeps the architecture honest:
- Emacs remains the intended computer
- shell does not accidentally become the default fallback
- later real integration can swap in without redesign

---

## Step 6 — Add Spine as an event stream/log shape
You do not need the full SSE server first.
You do need the **event model** first.

### Minimum Spine scope
Emit structured events during `molt run`:
- run started
- issue created
- drive spawned
- pi event received
- steer call attempted
- run finished / failed

### First implementation option
Start with:
- in-memory event list
- optionally write events to `events.jsonl`

Later this can become:
- SSE endpoint
- UI feed

---

## Step 7 — Make `molt run` prove the loop
This is the actual first vertical slice.

### Desired behavior
`zimaclaw molt run --prompt "..."` should:
1. create a Fang issue in `inbox`
2. transition it to `executing`
3. spawn Drive / Pi
4. attempt Steer operations through the Steer boundary
5. emit Spine events
6. finish by moving issue to `review` or `failed`

### That is enough for Molt v1
This gives a real artifact chain without overbuilding.

---

## Step 8 — Add tests immediately
Add tests after each meaningful component.

### First tests to write
- Fang store create/load/update tests
- JSONL framing tests for Drive
- subprocess lifecycle tests using a fake child or fixture process
- Spine event ordering tests
- `molt run` integration test with a fake Pi process if possible

---

## Step 9 — Commit after every meaningful change
The next implementation pass should follow this rhythm:
1. change one meaningful slice
2. `git add -A`
3. commit
4. push

Likely commit sequence:
- scaffold Zig app
- add Fang issue store
- add Drive JSONL transport
- add Steer boundary
- add Spine event model
- add first `molt run` flow
- add tests

---

## 6. Suggested file layout for the first slice

```text
zimaclaw/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── types.zig
│   ├── claw.zig
│   ├── fang.zig
│   ├── drive.zig
│   ├── drive_jsonl.zig
│   ├── steer.zig
│   └── spine.zig
├── tests/
│   ├── fang_test.zig
│   ├── drive_jsonl_test.zig
│   └── molt_run_test.zig
└── .zimaclaw/
    └── issues/
```

If the cloud environment wants a flatter structure, that is also fine. The key is clean boundaries, not folder purity.

---

## 7. Acceptance criteria for the first Molt slice

The first implementation slice should count as complete only if all of these are true:

- the repo has a compilable Zig project
- Fang can create and update durable issue artifacts
- Claw can run a local prompt-driven flow
- Drive can spawn Pi and handle at least one JSONL exchange
- Steer exists as a real interface boundary with structured failure if unavailable
- Spine emits structured events for the run
- the issue transitions at least through:
  - `inbox` → `executing` → `review` or `failed`
- there are automated tests for the new behavior
- every meaningful change is committed and pushed

---

## 8. What should come immediately after that

Once the first Molt slice works, the next sequence should be:

### Next wave
1. improve Fang schema for richer artifacts
2. add a true local simulation object model
3. begin Venom simulation flow
4. add Shell as constrained Zig exec
5. add Web abstraction
6. add real Jaw ingress
7. add SSE endpoint for Spine
8. start UI issue cards

### After that
- capture prototype learnings
- revise specs if needed
- delete Molt
- rebuild cleanly

---

## 9. Recommended handoff instruction for the next cloud chat

If you want to paste a crisp implementation instruction into the next cloud chat, use something like this:

> Start from the updated docs and revised Linear backlog.  
> Do not jump straight into the full product.  
> First implement the smallest useful **Molt** vertical slice:
> - scaffold the Zig project
> - implement a minimal **Fang** file-backed issue store
> - implement a minimal **Claw** CLI with `molt run --prompt`
> - implement **Drive** as a real Pi subprocess + JSONL boundary
> - implement **Steer** as an interface boundary with structured error if Emacs is unavailable
> - implement **Spine** as a structured event stream/log
> - make `molt run` prove: local prompt → issue creation → Pi mediation → event stream → issue ends in review/failed
> - add tests after each component
> - commit and push after every meaningful change

---

## 10. Final recommendation

The main strategic choice is:

**Start with a local issue-driven Molt loop, not with XMPP or UI.**

That is the right prototype because it teaches:
- issue shape
- process boundaries
- transport behavior
- event model
- failure model

without prematurely locking in:
- XMPP infra
- real Emacs runtime assumptions
- frontend structure
- final DAG design

That is where work left off, and that is the next best move.
