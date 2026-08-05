---
description: Break approved analysis into PLAN.md + task files
args: <project-slug>
---
Invoke the `project-workflow` skill. Arguments: {{ARGS}} (project slug).

Project dir: `{{PW_PROJECTS}}/<slug>`.

First check the analysis gate: look for an `approved ✅` sign-off row in any
`<project>/analysis/review/*.review.md`. If none, STOP and ask me to approve the analysis first.

Then produce, from `{{PW_HOME}}/template/task/`:
1. `<project>/task/PLAN.md` (from `_TEMPLATE-orchestration-plan.md`) — repo manifest, global
   rules, **breakdown rules / execution routing**, dependency DAG, and the task table
   **including the Execute with column and clickable `[T0n](./T0n.md)` links**. Fill **Produced
   by:** with the provider you (this breakdown agent) are running under — that becomes the
   **default execution provider** for every task (see routing).
2. One `<project>/task/T01.md … Tnn.md` per task (from `_TEMPLATE-task.md`), each self-contained,
   with a runnable `## Verify` block, an `Execute with: <provider>:<model-or-agent>` + `Why:`, a
   **`Story points:`** estimate, optional **`Effort:`**/**`Thinking:`**, and an empty `## Result`
   block.
   - **Default the provider to "Produced by"** (this agent) so I don't have to switch agents;
     only route a task elsewhere when it genuinely needs a stronger/cheaper/open-weight model, and
     justify it in `Why:`. Fold in any custom routing I gave ("run the mechanical bumps in
     KiloCode", "T03 → opus"). Resolve providers via `{{PW_HOME}}/tooling/providers.md`. **Pin the
     Claude version** (full name like `claude-opus-4-8`) on risky tasks; raise `Effort:` for complex ones.
   - **Write DETAILED `## Steps`** — name the exact file, the exact change (before/after snippet or
     literal edit), and the exact command per step, so the executor needs minimal independent
     reasoning (cheaper, more reliable — a small model shouldn't re-derive the work). Any unresolved
     judgement call is a `Q` for analysis/review, not something left to the executor. See the
     level-of-detail example in `_TEMPLATE-task.md`.
3. **Estimate manual effort/timeline** (`2 SP = 1 person-day`): give each task a story-point value
   in the task table's `SP` column, then fill PLAN's "## Manual-execution estimate" — total SP,
   sequential person-days (ΣSP÷2), and critical-path calendar days (ΣSP along the longest
   dependency chain ÷2). This is the *manual* estimate for planning; agent execution is faster.

Size each task as one worktree / one reviewable unit. Split anything needing two repos and add a
dependency edge. Then **MANDATORY final step — do NOT skip** — update status + log via the helper
(never hand-edit the Status line), and confirm the dashboard now shows `Status: breakdown`:
```bash
{{PW_HOME}}/tooling/pw-lib.sh status <slug> breakdown
{{PW_HOME}}/tooling/pw-lib.sh log <slug> breakdown "wrote PLAN.md + N task files (ΣSP=<n>)"
```

Stop and summarize the plan + task list (chosen provider:model per task, SP, and the total manual
estimate: person-days + critical-path days). Remind me that **only the PLAN review gates execution**
— I review + sign off `task/review/PLAN.review.md` before `/pw-execute`. **Per-task reviews are
optional** (`task/review/T0n.review.md`) — I only add one if I want to send a specific task back.
