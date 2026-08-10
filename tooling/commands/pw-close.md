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
2. **Tear down worktrees — use the safe helper** (it refuses to remove the worktree you're
   currently in or one with uncommitted changes, which is what unexpectedly closed an editor once):
   ```bash
   {{PW_HOME}}/tooling/pw-teardown.sh {{PW_PROJECTS}}/<slug>
   ```
   Run it from the bundle/project root — **NOT from inside a worktree**, and close any worktree
   folder still open in your editor first. It reports removed / skipped (current dir) / skipped
   (dirty); re-run after `cd`-ing out, or pass `--yes` only when you've confirmed a dirty worktree
   is safe to discard. It never deletes branches or the project dir.
3. **Learn — seed memory (only IF a memory tool is configured;** see
   `{{PW_HOME}}/tooling/docs/memory.md` / `PW_MEMORY`): distil durable, *workflow-level* learnings into
   your memory tool, mark superseded facts `[SUPERSEDED]`, and don't save what the repos/commits
   already record. **If `PW_MEMORY=none`, skip this — the project's "Decisions & learnings" section
   is the record.** Either way, make sure that section is filled before closing.
4. **Improve the template** if this run surfaced a workflow gap — note it, or edit the bundle
   (`{{PW_HOME}}/template/` for project scaffolding, `{{PW_HOME}}/tooling/` for machinery).
5. Close out via the helper, then summarize:
   ```bash
   {{PW_HOME}}/tooling/pw-lib.sh log <slug> close "closed — N MRs open, worktrees removed, memories seeded"
   {{PW_HOME}}/tooling/pw-lib.sh status <slug> done
   ```
   Summarize: MRs opened / merged, worktrees removed, memories seeded, and any leftover follow-ups.

Confirm with me before removing any worktree with uncommitted changes.
