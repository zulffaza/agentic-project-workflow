---
name: pw-sync
description: Update all of a project's open MR branches — merge the moved base branch into each, re-verify, push
args: "--project <project-slug> [--task <T0n>]… [--auto-resolve]"
scope: project
---

**Load shared guidance first.** Read the `pw-orchestration` skill's common rules
(`references/common.md`) before acting: authorization, operation scope, helper ownership, and
reporting. Load only the phase-specific references this operation needs. A read-only operation
must not run execution or mutation procedures.
Follow the `pw-guide-workflow` skill. Arguments: {{ARGS}} — `--project <project-slug>` selects the
project; each optional `--task <T0n>` (repeatable) restricts the sweep to that task (default: every
shipped task with an open MR). Unknown flags and stray positional values fail closed.

`--auto-resolve` is a boolean, off by default. Without it a conflict still aborts and returns the
task for manual resolution. With it, reconcile that conflict during this invocation, verify the
merged result, then push through the normal path. The flag never authorizes force-push, history
rewriting, MR merging, or MR thread resolution, and it cannot promise that every conflict is
resolvable. A supplied value (`--auto-resolve=true`) fails closed; no persistent setting is added.

## Delegated conflict repair (conflict-only)

Only a real conflict creates conflict work. A clean merge or no-op keeps its existing flow and spawns
no worker. Without `--auto-resolve`, a conflict still aborts for manual resolution: no agent edits, and
affected descendants stay blocked.

With `--auto-resolve`, delegate each conflicted branch to `pw-sync-conflict-fixer` in an executor lane,
passing that entry's resolved path in the work order (explicit-only — the worker reads the file)
(or a compatible resumed executor session) under the task's existing pin. The driver keeps the attempt
ownership and scheduling; it does not re-run the merge for the worker and does not take over normal
verification or CI polling.

**Scheduling.** Build the graph from the approved DAG and recorded stacks up front, but discover actual
conflicts in ready waves: a descendant's effective target is its parent's *resulting verified head*, so
its conflict cannot be predicted before that head exists. Do not merge every selected branch
speculatively. Serialize ancestor/descendant work in one stack; independent stacks and unrelated ready
branches may run concurrently within the project `max-parallel`. Same-repository tasks need distinct
worktrees/branches and no shared state collision. Block only the affected subtree.

**Work order.** Send invocation/attempt id, project, task, worktree/branch, pinned start/task/target
SHAs, the conflict manifest, effective target, task pin and tuning, push authorization, prior
publication state, and the remaining repair allowance. Warm context is not authorization: a resumed
executor must be told this is a sync-conflict operation and must recheck freshness.

The worker reconciles both intents, uses the guarded `sync-finish`/`sync-bind` path, runs the complete
`## Verify`, pushes plainly, and observes the new head/target CI before returning. It may use the
attempt's **single** resolution-caused repair; delegation adds no second allowance. Pending CI is not a
clean result, and a green from an older head or pre-target context cannot release a dependent.

Project dir: `{{PW_PROJECTS}}/<slug>`.

**The problem this solves:** once `/pw-ship` has opened several MRs, their base branches keep
moving, and each MR needs the base merged back in (and re-verifying) to stay mergeable. Doing that
one-by-one across repos is the hassle. `/pw-sync` does the whole batch in one sweep.

This **merges** the latest base into each branch (a merge commit, normal push — no force-push, no
history rewrite). Pushing is **outward-facing**, so confirm before anything goes out.

