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
   before filing anything (loop prevention — a 3rd item on the same anchor becomes a [OPEN]
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

**Step 0 — pinpoint before reading, IF a memory tool is configured** (optional; see
`{{PW_HOME}}/tooling/docs/memory.md` and `PW_MEMORY` in `pw.config.sh`). For the item(s) about to
be applied, query the configured tool for the concepts already in the item's own ask text + its
`§section or anchor` — BEFORE reading anything else. Treat any result strictly as a **location
pointer** (which heading/section) — never as content; the fix must still be grounded in a fresh
read of that live section regardless of what the query returns. If unconfigured, or it returns
nothing, fall back to the file's own `## Contents` table (below). **If `PW_MEMORY=none`, skip this
step silently — do not block.**

**Resolve WHICH review files to process (apply-comments flow — do NOT scan the whole project):**
- If the 2nd arg is a **path** to a `.review.md`, use exactly that file.
- If it's a **task id** (`T0n`), process `task/review/T0n.review.md`.
- If it's a **phase word** (`analysis` or `task`/`plan`), process that phase's `review/` dir only.
- Otherwise, infer from the current phase (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`):
  - `analysis` → `analysis/review/*.review.md`
  - `breakdown` → `task/review/*.review.md` (PLAN + any T0n)
  - `executing` / `review` → every task currently `verify-failed` (read the PLAN task table + task
    files to find them).

**Scoped reads — applying one item only needs that item's own block, never the whole file.** Use
the file's own `## Contents` table (heading-text-anchored, 🤖-owned — refresh it with
`…/{{PW_HOME}}/tooling/pw-lib.sh review reindex <slug> <review-rel-path>` if it looks stale) or
Step 0's pinpoint result to jump straight to the item's own heading + the doc section(s) its
anchor names. Never read `<file>.archive.md` (moved-out `[RESOLVED]`/`[ANSWERED]` history) unless
the item's own ask specifically asks about past rationale.

**Verify-failed tasks may not have a review file yet — that's the #1 reason "nothing happens".**
For each task I've flipped to `Status: verify-failed`:
- If `task/review/T0n.review.md` **exists**, process it (below).
- If it **does NOT exist**, don't stop silently. Create it deterministically —
  `{{PW_HOME}}/tooling/pw-lib.sh review-init <slug> task/review/T0n.review.md task/T0n.md`
  (never hand-write it; this guarantees the permanent format hints survive) — then write whatever
  feedback I gave you in chat as the `[OPEN]` item(s), and process it. If I flipped the task to
  verify-failed but gave you **no** feedback anywhere, tell me exactly that and ask what's wrong —
  don't guess.

**Before applying a fix — if the doc being edited is `analysis/<topic>.md` or `task/PLAN.md`,
check whether this fix needs to reopen that doc's own gate first** (analysis and PLAN are the two
docs with a real hard-gate Sign-off table — `/pw-breakdown` and `/pw-execute` read them via
`pw-lib.sh review gate`, the current/latest row only, never "was it ever approved"). This matters
even when the file you're processing ISN'T that doc's own review file — e.g. an RFC comment lives
in `analysis/review/RFC.review.md`, but the doc it fixes is `analysis/<topic>.md`, whose OWN gate
lives in the *separate* `analysis/review/<topic>.review.md` (derived from the doc's path per the
naming convention in `_REVIEW.template.md`'s "WHERE THIS LIVES" note). Skip this whole check for
any other doc (a task file, an RFC doc, a ship artifact) — nothing gates on those review files'
Sign-off, so there's nothing to reopen.
1. Derive the doc's own canonical review file: `analysis/<topic>.md` → `analysis/review/
   <topic>.review.md`; `task/PLAN.md` → `task/review/PLAN.review.md`. (Usually this IS the file
   already being processed — the derivation only diverges for RFC.review.md's case above.)
2. `…/{{PW_HOME}}/tooling/pw-lib.sh review gate <slug> <canonical-review>`. If it's not currently
   `approved`, there's nothing to reopen — just apply the fix as normal.
3. If it IS currently `approved`: compare that doc's phase (`analysis`→`analysis`,
   `task/PLAN.md`→`breakdown`) against the project's actual current phase
   (`…/{{PW_HOME}}/tooling/pw-lib.sh phase <slug>`), using the fixed order `context < analysis <
   breakdown < executing < review < done`:
   - **Same phase** (the common case — nothing has advanced past this doc yet, e.g. mid-RFC
     negotiation where `Status:` is still `analysis`) → reopen it automatically:
     `…/{{PW_HOME}}/tooling/pw-lib.sh review reopen <slug> <canonical-review>`, then apply the fix.
     This is the ordinary case and needs no confirmation — a bare `/pw-review <slug>` used for its
     everyday purpose will only ever hit this branch, never the one below.
   - **Doc's phase is EARLIER than the current phase** (only reachable by explicitly naming an
     earlier phase/file — the project has already moved on, e.g. `Status:` is `executing` and
     you're fixing analysis post-hoc) → **STOP and ask me to confirm before reopening.** A later
     phase already relied on this approval (execution may have real commits depending on the PLAN
     gate you're about to invalidate) — never do this silently. Only call `review reopen` after I
     explicitly say to proceed.

**If a single item's ask names 3+ distinct concerns/sections** (e.g. it touches several repos'
worth of design at once), first list every target heading by name before touching anything, apply
all of that item's edits across those headings in one coherent pass, then run consistency checks
**once** at the end for that item — never per-section, per-edit re-checks. When re-checking for
stale references after a rewrite, use one combined `grep -rnE 'pat1|pat2|pat3'` pass rather than N
serial single-pattern greps.

For each `[OPEN]` item in the resolved files:
- apply the fix to the doc it reviews — **if that doc is `analysis/<topic>.md`, rewrite its §1–4
  prose cleanly in place** (never append, never add an `(Rn)`/`(Qn)` tag or "supersedes"/"the user
  asked" narration there) and add exactly **one** terse line to its §5.1 Decisions log instead —
  that's the only place the tag belongs; see the template's own style-rule comment. **When the fix
  adds real depth to §3/§4, keep the density rule in force while rewriting** — one fact per
  (sub-)bullet, short table cells, fold into an existing `### 4.N` subsection before adding a new
  one — a fold-in is exactly the moment §4 tends to sprawl one subsection at a time; don't let this
  round be the one that does it,
- edit that SAME `### Rn · …` heading in place — flip `[OPEN]` → `[RESOLVED]` and its trailing
  `pw-item-status` marker together; **never add a second heading for the same item** (that's what
  makes consecutive items in the file visually run together — one heading per item, always),
- append a concrete reply as a quoted line directly below the item's ask, one blank line between
  them: `> ↳ **agent** (<YYYY-MM-DD HH:MM>): <section(s) + exactly what changed>` — never a bare
  "fixed"/"done", and **never restate my ask** (R-items never get a `↳ you:` line; my ask is
  already sitting right there as the item's own body text),
- add a `---` rule after the reply, before the next item.

**Also process the "## Open questions" section (QnA):** for each `Qn` whose `> ↳ **you**:` line has
an answer, fold that answer into the reviewed doc, edit that SAME `### Qn · …` heading in place
(flip `[PENDING]` → `[ANSWERED]` + marker — never a second heading), append
`> ↳ **agent** (<timestamp>): …` right after my `↳ you:` line inside the same quoted block (one
blank quoted line between the two), and add a `---` rule before the next question. Leave unanswered
`Qn` rows untouched and report them as still blocking.

Never edit or delete my comment text (items OR my `↳ you:` answers). Never write the Sign-off row
— only I clear the gate. Log the pass (this is the ONLY dashboard-adjacent write you make):
`…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> review "<n> items resolved in <file>"`. Then refresh
that file's `## Contents` table: `…/{{PW_HOME}}/tooling/pw-lib.sh review reindex <slug>
<review-rel-path>` — a heading just changed status, so the table would otherwise go stale.

**Archive once several items have piled up resolved** — a concrete trigger, not a vibe: once 3+
items/questions in this file are `[RESOLVED]`/`[ANSWERED]` since the last archive, or the file
itself has passed ~150 lines, run `…/{{PW_HOME}}/tooling/pw-lib.sh review archive <slug>
<review-rel-path>`. This moves them verbatim into a sibling `<topic>.archive.md`, never touches
`[OPEN]`/`[PENDING]` headings or the Sign-off table (see `docs/REVIEW.md`), and is what keeps a
long-lived review file from forcing every future round to re-read its whole resolved history.

**Opportunistically seed memory too — IF a memory tool is configured** (skip silently otherwise;
see `{{PW_HOME}}/tooling/docs/memory.md`). When a resolved item's fix was durable/generalizable
(not just this project's own bookkeeping), seed it — reuse the item's own `↳ agent:` reply text
(or, for an analysis-doc fix, the §5.1 Decisions-log one-liner you're already writing) verbatim as
the payload; never a separate authoring pass. Scope project-specific vs. cross-project per
whatever `PW_MEMORY_NOTES` already documents for this tool's buckets.

When done, recap each resolved item (one line) here, and tell me how many `[OPEN]` items remain
**in the resolved scope** (and, as a footnote, across the whole project:
`grep -rln "pw-item-status: open"` in the project dir). For a task review: after fixes are applied, remind me
to re-run `/pw-execute <slug> T0n` to re-verify in its worktree. **If a gate got auto-reopened**
(the check above), say so explicitly and name which file/phase — that's the one thing here that
changes whether a *later* command will run, so it can't just be buried in the item recap.
