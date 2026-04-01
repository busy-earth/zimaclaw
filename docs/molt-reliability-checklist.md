# Molt Reliability Checklist and Failure Budget

This is the reliability contract for the current Molt vertical slice.
Use it in PR review and release checks.

## Scope

- Fang issue store (`src/fang.zig`)
- Drive Pi boundary (`src/drive.zig`)
- Steer Emacs boundary (`src/steer.zig`)
- Spine event stream (`src/spine.zig`)
- End-to-end Molt flow (`src/claw.zig`)

## Failure Classes and Required State Transitions

The run must always finish in one of two states:
- `review` (success path)
- `failed` (any controlled failure path)

Expected mapping:

| Failure class | Source | Expected transition | Evidence |
| --- | --- | --- | --- |
| Drive binary missing or spawn fails | `DriveError` | `executing -> failed` | `tests/drive_test.zig`, `tests/molt_run_test.zig` |
| Drive protocol/response invalid | `DriveError` | `executing -> failed` | `tests/drive_test.zig` (unit), integration path covered by `failRun` in `src/claw.zig` |
| Steer unavailable/non-zero | `steer.FailureKind` | `executing -> failed` | `tests/steer_test.zig`, `tests/molt_run_test.zig` |
| No failure in Drive + Steer | success path | `executing -> review` | `tests/molt_run_test.zig` |

## 5-Minute PR Reliability Checklist

Mark each item in the PR description or review notes.

- [ ] **State safety:** run only ends in `review` or `failed`; no silent terminal state.
- [ ] **Failure typing:** Drive/Steer failures stay structured (no string-only errors).
- [ ] **Retry policy:** no hidden retry loops; behavior is deterministic and explicit.
- [ ] **Cleanup:** child process pipes/process are closed/waited on each exit path.
- [ ] **Observability:** Spine emits ordered events and writes JSONL trail.
- [ ] **Artifact linkage:** issue stores `execution_artifact` for both success and failure.
- [ ] **Tests:** `zig build test` passes on the branch.
- [ ] **Known gaps:** any uncovered rule is called out with owner + follow-up ticket.

## Reliability Rules with Test/Gaps Map

Every rule below has direct evidence in tests or an explicit known gap.

| Rule ID | Rule | Component | State impact | Evidence today |
| --- | --- | --- | --- | --- |
| R1 | New issues start in `inbox` with stable file path | Fang | pre-run correctness | `tests/fang_test.zig` |
| R2 | Transition writes new state + timestamp | Fang | `inbox/executing/review/failed` integrity | `tests/fang_test.zig` |
| R3 | Run always moves issue to `executing` before external calls | Claw/Fang | deterministic start | `src/claw.zig` implementation; covered indirectly by `tests/molt_run_test.zig` |
| R4 | Drive request/response is JSONL and typed | Drive | avoids unknown intermediate state | `tests/drive_jsonl_test.zig`, `tests/drive_test.zig` |
| R5 | Drive failures are explicit (`PiUnavailable`, `InvalidResponse`, etc.) | Drive | `executing -> failed` via `failRun` | `tests/drive_test.zig` |
| R6 | Steer unavailable is explicit typed failure | Steer | `executing -> failed` via `failRun` | `tests/steer_test.zig`, `tests/molt_run_test.zig` |
| R7 | Success path emits `run_finished` and lands in `review` | Claw/Spine | `executing -> review` | `tests/molt_run_test.zig` |
| R8 | Failure path emits `run_failed` and lands in `failed` | Claw/Spine | `executing -> failed` | `tests/molt_run_test.zig` |
| R9 | Event stream ordering is stable and persisted as JSONL | Spine | observability | `tests/spine_test.zig`, `tests/molt_run_test.zig` |
| R10 | Drive retries are explicit and bounded | Drive | prevents hidden loops | **Known gap:** no retry support yet (intentional for Molt v1) |
| R11 | Steer retries are explicit and bounded | Steer | prevents hidden loops | **Known gap:** no retry support yet (intentional for Molt v1) |
| R12 | Cleanup behavior is tested across all failure exits | Drive/Steer | prevents leaked child processes | **Known gap:** no dedicated cleanup assertions in tests yet |
| R13 | Storage/event write failures fail closed to `failed` | Fang/Spine/Claw | prevents stuck `executing` | **Known gap:** no explicit fail-closed test for disk write errors |

## Failure-Budget Policy (Molt Loop)

This keeps shipping decisions strict but simple.

- **Budget A — Silent failures:** `0` allowed.
  - Definition: process exits/crashes and issue does not end in `review` or `failed`.
- **Budget B — Unknown failure classes:** `0` allowed.
  - Definition: failure without typed class (`DriveError` / `FailureKind`) and run-failure event.
- **Budget C — Open P0 reliability gaps:** `0` allowed.
  - P0 means state safety or observability can break (`R13` category).
- **Budget D — Open P1 reliability gaps:** up to `2` allowed, each with owner + linked follow-up ticket.
  - Current P1 examples: `R10`, `R11`, `R12`.

If any budget is exceeded, release is **no-go**.

## Go / No-Go Criteria for Next Slice

Ship only when all conditions are true:

1. `zig build test` is green.
2. No budget overrun from the failure-budget policy above.
3. PR review checklist is fully completed.
4. Remaining gaps are documented with owner + concrete follow-up.

Do not ship when any condition below is true:

- Issue can get stuck in `executing` after terminal failure.
- `run_failed`/`run_finished` events are missing from the run trail.
- `execution_artifact` is missing on either success or failure path.
- A known gap has no owner or no planned follow-up.
