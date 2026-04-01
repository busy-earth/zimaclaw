# Zimaclaw Product Vision

Zimaclaw is a single Zig binary that acts as a local orchestration service on a headless NixOS machine. It is not a chatbot wrapper around Pi. It is an **issue-shaped coding appliance** with a simulation-first workflow:

1. a prompt arrives over XMPP,
2. Zimaclaw turns it into an issue,
3. a predispatch simulation harness explores the likely implementation DAG,
4. a human approves the distilled plan,
5. Pi executes the approved DAG against the real workspace,
6. the result returns to review as an issue artifact, not as more chat.

The system is designed to be reproducible and recoverable: OS configuration, services, packages, dotfiles, and pinned dependencies are declared in a version-controlled Nix flake so the full environment can be rebuilt or rolled back with standard NixOS workflows.

## Product Thesis

Zimaclaw is built around three ideas:

* **The issue is the unit of work.** Features and bugs live as durable issue artifacts with state, acceptance criteria, simulation traces, DAGs, and review history.
* **Emacs is the computer.** Zimaclaw's differentiator is that file and editor operations route through Emacs, not a general shell. This is the Emacs Bench idea.
* **Prototype slop belongs in simulation, not production.** Pi is used first to explore and prototype likely solutions in a controlled simulation phase. The real build starts only after those learnings have been distilled into a human-approved execution artifact.

## Build Strategy

Zimaclaw follows the strategy from `zigear.md`.

### 1. Build Molt first

Build a scrappy prototype that proves the core loop quickly:

* Jaw receives a prompt
* Fang creates an issue
* Drive spawns Pi
* Steer executes Emacs actions
* Spine broadcasts state to the UI

The purpose of Molt is to surface real unknowns fast, not to become the production system.

### 2. Capture learnings

Once Molt teaches us what the real interfaces and risks are, those learnings are written back into the issue backlog and architecture docs.

### 3. Delete Molt

Do not clean the prototype up into the final product. Throw it away.

### 4. Build the real product

Rebuild cleanly from the named components and the distilled issue/DAG model, using the fewest lines of code that still produce a reliable system.

## Component Dictionary

Zimaclaw uses named components with stable identities.

| Name | Role |
|------|------|
| **Claw** | The top-level Zig binary and supervisor. Claw owns the process tree, issue lifecycle, dispatch policy, and runtime orchestration. |
| **Steer** | The Emacs interface layer. All `emacsclient --eval` file/editor operations route through Steer. |
| **Drive** | The Pi interface layer. Drive manages the Pi subprocess, JSONL protocol, tool mediation, and run lifecycle. |
| **Fang** | The issue store. Fang tracks issue state, issue artifacts, acceptance criteria, DAGs, and review transitions. |
| **Venom** | The predispatch simulation harness. Venom explores candidate solution paths, predicts DAG structure, and validates plans before real execution. |
| **Web** | The web-search abstraction used during planning/simulation and during Pi execution. |
| **Spine** | The SSE event hub for real-time UI updates. |
| **Shell** | The constrained Zig exec tool. Shell is a narrow `std.process.Child` wrapper that allows only `zig build`, `zig test`, `zig fmt`, and `zig run` style commands. |
| **Jaw** | The XMPP transport and ingress boundary. Jaw handles remote prompts and message delivery. |
| **Marrow** | The NixOS flake and deployment layer: OS, packages, services, pins, and machine configuration. |
| **Molt** | The throwaway prototype layer used to learn fast before the real rebuild. |

## The Computer Is Emacs

Zimaclaw's core interaction model is not "bash plus some tools". It is:

* **Steer** for editor and filesystem operations via `emacsclient --eval`
* **Shell** only for tightly constrained Zig toolchain commands
* **Drive** for Pi mediation

This means:

* file reads/writes/edits should conceptually belong to Steer,
* code navigation and structured refactors should conceptually belong to Steer,
* general shell access is **not** a product primitive,
* Shell exists only as a narrow exception for Zig build/test/fmt/run workflows.

## Pi's Role

Pi is a **foundational subprocess**, not a library dependency and not the top-level orchestrator.

Zimaclaw runs outside Pi as a Zig supervisor. Drive owns the Pi process, mediates its tool calls, and pins Pi to a specific version or commit in Marrow. This gives Zimaclaw:

* stronger isolation,
* a stable issue layer above Pi,
* the ability to swap or upgrade Pi deliberately instead of coupling the whole system to Pi internals.

## Core Workflows

### 1. Simulation workflow

This is the predispatch planning workflow. It is issue-shaped, not chat-shaped.

An issue starts as a raw feature or bug card. Venom then uses Pi in a **simulate** mode to:

* research the problem,
* explore multiple candidate paths,
* surface likely dead ends,
* predict which work can run concurrently,
* propose a DAG of subissues/subagents,
* produce a distilled execution artifact.

The output of simulation is not "the final implementation". It is:

* a simulation artifact,
* a predicted DAG,
* confidence and risk notes,
* a refined issue ready for human approval.

### 2. Execution workflow

After approval, Claw dispatches the approved issue through Drive using Pi in **execute** mode. Pi receives:

* the approved issue spec,
* the approved DAG or subissue slice,
* the allowed tool manifest,
* the necessary workspace and policy constraints.

Execution is then more token-efficient and more reliable because the sloppier exploration work has already happened during simulation.

## Two Pi Modes

Zimaclaw treats Pi as having two orchestrator-visible modes:

