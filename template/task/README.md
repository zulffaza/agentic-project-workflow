# task/ — the "how"

Turns approved analysis into an executable plan. Two kinds of file:

### `PLAN.md` — the orchestration plan  ← **the executor reads this first**
From [`_TEMPLATE-orchestration-plan.md`](./_TEMPLATE-orchestration-plan.md). Carries:
- **Repo manifest** — which sibling repos are touched, base branches.
- **Global rules** — branch naming, commit convention, DoD standard, guardrails that apply to
  *every* task (e.g. "don't touch files outside your worktree").
- **Dependency DAG** — task IDs, `depends_on` edges, and which groups run in parallel.

### `T01.md … Tnn.md` — one task each
From [`_TEMPLATE-task.md`](./_TEMPLATE-task.md). Each file is a **self-contained spawnable
prompt**: an agent handed only that one file can do the work. Non-negotiable parts:
- exactly one repo + branch + worktree path,
- links to the specific context/analysis it needs,
- a `## Verify` block with runnable commands and expected result (the Definition of Done).

**Rule of thumb for sizing a task:** one worktree, one branch, one reviewable unit, verifiable in
isolation. If a task needs two repos, split it and add a dependency edge.

**Review:** comment on `PLAN.md` or a task in `review/PLAN.review.md` / `review/T0n.review.md`
(a `review/` subdir here, from `../_REVIEW.template.md`), not inline. To reject an execution
result, add items to `review/T0n.review.md` **and** set that task's `Status: verify-failed` so
it's re-run. See `../README.md` → "Review & feedback".

Files starting with `_` are templates.
