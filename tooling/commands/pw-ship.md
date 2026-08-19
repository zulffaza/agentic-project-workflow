---
description: Push verified task branches and open MRs with rich descriptions
args: <project-slug> [task-ids] [comments]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} (first token = project slug; optional task
IDs to scope to a subset; the word `comments` = go into MR-comment mode, below). Task IDs are
**optional in both modes** — with none, the command applies to **every** eligible task (all
shippable tasks in ship mode; all tasks with an open MR in comment mode).

Project dir: `{{PW_PROJECTS}}/<slug>`.

Publishing is **outward-facing** — this is the explicit "make it public" step, kept separate from
`/pw-execute` so nothing pushes until you run it. `/pw-execute` already committed + verified each
task; here we push branches and open MRs.

## Ship mode (default)
1. Determine which tasks are shippable: `Status: done`/`accepted`, verify passed, a real commit on
   their branch. **Skip zero-change tasks** (note "zero-change — no branch/MR" in their Result) and
   any already-shipped task (Result → MR already set).
   - **Adopted (continuation) project** (dashboard `Adopted:` note / `context/ADOPTED.md`): ship
     **per adopted branch**, not per task — each adopted branch is one shipment. For each, push the
     branch and, if an MR already exists (from `ADOPTED.md → MR:` or a `glab/gh` lookup on the
     branch), **update it — do NOT open a duplicate**; open a fresh MR only if there's genuinely none
     yet. With several units, that's one MR per adopted branch.
2. **Confirm before anything goes out.** List, for each shippable task: repo, branch
   (`agent/<slug>/<T0n>-<slug>`), target base branch, and the MR title. Ask me to confirm the list.
   Only after I say go:
3. For each confirmed task, from its worktree
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - Push the branch to origin.
   - Open an MR **targeting the task's Base branch** with a rich description (template below).
     **Resolve the forge + CLI per `tooling/docs/forges.md`** (host from this repo's own `origin`
     remote → `PW_FORGE_HOSTS` override, else auto-detect) — GitLab: `glab` run from inside the
     worktree with `GITLAB_HOST=<resolved-host>`; GitHub: `gh pr create`. Never hardcode a host.
   - Record the MR in the task's `## Result → MR:` field **and** the dashboard **Merge requests**
     table (Task · Repo · MR url · Target branch · State=open), then log it:
     `…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> ship "T0n pushed <branch>; MR <url>"`.
4. Recap: one line per task (branch → MR url → state). Remind me that **open/on-hold MRs don't block
   `/pw-close`** — `accepted` means verified + MR opened + my sign-off; merging is downstream.

### MR description template (make it genuinely useful — this is what a reviewer reads first)
```
## What & why
<1–3 sentences: the change and the reason. Link the task: task/T0n.md.>

## Changes
- <file/area>: <what changed>
- …

## Verification
<the exact `## Verify` command(s) run, and the real output — "BUILD SUCCESS, 0 failures", test
counts, etc. Note any pre-existing/environmental failures and that they reproduce on the base branch.>

## Notes for the reviewer
- **Pinned/kept as-is:** <e.g. "kept lib X at 1.2 — bumping is out of scope, tracked as follow-up">
- **Risk / blast radius:** <what could break, how it's mitigated / behind a flag>
- **Follow-ups / out of scope:** <deliberately not done here>

Part of project `<slug>` (task T0n).
```
Fill every section from the task file + its `## Result`; don't ship a bare "updates X" description.

## MR-comment mode  (`/pw-ship <slug> [task-ids] comments`)
Handle review comments left on the **MR itself**. **Scope:** with task IDs, only those; **with no
task IDs, sweep EVERY task that has an open MR** (`## Result → MR:` recorded, state open) — so
`/pw-ship <slug> comments` clears review comments across all of the project's MRs in one run.

0. **Resolve the set** of tasks to process (the given IDs, or all tasks with an open MR). Announce
   the list. Then, **for each task in the set**, do steps 1–3 in its own worktree:
