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
anchor** (`R1 · §2`) and a status dot: 🔴 open / 🟢 resolved.

**Two dials, don't confuse them:** the per-item dot (🔴→🟢) is flipped by the **agent** after it
addresses your item — you never set it. The only status *you* decide is the **gate** in the Sign-off
table (`in-review` / `changes-requested` / `approved ✅`). Writing an item does **not** require you
to set any status; you just leave it 🔴 open and run `/pw-review`.

**The contract:**
- You write items. The agent **never edits or deletes your text** — it appends a `↳ agent:` reply
  and flips 🔴→🟢. Your words stay the source of truth for what was asked.
- **How you know what the agent did:** the `↳ agent:` reply is a concrete summary per item (which
  section, what changed). The agent also recaps the resolved items in chat after each pass.
- Before editing any doc, the agent reads its `.review.md` first. `/pw-review` never changes the
  dashboard Status.
- Only **you** write the Sign-off row. An agent cannot self-approve a gate — an `approved ✅` row is
  what clears a phase.
- **Task review is optional, and created on demand.** Only the PLAN sign-off gates execution. To
  reject an **execution** result, flip that task's `Status: verify-failed` and either add items to
  `task/review/T0n.review.md` **or** just tell the agent what's wrong — `/pw-review <slug> T0n`
  creates the review file (via `pw-lib.sh review-init`, same as above) if it doesn't exist, applies
  the fix, then `/pw-execute <slug> T0n` re-runs just that task and re-verifies.

List everything still needing work across a project:
```bash
grep -rln "🔴 open" projects/<project-slug>/
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
                 • task/review/T03.review.md  (create it if missing — a 🟢 resolved item per thread,
                   PLUS a row in its `## MR comment tracking` table via
                   `pw-lib.sh ship comment-seen <slug> T03 <thread-id> <resolvable|unresolvable> yes`)
                 • LOG.md line via pw-lib.sh log
```

### ⚠️ Don't filter by diff-position — verified case of a real thread getting missed
An earlier version of this doc said GitLab's `individual_note` field tells a diff-anchored comment
from a general one, and that only diff-anchored threads are resolvable. **That's wrong**, and
following it (or the more common shortcut of only looking at notes with a diff `position`) causes a
real failure mode: a general/no-diff MR comment can still be `resolvable: true` — GitLab lets you
"Start a thread" from the Overview tab, not just from a diff line — and in a real production MR this
showed up as `individual_note: false`, `resolvable: true`, `resolved: false`, containing a
reviewer's unaddressed follow-up ("I still want it to be executed parallel, please fix"), which was
completely missed because the fetch step only ever surfaced diff-positioned (`DiffNote`) comments.

**The fields that actually matter** (verified against real MR API responses — see
[`tooling/forges.md`](../tooling/forges.md#standalone-vs-diff-anchored-comments-both-forges--read-before-writing-a-fetch-comments-step)
for the full breakdown and a `jq` recipe):
- `notes[].system == true` → GitLab's own activity log (approvals, commit-push notices, the
  security-scan bot) — not reviewer feedback, skip it. This is the real noise filter.
- `notes[].resolvable` → can the forge *ever* report this resolved? True for diff-anchored **and**
  general "thread" comments alike; false only for a genuine one-off "Comment" (diff or general) —
  those can never be marked resolved via the API, no matter how many replies they get.
- `notes[].resolved` → only meaningful when `resolvable: true`. GitLab **auto-resolves a
  diff-anchored thread when its line changes on a later push** — but does **not** auto-resolve a
  resolvable *general* thread just because you pushed a fix; that one needs an explicit resolve call
  or it looks open forever even after being fixed.
- Diff-position (`position`/`type: DiffNote`) is informational only — **never** the filter for
  whether something needs action.

Two failure modes follow from getting this wrong: (1) filtering on diff-position **silently drops
real general-comment threads entirely** — they never surface as something to act on (the case
above); (2) for a genuinely `resolvable: false` comment, a naive "is it still open?" check based on
the forge's resolved bit will say yes **every single run**, causing endless re-processing (or, if an
agent gives up and treats "always open" as "must already be handled," the opposite mistake of
ignoring it). `/pw-ship … comments` fixes (2) by checking the **local** `## MR comment tracking`
table in `task/review/T0n.review.md` (written by `pw-lib.sh ship comment-seen`) instead of the
forge's resolved state for anything `resolvable: false` — the same pattern `/pw-rfc comments`
already uses for RFC-platform comments via `pw-lib.sh rfc comment-seen`.

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
