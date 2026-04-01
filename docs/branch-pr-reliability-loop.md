# Branch/PR Reliability Loop

Use this loop before opening or updating a pull request. It is deterministic and safe to repeat.

## 1) Branch naming standard

Required format:

`feature/<ticket-id>_<short_snake_case_name>`

Examples:
- `feature/BUS-35_branch_pr_reliability_loop`
- `feature/BE-42_auth_session_refresh`

If your branch does not follow this format, create a new branch with the correct name before continuing.

## 2) Deterministic command flow

Run these commands in order from repo root:

```bash
git fetch --prune
git status --short --branch
git rev-list --left-right --count origin/main...HEAD
git rev-list --left-right --count @{upstream}...HEAD
./scripts/bootstrap-zig.sh && export PATH="$PWD/.toolchain/zig/current:$PATH"
zig build test --summary all
gh pr status
```

What each command validates:
- `git fetch --prune`: local refs are fresh.
- `git status --short --branch`: working tree cleanliness and current branch.
- `origin/main...HEAD`: whether your branch is stale vs main.
- `@{upstream}...HEAD`: whether local and remote branch are in sync.
- bootstrap + test: pinned toolchain + test gate.
- `gh pr status`: branch/PR state and review readiness.

## 3) Verification checklist (copy/paste)

- [ ] Branch name follows `feature/<ticket-id>_<short_snake_case_name>`.
- [ ] `git status --short` is clean before push (or all changes are intentionally staged/committed).
- [ ] `origin/main...HEAD` left side is `0` (not behind main).
- [ ] `@{upstream}...HEAD` is `0 0` after push.
- [ ] `zig build test --summary all` succeeds.
- [ ] `gh pr status` shows the expected open PR state.
- [ ] PR body includes test evidence and linked ticket.

## 4) First self-healing path: missing Zig toolchain

Symptom:
- `zig: command not found`

Recovery:

```bash
./scripts/bootstrap-zig.sh
export PATH="$PWD/.toolchain/zig/current:$PATH"
zig version
zig build test --summary all
```

Retry policy:
- Retry once after bootstrap.
- If test still fails, do not keep retrying blindly.

Escalation path:
- If bootstrap or tests keep failing after one clean retry, assign/escalate to DevOps with:
  - failing command
  - full error output
  - current branch and commit SHA
  - whether this blocks release or only local progress

## 5) Reliability risks this loop is designed to catch

- Stale branch behind `main`.
- Dirty working tree causing accidental mixed commits.
- Local/remote branch drift.
- Missing toolchain in local environment.
- Missing PR readiness evidence.
