---
description: Close out a finished project — verify, tear down, learn
args: <project-slug>
---
Invoke the `project-workflow` skill (close phase — learn + teardown). Arguments: {{ARGS}} (project slug).

Project dir: `{{PW_PROJECTS}}/<slug>`.

<!-- Pre-flight: deterministic checks before agent reasoning -->
```bash
{{PW_HOME}}/tooling/scripts/entities/pw-preflight.sh close <slug> || exit 1
{{PW_HOME}}/tooling/scripts/entities/pw-doc.sh lint all <slug> || exit 1
```
**Reading the pre-flight:** `pw-preflight.sh close` checks every task is `accepted` in a legal
phase; `pw-doc.sh lint all` checks every doc kind (analysis §1–5, PLAN, tasks, reviews, dashboard
row-count) at once. Non-zero + `pw-…:` stderr = STOP and relay it — closing is exactly the wrong
moment to skip a lint. (`{{PW_HOME}}/tooling/docs/scripts/README.md`)

1. **Verify done.** Confirm every task in `task/PLAN.md` is `accepted` (or explicitly dropped with
   a note). If any isn't, list them and STOP — don't close a project with unaccepted work.
   **`accepted` ≠ merged:** a task is accepted when it's verified, its MR is opened, and I've
   signed off on the change. Open/on-hold MRs are fine — merging is downstream and may take a long
   time, so it does NOT block close-out. Record each MR's state (open/on-hold/merged) in the
   dashboard Merge-requests table before closing.
1b. **Final review — only when configured.** After step 1's checks pass and BEFORE any teardown,
   read the `close` axis (`{{PW_HOME}}/tooling/scripts/entities/pw-config.sh project get <slug>
   review-trigger` and `… ai-review`) and, ONLY when the trigger is `completion` and the outcome is
   callable (`advisory` default; a legacy `off` row reads as advisory), run the
   `/pw-review <slug> ai close` flow against the project's close evidence
   (`review/CLOSE.review.md`; the packet snapshots README + PLAN + task/review records). A fresh
   reviewer only; bounded repairs only when `review-repair close=bounded` within `review-rounds`
   passes (repairs may correct records; they never delete history or clear stack debt — the
   preflight above owns that). Outage or unverified route: one skip line, continue. Findings do
   not stop a close whose existing gates pass unless an item needs my decision — surface any
   unresolved finding as a follow-up in the recap. The reviewer never removes worktrees, never
   seeds memory, and never takes over this command's own steps.
2. **Tear down worktrees — use the safe helper** (it refuses to remove the worktree you're
   currently in or one with uncommitted changes, which is what unexpectedly closed an editor once):
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-worktree.sh teardown {{PW_PROJECTS}}/<slug>
   ```
   Run it from the bundle/project root — **NOT from inside a worktree**, and close any worktree
   folder still open in your editor first. It reports removed / skipped (current dir) / skipped
   (dirty); re-run after `cd`-ing out, or pass `--yes` only when you've confirmed a dirty worktree
   is safe to discard. It never deletes branches or the project dir.
2b. **Stack debt.** `pw-preflight.sh close` also rejects unresolved stack debt — a task whose
   verification tuple is **stale** (merge the updated parent, re-verify, push to clear it) or a
   pending stack operation. Clear it before closing; do **not** delete stack branches or recovery
   refs automatically — preserve enough evidence to repair still-open children after teardown.
3. **Learn — seed memory (only IF a memory tool is configured;** see
   `{{PW_HOME}}/tooling/docs/memory.md` / `PW_MEMORY`): distil durable, *workflow-level* learnings into
   your memory tool, mark superseded facts `[SUPERSEDED]`, and don't save what the repos/commits
   already record. **If `PW_MEMORY=none`, skip this — the project's "Decisions & learnings" section
   is the record.** Either way, make sure that section is filled before closing.
4. **Improve the template** if this run surfaced a workflow gap — note it, or edit the bundle
   (`{{PW_HOME}}/template/` for project scaffolding, `{{PW_HOME}}/tooling/` for machinery).
5. Close out via the helper, then summarize:
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-status.sh provider-audit <slug>
   {{PW_HOME}}/tooling/scripts/entities/pw-status.sh log <slug> close "closed — N MRs open, worktrees removed, memories seeded"
   {{PW_HOME}}/tooling/scripts/entities/pw-status.sh status <slug> done
   ```
   Summarize: MRs opened / merged, worktrees removed, memories seeded, and any leftover follow-ups.
   **Include unresolved `provider-audit` verdicts** (`stale-provider`/`unbound`/`mismatch` rows) in
   the recap — a provider that drifted mid-project is exactly the kind of follow-up the close
   summary exists to carry forward.

Confirm with me before removing any worktree with uncommitted changes.
