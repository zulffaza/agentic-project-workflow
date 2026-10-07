# Review & feedback

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) ·
[Adoption](./ADOPTION.md) · [Execution & routing](./EXECUTION.md)

There are **two places** review happens, and they run at different times:

| When | Where you comment | What you're reviewing | Command |
|------|-------------------|-----------------------|---------|
| **Before ship** (steps 3, 5, 8) | a local `*.review.md` file | analysis, the plan, a task's result | `/pw-review` |
| **After ship** (step 7+) | comments **on the MR itself** | the pushed diff, in your Git host's UI | `/pw-ship <slug> [task-ids] comments` |

Both feed the **same source of truth** — the project dir. MR comments never live only on the MR;
they get mirrored back in. The two sections below cover each in turn.

A **third, more read-only variant** services comments on a published RFC doc (see
[docs/RFC.md](./RFC.md)) — it only *pulls* threads into a local review file; unlike the MR flow
below, the agent never fixes-in-worktree or replies on the thread, since RFC comments are prose
feedback you resolve yourself.

---

## 1. Local review files (pre-ship)

Feedback does **not** go inline in the doc being reviewed — the agent rewrites that doc when it
applies fixes and would clobber your notes. Instead, each reviewed artifact gets its own review file
in a **`review/` subdir** beside it, which is the durable record of what you asked for:

| Reviewing | Review file |
|-----------|-------------|
| `analysis/spring-boot-3.md` | `analysis/review/spring-boot-3.review.md` |
| `task/PLAN.md` | `task/review/PLAN.review.md` |
| `task/T03.md` | `task/review/T03.review.md` |

(The `review/` subdir keeps reviews from cluttering the result docs — `task/` can hold a dozen
`T0n.md` files, so their reviews live under `task/review/`.) **You don't create these yourself** —
`/pw-analyze` and `/pw-breakdown` auto-create `analysis/review/<topic>.review.md` and
`task/review/PLAN.review.md` (idempotently, from
[`_REVIEW.template.md`](../template/_REVIEW.template.md)) as their last step, already in-review and
empty. Missed one? **`/pw-review <slug> init <artifact-path> [<artifact-path> …]`** creates the
review files for exactly the documents you name — one or many, and nothing else (a wrong entry
rejects the whole list before anything is written; rerunning is safe and never overwrites history).
**`/pw-review <slug> init-all`** is the catch-up for the project's **current dashboard phase**: in
the `analysis` phase it creates analysis-doc reviews, in `breakdown` the PLAN + current task-plan
reviews, while `executing`/`review` covers current task-result artifacts — it never creates
earlier- or later-phase reviews, and `context`/`done` create none implicitly. The template ships
with **worked examples**, a **decision-status legend**, and — permanently, even once items exist —
a one-line **"how to add an item / answer a question" hint** right under each section heading, so
the syntax is always there to copy from. Each item has an **ID + section anchor** (`R1 · §2`) and a
status tag: `[OPEN]` / `[RESOLVED]` — plain bracket text, nothing to hunt down and copy-paste.

**You don't hand-copy those blocks either.** The write side of a review file is deterministic —
one `/pw-review` operator per kind of edit, each writing the exact house shape (heading, timestamp,
machine marker, `---` rule, quoted `↳` line) and refreshing `## Contents` for you:

```
/pw-review <slug> init <artifact-path> [<artifact-path> …]          review files for exactly the docs you name
/pw-review <slug> init-all                                          … for the CURRENT dashboard phase's docs only
/pw-review <slug> item <path> §4 <your ask, spaces and all>         add the next Rn item
/pw-review <slug> answer <path> Q2 <your answer>                    add your ↳ you: line under Q2
/pw-review <slug> signoff <path> approved                           append your Sign-off row
                                    (or: changes-requested / in-review)
```

Free text is everything after the last fixed argument — no quoting needed. Hand-editing stays
legal (the hints in the file teach the syntax), but the operators are the recommended path: they
never forget the marker, the rule, or the reindex. **`signoff` is yours alone** — the agent runs
it only when your message explicitly asks for that gate decision, never on its own initiative
(the one guarded exception remains AI `auto` mode, below).

**Two dials, don't confuse them:** the per-item tag (`[OPEN]`→`[RESOLVED]`) is flipped by the
**agent** after it addresses your item — you never set it. The only status *you* decide is the
**gate** in the Sign-off table (`in-review` / `changes-requested` / `approved`). Writing an item
does **not** require you to set any status; you just leave it `[OPEN]` and run `/pw-review`.

