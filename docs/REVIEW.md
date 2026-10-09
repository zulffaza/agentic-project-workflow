# Review & feedback

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) ·
[Adoption](./ADOPTION.md) · [Execution & routing](./EXECUTION.md)

## Start with your review task

Record feedback, apply it, inspect the revision, then approve it.
Adding an item or answering a question does not apply the correction by itself.

| You need… | Use |
|---|---|
| Copyable feedback and approval commands | [Review recipe](RECIPES.md#record-feedback-answers-and-approval) |
| Review an analysis or PLAN | [Local review files](#1-local-review-files-pre-ship) |
| Fix a reviewer's MR comment | `/pw-ship <slug> [task-ids] comments` and [MR review](#2-the-mr-review-flow-post-ship) |
| An AI pass that keeps human approval | [Advisory recipe](RECIPES.md#use-ai-review-with-human-approval) |
| Understand automatic approval safeguards | [AI-assisted review](#3-ai-assisted-review-optional-per-phase) |

Use `/pw-help project <slug> pw-review` for paths and commands matched to your actual project.

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

### Create or find a review file

`/pw-analyze` creates the matching analysis review. `/pw-breakdown` creates PLAN's review.
They start empty and in review. To create missing files:

| Command | Scope |
|---|---|
| `/pw-review <slug> init <artifact-path> [artifact-path…]` | Exactly the existing artifacts you name; one invalid entry rejects the whole list |
| `/pw-review <slug> init-all` | Missing reviews for the current dashboard phase only |

Rerunning either command preserves existing review content and history.
`init-all` covers analysis docs during `analysis`, PLAN and current task plans during `breakdown`,
and current task results during `executing`/`review`. It creates none implicitly during `context`/`done`.

<a id="add-feedback-with-section-and-text"></a>
### Add feedback with `--section` and `--text`

Use this form when recording a change request, especially for a heading with spaces:

```text
/pw-review delivery-note item task/review/PLAN.review.md --section Execution strategy --text Run compatibility tests before storefront changes
```

| Argument | What to put there |
|---|---|
| `<slug>` | Project name, here `delivery-note` |
| `item` | The action that records a new feedback item |
| `<review-path>` | Project-relative review file; here `task/review/PLAN.review.md` |
| `--section` | Heading or anchor in the reviewed artifact; here `Execution strategy` in `task/PLAN.md` |
| `--text` | The requested change; here `Run compatibility tests before storefront changes` |

Both flags belong to `item`. Each value continues until the next `--flag` or the command ends.
Multi-word values need no quotes. For a single section token, the shorter form also works:

```text
/pw-review delivery-note item task/review/PLAN.review.md §4 Add compatibility tests
```

The operator creates the next `Rn` item with its section, timestamp, and `[OPEN]` status.
It also refreshes the review file's contents table. Your first new item after approval queues a fresh review cycle automatically.
Recording the item does not apply the change yet.

### Apply feedback to the scope you choose

| Command | Reviews processed |
|---|---|
| `/pw-review <slug> analysis` | Files in `analysis/review/` |
| `/pw-review <slug> plan` | Files in `task/review/`, including PLAN and individual task reviews; `task` is an alias |
| `/pw-review <slug> task/review/PLAN.review.md` | Only PLAN's review file |
| `/pw-review <slug> T01 T02` | The named tasks' review files |
| `/pw-review <slug>` | Scope inferred from the current phase |

`plan` is a scope word. The actual plan artifact is `task/PLAN.md`.
For inferred scope, `analysis` uses analysis reviews, `breakdown` uses task reviews,
and `executing`/`review` targets tasks currently marked `verify-failed`.

### Answer questions and approve the revision

| Action | Command |
|---|---|
| Answer an existing question | `/pw-review <slug> answer <review-path> Q2 <your answer>` |
| Approve the reviewed artifact | `/pw-review <slug> signoff <review-path> approved` |
| Request changes or leave the gate open | `/pw-review <slug> signoff <review-path> changes-requested` or `in-review` |

`answer` records your response; the next apply pass incorporates it and resolves the question.
Free text after `Q2` is your answer, including spaces.

Read the revised artifact and replies before approving it. `signoff` runs only when you explicitly request that decision.
Resolving items alone does not grant human approval. The guarded AI `auto` mode is described below.
Hand-editing remains supported; the [review template](../template/_REVIEW.template.md) includes syntax hints.

### Item status and gate history

There are two statuses to read: the per-item tag (`[OPEN]`→`[RESOLVED]`) is flipped by the
**agent** after it addresses your item — you never set it. The only status *you* decide is the
**gate** in the Sign-off table (`in-review` / `changes-requested` / `approved`). Writing an item
does **not** require you to set any status; you just leave it `[OPEN]` and run `/pw-review`.

**Who writes which row.** The Sign-off table is append-only history, and every row names its
author in the `By` column:

| `By` value | When that row appears | Decisions it can hold |
|---|---|---|
| `you` (or a named human) | An explicit sign-off you asked to record | `in-review` · `changes-requested` · `approved` |
| `pw-review (feedback)` | Your first new item or answer queues a review cycle; a previous `approved` stops being the live decision | `in-review` |
| `pw-review (repair)` | A `/pw-review` pass starts on real actionable work in that file | `changes-requested` |
| `pw-reviewer (advisory; provider=…, model=…)` | An independent AI pass filed real findings | `changes-requested` |
| `pw-reviewer (auto; provider=…, model=…)` | Same, plus the guarded `auto`-mode approval | `changes-requested` · `approved` |

Read the row's author alongside its decision:

- Feedback and repair rows track workflow activity. They never record `approved` or claim you made a decision.
- An AI row records the reviewer that actually ran, with `unknown` when runtime identity cannot be confirmed. A fallback records its own attempt.
- Your explicit `changes-requested` remains in force until you record `in-review` or `approved` again. Automatic rows never erase your rejection.
- Legacy rows remain valid history, including rows without identity fields.

New timestamps use forms such as `5 October 2026 23.11 WIB`. Older formats remain accepted and can coexist in one table.

### What to expect from the agent

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
  one, so it can't sneak a phase forward (see the `By` table above). Your own decisions
  and their bookkeeping stay visibly distinct by the `By` attribution; see
  [docs/RFC.md](./RFC.md) for why the post-approval invalidation exists.
- Task review is optional. Only PLAN approval gates execution. To reject a result, tell the agent what failed and ask it to record `verify-failed`.
  Add feedback to the task review, or describe the correction in chat. `/pw-review <slug> T0n` creates a missing review for a `verify-failed` task and applies the repair.
  Task repair normally re-runs `## Verify`. Use `/pw-execute <slug> T0n` if the repair remains unverified or checks still fail.
- **Who applies a fix.** Pre-execution artifacts (analysis doc, PLAN, task doc) are edited
  **inline by the driver** — the review file is the work order; no separate session is spawned and
  what you re-read is the edited doc. Post-execution *task* fixes follow the **same routing ladder
  as execution** ([docs/EXECUTION.md](./EXECUTION.md) §The per-spawn ledger): same provider → an
  in-process fixer you can watch (a single task may be fixed inline by the driver); different
  provider → a supervised headless session that resumes the executor's recorded session **only
  when a deterministic liveness check reports it resumable**; ≥2 tasks with open items fan out as
  parallel per-task fixers. One batched pass per artifact in every case — never one pass per item.

Find the current review files and their open-item counts:

```text
/pw-help project <slug> pw-review
```

Open the named review file and use its contents table to jump to an item.

Keep this separate from the dashboard's **decision log** (that's "why we chose X", durable
rationale) — review files are the transient back-and-forth that empties out as items resolve.

### Review-file maintenance is automatic

Review commands keep the active file short and navigable:

| Part of the file | What the workflow maintains |
|---|---|
| `## Contents` | Item IDs, anchors, and statuses, refreshed when a write adds or resolves a heading |
| Resolved items and answered questions | Moved verbatim to a sibling archive during review maintenance, with pointers left in `## Archived items` |
| Open items, pending questions, and `## Sign-off` | Kept in the active file; archiving preserves these records |

Use the review commands to add feedback or answers. You do not need a separate reindex or archive command.
The contents table uses heading anchors, so an item remains findable after the document changes.

If an older review file asks you to run internal scripts, preview its recognized guidance updates with:

```text
/pw-doctor --project <slug> --guidance
```

Follow the [preview/apply/recheck recipe](RECIPES.md#refresh-old-project-guidance-after-a-workflow-update).
This updates old instructions while preserving review items and decisions.

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

**Pending description delivery is checked before MR-state skips.** A rerun recovers saved attempts
without repeating completed pushes or replies. Closed/merged MRs retain pending project records
without another body write; worktree cleanup does not erase that evidence.

**MR state is then checked per task** (the ship flow queries the forge directly):
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
        ├─ 0. RECOVER pending description delivery, then CHECK MR state — merged/closed/unknown ⇒
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
        ├─ 4. REFRESH the current MR summary and DELIVER one frozen attempt for this invocation
        │                          — preserve prior attempts, reviewer text, and actual verification
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

### Description and review-attempt history

One `/pw-ship … comments` invocation creates at most one attempt per MR, even when it handles
many comments, commits, and CI repairs. Tasks sharing one adopted branch/MR share that attempt.
An empty sweep creates none. Thread IDs and reply links remain in the local record, not a noisy
request list in the description.

The main description stays current: What & why, High-level changes, Low-level changes,
Verification, and Notes for the reviewer are inside one owned summary region. Obsolete claims
are replaced rather than accumulated. Review changes is last and shows newest attempts first,
each attempt collapsed under a `Review attempt: <date> - <time> WIB` heading so the list stays
readable; your reviewer-facing text above it stays open. New event times carry the dashed
`D MMMM YYYY - HH.mm WIB` separator; earlier records keep whatever they stored, and both forms
mean the same instant.

Each attempt contains Changes with Before/After/Summary bullet lists, Commits as individual
bullets, and Verification combining local checks and pipeline results, each tied to its head.

Completed attempt blocks never change. Later pipeline evidence belongs to the later invocation,
not an edit to earlier history. A delivery-only retry reuses the saved block and original order.
If a documented body limit requires space, only complete oldest blocks are removed; their full
local archive remains. Reviewer text, the newest block, and required evidence are never truncated.

The recap reports description delivery separately from push, replies, tests, and pipeline state.
`description update pending` means the body did not verify after delivery. `summary refresh pending`
means history can be present while an ambiguous legacy or newer-head summary still needs repair.
Do not treat either outcome as a fully current description. Resolve the reported ownership, capacity, or delivery error, then rerun `/pw-ship … comments`.
Failed delivery remains recoverable locally. See [pending description recovery](TROUBLESHOOTING.md#changes-were-pushed-but-the-mr-description-update-is-pending) for retry steps and GitLab HTTP 415 failures.

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
comments). If a comment is missing from the recap, follow [MR comment troubleshooting](TROUBLESHOOTING.md).

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
/pw-config myproj set ai-review plan=auto    # e.g. let the plan-review gate run itself
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
