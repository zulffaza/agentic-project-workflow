# MR-comment fixes (post-ship)

Loaded by `/pw-ship comments` (and by the `/pw-ship stack` comment cascade). The command
owns dispatch, the `--resolve` opt-in contract, and the pre-flight `comments` gate; this
file owns the comment-handling procedure: invocation and pending delivery, MR-state
resolution, one fixer pass per MR, reply/resolve, the recap, and the stacked cascade.

## MR-comment mode procedure

### Invocation and pending delivery
Before MR-state skips, cleanup, or the no-open-comments shortcut, run
`{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh history --project <slug> --operation pending`.
Recover frozen pending description writes without repeating completed pushes, tests, or replies.
Closed/merged MRs keep their project-owned records and receive no description write.
Do not remove pending records when accepting tasks or removing worktrees.

Generate one call ID with `pw-ship.sh history --project <slug> --operation invocation` and retain it in the run ledger.
After discovering actual review work, group tasks by resolved forge/host/repository/MR identity.
For each distinct MR, run `pw-ship.sh history --project <slug> --operation begin --mr <MR-url> --options --invocation <call-id>` once.
Retain its returned attempt key, start timestamp, before head, and body snapshot. Reuse them through
all comments, commits, pushes, CI repairs, and any resumed interrupted invocation. An empty sweep
creates no attempt; delivery-only recovery does not create a new one.

Before handling work, checkpoint the planned evidence with current published head and explicit
not-yet-run verification. Update the checkpoint after each fix/push/verification and before
acknowledging replies with `comment-seen`. If persistence fails, stop further acknowledgement
and description delivery. Author text from actual code/diff/results; the helper does not invent it.

Use `pw-ship.sh history --project <slug> --operation checkpoint --mr <MR-url> --options --attempt <key> --file <JSON-file>`.
The JSON object contains `before`, `after`, `summary` string-bullet lists, a `commits` list
of `{sha, subject, published}` objects, `verification` objects `{head, text}`, actual published
`head`, and `summary_body` (only the complete marked current-state summary). Optional `tasks`
and namespaced `comments` retain local traceability and never appear as comment-reference lists.
Use full recorded SHAs in checkpoints, including intermediate CI failures and local-only commits.

At the end of this invocation's MR work, freeze one consolidated block with
`pw-ship.sh history --project <slug> --operation freeze --mr <MR-url> --options --attempt <key>`.
Never split that call into one block per comment, task, fixer pass, or CI repair.
Publish with `pw-ship.sh history --project <slug> --operation deliver --mr <MR-url> --options --attempt <key>
--limit <documented-number> --unit <utf8|chars> --limit-source <reference>`.
Resolve the forge/instance's documented capacity and measurement unit first; unknown capacity
must be reported as pending, not guessed or inferred from a rejected write. Pass argv quote-safe.
The helper uses explicit forge host/repo API calls, JSON stdin, and readback. It never pushes or replies.

Visible blocks contain Changes with Before/After/Summary bullet groups, a flat Commits list,
and Verification with both local and pipeline/check outcomes. No Request field, comment IDs/URLs,
or separate CI section. Refresh the main description to the actual latest published whole-MR diff,
replacing obsolete statements instead of accumulating bullets. Local-only work is labeled as such.
Review changes is the final section, after reviewer notes and preserved outside text; attempts
are newest-first and previously frozen blocks remain byte-identical. Only complete oldest blocks
can be pruned at capacity; the full local archive and pruned-key metadata survive retries.
Late pipeline evidence from a later call belongs to a new verification-only attempt, never an edit
to a previous block. No new evidence/work means no new block or timestamp-only description write.
Ownership conflicts, malformed markers, capacity failure, or failed readback remain pending.
Unmarked legacy summaries are preserved; report `summary refresh pending` and obtain a reviewed
ownership repair rather than claiming the description is fully current.
Only after explicit owner approval of a repaired, currently published marked body, use
`pw-ship.sh history --project <slug> --operation init --mr <MR-url> --options --file <reviewed-current-body> --reviewed`.
This ownership repair is **human-triggered only, never on agent initiative**. It verifies exact
readback and retained history before adopting the summary snapshot; it is not permission to edit history.
An initial snapshot failure retains its creation body locally; retry `history ... init <MR-url>`
from the retained payload before starting new review work.