**Who writes which row.** The Sign-off table is append-only history, and every row names its
author in the `By` column:

| `By` value | When that row appears | Decisions it can hold |
|---|---|---|
| `you` (or a named human) | An explicit sign-off you asked for, filled by hand | `in-review` · `changes-requested` · `approved` |
| `pw-review (feedback)` | Your first new item or answer queues a review cycle; a previous `approved` stops being the live decision | `in-review` |
| `pw-review (repair)` | A `/pw-review` pass starts on real actionable work in that file | `changes-requested` |
| `pw-reviewer (advisory; provider=…, model=…)` | An independent AI pass filed real findings | `changes-requested` |
| `pw-reviewer (auto; provider=…, model=…)` | Same, plus the guarded `auto`-mode approval | `changes-requested` · `approved` |

The operational rows are bookkeeping, not judgment: they never claim you rejected or approved
anything, and feedback/repair rows never read `approved`. The provider/model in an AI row is the
reviewer that **actually ran** the pass, not the configured pin, the orchestrator, or the artifact
author; a fallback records the new identity as its own attempt, and a runtime that cannot confirm
identity records `unknown`. A `changes-requested` you explicitly recorded stands until you
record `in-review` or `approved` again; automatic rows never erase your rejection. Legacy rows
(`pw-review (auto-reopen)`, plain `pw-reviewer (auto)`, rows without identity fields) stay valid
history and remain readable. New review rows and item stamps read like
`5 October 2026 23.11 WIB` (day, month, year, dot-minutes); files already using older date-time
formats are accepted as-is, and both forms can sit in one table.

**The contract:**
- You write items. The agent **never edits or deletes your text** — it edits that item's SAME
  heading in place (flips `[OPEN]`→`[RESOLVED]`, never adding a second heading) and appends a quoted
  `> ↳ agent: …` reply below your ask, followed by a `---` rule before the next item. Your words
  stay the source of truth for what was asked — the reply never restates them.
- **How you know what the agent did:** the `↳ agent:` reply is a concrete summary per item (which
  section, what changed) — never a bare "fixed"/"done". The agent also recaps the resolved items in
  chat after each pass.
- Before editing any doc, the agent reads its `.review.md` first. `/pw-review` never changes the
  dashboard Status.
- **Applying one item only needs that item's own block** — the file's own `## Contents` table
  (heading-text-anchored, 🤖-owned) points straight at the section it targets, so the agent never
  needs to read the whole file — and never the archived resolved history (below) — to apply a
  single new item.
- Only **you** write an `approved` Sign-off row — an agent cannot self-approve a gate (the one
  narrow, heavily-guarded exception is AI-assisted `auto` mode below). Agents *are* allowed to
  record **operational rows** — workflow bookkeeping that only ever closes a gate, never opens
  one, so it can't sneak a phase forward (see "Who writes which row" below). Your own decisions
  and their bookkeeping stay visibly distinct by the `By` attribution; see
  [docs/RFC.md](./RFC.md) for why the post-approval invalidation exists.
- **Task review is optional, and created on demand.** Only the PLAN sign-off gates execution. To
  reject an **execution** result, flip that task's `Status: verify-failed` and either add items to
  `task/review/T0n.review.md` **or** just tell the agent what's wrong — `/pw-review <slug> T0n`
  creates the review file (same as above) if it doesn't exist, applies
  the fix, then `/pw-execute <slug> T0n` re-runs just that task and re-verifies.
- **Who applies a fix.** Pre-execution artifacts (analysis doc, PLAN, task doc) are edited
  **inline by the driver** — the review file is the work order; no separate session is spawned and
  what you re-read is the edited doc. Post-execution *task* fixes follow the **same routing ladder
  as execution** ([docs/EXECUTION.md](./EXECUTION.md) §The per-spawn ledger): same provider → an
  in-process fixer you can watch (a single task may be fixed inline by the driver); different
  provider → a supervised headless session that resumes the executor's recorded session **only
  when a deterministic liveness check reports it resumable**; ≥2 tasks with open items fan out as
  parallel per-task fixers. One batched pass per artifact in every case — never one pass per item.

List everything still needing work across a project:
```bash
grep -rln "pw-item-status: open" projects/<project-slug>/
```

Keep this separate from the dashboard's **decision log** (that's "why we chose X", durable
rationale) — review files are the transient back-and-forth that empties out as items resolve.

**A review file doesn't grow forever.** Two tools keep a long-lived one (many rounds, dozens of
items) cheap to work with instead of turning every future round into "re-read the whole resolved
history to apply one new item":
- **reindex** (re)builds the `## Contents` table at the
  top — ID, section/anchor, status — for every real item/question, so applying one means jumping
  straight to it instead of scanning start-to-finish. Anchored by heading TEXT, never a line
  number, so it never goes stale on a rewrite; safe to re-run any time.
