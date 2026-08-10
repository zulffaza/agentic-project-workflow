---
description: Break approved analysis into PLAN.md + task files
args: <project-slug>
---
Invoke the `project-workflow` skill. Arguments: {{ARGS}} (project slug).

Project dir: `{{PW_PROJECTS}}/<slug>`.

First check the analysis gate: look for an `approved ✅` sign-off row in any
`<project>/analysis/review/*.review.md`. If none, STOP and ask me to approve the analysis first.

Then produce, from `{{PW_HOME}}/template/task/`:
1. `<project>/task/PLAN.md` (from `_TEMPLATE-orchestration-plan.md`) — repo manifest as
   **`(repo, base branch)` pairs** (a repo may appear on **multiple rows** if tasks target different
   base branches, e.g. `master` and `spring3` — that's a normal case, not adoption-only), global
   rules, **breakdown rules / execution routing**, dependency DAG, and the task table
   **including the Execute with column and clickable `[T0n](./T0n.md)` links**. Fill **Produced
   by:** with the provider you (this breakdown agent) are running under — that becomes the
   **default execution provider** for every task (see routing).
2. One `<project>/task/T01.md … Tnn.md` per task (from `_TEMPLATE-task.md`), each self-contained,
   with its **`Repo:` + `Base branch:`** set (the base the task forks from — two tasks in the same
   repo may declare different bases, e.g. `master` vs `spring3`), a runnable `## Verify` block, an
   `Execute with: <provider>:<model-or-agent>` + `Why:`, a **`Story points:`** estimate, optional
   **`Effort:`**/**`Thinking:`**, and an empty `## Result` block.
   - **Default the provider to "Produced by"** (this agent) so I don't have to switch agents;
     only route a task elsewhere when it genuinely needs a stronger/cheaper/open-weight model, and
     justify it in `Why:`. Fold in any custom routing I gave ("run the mechanical bumps in
     KiloCode", "T03 → opus"). Resolve providers via `{{PW_HOME}}/tooling/docs/providers.md`. **Pin the
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
dependency edge.

**Adopted units present?** If the dashboard has an `Adopted:` note (from `/pw-adopt`; the units are
in `context/ADOPTED.md`), read every adopted unit `(repo, branch, base)` and route **per task** —
this works whether the project is pure-continuation OR a **mixed** project (`/pw-new` fresh tasks
plus adopted branches folded in with `/pw-adopt`; see the WORKFLOW "mixed projects" note):
- A task that **extends an adopted unit** (touches that unit's repo *and* belongs to that
  in-progress branch's work) → set its `Branch:` to that **adopted branch** (not a new `agent/…`
  branch); it will continue-on-that-branch.
- Every **other** task → a normal fresh `Branch: agent/<slug>/<Tid>-…` forked from its `Base branch:`.

State the routing in PLAN's global rules. If any task is adopted, add "**adopted branches:
per-branch serial; cross-branch parallel; fresh tasks independent**". Then shape the DAG: tasks
sharing the **same** adopted branch get a **linear dependency chain** (one shared worktree → must
run in sequence); tasks on **different** adopted branches, and all fresh tasks, stay independent and
run in parallel. Split into tasks for reviewability as usual; adopted tasks' changes extend the
existing branch (and its MR, if any), fresh tasks open new branches.

Then, **create the PLAN review file (idempotent)** — never hand-write it:
```bash
{{PW_HOME}}/tooling/pw-lib.sh review-init <slug> task/review/PLAN.review.md task/PLAN.md
```
No-ops if it already exists; otherwise creates it verbatim from the template so I don't have to
copy it myself.

Then **MANDATORY final step — do NOT skip** — update status + log via the helper
(never hand-edit the Status line), and confirm the dashboard now shows `Status: breakdown`:
```bash
{{PW_HOME}}/tooling/pw-lib.sh status <slug> breakdown
{{PW_HOME}}/tooling/pw-lib.sh log <slug> breakdown "wrote PLAN.md + N task files (ΣSP=<n>)"
```

Stop and summarize the plan + task list (chosen provider:model per task, SP, and the total manual
estimate: person-days + critical-path days). Remind me that **only the PLAN review gates execution**
— `task/review/PLAN.review.md` is already there for me; I just add items and sign off before
`/pw-execute`. **Per-task reviews are optional** (`task/review/T0n.review.md`) — created on demand
only if I send a specific task back.