Handle review comments left on the **MR itself** — **all open threads on one task arrive as ONE fixer pass** for that task's worktree (a batched `seed-review-batch`, per-thread replies mirrored
into `task/review/T0n.review.md`; the pass is routed by the §routing ladder —
`references/execution-and-routing.md` — not by blind resume: same-provider single task → you fix
it inline; `Route: headless` → resume iff `pw-session.sh session-check --project <slug> --task <task-id>` says the recorded id is
live, else inline fallback; cross-provider → resume-first-then-supervised-cold-headless), not one
run per comment. And when a fix *lands* on a task whose dependents
already ran, apply the **§3.6 fan** exactly once: merge the fixed branch → re-run each already-run
dependent's own `## Verify` (clean → stays `done`; conflict/regression → that dependent's own flip,
driver-side) + ≤1 `dep-impact:T0n` review-style pass where their files/landing units actually
overlap — filed as items for the dependent's batch, never a direct edit into it. **Scope:** with task IDs, only those, plus (for a selected **stacked** task) its transitive stack descendants, per the cascade section below; **with no
task IDs, sweep EVERY task that has an open MR** (`## Result → MR:` recorded, state open) — so
`/pw-ship comments --project <slug>` clears review comments across all of the project's MRs in one run.

0. **Resolve the set** of tasks to process (the given IDs, or all tasks with an MR). **Check MR
   state for the whole set in one call** before proceeding — `pw-ship.sh mr-state-batch` (no task-ids =
   every PLAN task; prints `task-id|state` per line, plain-text pipe-delimited; per-line semantics
   identical to the helper it wraps):
   ```bash
   {{PW_HOME}}/tooling/scripts/entities/pw-ship.sh mr-state-batch --project <slug> [--task <T0n>]…
   ```
   Read each line's state per the bullets below (a single-task `state` recheck mid-flow can still
   use `pw-ship.sh mr-state --project <slug> --task <task-id>`).
    - **If `merged`**: The MR was already merged downstream. Handle it:
      1. Accept the task — ONE call sets all three acceptance holders (task-file `Status:`, the
         PLAN task-table cell the close gate reads, and the dashboard task row; the dashboard is
         best-effort): `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh task-accept --project <slug> --task <task-id> --observed-merged`
      2. Update dashboard MR table: `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh dashboard-mr-state --project <slug> --task <task-id> --state merged`
      3. If the task is **stacked** or a stacked **parent**, settle the stack before removing
         anything: record its landing (`stack-land`) and each open child's promotion debt
         (`stack-promote`), per "Comment fixes on a stack (cascade)" below. The recovery refs and
         child debt must exist **before** the removal in the next step. An independent task skips
         this.
      4. Remove worktree: `{{PW_HOME}}/tooling/scripts/entities/pw-worktree.sh remove --project <slug> --task <task-id>`
      5. **Skip this task** — do NOT attempt to fetch/process comments.
   - **If `closed`**: The MR was closed without merging. Note it in the recap and skip.
   - **If `open`**: Proceed with comment processing (steps 1–3).
   - **If it prints `unknown`** (no MR URL/worktree/origin, or the forge query failed or returned
     null — the helper exits 1): Note it as `mr-state-unknown` and skip.
   
   Announce the list, separating `open` tasks (will process) from `merged`/`closed`/`unknown`
   tasks (will skip). Then, **for each task with an open MR**, do steps 1–3 in its own worktree:
