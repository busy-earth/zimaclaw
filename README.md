# zimaclaw
OpenClaw without the hops

## Molt prototype status

Shipped in this slice:
- `zimaclaw issue create --title ... --prompt ...`
- `zimaclaw issue show <issue-id>`
- `zimaclaw molt run --prompt ...` end-to-end through Fang + Drive + Steer + Spine
- Deterministic issue transitions: `inbox -> executing -> review|failed`
- JSONL event trail persisted at `.zimaclaw/issues/<issue-id>/events.jsonl`

Still deferred:
- Jaw/XMPP ingress
- Venom simulation flow
- Shell/Web abstractions
- UI/SSE event streaming
