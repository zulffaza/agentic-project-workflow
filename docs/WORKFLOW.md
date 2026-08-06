# The workflow, step by step

← [back to README](../README.md) · related: [Review & feedback](./REVIEW.md) ·
[Execution & routing](./EXECUTION.md) · [Reference](./REFERENCE.md)

The pipeline is nine steps. Each phase writes to its own directory and stops at a **human sign-off
gate** before the next begins — so you review one artifact type at a time, and a stalled run is
resumable because all state lives on disk, not in an agent's head.

| # | Step | Who | Produces | Gate | Command |
|---|------|-----|----------|------|---------|
| 1 | Drop context | You | files in `context/` + a row in `context/INDEX.md` | — | `/pw-new` |
| 2 | Analyze | any agent | `analysis/<topic>.md` + dashboard one-liner | — | `/pw-analyze` |
| 3 | Review analysis | You + agent | `analysis/review/<t>.review.md` + fixes | ✅ analysis approved | `/pw-review` |
| 4 | Break down | any agent | `task/PLAN.md` + `task/T01…Tnn.md` | — | `/pw-breakdown` |
| 5 | Review tasks | You | `task/review/PLAN.review.md` + fixes | ✅ **plan approved (only hard gate)** | `/pw-review` |
| 6 | Execute | Executor agent | commits/branches in `worktree/*` (committed + verified) | per-task DoD | `/pw-execute` |
| 7 | Ship | Executor agent | pushed branches + MRs (rich description) | you confirm the push | `/pw-ship` |
| 8 | Review results | You + agent | accepted tasks (optional `task/review/T0n`) | ✅ you accept each task | `/pw-review` |
| 9 | Learn + close | You + agent | memory (if configured), worktrees torn down, Status→done | — | `/pw-close` |