1. Fetch **every** open comment thread. **Read `tooling/docs/forges.md`'s "Standalone vs diff-anchored
   comments" section in full before writing this step** — it documents the exact fields, verified
   against real production MR data (an earlier version of this instruction relied on the wrong
   field and a real reviewer follow-up was silently missed as a result):
   - **GitLab — use `/notes` as the primary source, NOT `/discussions`.**
     The `/discussions` endpoint has persistent indexing lag — notes can be visible in the GitLab
     web UI and `/notes` API **20+ minutes** before appearing in `/discussions`. Using `/discussions`
     as the primary source silently misses unindexed threads. Verified 2026-08-26: multiple
     DiffNote threads on the same MR were present in `/notes` but absent from `/discussions` for
     the entire duration of a multi-hour review session.

     **Discovery (always use `/notes`):**
     ```bash
     glab api projects/:id/merge_requests/<iid>/notes?sort=desc&order_by=updated_at
     ```
     For each note:
     1. `system == true` → GitLab's own activity log — skip it.
     2. Otherwise, check the local tracking table (below) for this note ID. If the row is
        recorded with `replied=yes` and its evidence marker names this same feedback revision,
        skip it — it is already addressed (open or closed, depending on the run that handled it).
        A row with no evidence marker, or a newer reviewer reply / edited note than the recorded
        revision, is **not** already handled: process it.
     3. Otherwise, this is an actionable note. Read its `body`, `position.new_path`,
        `position.new_line`, `resolvable`, and `resolved` fields.

     **Reply/resolve (use `/discussions` only when needed):**
     When you need to reply in-thread or resolve a `resolvable: true` thread, look up the
     `discussion_id` from `/discussions`:
     ```bash
     glab api projects/:id/merge_requests/<iid>/discussions
     ```
     Search for the note ID within the discussions response. If found, use the `discussion_id`
     to reply (`POST .../discussions/<id>/notes`) and resolve (`PUT .../discussions/<id> -f resolved=true`).
     If **not found** (still lagging), reply with a **plain new top-level note**
     (`POST .../notes` with just a `body` — no `discussion_id` needed) that quotes the file/line
     and the original comment text, explicitly noting the thread hadn't synced into the discussions
     API yet. Record it in the local tracking table as `unresolvable` with a note explaining the
     degraded reply, so a **human** re-checks once the real discussion eventually appears.
   - **GitHub:** two separate endpoints, both needed — `gh pr view --comments` (standalone/general
     PR conversation comments) **and** `gh api repos/:owner/:repo/pulls/<n>/comments` (diff-anchored
     review comments). `gh pr view --comments` alone misses every inline review comment.
   - **Resolve the forge + CLI per `tooling/docs/forges.md`** (same per-repo resolution as ship mode).
   - **Before treating anything as "already handled," check the local tracking table** —
     `task/review/T0n.review.md`'s `## MR comment tracking` section (see step 3) — for that
     thread/comment ID. Only the forge's `resolved` flag is trustworthy for a `resolvable: true`
     thread; for a `resolvable: false` one, **the local table is the only source of truth** for "did
     I already reply to this." Also remember: GitLab auto-resolves a diff-anchored thread when its
     underlying line changes (a later push can silently flip `resolved` with no explicit API call)
     — but that auto-resolve does **not** happen for a resolvable *general* (no diff position)
     thread.
   - **An open thread this run handled is still "handled" — open ≠ actionable.** Because the
     default no longer resolves threads, a resolvable-but-still-open thread is not automatically
     "not actionable." Treat it as handled when the local row records the same feedback revision
     (its evidence marker, step 3): skip the fix, and with `--resolve` close it without re-fixing.
     A newer reviewer reply or an edited note changes the revision and returns the thread to triage.
     A row with no evidence marker (legacy) is not proof — re-check the live thread before skipping
     or resolving it. Likewise, when the *same thread* surfaces through a fresh note ID you have not
     recorded, process that feedback even if an earlier note in the thread was answered.
    - A task whose MR has no open/unrecorded threads is skipped only after pending-description
      recovery and any newly observed matching-head verification evidence (note it in the recap),
      **unless** it is a stacked descendant pulled in by the cascade: its inherited code changed, so
      it still gets its inherited update and its own `## Verify` (see the cascade section below).
