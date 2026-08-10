# Breakdown phase (`/pw-breakdown`)

Asked to break analysis into tasks — refuses unless the analysis review file has an `approved ✅`
sign-off (see `references/review.md`). Once approved, produce:

1. **`task/PLAN.md`** (from `_TEMPLATE-orchestration-plan.md`) — repo manifest, global rules,
   **Produced by** (the provider this breakdown ran under = default execution provider), the
   dependency DAG, and the task table. **This is what the executor reads first.**
2. **`task/T01.md … Tnn.md`** (from `_TEMPLATE-task.md`) — each **self-contained** (one repo, one
   branch, one worktree, linked context, a runnable `## Verify` block = its Definition of Done).
   Write **DETAILED `## Steps`** (exact file + exact change + exact command per step) so the
   executor needs minimal independent reasoning — cheaper, more reliable. **Default each task's
   provider to "Produced by"** so the human isn't forced to switch agents; only route elsewhere
   with a `Why:`. See `references/execution-and-routing.md` for the full model/provider-routing
   rules that apply when filling in `Execute with:`.

**Last step, mandatory:** `pw-lib.sh status <slug> breakdown` + a `pw-lib.sh log` line (see
`references/conventions-and-gotchas.md`). Remind the human that **only the PLAN sign-off gates
execution** — per-task reviews (`task/review/T0n.review.md`) are optional, created on demand.