1. Fetch **every** open comment thread. **Read `tooling/docs/forges.md`'s "Standalone vs diff-anchored
   comments" section in full before writing this step** — it documents the exact fields, verified
   against real production MR data (an earlier version of this instruction relied on the wrong
   field and a real reviewer follow-up was silently missed as a result):
   - **GitLab:** `glab api projects/:id/merge_requests/<iid>/discussions` (run from inside the repo
     with `GITLAB_HOST=<resolved-host>`) — one call returns everything. For each note, in order:
     1. `notes[].system == true` → GitLab's own activity log (approvals, "added 1 commit", the
        security-scan bot, description changes) — **not** reviewer feedback, skip it.
     2. Otherwise, if `resolvable == true` → trust `resolved`. **Do not additionally filter on
        whether the note has a diff `position`/is `type: DiffNote`** — a general "Start thread"
        comment (no diff line) can be `resolvable: true` too, and is exactly as actionable as a
        diff comment. Filtering on diff-position is the concrete bug that caused a real, open
        reviewer thread to be missed entirely.
     3. Otherwise (`resolvable == false`, not system) → a genuine one-off standalone comment; the
        forge can **never** report it resolved. Check the local tracking table instead (below).
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
     thread, so don't assume pushing a fix closed it out; you must explicitly resolve it (below).
   - **Freshness guard — `/discussions` can lag the raw notes table.** Verified 2026-08-10: a
     brand-new, perfectly normal `DiffNote` (visible immediately in the GitLab web UI) was still
     completely absent from `/discussions` **20+ minutes** after posting, on a self-hosted GitLab
     instance. Before concluding "nothing open," cross-check freshness:
     - **GitLab:** also fetch `glab api projects/:id/merge_requests/<iid>/notes?sort=desc&order_by=updated_at`
       (a flat, un-grouped list straight off the notes table — no `discussion_id` in it, so it can't
       replace `/discussions` for replying/resolving, only for detecting staleness). Take its newest
       `system == false` entry's `id`/`created_at`.
     - **GitHub:** compare `gh api repos/:owner/:repo/pulls/<n>/comments` (or the issue-comments
       list)'s newest entry the same way, if you suspect the same class of lag there.
     - If that note's `id` doesn't appear anywhere in the `/discussions` pull, retry `/discussions`
       once or twice with a short pause. If it's *still* missing:
       - **Don't report "no open threads."** Surface the note's body/file/line in the recap as
         "detected via /notes, not yet in /discussions — forge indexing lag" and read what it's
         asking so you're not blocked on understanding it.
       - You do **not** have a `discussion_id` yet, so you can't reply-in-thread or resolve it
         properly. Apply the code fix in the worktree as normal, then reply with a **plain new
         top-level note** (`POST .../notes` with just a `body` — no `discussion_id` needed) that
         quotes the file/line and the original comment text, explicitly noting the thread hadn't
         synced into the discussions API yet. Record it in the local tracking table (step 3) as
         `unresolvable` with a note explaining the degraded reply, so a **human** re-checks once the
         real discussion eventually appears (don't try to auto-reconcile the two IDs later — flag it
         instead).
       - This is a genuinely stuck case for the tool, not a decision to make silently — call it out
         in the recap rather than treating the plain-note reply as equivalent to a normal resolved
         thread.
   - A task whose MR has no open/unrecorded threads at all is skipped (note it in the recap).
2. Apply the fixes in that task's **worktree**, re-run its `## Verify`, and push.
3. **Reply to every thread you acted on — general/no-diff comments included — AND mirror it into
   the internal record:**
   - **Reply on the thread itself.** GitLab: `POST` a new note into that same discussion (works
     whether or not it's resolvable). If it's `resolvable: true` **and has no diff position**
     (won't auto-resolve from your push), also explicitly resolve it:
     `glab api -X PUT projects/:id/merge_requests/<iid>/discussions/<discussion-id> -f resolved=true`.
     GitHub diff comments: reply in that review-comment thread; GitHub standalone/conversation
     comments have no native reply-thread API — post a new PR comment (`gh pr comment`) that quotes
     or clearly references the original so the connection is legible to the reviewer.
   - **Record it via the helper — this is what makes resolvable-general and unresolvable comments
     idempotent across reruns:**
     `…/{{PW_HOME}}/tooling/pw-lib.sh ship comment-seen <slug> <T0n> <thread-id> <resolvable|unresolvable> yes`
     Do this for **every** thread you replied to — it upserts a row into
     `task/review/T0n.review.md`'s `## MR comment tracking` table keyed by thread ID, which step 1
     reads back on the next run. Without this call, an unresolvable comment (which the forge can
     never mark resolved) either gets silently skipped forever or re-processed every single run.
   - Also mirror as usual: task `## Result`, a `[RESOLVED]` item in `task/review/T0n.review.md`'s
     `## Items` section (create the file first via `pw-lib.sh review-init` if it doesn't exist yet),
     and a `LOG.md` line via the helper. The project dir stays the source of truth even for
     MR-driven changes.
4. **Recap** a table — one row per task in the set: Task · Repo · MR · threads addressed (note how
   many were general/no-diff-position) · verify (green/failed) · pushed?. Flag any task whose verify
   failed after the fix (leave it for review) and any thread you couldn't resolve without a decision.

Process the set **serially by default** (each is a real edit-verify-push in a worktree); parallelize
only independent repos if you're confident. Never merge an MR as part of this command — merging is a
human decision downstream.
