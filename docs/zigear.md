how does disler extend pi from an orchestration perspective. I am building a product called zimaclaw and instead of just bash, read write edit, it will be zig instead of bash and emacs for everything else which has much more power.  how could I build an orchestration layer with web search and a plan mode that was less lime a chatbot and more like linear but more integrated into the coding agent which is pi in way that letsyou iterate on features and bugs as issues then has a separate workflow for assigning pi to go tackle them in a way that leverages substantial https://github.com/disler/pi-vs-claude-code

Your attached orchestration deep-dive already maps the Zig-level primitives (subprocess lifecycle, SSE hub, async correlation) beautifully. What it doesn't cover yet is the **issue-shaped entry point** that makes Zimaclaw feel like Linear rather than a chat harness. Here's the full picture, starting with what Disler actually does.

***

## How Disler Extends Pi

Disler's `pi-vs-claude-code` repo is primarily a **showcase of Pi's extension system** — it demonstrates that you can add everything Claude Code ships built-in as first-party TypeScript extensions without forking Pi internals [1]. The pattern is Pi's `Extension` class with three primitive hooks:

```typescript
class MyExtension extends Extension {
  registerTools(): Tool[] { ... }       // inject new tools into Pi's tool manifest
  registerCommands(): Command[] { ... } // add /slash-commands to Pi's REPL
  async onInput(input, ctx) { ... }     // intercept before Pi sees the user message
  async onToolCall(tool, params, ctx) { ... } // intercept/audit before any tool executes
  async onOutput(output, ctx) { ... }   // post-process every Pi response
}
```

Loaded via `pi -e ./dist/index.js` [2]. The specific extensions Disler layers on top of Pi include: **plan mode** (implemented via `onInput` to detect `/plan` and a `registerCommands` entry, not a built-in), **web search** (a registered `Tool` that calls a search API), **safety auditing** (an `onToolCall` hook that blocks destructive operations), and **cross-agent integrations** (orchestration tools that spawn secondary Pi instances) [1][3]. None of this touches Pi's core — they're all `registerTools` + hook compositions mounted at runtime.

The critical insight for Zimaclaw: Disler's plan mode is still **chatbot-shaped** — it's a `/plan` command that generates a markdown plan inside the conversation. What you want is structurally different: the plan is a **pre-dispatch artifact**, not a message in the thread.

***

## Zimaclaw's Issue-Driven Architecture

The core conceptual shift is a **two-workflow system** with a hard gate between them. Issues live in the Zig orchestrator's store; Pi only sees them when explicitly dispatched.

### Workflow 1: Issue Planning (Linear-like)

This workflow is **Pi-free**. It's a structured UI — not a chat interface — where issues are composed as data objects:

```toml
# .zimaclaw/issues/ISS-042.toml
id = "ISS-042"
type = "feature"          # or "bug"
status = "draft"          # draft → planned → dispatched → in_progress → review → done
title = "Add SIMD matrix multiply to hot path"
priority = "high"
context_files = ["src/math/matrix.zig", "bench/matrix_bench.zig"]

[[acceptance_criteria]]
description = "All existing tests pass"
[[acceptance_criteria]]
description = "Benchmark shows ≥2x improvement on AVX2 target"

[plan]
version = 3
content = "..."           # structured plan text, diffable between versions
approved_at = ""          # empty = not yet approved
```

Web search lives here, not just in Pi. Before writing acceptance criteria you can invoke `web_search` (as a Zimaclaw orchestrator call, not a Pi tool call) to research the problem space. The **plan review step** shows a diff between plan versions before you approve — this is the "less chatbot, more Linear" moment.

### Workflow 2: Pi Dispatch (Execution)

When you mark an issue `status = "planned"` and hit dispatch, the Zig orchestrator (following your nullboiler `subprocess.zig` pattern) composes a structured JSONL prompt from the issue fields and spawns a Pi subprocess:

```json
{
  "type": "task",
  "task_id": "ISS-042-run-001",
  "prompt": "Implement SIMD matrix multiply in src/math/matrix.zig.\n\nAcceptance criteria:\n1. All existing tests pass\n2. Benchmark shows ≥2x improvement on AVX2 target\n\nApproved plan:\n...",
  "tools": [
    {"name": "zig_exec",   "description": "Run zig build, zig test, zig run", "input_schema": {"args": "string[]"}},
    {"name": "emacs_eval", "description": "Evaluate elisp in the Emacs daemon", "input_schema": {"expression": "string"}},
    {"name": "web_search", "description": "Search the web for technical reference", "input_schema": {"query": "string"}}
  ]
}
```

