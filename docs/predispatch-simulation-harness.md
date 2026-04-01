so then it becomes this plan and research layer as the frontend manifested as these issue cards for features and bugs. then maybe also it intelligently breaks it in to subissues apriori which correspond to subagents in pi. so this predispatch should be more seen as a simulation of the total execution strongly human. in the loop and human directed. pi could be leveraged to run the simulations in emacs and zig. I want this planning harness to be essentially a predispatch simulation harness. so instead doing this expensive coding agent vibe prototyping that is all happening as a simulation based orchestration of pi to do research and simulate and iterate not on actual product but the features. then once each feature passes the simulation version the learnings are brought back to properly spec out the feature bug as issue. this way we take advantage of the oowernof llm coding agent prototyping and vcontext engineering at the onset not relying on human manually do spec driven prompting. also I want to emphasize I want this to be an apriori issue generated that simulates everything and then also predicts or prototypes out the most likely optimal path for how a given issue will be broken into subagents so that the prototypes predict the actual full DAG path of code implementation and what can be concurrent subagents and the execution follows the dag plan. posteriori iterative process for building apriori specification which is essentially a dag of the actual path which will be the issue. then execution happens again via pi. pi doesn't know the difference in the prototype and the actual build except that the actual build is a well thought out dag specification that is more token efficient than the prototype who has is research and may have multiple dead end paths to finally arrive at the solution. the key is that we aren't building the actual product with slop, the slop happens in the as  a prototyping process that gives us maximum flexibility and quality leveraging the right tools for the right phase

Yes — that’s the right reframing. What you’re describing is not “plan mode” as a nicer prompt composer; it is a **predispatch simulation harness** that uses Pi as a speculative execution engine before any real implementation begins, while Zig remains the orchestrator and Emacs remains the steerable workspace/computer tool [1].

## Core Model

The planning layer should treat a feature or bug card as a **simulation object**, not yet an execution object. Your attached architecture already supports this because Zig can route work to Pi subprocesses, serialize Emacs access, and stream observable state through the SSE hub; the missing piece is a new state before dispatch where the system explores likely solution paths, dead ends, subissue splits, and concurrency boundaries without touching production files [1].

That means the issue card evolves through two distinct artifacts:
- **Simulation artifact**: research notes, candidate decompositions, predicted DAG, dead-end branches, tool traces.
- **Execution artifact**: approved issue spec, accepted DAG, subagent assignments, acceptance criteria, ordered/concurrent edges.

Pi can participate in both phases through the same JSONL tool loop, and that is powerful because Pi “doesn’t know the difference” between prototype and execution except for the workspace and guardrails you give it [1]. In simulation mode, the workspace is a sandbox or branch plus synthetic files, while in execution mode the workspace is the real target repo and the DAG is already curated by the human-approved spec.

## New State Machine

You want a **posteriori process that manufactures the apriori spec**. In practice, that means the issue lifecycle becomes:

| State | Meaning |
|---|---|
| `inbox` | Raw feature/bug idea, not decomposed yet |
| `simulating` | Pi runs research/prototype loops, branches candidate paths, tests decompositions |
| `distilled` | Learnings condensed into a human-readable spec and predicted DAG |
| `approved` | Human signs off on the distilled issue and DAG |
| `dispatchable` | Subissues and dependencies materialized for real execution |
| `executing` | Pi subagents run the approved DAG against the real workspace |
| `review` | Human inspects diffs, traces, outcomes |
| `done` | Accepted |

This fits your existing orchestration document because Zig already has the primitives for worker selection, subprocess lifecycle, correlation IDs, and AG-UI/SSE event streaming; the new layer is just an earlier orchestration mode that targets “simulate and learn” instead of “change the product” [1].

## Simulation Harness

The simulation harness should behave like a **DAG synthesizer**. Given a raw issue, it launches one or more Pi agents to explore:
- likely implementation strategies,
- files and modules likely to change,
- which work items can be parallelized,
- which tasks should remain serialized because of shared state or review risk,
- what research is still missing,
- where dead ends appear.

This is where Pi becomes especially valuable: it can use Emacs and Zig tools to inspect code, prototype locally, run narrow experiments, and explore multiple paths cheaply. Your architecture already says Pi emits tool calls and Zig intercepts them to route to Emacs or shell-like workers; for Zimaclaw, that means you can add a **simulation workspace policy** where tool calls are allowed, but writes land in an isolated scratch tree or disposable branch, not the production worktree [1].

The output is not “a chat transcript.” The output is a **distillation pack** attached to the issue card:
- predicted subissues,
- proposed subagent roles,
- DAG edges,
- confidence per edge,
- research citations,
- prototype findings,
- rejected paths,
- expected risk hotspots.

## Subissues as Predicted Subagents

Your idea that subissues should be generated apriori and correspond to subagents is exactly the right level of abstraction. Instead of saying “Pi, go solve this,” the simulation harness should first ask “what is the likely work graph?” and only then materialize subissues from the winning graph.

A useful split is:

