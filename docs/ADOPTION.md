# Adoption — the continuation workflow (`/pw-adopt`)

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) ·
[Execution & routing](./EXECUTION.md) · [Review & feedback](./REVIEW.md)

Most projects start empty with `/pw-new`. **Adoption** is the other on-ramp: work is **already
underway on real branches** (with or without an MR) and you want to finish it *through* the pipeline
instead of by hand. Everything from analysis onward — the gates, review flow, `/pw-sync`,
`/pw-close` — is identical to a fresh project; only the branch/worktree/ship mechanics differ.

```
/pw-new    → empty context/, build from scratch in fresh agent/… branches
/pw-adopt  → snapshot existing branch(es), continue them ON THE SAME branch
```

## Adoption is a *context* action, with two intents

`ADOPTED.md` lives in `context/` for a reason: adopting a branch **adds to the baseline** that
analysis reasons from. So adoption is only meaningful at two moments — never as a way to park in a
mid-pipeline phase. The trailing `review` keyword picks the intent:

| Intent | Command | Lands at | For |
|---|---|---|---|
| **Continue development** (default) | `/pw-adopt <slug> <repo> <branch> [mr]` | `context` | the branch needs *more work* → analyze → breakdown → execute → ship the **remaining** work |
| **Review-only** | `/pw-adopt <slug> <repo> <branch> <mr> review` | `review` | branch is **done + already has an MR** → just service MR comments (`/pw-ship … comments`, `/pw-sync`); skips analyze/breakdown |

**Phase guard:**
- Adopting into a **`done`** (closed) project is refused — reopen it deliberately first.
- A **continue-dev** adopt onto a project **already past `context`** records the unit but **does not
  rewind `Status`** (that would falsely imply the in-flight units regressed). It warns you to re-run
  `/pw-analyze` + `/pw-breakdown` to fold the newcomer in.
- Adoption never lands the project in `analysis` / `breakdown` / `executing` — those aren't entry
  points, only phases the pipeline moves *through*.

## Adopt one branch, or many

An **adoption unit** is a tuple `(repo, in-progress-branch, [mr])`. Run `/pw-adopt` **once per
in-progress branch** — multi-repo work already in flight = several units:

```bash
/pw-adopt my-project repo-a feat-a https://…/mr/42     # unit A1 (has an MR)
/pw-adopt my-project repo-b feat-b                      # unit A2 (no MR yet)
```

Each run:
1. **Resolves the base** from the MR's target branch (GitLab `glab mr view … .target_branch`, GitHub
   `gh pr view --json baseRefName`). No MR → best-effort infer + **flag it unconfirmed** for you to
   verify.
2. **Snapshots** what that branch already did (commits + diff vs its base) into `context/ADOPTED.md`.
3. **Records the unit deterministically** (`pw-lib.sh adopt`) — appends a new unit, or updates an
   existing `repo@branch` in place. It also maintains the `context/INDEX.md` rows (a one-time generic
   `ADOPTED.md` provenance row + one `(repo, base)` "Repos in scope" row per unit). **Adopting the
   Nth branch never clobbers the earlier ones** — that determinism is the whole point; don't
   hand-edit `ADOPTED.md` or those `INDEX.md` rows.

Then fill each unit's `### Remaining work` in `ADOPTED.md` and continue at `/pw-analyze` — analysis
reads `ADOPTED.md` + each unit's existing diff as the baseline and proposes only the *remaining*
changes.

## The two rules that follow from adopting real branches

- **Continue-on-the-same-branch** — a task that extends an adopted unit commits onto the **existing**
  branch (and its MR, if any); no fresh `agent/…` branch for that task.
- **Serialization is per-branch** — tasks on the *same* adopted branch run **serially** in that
  branch's one shared worktree; tasks on *different* adopted branches are independent and run **in
  parallel**. Multiple units keep cross-unit parallelism while staying continue-on within a unit.

## Fresh vs. continuation, side by side

| | Fresh (`/pw-new`) | Continuation (`/pw-adopt`) |
|---|---|---|
| Branches | new `agent/<slug>/T0n` per task | your existing branch(es) |
| Worktrees | one per task, all parallel | one per adopted branch; serial within, parallel across |
| Ship | opens new MRs | updates an existing MR if present, else opens one |
| Analysis baseline | just `context/` | `context/` + each unit's existing diff (proposes only *remaining* work) |

Worktree mechanics for adopted branches (attach the existing branch, no `-b`):
[Execution → multi-repo worktrees](./EXECUTION.md#multi-repo-worktrees--how).

## Mixed projects — fold a branch into an existing project

`/pw-adopt` is **not** only a way to *start* a project. Run it against a slug that already exists —
one you began with `/pw-new`, or one that already has adopted units — to **fold an in-progress
branch into it**. If the project dir exists, `/pw-adopt` skips scaffolding and just appends the unit,
so the fresh tasks and earlier units are untouched.

The result is a **mixed project**, and adoption is then decided **per task/branch, not per project**:

- A task that **extends an adopted unit's branch** → continues on that branch (no new `agent/…`
  branch), shares that branch's one worktree, runs **serially** with its branch-mates.
- Every **other** task → a fresh `agent/<slug>/T0n` branch forked from its `Base branch:`, its own
  worktree, parallel as usual.

Breakdown reads `context/ADOPTED.md`, routes each task by whether it touches an adopted unit, and the
DAG serializes only within each adopted branch. `/pw-ship` then opens new MRs for the fresh tasks and
updates the existing MR(s) for the adopted branches — in the same shipment.

> **When to keep it separate instead:** if the in-progress branch is logically unrelated to what the
> project is already doing, give it its own slug — a tighter review gate and a cleaner dashboard beat
> cramming unrelated work into one project. Mix only when the adopted branch is *part of the same
> change* as the fresh work.

## What changes downstream (continue-dev intent)

Review-only adopts skip breakdown/execution entirely — they go straight to `/pw-ship … comments`.
For continue-dev, the differences vs a fresh project are:

- **Breakdown** — a task extending an adopted unit gets `Branch:` = that adopted branch (not a new
  `agent/…` branch); every other task gets a fresh `agent/…` branch off its base. Tasks sharing an
  adopted branch form a **linear dependency chain**; different adopted branches and all fresh tasks
  stay independent.
- **Execution** — adopted-branch tasks share **one worktree per adopted branch**, attaching the
  existing branch. Serial within a branch, parallel across branches and fresh tasks.
- **Ship** — each adopted branch is **one shipment**: `/pw-ship` updates its existing MR (no
  duplicate) or opens one. `/pw-sync` and `/pw-ship … comments` work as normal.

Full command detail: [`tooling/commands/pw-adopt.md`](../tooling/commands/pw-adopt.md).
