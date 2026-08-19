# Breakdown phase (`/pw-breakdown`)

Asked to break analysis into tasks — refuses unless **every** real `analysis/<topic>.md`'s review
file has an `approved` sign-off (see `references/review.md`) — a project may have more than one
analysis doc (large, mostly-independent solution areas analyzed separately; see the analysis
template's "MULTIPLE LARGE SOLUTION AREAS" note). Once all are approved, produce **ONE merged**
PLAN + task set spanning every analysis doc — never one PLAN per doc:

1. **`task/PLAN.md`** (from `_TEMPLATE-orchestration-plan.md`) — repo manifest, global rules,
   **Produced by** (the provider this breakdown ran under = default execution provider), the
   dependency DAG, and the task table. **This is what the executor reads first.**
2. **`task/T01.md … Tnn.md`** (from `_TEMPLATE-task.md`) — each **self-contained** (one repo, one
   branch, one worktree, linked context, a runnable `## Verify` block = its Definition of Done).
   Write **DETAILED `## Steps`** (exact file + exact change + exact command per step) so the
   executor needs minimal independent reasoning — cheaper, more reliable. **The only thinking left
   to the executor is debugging why a given step didn't work, never deciding what a step should
   do.** Once Steps would run past ~8-10 flat items, split into named `### A.`/`### B.`/… phase
   sub-headings with continuous numbering (see `_TEMPLATE-task.md`'s sub-sectioning note). **Default
   each task's provider to "Produced by"** so the human isn't forced to switch agents; only route
   elsewhere with a `Why:`. See `references/execution-and-routing.md` for the full
   model/provider-routing rules that apply when filling in `Execute with:`.

**Last step, mandatory:** `pw-lib.sh status <slug> breakdown` + a `pw-lib.sh log` line (see
`references/conventions-and-gotchas.md`). Remind the human that **only the PLAN sign-off gates
execution** — per-task reviews (`task/review/T0n.review.md`) are optional, created on demand.
