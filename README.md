# zimaclaw
OpenClaw without the hops

## Quickstart

Deterministic Zig setup (pinned to `0.12.0`):

```bash
./scripts/bootstrap-zig.sh && export PATH="$PWD/.toolchain/zig/current:$PATH"
```

Run tests:

```bash
zig build test
```

## CI reliability gate

GitHub Actions runs `zig build test --summary all` on pull requests to `main` and pushes to `main`. Failures keep the check red and include full test output in logs.

## Engineering workflow

Required branch/Linear/PR process for all engineers:
- `docs/engineering-workflow.md`
- `docs/branch-pr-reliability-loop.md`
- `docs/new-engineer-onboarding.md`
- `docs/molt-reliability-checklist.md`

## Molt prototype status

Shipped in this slice:
- `zimaclaw issue create --title ... --prompt ...`
- `zimaclaw issue show <issue-id>`
- `zimaclaw molt run --prompt ...` end-to-end through Fang + Drive + Steer + Spine
- Deterministic issue transitions: `inbox -> planned -> executing -> review|failed`
- Explicit review rejection loop: `review -> rejected -> planned`
- JSONL event trail persisted at `.zimaclaw/issues/<issue-id>/events.jsonl`

Still deferred:
- Jaw/XMPP ingress
- Venom simulation flow
- Shell/Web abstractions
- UI/SSE event streaming