| Mode | Goal | Workspace | Allowed slop |
|---|---|---|---|
| **simulate** | Explore, prototype, research, branch candidate DAGs | Scratch tree, disposable branch, or synthetic workspace | High |
| **execute** | Implement approved work against the real target repo | Real worktree/branch | Low |

Pi itself may not know the philosophical difference. Claw and Drive enforce the difference through workspace policy, context shaping, and issue state.

## Issue Model

Fang is the durable source of truth for work. The issue, not the transcript, is the object that moves through the product.

### Issue artifacts

A mature issue may contain:

* title and description
* acceptance criteria
* simulation artifact
* predicted DAG
* approved execution artifact
* run history
* review notes
* approval/rejection decisions

### Suggested lifecycle

| State | Meaning |
|---|---|
| `inbox` | Raw incoming prompt or idea |
| `simulating` | Venom is exploring candidate paths |
| `distilled` | Learnings and predicted DAG have been condensed |
| `approved` | Human approved the distilled artifact |
| `dispatchable` | Concrete execution units are ready |
| `executing` | Pi is running the approved work |
| `review` | Human reviews output, diffs, and traces |
| `done` | Accepted |

The important principle is that rejection sends the work back to an issue/planning state, **not back to chat**.

## Predispatch Simulation Harness

Venom is the predispatch lab where posteriori exploration produces the apriori execution spec.

The harness should:

* treat an issue as a simulation object,
* prototype against safe workspaces,
* produce candidate decomposition graphs,
* estimate concurrency safety,
* highlight integration points and review gates,
* attach its learnings back to Fang.

The harness exists so the real product is not built directly on top of exploratory agent slop.

## DAG-Oriented Execution

Execution should follow a DAG, not an unstructured conversation.

That DAG may include:

* research nodes,
* code-change nodes,
* validation nodes,
* integration nodes,
* human review gates.

Zimaclaw should prefer:

* concurrent execution for safe, independent leaves,
* serialization for shared-state or high-risk nodes,
* explicit review gates before integration or merge-critical steps.

## UI Model

The UI is issue-card oriented. It should feel closer to Linear plus live agent telemetry than to a terminal chat log.

Each issue card should expose two visible tracks:

1. **Simulation track**
   * candidate branches
   * prototype traces
   * predicted DAG
   * confidence and risk updates

2. **Execution track**
   * approved DAG nodes
   * assigned subagents
   * live progress
   * review outcome

Spine streams the state changes that let the UI stay live.

## Dependency Philosophy

Dependencies are a liability, not a feature.

### Preferred dependencies

* **Pi** — foundational, pinned, subprocess only
* **libstrophe** — acceptable for Jaw
* **Zig stdlib** — preferred for HTTP, JSON, process management, threading, and file I/O

### Rules

* Prefer Zig stdlib before adding libraries.
* Prefer a minimal library only when stdlib is clearly not enough.
* Run `sorcy` before major dependency additions to understand the dependency surface.
* Keep the code understandable in one sitting whenever possible.

## Reference Repos

These are architectural references, not direct product dependencies.

| Repo / Resource | Relevance |
|-----------------|-----------|
| `disler/pi-vs-claude-code` | Pi extension patterns, orchestration concepts, plan mode precedent |
| `disler/mac-mini-agent` | Listen/steer/drive orchestration inspiration |
| `busy-earth/sorcy` | Dependency-surface analysis workflow and named-component inspiration |
| `mariozechner/pi-coding-agent` | Pi runtime and JSONL/RPC behavior |
| `joshuablais/nixos-config` | NixOS + Emacs integration patterns |
| `tonybanters/nixos-from-scratch` | Flake-first NixOS setup patterns |
| `https://joshblais.com/blog/how-i-am-deeply-integrating-emacs/` | Emacs-as-computer patterns relevant to Steer |
| `https://www.tonybtw.com/tutorial/nixos-from-scratch/` | NixOS appliance and flake reference |

## Deployment and Environment

Marrow is the deployment truth.

Marrow should own:

* NixOS configuration
* package pins
* Pi pinning
* Emacs daemon setup
* service wiring
* machine reproducibility and rollback

Self-hosted Prosody is a valid Marrow deployment option, but it is **not the product itself**. The product core is Jaw, the XMPP transport boundary.

## Reliability Constraints and Guardrails

* Emacs calls are **sequential** because the daemon is single-threaded.
* Large Emacs payloads may need chunking or file handoff.
* Pi compatibility is protected by pinning Pi in Marrow.
* JSONL framing is strictly LF-delimited at the Zig boundary.
* Process failures are explicit runtime states, not hidden assumptions.
* Shell is constrained to Zig toolchain operations only.
* Simulation and execution must use different workspace policies.

## Success State

A successful Zimaclaw session looks like this:

1. Jaw receives a prompt over XMPP.
2. Claw creates an issue in Fang.
3. Venom simulates likely execution paths and predicts a DAG.
4. A human approves the distilled issue artifact.
5. Claw dispatches execution through Drive.
6. Pi uses Steer, Shell, and Web under Zimaclaw's mediation.
7. Spine streams live state to the UI.
8. The issue lands in review with diffs, traces, and execution artifacts.
9. The human approves or rejects from the issue workflow.

## Outcome

Zimaclaw is a private, reproducible, rollback-safe coding appliance where:

* XMPP is the ingress channel,
* Zig is the orchestrator,
* Emacs is the computer,
* Pi is the pinned execution worker,
* the issue is the unit of work,
* simulation produces the approved execution DAG,
* and the real build starts only after the product has learned enough to do it cleanly.