2. **Analyze the whole set once, then fix one MR at a time:** before any fixer starts, dispatch the
    single `pw-ship-comment-analyst` prerequisite over every MR that has actionable work (see
    "Comment analysis prerequisite" below). No source edit begins until its artifact is complete and
    validated. Then apply all fixes for one MR in that MR's shared **worktree**, re-run its
    `## Verify` once for the batch, and push. Within one MR, process the analyst's fix groups
    **sequentially**; groups never run as parallel writers. For tasks sharing one MR, use the union of
    their comment-tracking tables, reply once per thread, and mirror the result/tracking into every
    contributing task.
    If those tasks have incompatible execution pins, serialize bounded owner work orders under
    their recorded pins; never edit the shared branch concurrently or invent a replacement pin.
    Aggregate all such passes under the same invocation/MR attempt.
    Fan-out per the ladder and the project `max-parallel`: **≥2 distinct MRs with open threads →
    one fixer per MR, admitted only when they are independent and a slot is free** (independent
    worktrees; each routed by the ladder — same provider → in-process sub-agent,
    `Route: headless`/cross-provider → supervised headless). `max-parallel` is a shared project
    ceiling across fixers, analysts, reviewers, and delegated verification — never a per-MR
    allowance. A queued MR waits for a slot; spare capacity never justifies an extra writer.
    A stacked ancestor and its descendant are **never** fixed concurrently, and run parent-first
    per the cascade section below; **exactly one MR, same
   provider, `Route: auto|subagent` → you fix it inline** (bounded exception to the no-source-edit
   rule: listed items only, run its `## Verify`, commit, reply per item); `Route: headless` single
   task → resume-try iff `pw-session.sh session-check --project <slug> --task <task-id>` exits 0, dead/failed →
   inline fallback (`resume-failed→inline` + `model-degraded` in the ledger). Where a session is
   resumed, you are handing it a work order, not re-deriving context from a cold spawn.
   - **A landed fix on a dependency fans the §3.6 passthrough** onto tasks *already run* from it:
     each affected dependent re-merges its dependency and re-runs **its own** `## Verify` (conflict
     = that dependent's own `verify-failed`; the driver flips statuses, never the fixer); where
     file/landing-unit overlap is real, one `dep-impact` reviewer pass files items into the
     dependent's queue — no edit-backward into the fixed task, new DAG task if it needs one.
    - **Unless `--skip-build-check` was passed:** monitor the pipeline/checks to a terminal state
      right after this push via `{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh monitor --project <slug> --task <task-id>`
      (same contract as ship mode — see "Build check" below), before moving on to step 3 — so a failed
      build shows up in the recap and can be mentioned in the thread reply, not discovered later.
      A **red** build → the task is **not done**: enter the build-check fix loop below (fix in the
      worktree, re-verify, push, re-monitor) until it passes or the cap is hit.
3. **Reply to every thread you acted on — general/no-diff comments included — then, only with
   `--resolve`, close the ones you fixed; and mirror the result into the internal record:**
   - **Reply on the thread itself — always, either mode.** GitLab: `POST` a new note into that same
     discussion (works whether or not it's resolvable). GitHub diff comments: reply in that
     review-comment thread; GitHub standalone/conversation comments have no native reply-thread API
     — post a new PR comment (`gh pr comment`) that quotes or clearly references the original so the
     connection is legible to the reviewer.
   - **Default (no `--resolve`): leave every thread OPEN.** Do **not** call any resolve or unresolve
     endpoint. A handled thread stays open for you to inspect. Never describe a thread as closed
     because the fix landed — say "addressed — left open for review".
   - **Only with `--resolve`, close a thread when all of these hold:** it is `resolvable: true`; its
     fix landed on the branch you pushed this run; the batch `## Verify` passed on that published
     head; and, when the build check ran, the pipeline/checks reached a green terminal state. With
     `--skip-build-check` the required local `## Verify` passing is sufficient — and both the thread
     reply and the recap must say CI was skipped. GitLab: `glab api -X PUT
     projects/:id/merge_requests/<iid>/discussions/<discussion-id> -f resolved=true` (covers diff
     threads and resolvable general threads). GitHub: use the review thread's own resolve operation;
     a standalone/conversation comment has no native resolved state — never invent one. **Read the
     thread back after resolving** and record the observed state. If the fix failed, verification
     failed, the head is unknown, or CI is red/pending/unreadable, leave it open and say why in the
     recap. A resolve request that fails: keep the fix and reply evidence, report the thread as still
     open, and retry only the pending resolve — never claim closure from an unconfirmed request. If
     the forge already auto-resolved a diff thread on push, record that observation without a second
     write and without reopening it.
   - **Record it via the helper — this is what makes resolvable and unresolvable comments idempotent
     across reruns, whether a thread was left open or closed:**
     `…/{{PW_HOME}}/tooling/scripts/entities/pw-ship.sh comment-seen --project <slug> --task <T0n> --thread <thread-id> --kind <resolvable|unresolvable> --replied yes --feedback <seen-revision> --reply <reply-id> --head <published-head>`
     Do this for **every** thread you replied to — it upserts a row into
     `task/review/T0n.review.md`'s `## MR comment tracking` table keyed by thread ID, which step 1
     reads back on the next run. `--feedback` is the reviewer-feedback revision you handled (the
     latest actionable note id, or a short fingerprint of its text+timestamp), `--reply` is your own
     reply's note id, and `--head` is the verified published head. All three are optional, but a row
     without `--feedback` cannot prove the current feedback was handled, so the next run re-checks
     it. Without this call, an unresolvable comment (which the forge can never mark resolved) either
     gets silently skipped forever or re-processed every single run.
    - **Checkpoint and deliver the description through `history`, never ad-hoc forge body edits.**
      Retain the invocation/MR key, aggregate all comment and CI work, freeze once, and deliver
      using the protocol above. Preserve older blocks and external edits. Readback and the
      helper's `summary refresh pending` result determine the delivery recap, not an API exit alone.
   - Also mirror as usual: task `## Result`, a `[RESOLVED]` item in `task/review/T0n.review.md`'s
     `## Items` section (create the file first via `pw-review.sh init-docs --project <slug> --file task/T0n.md`
     if it doesn't exist yet — init-all only ever covers the current dashboard phase), and a `LOG.md` line via the
     helper. Write the mirrored item + its resolution deterministically via
     `pw-review.sh add-item --project <slug> --file task/review/T0n.review.md --section <§anchor> --text <finding> --actor pw-reviewer` then `pw-review.sh resolve --project <slug> --file task/review/T0n.review.md --item <Rn>` — never
     a hand-copied heading block. The project dir stays the source of truth even for MR-driven
     changes.
4. **Recap** a table — one row per task in the set: Task · Repo · MR · state (open/merged/closed) ·
   threads addressed (note how many were general/no-diff-position) · **thread resolution** (how many
   left open for your review — the default — versus closed under `--resolve`) · verify
   (green/failed) ·
   pushed? · build result (or "skipped" if `--skip-build-check` was passed) · description delivery
   (verified / pending / history delivered but summary pending). Flag any task whose
   verify failed after the fix (leave it for review) and any thread you couldn't resolve without a
   decision. Under the default, link the threads you left open so they are easy to review; under
   `--resolve`, flag any resolve request that failed or was skipped. For `merged` tasks, note that
   the worktree was removed and docs updated.

Independent MRs may run concurrently within `max-parallel`; groups inside one MR stay sequential.
Dependencies, stack barriers, shared-MR ownership, and provider/runtime capacity still decide what is
ready — repository count alone proves nothing. Never merge an MR as part of this command — merging is
a human decision downstream.

### Comment analysis prerequisite

One `pw-ship-comment-analyst` pass covers the whole selected scope before any fixer starts. It is
read-only and uses the project `AI Models: ship-comment-analyst` row (provider/session default when
unset). Do not duplicate its investigation in the driver first, and do not launch one analyst per MR.

- **Work order:** the resolved task/MR set, task-to-MR mapping, pins, tracking pointers,
  dependency/stack evidence, and a driver-assigned output path **outside the source checkout** (for
  example `worktree/.pw-ship-comments/<invocation>.json`). The analyst fetches the comments itself.
- **Returns:** a versioned manifest with the input snapshot (heads, tree/index state, comment IDs and
  feedback revisions), an interpretation and disposition per actionable comment, confirmed/potential/
  not-applicable cross-MR mapping, ordered fix groups per MR, a proposed fixer DAG with reasons, and
  explicit pending decisions. Every discovered candidate has a disposition; nothing disappears into a
  group.
- **Validate before dispatch:** coverage of the selected scope, exact input freshness, proposed edges
  against the approved execution DAG and recorded stack topology, and that no pending decision was
  converted into work. The analysis supplements the DAG; it never removes a dependency barrier or
  creates a stacked branch.
- **Authorization:** a comment like "do this for the other tasks too" is a cross-MR candidate, not
  permission to widen scope. Confirmed applicability plus an already-authorized target may become a
  bounded work order; potential applicability or an unselected target stays pending for the human.
- **No fabrication:** a target MR without a reviewer comment gets a bounded derived work order and
  **no invented thread or reply**.
- **Staleness:** re-check each fixer's head, tree/index state, feedback revisions, and pins before
  dispatch. If they moved, invalidate affected work orders and refresh with the analyst before
  editing; unrelated completed work is not replayed.
- **Failure:** no valid artifact means no fixing. Report the blocker and keep pending-delivery
  recovery separate. If the chosen route cannot enforce read-only source access, stop rather than
  running the analyst as a writer.
- **Bookkeeping:** log the analyst spawn through `pw-status.sh log` with its session id and output
  path. Keep its session separate from a task's canonical executor `Session:` pointer.

An empty sweep, or one whose only work is pending description delivery, needs no new analyst. New
actionable feedback always needs the prerequisite, even for a single small comment.

### Comment fixes on a stack (cascade)

When a selected task is stacked (or has stacked descendants), an upstream fix must reach **every
affected descendant** with fresh verification and an explicit publication result:

- Selecting `A` expands to A's transitive stack descendants (`pw-ship.sh stack`/`stack-plan` show
  the set and order). Descendant MRs with **no comments** are still updated — inherited code changed.
- **Order is parent-first.** Fix and settle `A` first (batch its comments, run its `## Verify`, bind
  it with `pw-ship.sh stack-verify --project <slug> --task A --evidence <captured-verify-output>`), then drive the mechanical
  propagation with the deterministic operator (one per invocation):
  `pw-ship.sh stack-cascade --project <slug> --task A --verify-cmd '<descendant Verify command>' [--evidence-dir <dir>] [--push]`.
  It walks descendants root-first and, per descendant, integrates the immediate parent's recorded
  verified head (normal merge; no merge when already contained), runs your Verify command, binds the
  tuple through `stack-verify --head`, records the inherited update, and — only with `--push` (the
  publication authorization) — normal-pushes already-shipped MRs. An **unstarted** descendant (its
  branch exists nowhere) is recorded with the new prerequisite head and every stage is skipped
  (terminal): no branch, worktree, push, or Verify is created for it, and independent siblings still
  run. An existing branch without a mounted worktree is integrated in a rehydrated worktree at the
  approved task-worktree location — the shared clone's checkout is never touched. Fixes stay with the
  fixer ladder: run each descendant's comment batch before its Verify. Coalesce all known upstream
  changes into **one** descendant update for the invocation. Never run concurrent ancestor and
  descendant fixers; independent stack components and settled siblings may run in parallel.
- **Publication is separate from fixing.** Already-run unpublished descendants get local integration
  and verification but stay unpublished unless separately selected and authorized. Unstarted
  descendants just record the new prerequisite head and consume it at spawn.
- **Reply only where a reviewer asked.** Post the outcome on A's original threads; do **not**
  fabricate replies on descendants that received only inherited updates. `stack-cascade` records the
  inherited update deterministically (`stack-inherited`: a `- **Inherited:**` bullet + LOG line with
  the upstream commit); no reviewer-comment text is invented. Refresh each shipped descendant's MR
  description through the `history` protocol as an inherited-update round (never a fake reviewer
  request), and keep its `describe` stage pending until that delivery lands.
- **Before outward writes**, show the selected comment tasks, affected descendants, publication
  actions, and blocked ancestors. Thread resolution follows the same `--resolve` policy for each
  handled thread; a descendant that received only an inherited update never has its own threads
  resolved. If expanded publication lacks approval, run without `--push`: the
  pending push/describe stages keep the stack blocked and the run reports it incomplete.

**Failure and freshness:** if A fails verification, do not publish or advance descendants. If a
child conflicts, `stack-cascade` aborts that merge and blocks that child's subtree (independent
stacks continue). If a child fails verification, keep its local commit, do not push, and block later
descendants. A descendant whose recorded tuple no longer covers its current head, parent, or target
is **stale** automatically (`stack`/`stack-plan` derive this from live Git); `pw-ship.sh stack-stale`
forces the flag when a local change has not yet been re-verified. A never-started descendant (no
tuple, no branch, still todo) reads **unverified** in the read-only preview — it must bind before
its own publication, but it never blocks an ancestor's incremental ship; a done/accepted task
without its binding is stale, not unverified, and always blocks. Stale debt blocks execution,
shipping, acceptance consumption, and close readiness until `stack-verify` re-binds the tuple —
`stack-verify` writes the whole tuple (including the CI disposition) in one atomic record write, so a
half-written binding cannot certify anything. Bind CI explicitly with
`--ci-sha <sha|skipped|pending>`: an old-target or old-head green never carries across a retarget,
and `failed` blocks until replaced. A merged parent promotes its children only when the promotion
target is published on the freshly fetched origin; move the MR base with `stack-retarget --apply`,
which writes its pending recovery row first, verifies state/target/head before and after the forge
write, and resumes without a duplicate write when a previous attempt published remotely but failed
locally. Every cascade persists stages (`stack-op`) keyed by the upstream commit, so a rerun
**resumes** pending stages instead of duplicating merges, pushes, replies, or inherited-update
records; a pending `retarget:<task>` row is resumed before any noop shortcut, and the description
(`describe`) stage clears only after the history delivery is done
(`stack-op set <key> '<T0n>:describe=done'`).
