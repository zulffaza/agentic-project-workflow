---
description: Apply my review comments for the current phase (or a given review file) — or, with the "ai" sub-verb, delegate a fresh review pass to pw-reviewer — or, with "config", view/change this project's AI Review settings
args: <project-slug> [ai | config] [phase | Tid | path-to-.review.md | <phase> <mode>]
---
Invoke the `project-workflow` skill (review rules). Arguments: {{ARGS}}.

Project dir: `{{PW_PROJECTS}}/<slug>`.

**This command NEVER changes the dashboard `Status:` line or any other dashboard field.** Reviewing
is not a phase transition — the phase only moves when the next `/pw-*` command runs. (If you meant
to rewind a phase, that's `/pw-status <slug> rewind <phase>`, not this command.)

**If the 2nd argument is literally `ai`, this is the AI-assisted review flow, not apply-comments —
skip everything below and follow this instead** (the 3rd argument, if given, narrows scope exactly
like the apply-comments flow does):

1. Resolve scope the same way apply-comments does (below) — explicit path > task id > phase word >
   infer from the current phase — but map it to one of the five AI-Review phase keys: `analysis`,
   `plan`, `task-plan`, `task-exec`, `ship`.
2. Check this project's mode for that phase: `…/{{PW_HOME}}/tooling/pw-lib.sh ai-review <slug>` (an
   internal check — I never type this myself). If `off`, tell me AI review isn't enabled for this
   phase and stop — point me at `/pw-review <slug> config <phase> <mode>` rather than guessing I
   want it turned on, and never at the underlying script.
3. If `advisory` or `auto`, ensure the review file exists (`review-init` if not), then spawn the
   `pw-reviewer` agent **fresh** — same provider, in-process sub-agent (Claude Task tool / kilo
   `mode: subagent`). Hand it **only**: the artifact path, the review-file path, the phase name,
   and `REVIEWER-NOTES.md` if it exists. Do **not** pass this session's own reasoning about the
   artifact, or any chat history about how it was produced — that defeats the entire point of a
   second opinion. Invoke the `pw-review` skill yourself first if you need the full method before
   spawning it.
4. `pw-reviewer` files items (tagged `(pw-reviewer, <timestamp>)`) and a `REVIEWER-NOTES.md` entry
   on its own — you don't do this part. It checks for an existing item on the same section anchor
   before filing anything (loop prevention — a 3rd item on the same anchor becomes a 🔴 open
   escalation instead of a normal finding, never resolved by it). In `auto` mode with a genuinely
   clean pass, it may also call `pw-lib.sh review auto-signoff` itself; you never write that row.
5. Recap what it did (items filed, whether it signed off, any escalation) exactly like the
   apply-comments recap below. `advisory` mode: remind me a human still needs to review its items
   and sign off. An escalation means this needs my attention now, not another `ai` re-run.

**If the 2nd argument is literally `config`, this is how I view/change this project's AI Review
settings — skip everything below and follow this instead.** This command is the interface for
that; regardless of what else I ask for, never tell me to run `pw-lib.sh` myself for this — that's
the internal mechanism this sub-verb wraps, not something I should need to know exists.

1. **No further arguments** → run `…/{{PW_HOME}}/tooling/pw-lib.sh ai-review <slug>` and show me
   the five phases (`analysis`/`plan`/`task-plan`/`task-exec`/`ship`) and their current mode
   (`off`/`advisory`/`auto`) as a small table, in plain language — not the raw
   `analysis=off plan=off …` line verbatim. One line reminding me what each mode means: `off` = no
   AI reviewer, `advisory` = it files items but I still sign off, `auto` = it may sign off itself
   on a genuinely clean pass. Tell me how to change one: `/pw-review <slug> config <phase> <mode>`.
2. **`<phase> <mode>` given** → validate `<phase>` is one of the five above and `<mode>` is one of
   `off`/`advisory`/`auto` yourself (a friendlier error than the tool's if not), then run
   `…/{{PW_HOME}}/tooling/pw-lib.sh ai-review <slug> <phase> <mode>` and confirm back in plain
   language — e.g. *"AI review for the plan-approval gate is now `auto` — a clean pw-reviewer pass
   can sign off the PLAN itself now, no human needed, unless something's still open."* If `plan`
   is being set to `auto`, add a one-line reminder that it's the only hard gate, so I know what
   I'm opting into.
3. This never changes the dashboard `Status:` line either — same rule as everything else here.

**Resolve WHICH review files to process (apply-comments flow — do NOT scan the whole project):**
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
`grep -rln "🔴 open"` in the project dir). For a task review: after fixes are applied, remind me
to re-run `/pw-execute <slug> T0n` to re-verify in its worktree.
