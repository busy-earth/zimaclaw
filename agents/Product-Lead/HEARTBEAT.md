# HEARTBEAT.md — ticket playbooks

These instructions were previously tracked as recurring Paperclip issues (standing monitoring / hygiene loops). They are captured here so each agent has a local `HEARTBEAT.md` alongside `AGENTS.md`.

_Exported from `paperclip-20260401-210446.sql`._

---

### BUS-25 — Product Lead heartbeat: monitor team workload and blockers

_Sourced from Paperclip DB export `paperclip-20260401-210446.sql` (assignee agent id `849c10a9-1f96-4a4e-9c66-ed9c50573956`)._ 

Board direction: now that your current tasks are complete, establish and run a repeatable heartbeat routine to monitor team execution flow.

Scope:
1. Review assigned work each heartbeat (todo/in_progress/blocked) across Architect, Founding Engineer, and Product Lead.
2. Verify each person has clear next work based on Linear tickets, branch progress, commits, and PR state.
3. Identify blockers early, add concise status comments with links, and escalate to CEO only when needed.
4. If someone becomes idle and backlog work exists, create or recommend role-aligned next tasks immediately.

Deliverables:
- Post a short monitoring report comment on this issue with current workload map + blockers + next assignments.
- Create/update a simple checklist artifact for your own future heartbeat runs so this becomes consistent.

### BUS-28 — Linear hygiene heartbeat: hourly sync + daily CEO report

_Sourced from Paperclip DB export `paperclip-20260401-210446.sql` (assignee agent id `849c10a9-1f96-4a4e-9c66-ed9c50573956`)._ 

Maintain a lightweight but repeatable board hygiene cadence so status/ownership stays current without CEO intervention.

Cadence:
- Hourly: reconcile open issues (`todo`, `in_progress`, `blocked`, `in_review`) with real execution state.
- Hourly: ensure each active engineering thread includes current branch and PR references where applicable.
- Hourly: if any issue is blocked, tag the explicit unblock owner in-thread.
- Daily: post a concise board-health report to CEO with drift fixes and outstanding risks.

Acceptance criteria:
- Open issue statuses/owners stay aligned with active execution runs.
- Branch/PR references are present on active implementation tickets.
- CEO receives a daily board-health summary comment.

### BUS-40 — Root-cause fix: Product Lead idle-to-assignment loop

_Sourced from Paperclip DB export `paperclip-20260401-210446.sql` (assignee agent id `849c10a9-1f96-4a4e-9c66-ed9c50573956`)._ 

Board escalation indicates a staffing-gap root cause: engineers can become briefly idle without immediate task handoff despite active roadmap work.

Validated facts:
- Product Lead does have ticket assignment permission (`access.canAssignTasks=true`, source=`explicit_grant` with `tasks:assign`).
- The gap is operational scope/cadence, not permission: active loop [BUS-28](/BUS/issues/BUS-28) is currently focused on Linear hygiene and status drift, but it does not explicitly require immediate idle-engineer assignment handoff.

Required fix:
1. Add explicit idle coverage to the Product Lead heartbeat loop:
   - On each heartbeat, check Architect + Founding Engineer for open assigned work (`todo`,`in_progress`,`blocked`,`in_review`).
   - If an engineer has no active work and backlog/queued implementation exists, assign a next task within the same heartbeat.
2. Route assignment requests to Product Lead directly:
   - If an engineer reports no work, Product Lead owns assignment response first; escalate to CEO only if no suitable task exists.
3. Add execution evidence in-thread each run:
   - Current workload map.
   - Any assignment decisions made.
   - Explicit blocker owner when no assignment can be made.
4. Immediate action item:
   - Resolve current assignment gap represented by [BUS-38](/BUS/issues/BUS-38) and confirm Founding Engineer has a concrete next implementation task.

Acceptance criteria:
- Product Lead posts an update confirming the loop changes and first run evidence.
- Founding Engineer is no longer idle without a next owned task.
- Escalation path is explicit when no suitable task exists.

Context links:
- Escalation source: [BUS-37](/BUS/issues/BUS-37)
- Current hygiene loop: [BUS-28](/BUS/issues/BUS-28)
- Current assignment gap ticket: [BUS-38](/BUS/issues/BUS-38)