- **archive** moves every fully `[RESOLVED]`/`[ANSWERED]`
  heading, verbatim, into a sibling `<topic>.archive.md` — leaving a one-line pointer row in a
  `## Archived items` table. It **never** touches `[OPEN]`/`[PENDING]` headings or the `##
  Sign-off` table, since the gate logic (gate read / reopen / auto-signoff) only
  ever reads those two things — archiving is provably gate-safe. Run it once several items have
  piled up resolved (a few, or the file getting long) rather than waiting for it to feel unwieldy.

---

## 2. The MR review flow (post-ship)

Once `/pw-ship` opens an MR, a **second** review entry point exists: comments left directly on the
MR in your Git host (GitLab / GitHub). These come from *other* reviewers (or you, reviewing the real
diff). They are handled by a dedicated mode of `/pw-ship`, **not** `/pw-review` — because fixing
them means going back into the task's worktree and pushing, which is ship-side work.

**One MR or all of them.** `/pw-ship <slug> T03 comments` handles a single task's MR;
**`/pw-ship <slug> comments`** (no task IDs) sweeps **every** open MR in the project in one run —
so you don't have to invoke it per task. It processes them serially (each is a real
edit → verify → push) and recaps a per-task table at the end.

**MR state is checked first, per task** (the ship flow queries the forge directly):
`merged` → the MR was already merged downstream — accept the task, update the dashboard, remove the
worktree, and skip it (never process comments on a merged MR); `closed` → note it and skip; `unknown`
(the forge query failed or couldn't resolve the MR) → note it as `mr-state-unknown` and skip. Only
`open` MRs are actually processed. `/pw-sync` does the same pre-check before refreshing a branch.

### How it flows

```
reviewer leaves a comment on MR !123 (thread on file X, line N — OR a general/no-diff comment)
        │
        ▼
/pw-ship <slug> T03 comments
        │
        ├─ 0. CHECK MR state   per-task forge query — merged/closed/unknown ⇒
        │                      accept/update dashboard/remove worktree + skip; only open MRs proceed
        │
        ├─ 1. FETCH open threads   GitHub: gh pr view --comments + gh api …/pulls/<n>/comments (BOTH
        │                          endpoints, or inline review comments are missed).
        │                          GitLab: glab api …/merge_requests/<iid>/notes — the PRIMARY source
        │                          (/discussions lags 20+ min; use it only to look up discussion_id
        │                          for reply/resolve). Classify by `system`/`resolvable`/`resolved`,
        │                          NEVER by diff position (see box below); cross-check the local
        │                          tracking table, not just the forge's resolved flag
        ├─ 2. FIX in the worktree  worktree/<repo>/T03-<slug>/ … edit, re-run ## Verify, push
        │                          (build-check monitors the pipeline here too, unless
        │                          --skip-build-check was passed)
        ├─ 3. REPLY on each thread  summarising the fix (never a bare "done") — general comments too;
        │                          explicitly resolve a resolvable-but-general thread (no auto-resolve)
        ├─ 4. REFRESH the MR description  every round, not just the first — add what this round
        │                          fixed, update the verification output, adjust reviewer notes
        └─ 5. MIRROR into the project dir  ← the important bit
                 • task/T03.md  ## Result   (what changed + verify output + build-check result)
                 • task/review/T03.review.md  (create it if missing — a [RESOLVED] item per thread,
                   PLUS a row in its `## MR comment tracking` table —
                   the flow records each thread's kind + replied-state there)
                 • LOG.md line via the flow's log step
```

**The description goes stale otherwise.** A reviewer (or you, later) reads the MR description
first — if it still only describes the original diff after three rounds of review fixes, it's
actively misleading. Refreshing it is as mandatory as replying on the thread, just easy to forget
since the forge doesn't prompt for it the way an unresolved thread does.

**Build check runs by default, in both modes:** polls the MR's pipeline/checks to a terminal state
(green/red/still-running) and shows the result in the recap and the task's `## Result` — meaning a
plain run now waits on CI before it finishes. Pass `--skip-build-check` to opt out and get the
immediate-return behavior back — `/pw-help command pw-ship` spells out the exact per-forge
mechanics, the build-check section, and timeout handling. **A red build means that task is NOT done:** the
agent diagnoses the failure, fixes the change in the worktree, re-runs the task's `## Verify`,
pushes, and re-monitors until the pipeline passes — up to 3 fix rounds, then it stops and surfaces
the failure for you (the same help output covers the build-check fix loop). With `--skip-build-check`, the
whole check (and the fix loop) is skipped.

### ⚠️ A general MR comment (no diff line) can still need action
A reviewer can "Start a thread" from an MR's Overview tab, not just from a diff line — that
general comment can be just as actionable as one anchored to a line, so the fetch step never
filters by diff-position. And some comment types can never be marked "resolved" by the forge no
matter what — for those, `/pw-ship … comments` checks the **local** `## MR comment tracking` table
in `task/review/T0n.review.md` (written by the comments flow) instead of waiting on a
forge-side flag that will never flip (the same pattern `/pw-rfc comments` uses for RFC-platform
comments). The exact API fields this relies on, and why, live with the machinery —
[TOOLING.md](./TOOLING.md) says where — only worth opening if you're implementing a new forge or
debugging a missed comment.

### Why the mirror matters (the reconciliation rule)
An MR comment lives in your Git host, which the project dir doesn't automatically know about. If a
fix only happened in reply to an MR thread, the project's record would silently diverge from what
actually shipped. So the rule is: **the project dir stays the source of truth even for MR-driven
changes.** Every MR-comment fix lands in four places — the MR thread reply *and* the refreshed MR
description (both for the reviewer), the task `## Result` + a `task/review/T0n.review.md` item (for
the project record), and `LOG.md` (for the audit trail). After a pass you can still answer "what was
asked and what changed?" entirely from the project dir, without opening the MR.

### What each command does *not* do
- `/pw-ship … comments` **never merges** the MR — merging is a human decision downstream.
- `/pw-review` is for the **local** `.review.md` files only; it doesn't touch MRs.
- Bringing a stale MR up to date with its moved base is a *different* concern from review comments —
  that's [`/pw-sync`](./WORKFLOW.md#ship-and-sync), which merges
  the base in and re-verifies. Use `comments` for "a reviewer asked for a change"; use `/pw-sync`
  for "the base moved and the MR needs refreshing".

### The typical post-ship loop
```
/pw-ship  myproj                 # open the MRs
… reviewer comments on MR for T03 …
/pw-ship  myproj T03 comments    # fix + reply + mirror
… base branch moves …
/pw-sync  myproj                 # merge base into all open MR branches + re-verify
… all approved & merged by a human …
/pw-close myproj                 # tear down + learn
```

---

## 3. AI-assisted review (optional, per-phase)

Everything above assumes a human. You can instead (or additionally, as a pre-filter) delegate any
of the five review points — analysis, the plan, a task's plan, a task's execution result, MR/PR
comments — to a **fresh** AI review pass. "Fresh" is the whole point: the reviewer is spawned with
no shared context with whoever produced the artifact, so it's a genuine second opinion rather than
an echo of the producer's own reasoning — the same idea as having someone who's never seen your
draft read it cold, rather than asking yourself "does this look right to me?"

**Turning it on** — one dashboard line per project, five independent phases, viewed/changed through
the config command (never a shell script, and not from `/pw-review` — reviewing is not configuring):
```
/pw-config myproj show                # every axis incl. all 5 phases' modes, in plain language
/pw-config myproj set ai-review plan auto    # e.g. let the plan-review gate run itself
```
Each phase (`analysis` / `plan` / `task-plan` / `task-exec` / `ship`) is independently `off`
(default — nothing changes), `advisory`, or `auto`:

| Mode | What happens |
|---|---|
| `off` | No AI reviewer involved. Identical to everything in sections 1–2 above. |
| `advisory` | `pw-reviewer` files items into the normal `.review.md`, tagged `(pw-reviewer, <timestamp>)` so they're never confused with a human's. **A human still writes the Sign-off row** — this is a pre-filter, not a replacement, even when every finding has been resolved. |
| `auto` | Same filing, but if the pass leaves **nothing** [OPEN] or [PENDING], `pw-reviewer` may sign off itself, via a guarded tool call that independently re-checks its conditions (mode, open counts, artifact/lane match, no standing human rejection). |

**Run it** with `/pw-review <slug> ai [phase|Tid(s)|path]` — same scope resolution as the normal
`/pw-review` (a list of task ids = one fresh reviewer pass per task). Under the hood this spawns the
`pw-reviewer` agent fresh, in-process, same provider
(or hand the artifact + the standalone `pw-review` skill to a completely different agent/session
yourself, if you want it run somewhere with zero shared context at all).

**On `auto`'s self-approval** — this is the one place this feature changes an existing invariant
("only a human clears a gate"), so it's deliberately the most auditable part: the Sign-off row
reads `pw-reviewer (auto; provider=<actual>; model=<actual>)` in the "By" column, never blended
with a human "you" row, and the underlying tool (the auto-signoff step) refuses outright unless
the project's mode for that phase is genuinely `auto`, **and** the file has no real open
item/question left, **and** the artifact actually belongs to the lane being approved, **and** no
explicit human `changes-requested` is still standing — it doesn't take the reviewer's word for
any of them. ("Real" means a *filled* heading: the template's never-used
R1/Q1 stubs — recognized by their live timestamp/section placeholders, including legacy `<YYYY-MM-DD>` — are copies to
fill, not items, so a clean pass over an untouched stub section auto-signs; a filled `[OPEN]`/
`[PENDING]` heading or a stale `pw-item-status: open` marker does not.)

**Reviewer identity on the rows.** The provider/model in an AI row comes from the run that actually
performed the pass (its run metadata), not from the configured spawn-lane pin, not from the
orchestrating session, and not from whatever model wrote the artifact. If routing fell back to
another provider/model mid-run, the row names the actual reviewer and the audit log keeps the
requested identity. A provider or model the runtime cannot confirm shows as `unknown` — never
guessed — and missing identity grants no approval authority. A retry with a different reviewer is
a distinct attempt with its own attribution; plain `pw-reviewer (auto)` rows written before this
attribution shipped stay readable history, without invented provider/model values.

**A clean pass changes nothing unless `auto` approves.** An AI pass may start with no items at all —
reading an artifact does not invalidate an approval or record a row. If it finds real findings it
persists them first (a first real item invalidates a stale approval exactly like feedback does), and
only then records its `changes-requested` pass row; its later internal writes never toggle that
state back. A clean `advisory` pass adds no row and leaves any existing approval alone — you still
sign it off. A clean `auto` pass may approve straight through the guards above; it never first
fabricates a `changes-requested` row. A normal repair pass (`/pw-review` without `ai`) records
`pw-review (repair)` `changes-requested` only when the selected file genuinely has eligible work to
process: a no-op call over stubs, resolved items, or a question merely waiting for your answer adds
no row and is reported as skipped.

**Earlier phases need your explicit go-ahead.** Feedback on an artifact from a phase the project has
already moved past can still be recorded — its open status blocks the next phase from consuming the
now-stale approval even while the historical `approved` row stays untouched. But the gate itself is
not reopened and no repair runs there until you confirm; nothing rewinds the dashboard on its own.

**How open counts are computed.** Every display surface (`pw-status`'s unresolved section,
the review scan, the review lint) reads the same machine predicate as the gates —
the count read → `open=N resolved=M items=K` — and every surface that shows gate state (the
scan's per-file tail, `pw-status`'s blockers, `/pw-help`'s next-steps lines) shows the same
latest decision **and** its `By` actor, read through one shared latest-row reader (legacy rows
included, hyphenated decisions never truncated at a dash). Never grep a review file
raw for `pw-item-status`: the template's guidance line and worked examples contain the marker
*text* as prose and will phantom-count — the shared detector every surface reads is the guard.

**What stops an endless loop** — before filing anything, `pw-reviewer` checks the review file for
an existing item on the same section it's about to flag. A 2nd item on that same section (after
the 1st was marked resolved) is filed as a linked **recurrence** — "the fix didn't hold" — rather
than looking like a brand-new, unrelated complaint. A **3rd** item on that same section gets filed
as a [OPEN] **escalation** instead: pw-reviewer never resolves it itself, which is what keeps
`auto-signoff` genuinely blocked (the tool checks the file, not the reviewer's promise) — a section
that keeps failing the same way forces a human decision instead of spinning forever.

**Reviewer notes — the *why*.** Every AI-review pass appends a dated entry to `REVIEWER-NOTES.md`
(project root, sibling of `LOG.md`): what it checked, why it decided what it decided, and —
sometimes, not every pass — a generalizable **Lesson**. Each entry is short labeled bullets, never
a paragraph, and ends with a `---` rule, so the file stays fast to scan even after many passes.
This is separate from the `.review.md`'s items on purpose: items are the actionable record,
`REVIEWER-NOTES.md` is the reasoning behind them, especially worth reading whenever `auto` mode
approved something without you. A later reviewer pass reads prior entries too; `/pw-close`'s
memory-seeding step folds its Lessons in if you've configured a memory tool (see
[docs/MEMORY.md](./MEMORY.md)) — the file itself is always there regardless.
