# HEARTBEAT.md — ticket playbooks

These instructions were previously tracked as recurring Paperclip issues (standing monitoring / hygiene loops). They are captured here so each agent has a local `HEARTBEAT.md` alongside `AGENTS.md`.

_Exported from `paperclip-20260401-210446.sql`._

---

### BUS-35 — DevOps: ship deterministic branch/PR reliability loop

_Sourced from Paperclip DB export `paperclip-20260401-210446.sql` (assignee agent id `52de34ae-0687-4593-bf43-c3d6e7d0d1a5`)._ 

Create and run a lightweight reliability loop for branch and PR workflow so engineers can move from intent to merge with low friction and high safety.

Scope (small + executable):
1. Write a concise runbook for deterministic git/PR command patterns (branch naming, rebase/pull flow, pre-push checks, PR readiness checks).
2. Add a repeatable verification checklist focused on reliability risks (conflicts, stale branches, failing checks, missing test evidence).
3. Add one self-healing response path for common failures (what to run, when to retry, when to escalate).

Deliverables:
- Runbook artifact linked in issue comments.
- One heartbeat-style status comment showing first execution of the loop on current active branch(es).
- Explicit list of risks found + mitigation actions.

Acceptance criteria:
- Another engineer can follow the runbook end-to-end without extra guidance.
- Checklist catches at least one real reliability risk or explicitly reports none found with evidence.
- Escalation path is defined for blockers outside DevOps control.

### BUS-47 — DevOps heartbeat: CI/workflow reliability sweep

_Sourced from Paperclip DB export `paperclip-20260401-210446.sql` (assignee agent id `52de34ae-0687-4593-bf43-c3d6e7d0d1a5`)._ 

Own a recurring DevOps reliability loop so engineering execution does not stall between assignments.

Scope:
- Audit all active engineering issues for branch, PR, and CI signal coverage.
- Flag and fix workflow hygiene drift (missing branch refs, missing PR links, stale blocked states) via comments and owner follow-ups.
- Validate branch protection and required checks on active repos touched by current work.
- Escalate any unblock dependency to CEO/Product Lead with explicit owner + next action.

Acceptance criteria:
- Every active engineering issue has current branch/PR/CI references where applicable.
- Any workflow drift is corrected or has a named unblock owner in-thread.
- A concise heartbeat summary comment is posted with findings and actions taken.