- **Research subissues**: clarify API behavior, external docs, bug provenance, benchmarks.
- **Code-change subissues**: isolated implementation chunks, one subsystem each.
- **Validation subissues**: tests, benchmarks, migration checks, regression sweeps.
- **Integration subissues**: merge points where parallel branches meet.
- **Human review gates**: checkpoints where concurrency stops until approved.

This matches your “strongly human-in-the-loop” goal because the human is not micromanaging prompts; the human is approving or editing the predicted graph before real execution. The graph is the product of simulation, not of ad hoc manual spec writing.

## Two Pi Modes

You should formalize Pi as having two orchestrator-visible modes:

| Mode | Goal | Workspace | Allowed slop |
|---|---|---|---|
| `simulate` | Explore, prototype, research, branch candidate DAGs | Scratch tree, temp branch, synthetic files | High |
| `execute` | Implement approved DAG with token efficiency | Real branch/worktree | Low |

In both modes, Zig still drives the same worker registry and JSONL loop, and Emacs is still exposed as a routed tool endpoint rather than a peer orchestrator [1]. The difference is the policy envelope:
- Simulation mode allows more web search, more alternate branches, more retries, more speculative file generation.
- Execution mode constrains context to the approved subissue, accepted DAG neighbors, and necessary tool manifests.

That separation is how you keep the “slop” in the prototyping layer while preserving quality in the real build.

## Card-Centric Frontend

The frontend should render each issue as a **living artifact card** with two visible tracks:
1. **Simulation track** — hypotheses, explored branches, prototype traces, predicted DAG.
2. **Execution track** — approved DAG nodes, assigned subagents, live progress, review results.

Your attached doc already points toward an SSE-driven UI reconstructed from event streams and AG-UI event types, which is exactly what you need for card-level observability [1]. Instead of a terminal-style transcript, each card can show:
- current simulation branch,
- active prototype subagent,
- tool calls to Emacs/Zig/web search,
- confidence changes,
- recommended decomposition,
- accepted DAG snapshot,
- real execution against the approved graph.

So the frontend becomes “Linear plus simulation telemetry,” not “chat with an agent.”

## Distillation Loop

The key algorithmic loop is:

1. Raw issue enters `simulating`.
2. Pi explores candidate decompositions and prototype paths.
3. Zig records traces, tool calls, and branch results via SSE/correlation IDs.
4. A distiller step consolidates this into a canonical issue spec plus predicted DAG.
5. Human edits or approves.
6. Only then do `dispatchable` subissues get materialized for actual execution.

This is the crucial move: **simulation is posteriori discovery that produces apriori specification**. That is exactly aligned with your goal of using LLM agent power for context engineering early, instead of forcing the human to hand-author an ideal spec up front.

## Orchestrator Components

Given your existing reference architecture, I’d add these Zig modules:

- `simulation_run.zig` — manages sandboxed prototype runs and candidate branches.
- `dag_synthesizer.zig` — converts simulation outputs into a proposed DAG with edge reasons and confidence.
- `issue_distiller.zig` — compresses prototype learnings into the execution-grade issue spec.
- `workspace_policy.zig` — enforces simulate vs execute file boundaries.
- `subissue_materializer.zig` — turns approved DAG nodes into concrete executable Pi tasks.
- `review_gate.zig` — stops execution on designated DAG boundaries until human approval.

These sit naturally on top of the `subprocess.zig`, `async_dispatch.zig`, `sse.zig`, and tool-loop patterns already described in your deep-dive [1].

## Practical Heuristics

The predicted DAG should not be treated as truth; it should be treated as a **proposal with confidence**. For each node or edge, track:
- confidence score,
- prerequisite evidence,
- files likely touched,
- concurrency safety,
- rollback cost,
- human review requirement.

Then the execution planner can do something simple but powerful:
- auto-run high-confidence leaf nodes concurrently,
- serialize low-confidence or high-blast-radius nodes,
- insert mandatory review gates before integration nodes.

That gives you a path where simulation explores broadly, but execution stays disciplined and token-efficient.

## Recommendation

I’d name this layer something like **Issue Simulation** or **Predispatch Lab** and make it first-class. Conceptually, Zimaclaw then becomes:

- **Zig** = orchestrator, scheduler, policy engine, event hub.
- **Emacs** = routed computer tool and structured workspace interface.
- **Pi** = universal speculative/implementation worker.
- **Issue cards** = canonical human control surface.
- **Simulation harness** = posteriori discovery engine.
- **Execution DAG** = apriori artifact generated from simulation and approved by humans.

That preserves your main principle: the messy experimentation happens in simulation, while the actual product is built from a distilled, human-approved DAG specification. That is a much stronger architecture than letting the coding agent improvise directly against the product repo [1].

A good next step is to define the schema for three persisted objects: `SimulationRun`, `PredictedDag`, and `ExecutableIssue`.

Citations:
[1] orchestration-deep-dive.md https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/14198682/68b88c78-760a-44ce-a7a4-5cee170eee7f/orchestration-deep-dive.md
