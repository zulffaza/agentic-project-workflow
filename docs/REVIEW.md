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
`task/review/PLAN.review.md` (idempotently, via `pw-lib.sh review-init`, from
[`_REVIEW.template.md`](../template/_REVIEW.template.md)) as their last step, already in-review and
empty. It ships with **worked examples**, a **decision-status legend**, and — permanently, even
once items exist — a one-line **"how to add an item / answer a question" hint** right under each
section heading, so the syntax is always there to copy from. Each item has an **ID + section
anchor** (`R1 · §2`) and a status tag: `[OPEN]` / `[RESOLVED]` — plain bracket text, nothing to
hunt down and copy-paste.

**Two dials, don't confuse them:** the per-item tag (`[OPEN]`→`[RESOLVED]`) is flipped by the
**agent** after it addresses your item — you never set it. The only status *you* decide is the
**gate** in the Sign-off table (`in-review` / `changes-requested` / `approved`). Writing an item
does **not** require you to set any status; you just leave it `[OPEN]` and run `/pw-review`.

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
- Only **you** write an `approved` Sign-off row — an agent cannot self-approve a gate (the one
  narrow, heavily-guarded exception is AI-assisted `auto` mode below). The tooling has one *other*
  narrow exception in the opposite direction: on analysis's or the PLAN's own review file, `/pw-review`
  auto-appends an `in-review` row (tagged `pw-review (auto-reopen)`) if a fix lands there after it
  was already `approved` — this only ever *closes* a gate, never opens one, so it can't be used to
  sneak a phase forward; see [docs/RFC.md](./RFC.md) for why this exists.
- **Task review is optional, and created on demand.** Only the PLAN sign-off gates execution. To
  reject an **execution** result, flip that task's `Status: verify-failed` and either add items to
  `task/review/T0n.review.md` **or** just tell the agent what's wrong — `/pw-review <slug> T0n`
  creates the review file (via `pw-lib.sh review-init`, same as above) if it doesn't exist, applies
  the fix, then `/pw-execute <slug> T0n` re-runs just that task and re-verifies.

List everything still needing work across a project:
```bash
grep -rln "pw-item-status: open" projects/<project-slug>/
```

Keep this separate from the dashboard's **decision log** (that's "why we chose X", durable
rationale) — review files are the transient back-and-forth that empties out as items resolve.

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

### How it flows

```
reviewer leaves a comment on MR !123 (thread on file X, line N — OR a general/no-diff comment)
        │
        ▼
/pw-ship <slug> T03 comments
        │
        ├─ 1. FETCH open threads   glab api …/merge_requests/<iid>/discussions   (or gh pr view --comments
        │                          + gh api …/pulls/<n>/comments — GitHub needs BOTH endpoints)
        │                          — classify by `system`/`resolvable`/`resolved`, NEVER by whether
        │                          it has a diff position (see box below); cross-check the local
        │                          tracking table, not just the forge's resolved flag
        ├─ 2. FIX in the worktree  worktree/<repo>/T03-<slug>/ … edit, re-run ## Verify, push
        ├─ 3. REPLY on each thread  summarising the fix (never a bare "done") — general comments too;
        │                          explicitly resolve a resolvable-but-general thread (no auto-resolve)
        └─ 4. MIRROR into the project dir  ← the important bit
                 • task/T03.md  ## Result   (what changed + verify output)
                 • task/review/T03.review.md  (create it if missing — a [RESOLVED] item per thread,
                   PLUS a row in its `## MR comment tracking` table via
                   `pw-lib.sh ship comment-seen <slug> T03 <thread-id> <resolvable|unresolvable> yes`)
                 • LOG.md line via pw-lib.sh log
```

### ⚠️ A general MR comment (no diff line) can still need action
A reviewer can "Start a thread" from an MR's Overview tab, not just from a diff line — that
general comment can be just as actionable as one anchored to a line, so the fetch step never
filters by diff-position. And some comment types can never be marked "resolved" by the forge no
matter what — for those, `/pw-ship … comments` checks the **local** `## MR comment tracking` table
in `task/review/T0n.review.md` (written by `pw-lib.sh ship comment-seen`) instead of waiting on a
forge-side flag that will never flip (the same pattern `/pw-rfc comments` uses for RFC-platform
comments). The exact API fields this relies on, and why, are in
[`tooling/docs/forges.md`](../tooling/docs/forges.md#standalone-vs-diff-anchored-comments-both-forges--read-before-writing-a-fetch-comments-step)
— only worth opening if you're implementing a new forge or debugging a missed comment.

### Why the mirror matters (the reconciliation rule)
An MR comment lives in your Git host, which the project dir doesn't automatically know about. If a
fix only happened in reply to an MR thread, the project's record would silently diverge from what
actually shipped. So the rule is: **the project dir stays the source of truth even for MR-driven
changes.** Every MR-comment fix lands in three places — the MR thread reply (for the reviewer), the
task `## Result` + a `task/review/T0n.review.md` item (for the project record), and `LOG.md` (for
the audit trail). After a pass you can still answer "what was asked and what changed?" entirely from
the project dir, without opening the MR.

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
an agent command, never a shell script:
```
/pw-review myproj config              # view all 5 phases' current modes, in plain language
/pw-review myproj config plan auto    # e.g. let the plan-review gate run itself
```
Each phase (`analysis` / `plan` / `task-plan` / `task-exec` / `ship`) is independently `off`
(default — nothing changes), `advisory`, or `auto`:

| Mode | What happens |
|---|---|
| `off` | No AI reviewer involved. Identical to everything in sections 1–2 above. |
| `advisory` | `pw-reviewer` files items into the normal `.review.md`, tagged `(pw-reviewer, <timestamp>)` so they're never confused with a human's. **A human still writes the Sign-off row** — this is a pre-filter, not a replacement. |
| `auto` | Same filing, but if the pass leaves **nothing** [OPEN] or [PENDING], `pw-reviewer` may sign off itself, via a guarded tool call that independently re-checks both conditions. |

**Run it** with `/pw-review <slug> ai [phase|Tid|path]` — same scope resolution as the normal
`/pw-review`. Under the hood this spawns the `pw-reviewer` agent fresh, in-process, same provider
(or hand the artifact + the standalone `pw-review` skill to a completely different agent/session
yourself, if you want it run somewhere with zero shared context at all).

**On `auto`'s self-approval** — this is the one place this feature changes an existing invariant
("only a human clears a gate"), so it's deliberately the most auditable part: the Sign-off row
always reads `pw-reviewer (auto)` in the "By" column, never blended with a human "you" row, and the
underlying tool (`pw-lib.sh review auto-signoff`) refuses outright unless the project's mode for
that phase is genuinely `auto` **and** the file has no real open item/question left — it doesn't
take the reviewer's word for either.

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