**`zig_exec` is the replacement for bash**. Instead of an unscoped shell, it's a constrained subprocess runner that only invokes the Zig toolchain — `zig build`, `zig test`, `zig fmt`, etc. — with the workspace as cwd. The Zig orchestrator intercepts tool calls in Pi's JSONL output and routes `zig_exec` to a `std.process.Child` spawn, `emacs_eval` to `dispatchEmacsEval()`, and `web_search` to your search API. This is your `pi_tool_loop.zig` from the implementation sequence in the attached doc [4].

### The Issue Lifecycle State Machine

```
draft ──(plan edit + web search)──▶ planned
planned ──(approve plan)──────────▶ dispatched
dispatched ──(Pi starts)──────────▶ in_progress
in_progress ──(Pi finishes)────────▶ review
review ──(accept patch)────────────▶ done
review ──(reject → re-plan)────────▶ planned  ← iterate here, not in chat
```

The **review → planned** loop is the key UX win over a chatbot. When Pi finishes, you see a diff of what it changed. If it's wrong, you annotate the issue's acceptance criteria and re-dispatch — exactly like commenting on a Linear issue and re-assigning it — not by scrolling back through a conversation.

***

## Where `web_search` Lives in Each Workflow

| Workflow | Who calls it | When | Why |
|---|---|---|---|
| **Planning** | Zimaclaw orchestrator | Before writing acceptance criteria | Research API docs, existing art, benchmark data |
| **Execution** | Pi (via tool manifest) | During implementation | Look up Zig stdlib docs, AVX intrinsic references, error messages |

Both use the same underlying search tool, but in planning mode it's orchestrator-initiated and results feed into the issue's `[plan]` section. In execution mode it's Pi-initiated and results feed into Pi's context window.

***

## How Disler's Extensions Map to Zimaclaw's Stack

| Disler Extension (TypeScript in Pi) | Zimaclaw Equivalent (Zig in orchestrator) |
|---|---|
| `registerTools([web_search])` | `web_search` in JSONL tool manifest sent to Pi subprocess |
| `onToolCall` safety audit hook | `pi_tool_loop.zig` intercepts tool calls before dispatch |
| `/plan` command (chat-shaped) | Issue planning workflow (data-shaped, pre-dispatch) |
| Cross-agent orchestration tool | `selectWorker()` in `dispatch.zig` (Pi pool + Emacs worker) |
| `onOutput` post-processor | SSE hub `broadcast(run_id, STATE_DELTA)` from Pi stdout reader |

The fundamental difference: Disler's extensions run **inside Pi's process** (TypeScript hooks). Zimaclaw's orchestration runs **outside Pi** as a Zig supervisor that mediates all tool calls. This gives you stronger isolation, the stall detection your attached doc describes [4], and the ability to swap Pi out without changing the issue layer.

***

## Concrete Next Steps for the Issue Layer

1. **`issue.zig`** — TOML-backed issue store with status FSM; Zig's `zig-toml` or a minimal hand-rolled parser. `Issue.approve()` transitions `planned → dispatched` and calls into `subprocess.zig`'s `spawnPi(issue)`.
2. **`plan.zig`** — Versioned plan artifact with diff support; store versions as `ISS-042.v1.plan`, `ISS-042.v2.plan`. The UI diffs them before approval.
3. **`web_search_tool.zig`** — HTTP client (Zig's `std.http.Client`) calling your search backend; used both in planning (orchestrator-direct) and execution (routed from Pi's JSONL tool calls via `pi_tool_loop.zig`).
4. **`zig_exec_tool.zig`** — Constrained `std.process.Child` wrapper that only allows `["zig", ...]` argv; returns stdout/stderr as the tool result back to Pi.
5. Wire the issue status transitions to your SSE hub so the UI shows `ISS-042: in_progress → review` in real time as Pi finishes, using the `RUN_FINISHED` AG-UI event [4].

