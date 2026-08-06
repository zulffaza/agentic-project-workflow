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

## Steps
1. **Resolve the set.** Find each task that is shipped: `Status: accepted`/`done`, a real branch,
   and an **open** MR recorded in its `## Result → MR:` (and the dashboard **Merge requests**
   table). Skip zero-change tasks, already-merged MRs, and `verify-failed` tasks. If task IDs were
   given, restrict to those.
2. **Confirm the list.** For each task in the set, show: repo, branch (`agent/<slug>/<T0n>-<slug>`),
   base branch, MR url. Ask me to confirm. Only after I say go:
3. **For each task, from its worktree** (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - `git fetch origin` then `git merge origin/<base>` (the task's **Base branch**).
   - **Conflict?** `git merge --abort`, mark the task `CONFLICT — needs manual resolution`, and
     **move on to the next task** — never leave a half-merged worktree. Don't try to auto-resolve.
   - **Clean merge?** Re-run the task's `## Verify` block and capture the **real output**.
     - Verify **fails** → do NOT push; mark `verify-failed after sync`, leave the merge commit in
       the worktree for inspection, and flip the task `Status: verify-failed` so it goes back
       through review. Continue with the others.
     - Verify **passes** → `git push` (plain push; the merge commit is a fast-forward-safe update to
       the existing MR branch).
   - On a successful push, log it: `{{PW_HOME}}/tooling/pw-lib.sh log <slug> sync "T0n merged
     origin/<base>; verify green; pushed"`, and add a one-line note to the task's `## Result`
     (`Synced with <base> @ <short-sha> on <date>`). The MR updates itself — no new MR is opened.
4. **Recap** a table — one row per task: Task · Repo · Base · Result
   (`synced ✓` / `conflict ✗` / `verify-failed ✗` / `skipped`). List any `conflict` /
   `verify-failed` tasks as the ones needing you next, with the exact worktree path for each.

Never merge or close the **MR** itself — that's a human decision downstream. This command only
brings each MR's branch up to date with its base.