Keeping an MR up to date after it's open is a side-loop, not a numbered step: **`/pw-sync`** (see
step 7). And you can reopen an earlier phase any time — see [rewind](#going-back-a-phase-rewind).

---

## Step 1 — Context
Put anything the agent needs to reason well into `context/`: PRD/RFC excerpts, ticket text,
relevant code paths, error logs, Slack/Lark threads. Record provenance in `context/INDEX.md` so
later steps (and future-you) know what each file is and can trust it. Prefer links + short excerpts
over dumping huge files. Optionally start a one-page brief — see
[`context/_REQUIREMENTS.template.md`](../template/context/_REQUIREMENTS.template.md) (copy it to
`REQUIREMENTS.md`); it's optional and sharpens the analysis phase.

<a id="adopting-existing-in-progress-work"></a>
### Two ways to start: fresh vs. continuation (`/pw-adopt`)
There are **two entry workflows**, and they differ only at the front:

- **Fresh start** (`/pw-new`) — empty `context/`, build from scratch in isolated `agent/…` branches.
- **Continuation** (`/pw-adopt`) — work is **already underway on real branches** (with or without an
  MR) and you want to finish it *through* the pipeline instead of by hand.

Everything from analysis onward — the gates, review flow, `/pw-sync`, `/pw-close` — is identical.
Only the branch/worktree/ship mechanics differ (below).

**Adopt one branch, or many.** An **adoption unit** is a tuple `(repo, in-progress-branch, [mr])`.
Run `/pw-adopt` **once per in-progress branch** — multi-repo work already in flight = several units.
Each run appends/updates a unit; it never clobbers earlier ones.
```bash
/pw-adopt my-project repo-a feat-a https://…/mr/42     # unit A1 (has an MR)
/pw-adopt my-project repo-b feat-b                      # unit A2 (no MR yet)
```
Each run scaffolds the project (first time), snapshots what that branch already did (commits + diff
vs its base) into `context/ADOPTED.md`, and bumps the dashboard `Adopted:` pointer (set
deterministically via `pw-lib.sh adopted`). Then fill each unit's `## Remaining work` in
`ADOPTED.md` and continue at `/pw-analyze`.

**The two rules that follow from adopting real branches:**
- **Continue-on-the-same-branch** — task commits extend your existing branch (and its MR); no fresh
  `agent/…` branches.
- **Serialization is per-branch** — tasks on the *same* adopted branch run **serially** in that
  branch's one shared worktree; tasks on *different* adopted branches are independent and run **in
  parallel**. So multiple units keep cross-unit parallelism while staying continue-on within a unit.

| | Fresh (`/pw-new`) | Continuation (`/pw-adopt`) |
|---|---|---|
| Branches | new `agent/<slug>/T0n` per task | your existing branch(es) |
| Worktrees | one per task, all parallel | one per adopted branch; serial within, parallel across |
| Ship | opens new MRs | updates an existing MR if present, else opens one |
| Analysis baseline | just `context/` | `context/` + each unit's existing diff (proposes only *remaining* work) |

Full mechanics: the [command](../tooling/commands/pw-adopt.md) ·
[worktree attach](./EXECUTION.md#multi-repo-worktrees--how).

## Step 2–3 — Analysis
Ask any agent to analyze against `context/`. Output goes to `analysis/` using
[`analysis/_TEMPLATE.md`](../template/analysis/_TEMPLATE.md). Analysis answers *what needs to change
and why*, surfaces unknowns/risks, and lists **confirmed** affected repos — it does **not** yet
decide task boundaries. Iterate here until you approve; this is the cheapest place to fix
misunderstandings. You review it via a `.review.md` file — see [Review & feedback](./REVIEW.md).

## Step 4–5 — Task breakdown
Ask any agent to turn approved analysis into a breakdown:

- **`task/PLAN.md`** — the orchestration plan ([template](../template/task/_TEMPLATE-orchestration-plan.md)).
  This is the artifact the executor reads first. It carries the **repo manifest**, **global rules**,
  the **dependency DAG** (which tasks are parallel, which block which), and **Produced by** (the
  provider that ran the breakdown = the default execution provider).
- **`task/T01.md … Tnn.md`** — one file per task ([template](../template/task/_TEMPLATE-task.md)).
  Each is **self-contained** — an agent handed only `T03.md` must be able to do the work: it names
  the repo, branch, files, links to needed context, writes **detailed `## Steps`** (exact file,
  exact change, exact command), and a **Verify / Definition of Done** block.

The **PLAN sign-off is the only hard gate for execution**. Per-task reviews are optional.

## Step 6 — Execution
Hand `task/PLAN.md` to one **orchestrator** agent. It reads the DAG and spawns **executor**
sub-agents — one per task, respecting dependencies. **Same-provider tasks run as native in-process
sub-agents** (easy to monitor); a different-provider task is shelled out to that CLI. Either way the
executor **tees its output to `worktree/<T0n>.log`** so you can `tail -f` a run in your own window.
Each executor works in its **own worktree**, runs the task's `Verify` block, reports the actual
output, and fills the task file's `## Result`. **Execution stops at committed + verified** — it does
*not* push or open MRs.

Full detail on roles, model/agent choice, and cross-provider execution:
[Execution & routing](./EXECUTION.md).

**Rejecting a result** goes through the review loop: flip the task to `Status: verify-failed` and
either add items to `task/review/T0n.review.md` or just tell the agent what's wrong (`/pw-review`
creates the review file from your feedback if it's missing), then re-run that one task. See
[Review & feedback](./REVIEW.md).

<a id="ship-and-sync"></a>
## Step 7 — Ship (`/pw-ship`), and keeping MRs fresh (`/pw-sync`)
Publishing is a **separate, explicit** step so nothing goes outward until you ask. `/pw-ship <slug>
[task-ids]` pushes each verified task's branch and opens an MR with a **rich description** (what &
why, changes, verification output, pinned-version rationale, risk, follow-ups), then records the MR
in the task's `## Result` and the dashboard's **Merge requests** table. It **confirms the push list
with you first**. Zero-change tasks get no branch/MR.

Once MRs are open they drift out of date as their base branches move. **`/pw-sync <slug>
[task-ids]`** brings them all back up to date in one sweep: it merges the latest base into each open
MR's branch, re-runs each task's `Verify`, and pushes — reporting per-task which merged cleanly,
which hit a conflict, and which fail verify after the merge. Review comments left on an MR are a
different loop — see the [MR review flow](./REVIEW.md#the-mr-review-flow-post-ship).

## Step 9 — Learn + close (`/pw-close`)
After the run, `/pw-close` verifies every task is `accepted`, **tears down the worktrees with the
safe helper** ([`pw-teardown.sh`](../tooling/pw-teardown.sh) — refuses to remove the worktree you're
in or a dirty one), captures what changed about the *workflow itself* (not the code — the repos
record that) into the project's "Decisions & learnings" section — and into your memory tool too, if
`PW_MEMORY` names one — sets the dashboard Status → `done`, and summarizes MRs/leftovers.
`accepted` ≠ merged: open/on-hold MRs don't block close-out. It does **not** delete branches or the
project dir.

---

## Who owns the dashboard `Status:` field?
The `/pw-*` commands do — each runs `tooling/pw-lib.sh status <slug> <phase>` as its **mandatory
last step** (analyze→`analysis`, breakdown→`breakdown`, execute→`executing`/`review`, close→`done`).
It is not something you maintain by hand (that's the "why is it still `planned`?" trap), and the
helper validates the phase, **refuses accidental backward moves** (`--rewind` to intend one), and
auto-logs the change to [`LOG.md`](#audit-log--logmd). `/pw-review` never touches Status.

<a id="audit-log--logmd"></a>
## Audit log — `LOG.md`
Every project has a `LOG.md` — an append-only audit trail, one line per meaningful action (phase
transition, sub-agent spawn, commit, push, MR, review pass, close-out), newest at the bottom:
```
YYYY-MM-DD HH:MM | <phase/actor> | <what happened>
```
The `/pw-*` commands append to it via `tooling/pw-lib.sh log …` (deterministic format); you can add
manual notes too. It answers "what did the agents actually do, and when?" without reconstructing it
from chat.

## Going back a phase (rewind)
Phases aren't one-way. To reopen an earlier phase after you've moved on (e.g. breakdown revealed the
analysis was wrong):
1. Add a fresh `🔴 open` item to that phase's review file (`analysis/review/…` or `task/review/…`)
   describing what needs to change, and add a new `in-review` Sign-off row (leave the old
   `approved ✅` row — it's history).
2. Set the dashboard `Status:` back to that phase **with the rewind flag**:
   `tooling/pw-lib.sh status <slug> <phase> --rewind` (a plain `status` refuses to move backward).
3. Re-run the phase command (`/pw-analyze` / `/pw-breakdown`), then `/pw-review`, then re-approve.
Downstream artifacts already produced stay on disk; regenerate them once the upstream phase is
re-approved.
