---
description: Update all of a project's open MR branches — merge the moved base branch into each, re-verify, push
args: <project-slug> [task-ids]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} (first token = project slug; optional task
IDs to sync a subset — default is every shipped task with an open MR).

Project dir: `{{PW_PROJECTS}}/<slug>`.

**The problem this solves:** once `/pw-ship` has opened several MRs, their base branches keep
moving, and each MR needs the base merged back in (and re-verifying) to stay mergeable. Doing that
one-by-one across repos is the hassle. `/pw-sync` does the whole batch in one sweep.

This **merges** the latest base into each branch (a merge commit, normal push — no force-push, no
history rewrite). Pushing is **outward-facing**, so confirm before anything goes out.

**Stacked tasks use the same resolver, ordering, freshness checks, and pending-operation recovery
as comment propagation.** A stacked task targets its **effective target** (nearest unmerged
ancestor's branch, else its ultimate base), not the static base. Preview the set first
(`pw-ship.sh stack <slug>` / `pw-ship.sh stack-plan <slug>`): sync roots against their ultimate
destinations first, then propagate the updated heads through their descendants in root-first order
— merge each descendant's **immediate parent's** recorded updated head, not the ultimate base.
Explicit task selection includes a disclosed descendant impact set; inspect omitted ancestors and
block stale prerequisites rather than ignoring them. No-op detection depends on the recorded
consumed-parent bindings and pending debt, not merely an unchanged destination. Resume any pending
`stack-op` stages before starting; never replay from the top.

## Steps
1. **Resolve the set.** Find each task that is shipped: `Status: accepted`/`done`, a real branch,
   and an MR recorded in its `## Result → MR:` (and the dashboard **Merge requests** table).
   Skip zero-change tasks and `verify-failed` tasks. If task IDs were given, restrict to those for
   independent tasks; a selected **stacked** task also pulls in its transitive stack descendants
   (their inherited code changed even where they have no comments). Never add an independent task
   just because it shares a repository.

2. **Check MR state for every task in the set — one batch call, not a per-task loop.** Before
   syncing, verify each MR is still open:
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-ship.sh mr-state-batch <slug> [task-ids…]   # no ids = every PLAN task
   ```
   This queries the forge (GitLab/GitHub) once per task and prints `task-id|state` lines, with
   `state` one of `open`, `merged`, `closed`, or `unknown` (per-task handling below is unchanged;
   a mid-flow recheck of a single task may use `pw-ship.sh mr-state <slug> <task-id>` directly).
    - **If `merged`**: The MR was already merged downstream. Handle it:
      1. Accept the task — ONE call sets all three acceptance holders (task-file `Status:`, the
         PLAN task-table cell the close gate reads, and the dashboard task row; the dashboard is
         best-effort): `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh task-accept <slug> <task-id>`
      2. Update dashboard MR table: `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh dashboard-mr-state <slug> <task-id> merged`
      3. If the task is **stacked** or a stacked **parent**, settle the stack before removing
         anything: record its landing
         (`pw-ship.sh stack-land <slug> <task-id> <merge-sha|-> <landed-into> [merge|ff|squash|rebase|closed|unknown]`)
         and every open child's promotion debt (`pw-ship.sh stack-promote <slug> <child>`), per
         "Parent landing and promotion" below. The recovery refs and child debt must exist
         **before** the removal in the next step. An independent task skips this.
      4. Remove worktree: `{{PW_HOME}}/tooling/scripts/entities/pw-worktree.sh remove <slug> <task-id>`
      5. Mark this task as `already-merged` in your tracking — **do NOT attempt to sync it**.
   - **If `closed`**: The MR was closed without merging. Note it in the recap but skip sync.
   - **If `open`**: Proceed with sync (step 3).
   - **If it prints `unknown`** (no MR URL/worktree/origin, or the forge query failed or returned
     null — the helper exits 1): Note it as `mr-state-unknown` and skip.

3. **Confirm the list.** For each task with an `open` MR, show: repo, branch
   (`agent/<slug>/<T0n>-<slug>`), base branch, MR url. Also list any `already-merged` / `closed` /
   `mr-state-unknown` tasks separately. Ask me to confirm. Only after I say go:

4. **For each task with an open MR, from its worktree**
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - `git fetch origin` then merge the task's **effective target**: `origin/<base>` (its **Base
     branch**) for an independent task; for a **stacked** task, the recorded updated head of its
     immediate parent, or of its nearest unmerged ancestor, after that ancestor synced. Never the
     ultimate base for a stacked task. `pw-ship.sh stack <slug>` prints each task's target.
   - **Conflict?** `git merge --abort`, mark the task `CONFLICT — needs manual resolution`, and
     **move on to the next task** — never leave a half-merged worktree. Don't try to auto-resolve.
     For a **stacked** task the conflict also blocks **that child's subtree** (a descendant cannot
     merge a parent that did not update); independent stacks and tasks continue.
   - **Clean merge?** Re-run the task's `## Verify` block and capture the **real output**.
     - Verify **fails** → do NOT push; mark `verify-failed after sync`, leave the merge commit in
       the worktree for inspection, and flip the task `Status: verify-failed` so it goes back
       through review. Continue with the others.
     - Verify **passes** → `git push` (plain push; the merge commit is a fast-forward-safe update to
       the existing MR branch).
   - On a successful push, log it: `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh log <slug> sync "T0n merged
     origin/<base>; verify green; pushed"`, and add a one-line note to the task's `## Result`
     (`Synced with <base> @ <short-sha> on <DD MMMM YYYY - HH.mm WIB>`). The MR updates itself — no new MR is opened.
   - Then settle the CI the push triggered: `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh monitor <slug> T0n`
     (exit 0 green — or neutral `SKIPPED`, no jobs ran — / 1 red / 2 still running; it records the task's `## Result → Build check:` line).
     Red → report it prominently in the recap; don't undo the sync. Still running → say so, don't
     claim green.

5. **Recap** a table — one row per task: Task · Repo · Base · Result
   (`synced ✓` / `already-merged ✓` / `closed` / `conflict ✗` / `verify-failed ✗` /
   `mr-state-unknown` / `skipped`). List any `conflict` / `verify-failed` tasks as the ones
   needing you next, with the exact worktree path for each.

Never merge or close the **MR** itself — that's a human decision downstream. This command only
brings each MR's branch up to date with its base, and cleans up work for MRs that were already
merged by someone else.

## Parent landing and promotion

When a stacked **parent MR merges**, observe the forge state and merge metadata before touching a
child, then refresh refs and resolve each open child's next target:

```bash
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-land <slug> <parent-task> <merge-sha|-> <landed-into-branch> [merge|ff|squash|rebase|closed|unknown]
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-promote <slug> <child-task>
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-verify <slug> <child-task> <captured-verify-output>
{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh stack-retarget <slug> <child-task> [--apply]
```

`stack-land` only records a landing it can prove: a merge/fast-forward is checked with real Git
ancestry into a **fetched origin ref** (a local-only branch proves nothing), the forge's observed MR
target is corroborated when the URL lets it answer, and squash/rebase/closed require the forge to
corroborate the MR state. An unprovable or `unknown` landing is refused, so no caller can assert
`landed=yes`; the parent's verified tip is retained as a recovery ref so promotion survives
source-branch deletion.

- **Ancestry preserved** (merge / fast-forward): merge the refreshed target into the child if
  needed, re-verify it and bind the new tuple
  (`stack-verify <slug> <child> <captured-verify-output> --ci-sha <sha|skipped|pending>` — the CI
  disposition is part of the tuple, and an old-target green never certifies the promoted MR), then
  move the MR's base with the deterministic retarget operator: `stack-retarget <slug> <child>`
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
