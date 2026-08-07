---
description: Apply my review comments for the current phase (or a given review file)
args: <project-slug> [phase | Tid | path-to-.review.md]
---
Invoke the `project-workflow` skill (review rules). Arguments: {{ARGS}}.

Project dir: `{{PW_PROJECTS}}/<slug>`.

**This command NEVER changes the dashboard `Status:` line or any other dashboard field.** Reviewing
is not a phase transition — the phase only moves when the next `/pw-*` command runs. (If you meant
to rewind a phase, that's `pw-lib.sh status <slug> <phase> --rewind`, not this command.)

**Resolve WHICH review files to process — do NOT scan the whole project:**
- If the 2nd arg is a **path** to a `.review.md`, use exactly that file.
- If it's a **task id** (`T0n`), process `task/review/T0n.review.md`.
- If it's a **phase word** (`analysis` or `task`/`plan`), process that phase's `review/` dir only.
- Otherwise, infer from the current phase (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`):
  - `analysis` → `analysis/review/*.review.md`
  - `breakdown` → `task/review/*.review.md` (PLAN + any T0n)
  - `executing` / `review` → every task currently `verify-failed` (read the PLAN task table + task
    files to find them).

**Verify-failed tasks may not have a review file yet — that's the #1 reason "nothing happens".**
For each task I've flipped to `Status: verify-failed`:
- If `task/review/T0n.review.md` **exists**, process it (below).
- If it **does NOT exist**, don't stop silently. Create it deterministically —
  `{{PW_HOME}}/tooling/pw-lib.sh review-init <slug> task/review/T0n.review.md task/T0n.md`
  (never hand-write it; this guarantees the permanent format hints survive) — then write whatever
  feedback I gave you in chat as the `🔴 open` item(s), and process it. If I flipped the task to
  verify-failed but gave you **no** feedback anywhere, tell me exactly that and ask what's wrong —
  don't guess.

For each `🔴 open` item in the resolved files:
- apply the fix to the doc it reviews,
- append a concrete `↳ agent:` reply naming the section + exactly what changed (never a bare
  "fixed"/"done"),
- flip the item to `🟢 resolved`.

**Also process the "## Open questions" section (QnA):** for each `Qn` that now has a `↳ you:`
answer, fold that answer into the reviewed doc, append a `↳ agent:` line saying what you changed,
and flip the row `⏳ awaiting answer` → `✅ answered`. Leave unanswered `Qn` rows untouched and
report them as still blocking.

Never edit or delete my comment text (items OR my `↳ you:` answers). Never write the Sign-off row
— only I clear the gate. Log the pass (this is the ONLY dashboard-adjacent write you make):
`…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> review "<n> items resolved in <file>"`.

When done, recap each resolved item (one line) here, and tell me how many `🔴 open` items remain
**in the resolved scope** (and, as a footnote, across the whole project:
`rtk grep -rln "🔴 open"` in the project dir). For a task review: after fixes are applied, remind me
to re-run `/pw-execute <slug> T0n` to re-verify in its worktree.