Citations:
[1] disler/pi-vs-claude-code - GitHub https://github.com/disler/pi-vs-claude-code
[2] PI Agent Revolution: Building Customizable, Open-Source AI ... https://atalupadhyay.wordpress.com/2026/02/24/pi-agent-revolution-building-customizable-open-source-ai-coding-agents-that-outperform-claude-code/
[3] Claude Code vs Pi Agent — Feature Comparison https://cultofclaude.com/skills/claude-code-vs-pi-agent-feature-comparison
[4] orchestration-deep-dive.md https://ppl-ai-file-upload.s3.amazonaws.com/web/direct-files/attachments/14198682/68b88c78-760a-44ce-a7a4-5cee170eee7f/orchestration-deep-dive.md?AWSAccessKeyId=ASIA2F3EMEYE6ROAZZQK&Signature=3Qgv3YGedupgXYvSB17ku3IXIPo%3D&x-amz-security-token=IQoJb3JpZ2luX2VjEDAaCXVzLWVhc3QtMSJIMEYCIQCVkJFPHo2%2BW1YAHo6hE%2ByTCiHxKp9bzvBsl%2FG3b0j7qwIhAN07kguKOB02FN84%2FyF4WmseLQy4GnRRF7TRFzGOtzrPKvwECPn%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwEQARoMNjk5NzUzMzA5NzA1IgyVVKadHpG6sEZz7%2FQq0AREoA0NIpGgXfKG%2BORcC2etaCugYPlSqZeR8Co2oCan0KFqMdaJ2tPVLJC7htBS90Oo3dZDOnB5uwjR3Hhhx%2BCYmzK9gzmc9%2F6zl%2FgIQq3S0T1LF6GA%2FoEQGS6ZCL%2FuFQXTluMu%2FBjMFNgc5Tnrhfpxqw9XLB7MH9t0y2B1US7WqtyqdOparB%2Br9sDrurnQmqD%2BhLO5LBQbqMrq4FQ6iFsHMzqU9kcU32BLgV6csAVzrBTfs1pJ2UfBFKsRpxd7niZOhLsUBOMjh%2BuhfEODBczxSrbNVSb3MytdVj%2FqBZpUbE3meEZj9IZqxw4PVkG3VWx4uu6m3NUsENdvBFOtbcHkGe%2FBFjqVgTVnRGxGtimAfB7wOyfioeKy2W9aE6eEINlWrGZk6JFIFa11tEsPDLbSngei31rt6gcc2aY6xdKpQrtkWV%2BuOMMw0IyT7EcDXVpkD2LJxUWDYVkiUrBQmGJBEN%2FgQzR4HfxTUbbDX5cfgIWGV2082XI5PKyNekpfrt3zpgPk9U98CxK6iEuut56bq2LKknTye%2B4ywcsE4EkUhIfy9BRnSIwTdO8QSM%2BiuG1yz4Dsp%2FRe37GDaA5nfIHXborqweOc5y4prhEFVXySeuMACOC89XmdEw9QjRZK6pN5R2%2FfgMwXhPQfpDicIG4E%2FMOfWoeDh9hjTWon5%2BYVzhnt9Jpvhc%2FMe1Oc%2BGolrcsAG5QMWbLIyvGSiFaB6IkiuBa7vHjYZHiVuu5jSxPcmNNV0dQFEhGdYUIhfkTPmBEpldh7gdQp77dD3MofOPEeMKP0n84GOpcBRHl3epEIWFlOz58PxOgtFkJ5AnRbi6Nprqoj%2FnWIHBbLO%2FFiuKQHljRrNYON9CitAsdvRkM5kfRbF6bPjhwbn%2BCDO6Vr87pQWQMztSq%2FZfnDNclvwoVYsgTRnAc4fY2xDbD1nTIwlWJN7yfy5FwVHAgwxtcKgN%2B8Q5vmR0WcPecDFxOU8DG4iAOApe%2BXIbWseL53lYH0Fw%3D%3D&Expires=1774716442
[5] Claude Code vs Pi Agent — Feature Comparison - GitHub https://github.com/disler/pi-vs-claude-code/blob/main/COMPARISON.md
[6] THEME.md - disler/pi-vs-claude-code - GitHub https://github.com/disler/pi-vs-claude-code/blob/main/THEME.md
[7] This is a very useful breakdown between Pi and OpenCode. https ... https://www.facebook.com/groups/1292754479356753/posts/1317300730235461/
[8] I built a small tool to review Claude Code plans like a GitHub PR https://www.reddit.com/r/ClaudeCode/comments/1rmv4el/i_built_a_small_tool_to_review_claude_code_plans/
[9] mariozechner/pi-coding-agent - NPM https://www.npmjs.com/package/@mariozechner/pi-coding-agent
[10] Plan Mode Diffs: Track all changes Claude Code makes to plans https://www.reddit.com/r/ClaudeAI/comments/1rcq4hz/plan_mode_diffs_track_all_changes_claude_code/
[11] How to Build a Custom Agent Framework with PI - Nader's Thoughts https://nader.substack.com/p/how-to-build-a-custom-agent-framework
[12] Packages - pi.dev - Pi Coding Agent https://shittycodingagent.ai/packages
[13] Which terminal coding agent wins in 2026: Pi (minimal + big model ... https://www.reddit.com/r/GithubCopilot/comments/1rpjq4l/which_terminal_coding_agent_wins_in_2026_pi/
[14] I built a tool that makes Claude Code's plans get reviewed by a rival ... https://www.reddit.com/r/ClaudeAI/comments/1rhaplu/i_built_a_tool_that_makes_claude_codes_plans_get/
[15] The Pi Coding Agent: The ONLY REAL Claude Code COMPETITOR https://www.youtube.com/watch?v=f8cfH5XX-XU
[16] Is there a plan to extend super claude with features of claude flow ... https://github.com/orgs/SuperClaude-Org/discussions/247
