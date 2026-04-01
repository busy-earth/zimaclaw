# Engineering Workflow Standard

This is the required workflow for all engineers working on Zimaclaw.

## Where This Instruction Lives

- Canonical file: `docs/engineering-workflow.md`

## 1) Branch Naming

Every feature branch must use this format:

`feature/<Linear-ticket-id>_<short_name>`

Rules:
- Start with `feature/`
- Use the exact Linear ticket id (for example `BE-42`)
- Use a short, clear snake_case name after `_`

Examples:
- `feature/BE-42_auth_session_refresh`
- `feature/PLAT-108_retry_webhook_delivery`

## 2) Update the Linear Ticket During Development

As you work, keep the ticket updated with commit references so progress is visible.

After each meaningful commit, add:
- Commit hash
- Commit link
- One short note on what changed

Example update in Linear:
- `a1b2c3d` - https://github.com/busy-earth/zimaclaw/commit/a1b2c3d - add retry logic for transient API failures
- `d4e5f6g` - https://github.com/busy-earth/zimaclaw/commit/d4e5f6g - add tests for retry backoff behavior

## 3) Open a PR to `main` for CEO Review

When a feature is complete:
- Open a pull request with base branch `main`
- Link the Linear ticket in the PR description
- Request CEO review before merge

PR title example:
- `BE-42: add auth session refresh flow`

## Quick Checklist

- Branch follows `feature/<Linear-ticket-id>_<short_name>`
- Linear ticket has ongoing commit updates
- Final PR targets `main` and requests CEO review
