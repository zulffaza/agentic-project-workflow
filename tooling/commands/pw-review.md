---
description: Apply my review comments for the current phase (or a given review file)
args: <project-slug> [phase | path-to-.review.md]
---
Invoke the `project-workflow` skill (review rules). Arguments: {{ARGS}}.

Project dir: `{{PW_PROJECTS}}/<slug>`.

**Resolve WHICH review files to process — do NOT scan the whole project:**
- If the 2nd arg is a **path** to a `.review.md`, use exactly that file.
- If it's a **phase word** (`analysis` or `task`/`plan`), process that phase's `review/` dir only.
- Otherwise, infer from the current phase (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`):
  - `analysis` → `analysis/review/*.review.md`
  - `breakdown` → `task/review/*.review.md` (PLAN + any T0n)
  - `executing` / `review` → `task/review/T0n.review.md` for tasks currently `verify-failed`
- Only read the review files in that scope. (This is the time-saver: don't open every `.review.md`
  in the project — just the current phase's.)

For each `🔴 open` item in the resolved files:
- apply the fix to the doc it reviews,
- append a concrete `↳ agent:` reply naming the section + exactly what changed (never a bare
  "fixed"/"done"),
- flip the item to `🟢 resolved`.

**Also process the "## Open questions" section (QnA):** for each `Qn` that now has a `↳ you:`
answer, fold that answer into the reviewed doc (e.g. update analysis §5 and any section the answer
affects), append a `↳ agent:` line saying what you changed, and flip the row `⏳ awaiting answer`
→ `✅ answered`. Leave `Qn` rows with no answer yet untouched and report them as still blocking.

Never edit or delete my comment text (items OR my `↳ you:` answers). Never write the Sign-off row
— only I clear the gate. Log the pass:
`…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> review "<n> items resolved in <file>"`.
Append a line to `<project>/LOG.md` (`<date time> | review | <n> items resolved in <file>`).

When done, recap each resolved item (one line) here, and tell me how many `🔴 open` items remain
**in the resolved scope** (and, as a footnote, across the whole project:
`rtk grep -rln "🔴 open"` in the project dir).