**Stacked tasks use the same resolver, ordering, freshness checks, and pending-operation recovery
as comment propagation.** A stacked task targets its **effective target** (nearest unmerged
ancestor's branch, else its ultimate base), not the static base. Preview the set first
(`pw-ship.sh stack --project <slug>` / `pw-ship.sh stack-plan --project <slug>`): sync roots against their ultimate
destinations first, then propagate the updated heads through their descendants in root-first order
— merge each descendant's **immediate parent's** recorded updated head, not the ultimate base.
Explicit task selection includes a disclosed descendant impact set; inspect omitted ancestors and
block stale prerequisites rather than ignoring them. No-op detection depends on the recorded
consumed-parent bindings and pending debt, not merely an unchanged destination. Resume any pending
`stack-op` stages before starting; never replay from the top.

## Steps
1. **Resolve the set.** Find each task that is shipped: `Status: accepted`/`done`, a real branch,
   and an MR recorded in its `## Result → MR:` (and the dashboard **Merge requests** table).
   Skip zero-change tasks and `verify-failed` tasks. If `--task` was given (repeatable), restrict to those for
   independent tasks; a selected **stacked** task also pulls in its transitive stack descendants
   (their inherited code changed even where they have no comments). Never add an independent task
   just because it shares a repository.

2. **Check MR state for every task in the set — one batch call, not a per-task loop.** Before
   syncing, verify each MR is still open:
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-ship.sh mr-state-batch --project <slug> [--task <T0n>]…   # no --task = every PLAN task
   ```
   This queries the forge (GitLab/GitHub) once per task and prints `task-id|state` lines, with
   `state` one of `open`, `merged`, `closed`, or `unknown` (per-task handling below is unchanged;
   a mid-flow recheck of a single task may use `pw-ship.sh mr-state --project <slug> --task <T0n>` directly).
    - **If `merged`**: The MR was already merged downstream. Handle it:
      1. Accept the task — ONE call sets all three acceptance holders (task-file `Status:`, the
         PLAN task-table cell the close gate reads, and the dashboard task row; the dashboard is
         best-effort): `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh task-accept --project <slug> --task <T0n>`
      2. Update dashboard MR table: `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh dashboard-mr-state --project <slug> --task <T0n> --state merged`
      3. If the task is **stacked** or a stacked **parent**, settle the stack before removing
         anything: record its landing
         (`pw-ship.sh stack-land --project <slug> --task <T0n> --merge-sha <sha|-> --landed-into
         <branch> [--kind <merge|ff|squash|rebase|closed|unknown>]`) and every open child's promotion
         debt (`pw-ship.sh stack-promote --project <slug> --task <T0n>`), per
         "Parent landing and promotion" below. The recovery refs and child debt must exist
         **before** the removal in the next step. An independent task skips this.
      4. Remove worktree: `{{PW_HOME}}/tooling/scripts/entities/pw-worktree.sh remove --project <slug> --task <T0n>`
      5. Mark this task as `already-merged` in your tracking — **do NOT attempt to sync it**.
   - **If `closed`**: The MR was closed without merging. Note it in the recap but skip sync.
   - **If `open`**: Proceed with sync (step 3).
   - **If it prints `unknown`** (no MR URL/worktree/origin, or the forge query failed or returned
     null — the helper exits 1): Note it as `mr-state-unknown` and skip.

   When this invocation uses `--auto-resolve`, or resumes a recorded sync attempt, read
   `{{PW_HOME}}/tooling/skills/model/pw-guide-workflow/references/sync-conflict-resolution.md` before
   step 3 and follow it for conflict work. Do not load it for an ordinary sync.

3. **Confirm the list.** For each task with an `open` MR, show: repo, branch
   (`agent/<slug>/<T0n>-<slug>`), base branch, MR url, and — when opt-in is present — the
   resolution mode (`auto` for this invocation, `clean` for a merge that stays conflict-free).
   Also list any `already-merged` / `closed` / `mr-state-unknown` tasks separately. Ask me to
   confirm. Only after I say go:

4. **For each task with an open MR, from its worktree**
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - `git fetch origin`. Resolve the task's **effective target**: `origin/<base>` (its **Base
     branch**) for an independent task; for a **stacked** task, the recorded updated head of its
     immediate parent, or of its nearest unmerged ancestor, after that ancestor synced. Never the
     ultimate base for a stacked task. `pw-ship.sh stack --project <slug>` prints each task's target.
   - With `--auto-resolve`, record the pinned attempt **before** merging, then use the deterministic
     merge operator (`S={{PW_HOME}}/tooling/scripts/entities/pw-ship.sh`):
     `$S sync-attempt begin --project <slug> --task <T0n> --kind <independent|stack> --mode auto --target-branch <effective-target-branch>`
     then `$S sync-merge --project <slug> --task <T0n> --target <pinned-target-sha> --keep-conflict`.
     `sync-merge` exits 3 only when it left the conflict in place for resolution; follow the loaded
     reference, then continue at its verification/publication steps. Exit 2 means it aborted or the
     merge failed operationally — mark the task failed and continue. A clean merge returns 0.
   - **Preserve both sides.** Never resolve a conflicted path by taking the task side or the target
     side as a whole. Merge both intents, including additive list/array entries. Before finishing,
     list each side's intended change and confirm the result contains it; `sync-finish` refuses a
     result byte-identical to one side when both sides changed the path. If the intents cannot
     coexist, **stop and ask the owner** with the path, base/task/target snippets, and candidate
     results. Only after the owner says one side is obsolete, run
     `$S sync-finish --project <slug> --task <T0n> --allow-one-sided <path> --reason "<why>" --owner-approved`.
     Do not use `git checkout --ours/--theirs` or "accept current/incoming".
   - Without `--auto-resolve`, merge the effective target directly.
   - **Conflict without the flag?** `git merge --abort`, mark the task `CONFLICT — needs manual
     resolution`, and **move on to the next task** — never leave a half-merged worktree. Do not
     auto-resolve without the explicit flag. For a **stacked** task the conflict also blocks **that
     child's subtree** (a descendant cannot merge a parent that did not update); independent stacks
     and tasks continue.
   - **Clean merge?** Re-run the task's `## Verify` block and capture the **real output**.
     - Verify **fails** → do NOT push. With `--auto-resolve`, if the failure is a regression caused
       by this resolution and no repair has been used, make **one** bounded repair, commit it, re-run
       Verify once, and rebind (`sync-bind`). That repair spends the shared `<task>@<branch>` budget;
       an exhausted shared budget refuses it. If it still fails, leave the merge commit for
       inspection, mark `verify-failed after sync`, flip the task `Status: verify-failed`, and record
       the failed attempt (`$S sync-attempt set --project <slug> --task <T0n> --stage failed`).
       Continue with the others.
     - Verify **passes** → with `--auto-resolve`, bind the evidence to the final committed HEAD
       (`$S sync-bind --project <slug> --task <T0n> --evidence <captured-file>`) and, for a stacked
       task, re-bind the stack tuple before any descendant advances (reference). Then `git push`
       (plain push; the merge commit is a fast-forward-safe update to the existing MR branch), and
       record the publication (`$S sync-attempt set --project <slug> --task <T0n> --stage pushed`).
   - On a successful push, log it: `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh log --project <slug>
     --actor sync --message "T0n merged origin/<base>; verify green; pushed"`, and add a one-line note to the task's `## Result`
     (`Synced with <base> @ <short-sha> on <DD MMMM YYYY - HH.mm WIB>`). The MR updates itself — no new MR is opened.
   - Then settle the CI the push triggered: `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh monitor --project <slug> --task <T0n>`
     (exit 0 green — or neutral `SKIPPED`, no jobs ran — / 1 red / 2 still running; it records the task's `## Result → Build check:` line).
     Red → report it prominently in the recap; don't undo the sync. Still running → say so, don't
     claim green.

5. **Recap** a table — one row per task: Task · Repo · Base · Result
   (`synced ✓` / `auto-resolved ✓` / `already-merged ✓` / `closed` / `conflict ✗` /
   `verify-failed ✗` / `stale-inputs ✗` / `mr-state-unknown` / `skipped`). List any `conflict` /
   `verify-failed` / `stale-inputs` tasks as the ones needing you next, with the exact worktree
   path and recorded attempt stage for each. `auto-resolved` means both sides were preserved and
   the final HEAD verified; local resolution alone is never reported as a successful sync.

Never merge or close the **MR** itself — that's a human decision downstream. This command only
brings each MR's branch up to date with its base, and cleans up work for MRs that were already
merged by someone else.

## Parent landing and promotion

When a stacked **parent MR merges**, observe the forge state and merge metadata before touching a
child, then refresh refs and resolve each open child's next target:

```bash
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-land --project <slug> --task <parent-task> --merge-sha <sha|-> --landed-into <branch> [--kind <merge|ff|squash|rebase|closed|unknown>]
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-promote --project <slug> --task <child-task>
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-verify --project <slug> --task <child-task> --evidence <path>
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-retarget --project <slug> --task <child-task> [--apply]
```

`stack-land` only records a landing it can prove: a merge/fast-forward is checked with real Git
ancestry into a **fetched origin ref** (a local-only branch proves nothing), the forge's observed MR
target is corroborated when the URL lets it answer, and squash/rebase/closed require the forge to
corroborate the MR state. An unprovable or `unknown` landing is refused, so no caller can assert
`landed=yes`; the parent's verified tip is retained as a recovery ref so promotion survives
source-branch deletion.

- **Ancestry preserved** (merge / fast-forward): merge the refreshed target into the child if
  needed, re-verify it and bind the new tuple
  (`stack-verify --project <slug> --task <child> --evidence <path> --ci-sha <sha|skipped|pending>` — the CI
  disposition is part of the tuple, and an old-target green never certifies the promoted MR), then
  move the MR's base with the deterministic retarget operator: `stack-retarget --project <slug> --task <child>`
  previews and `--apply` publishes through the resolved forge, checks the destination against
  freshly fetched refs and the MR's state/target/head, reads the target back, and mirrors local
  state/dashboard loudly. A pending retarget row is resumed before any noop shortcut and a retry
  after a remote success does **not** write to the forge again. Never close and recreate the MR. If
  the parent merged into another open ancestor, promote
  to that ancestor's branch, not straight to the ultimate base. If no open ancestor remains, promote
  to the ultimate destination.
- **Squash or rebase** changes commit ancestry: `stack-promote` returns `block|…`. Block automatic
  promotion; an approved restack must replay only descendant-owned changes onto the promoted target
  (derive the boundary from recorded ancestry — a blind `rebase --onto` over all child history is
  unsafe), retain backup refs, show the proposed diff, and require specific approval for
  `--force-with-lease` with an explicit expected remote SHA. Never retry with plain force when the
  lease fails. If ownership or topology is ambiguous, block and request owner-assisted repair.
- **Parent branch deleted**: use retained parent commit refs + forge merge metadata — never resolve
  solely from the deleted remote branch name. **Parent closed without merge / state unknown**: block
  and require an owner decision.

After any promotion, re-fetch and re-observe the MR's target/head before marking it complete, then
refresh local mirrors only after observed remote success (with pending-mirror recovery if a local
write fails). CI evidence must reflect the **new target context** — a same-head result from the old
target cannot certify a promoted MR; observe target-context checks, explicitly trigger an authorized
check, or report pending/skipped. Keep actual MR merging a human decision, and remove a merged
parent's worktree only after its recovery refs and child-promotion debt are durably recorded.
