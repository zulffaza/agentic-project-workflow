---
description: Close out a finished project — verify, tear down, learn
args: <project-slug>
---
Invoke the `project-workflow` skill (Step 8 — Learn + close). Arguments: {{ARGS}} (project slug).

Project dir: `{{PW_PROJECTS}}/<slug>`.

1. **Verify done.** Confirm every task in `task/PLAN.md` is `accepted` (or explicitly dropped with
   a note). If any isn't, list them and STOP — don't close a project with unaccepted work.
   **`accepted` ≠ merged:** a task is accepted when it's verified, its MR is opened, and I've
   signed off on the change. Open/on-hold MRs are fine — merging is downstream and may take a long
   time, so it does NOT block close-out. Record each MR's state (open/on-hold/merged) in the
   dashboard Merge-requests table before closing.
2. **Tear down worktrees.** For each worktree under `<project>/worktree/`, run
   `git -C <real-repo> worktree remove <path>` then `git -C <real-repo> worktree prune`; report
   what was removed. If a worktree has uncommitted changes, surface it and confirm before removing.
   Do NOT delete branches or the project dir.
3. **Learn — seed memory** (per the EverOS rules): distil durable, *workflow-level* learnings into
   EverOS `personal`, and any reusable *domain* facts into `midtrans`. Do NOT save what the
   repos/commits already record (code, fixes, git history). Mark superseded facts with
   `[SUPERSEDED]` rather than duplicating.
4. **Improve the template** if this run surfaced a workflow gap — note it, or edit `base/`.
5. Close out via the helper, then summarize:
   ```bash
   {{PW_HOME}}/tooling/pw-lib.sh log <slug> close "closed — N MRs open, worktrees removed, memories seeded"
   {{PW_HOME}}/tooling/pw-lib.sh status <slug> done
   ```
   Summarize: MRs opened / merged, worktrees removed, memories seeded, and any leftover follow-ups.

Confirm with me before removing any worktree with uncommitted changes.
