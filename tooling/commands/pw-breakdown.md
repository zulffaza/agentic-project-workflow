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
   rules, **breakdown rules / execution routing** (fold in any custom routing I gave, e.g. "run
   the mechanical bumps in KiloCode", "T03 → opus"), dependency DAG, and the task table
   **including the Execute with column and clickable `[T0n](./T0n.md)` links**.
2. One `<project>/task/T01.md … Tnn.md` per task (from `_TEMPLATE-task.md`), each self-contained,
   with a runnable `## Verify` block, an `Execute with: <provider>:<model-or-agent>` + `Why:`, a
   **`Story points:`** estimate, optional **`Effort:`**/**`Thinking:`**, and an empty `## Result`
   block. `Execute with:` resolves to a provider CLI via `{{PW_HOME}}/tooling/providers.md` (Claude
   models → Claude Code, open-weight → KiloCode, extendable). **Pin the Claude version** (full name
   like `claude-opus-4-8`, not the moving `opus` alias) on risky/reproducibility-sensitive tasks,
   and set `Effort:` higher for complex ones.
3. **Estimate manual effort/timeline** (`2 SP = 1 person-day`): give each task a story-point value
   in the task table's `SP` column, then fill PLAN's "## Manual-execution estimate" — total SP,
   sequential person-days (ΣSP÷2), and critical-path calendar days (ΣSP along the longest
   dependency chain ÷2). This is the *manual* estimate for planning; agent execution is faster.

Size each task as one worktree / one reviewable unit. Split anything needing two repos and add a
dependency edge. Then update status + log via the helper (don't hand-edit):
```bash
{{PW_HOME}}/tooling/pw-lib.sh status <slug> breakdown
{{PW_HOME}}/tooling/pw-lib.sh log <slug> breakdown "wrote PLAN.md + N task files (ΣSP=<n>)"
```

Stop and summarize the plan + task list (chosen provider:model per task, SP, and the total manual
estimate: person-days + critical-path days). Remind me to review via `task/review/PLAN.review.md`
(and `task/review/T0n.review.md`) and approve before `/pw-execute`.
