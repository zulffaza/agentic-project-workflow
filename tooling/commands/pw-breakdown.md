---
description: Break approved analysis into PLAN.md + task files
args: <project-slug>
---
Invoke the `project-workflow` skill. Arguments: {{ARGS}} (project slug).

Project dir: `{{PW_PROJECTS}}/<slug>`.

First check the analysis gate — **per analysis doc, its CURRENT Sign-off decision, not "was it
ever approved":** for each real `<project>/analysis/<topic>.md`, run
`{{PW_HOME}}/tooling/pw-lib.sh review gate <slug> analysis/review/<topic>.review.md` (the file
doesn't exist yet → treat as not approved). If it exits non-zero for **any** topic, STOP and ask me
to (re-)approve that analysis first — quote the decision it printed (`in-review` or
`changes-requested`). **Do not fall back to scanning the file for an `approved ✅` string anywhere
in its history** — a doc reopened after approval (e.g. an RFC comment folded back in post-approval,
see [`docs/RFC.md`](../../docs/RFC.md)) still has an old approved row sitting earlier in the same
file; `review gate` deliberately reads only the table's current/last row so a stale historical
approval can never satisfy this gate on its own. This is also why a *folded-in* RFC comment doesn't
need its own separate approval concept: once folded in, it reopens *this exact* gate, and your
fresh `approved ✅` here is what unblocks breakdown. That reopen only fires retroactively, though —
it says nothing about a comment that's been pulled but never folded in. That gap is the third check
below, a genuinely separate mechanism from this Sign-off read.

**Third check — an open RFC negotiation blocks breakdown outright:** run
`{{PW_HOME}}/tooling/pw-lib.sh review has-open <slug> analysis/review/RFC.review.md`. If it prints
`yes` (exit 0), STOP — do not produce `PLAN.md` or any task file, even if the analysis Sign-off
above reads `approved ✅`. Tell me which item(s) are still 🔴 open/⏳ awaiting-answer in that file
and that I need to either fold each one into the analysis via `/pw-review` (which reopens the
analysis gate above until re-approved) or resolve it directly in the review file myself, then
re-run `/pw-breakdown`. This closes the gap where analysis got approved on its own merits while a
live external RFC comment thread is still sitting unresolved — see
[`docs/RFC.md`](../../docs/RFC.md). A missing `RFC.review.md` (no RFC side-loop ever used, or no
comments pulled yet) prints `no`/exits 1 — not an error, nothing to block on.

**Second check, per analysis doc — a chosen approach, not just approval:** read that doc's §4.
If it lists 2+ options, `**Chosen approach:**` must be filled in (not `_pending your review_`). If
it's still pending, STOP and ask me to answer `Q0` in the review file first — **even if Sign-off
already reads `approved ✅`**, since approving without choosing leaves nothing concrete to build a
plan from. Build the PLAN and every task **only from the chosen option** — unchosen ones stay in
the doc as record; never implement them, even partially "just in case."

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
   - **Picking a kilo or opencode model: query the live catalog, never recall/guess an id from
     memory.** A plausible-looking id can simply not exist, or its display name can differ from
     the real id.
     ```bash
     kilo models <api-provider>      # once per entry in PW_KILO_API_PROVIDERS (pw.config.sh)
     opencode models                 # opencode manages its own provider config internally
     ```
     Pick the id from that actual output. Claude has no live catalog — its fixed alias set is
     already fully documented in `{{PW_HOME}}/tooling/docs/providers.md`.
   - **Before finalizing each task's `Execute with:`**, check the chosen model against the
     project's model allowlist (empty/unset = every model is allowed, the default — see
     `pw.config.sh`):
     ```bash
     {{PW_HOME}}/tooling/pw-lib.sh model-check <provider> <model-id>
     ```
     If it refuses, pick a different allowed model for that task rather than writing one the
     allowlist excludes — don't silently override it.
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
