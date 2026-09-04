---
description: Push verified task branches and open MRs with rich descriptions
args: <project-slug> [task-ids] [comments] [--skip-build-check]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} (first token = project slug; optional task
IDs to scope to a subset; the word `comments` = go into MR-comment mode, below; `--skip-build-check`
may appear anywhere after the slug, in either mode). Task IDs are **optional in both modes** — with
none, the command applies to **every** eligible task (all shippable tasks in ship mode; all tasks
with an open MR in comment mode).

**Build-check monitoring runs by default** — after the MR is opened/updated (ship mode) or after
each fix is pushed (comment mode), this command also polls that MR's pipeline/checks to a terminal
state and reports the result; see "Build check" near the bottom for the mechanics. **This means a
plain run now waits on CI** (up to the timeout below) before it finishes, unlike before. Pass
`--skip-build-check` to opt out for this run and get the old, immediate-return behavior back.

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
   (`agent/<slug>/<T0n>-<slug>`), target base branch, and the MR title (ticket prefix resolved per
   the convention below). Ask me to confirm the list. Only after I say go:
   - **Ticket-number → MR title convention:** before building the title, check `context/INDEX.md`'s
     `Source` column (ticket / URL / person) for the repo/task in question — for an adopted project,
     also check `context/ADOPTED.md` — for a ticket key (a Jira-style `PROJ-123`, or an equivalent
     issue reference). Found → prefix the title: `[<ticket-number>] <MR title>`. Nothing found →
     plain title, no brackets — **never invent or guess a placeholder ticket**. Different repos in
     the same shipment can carry different tickets — resolve **per repo/task**, not once for the
     whole project. More than one candidate ticket for the same repo/task → list every candidate in
     this confirm step and ask which one; don't pick for me.
3. For each confirmed task, from its worktree
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - Push the branch to origin.
    - Open an MR **targeting the task's Base branch** with a rich description (template below), title
      per the ticket convention above. **Resolve the forge + CLI per `tooling/docs/forges.md`** (host
      from this repo's own `origin` remote → `PW_FORGE_HOSTS` override, else auto-detect) — GitLab:
      `glab` run from inside the worktree with `GITLAB_HOST=<resolved-host>`; GitHub: `gh pr create`.
      Never hardcode a host.
    - **If the task has a `Landing unit:` field** (a must-land-together set from PLAN's `## Landing
      units`): fill the description template's "**Landing unit:**" bullet with the unit name + the
      sibling MRs/URLs of that unit's other tasks, so reviewers review the set as one unit and don't
      mistake an interdependent MR for an independent one.
   - Record the MR in the task's `## Result → MR:` field **and** the dashboard **Merge requests**
     table (Task · Repo · MR url · Target branch · State=open · Build), then log it:
     `…/{{PW_HOME}}/tooling/pw-lib.sh log <slug> ship "T0n pushed <branch>; MR <url>"`.
    - **Unless `--skip-build-check` was passed:** once the MR is open, monitor its pipeline/checks to
      a terminal state (see "Build check" below) and fill the task's `## Result → Build check:` field
      and the dashboard row's `Build` column with the outcome before moving to the next task. A **red**
      build → that task is **not done**: enter the build-check fix loop below (fix in the worktree,
      re-verify, push, re-monitor) until it passes or the cap is hit. If
      `--skip-build-check` was passed, leave both as `—` (not checked this run).
4. Recap: one line per task (branch → MR url → state → build result, or "skipped" if
   `--skip-build-check` was passed) — **group tasks that share a `Landing unit:`** so it's obvious
   which MRs must be reviewed/merged as a set. Remind me that **open/on-hold MRs don't block
   `/pw-close`** — `accepted` means verified + MR opened + my sign-off; merging is downstream.

### MR description template (make it genuinely useful — this is what a reviewer reads first)
```
## What & why
<1–3 sentences: the change and the reason. Link the task: task/T0n.md.>

## High-level changes        ← the behavior, NOT the files (≤3 bullets, no file paths)
- <one bullet per observable behavior change a reviewer should understand — e.g. "partner sync now
  advances a CDC watermark instead of full re-scans", "the endpoint is now idempotent by cursor">

## Low-level changes         ← the concrete diff, anchored to real files (1 line per file/module)
- <file or module>: <what precisely changed — function/endpoint/class names>
- …

## Verification
<the exact `## Verify` command(s) run, and the real output — "BUILD SUCCESS, 0 failures", test
counts, etc. Note any pre-existing/environmental failures and that they reproduce on the base branch.>

## Notes for the reviewer
- **Pinned/kept as-is:** <e.g. "kept lib X at 1.2 — bumping is out of scope, tracked as follow-up">
- **Risk / blast radius:** <what could break, how it's mitigated / behind a flag>
- **Follow-ups / out of scope:** <deliberately not done here>
- **What to review first:** <the 1–2 riskiest spots to eyeball>
- **Landing unit:** <only if this MR must merge as part of a set — the unit name + sibling MRs, so
  reviewers review them together and don't mistake an interdependent MR for an independent one>

Part of project `<slug>` (task T0n).
```
Fill every section from the task file + its `## Result` + the actual diff — don't ship a bare
"updates X" description. Derive **High-level changes** from the task's goal/intent (behavioral,
no paths — that forces real abstraction); derive **Low-level changes** by diffing the branch against
its base (`git diff origin/<base>...<branch>`), grouped per file/module with real identifiers.

## MR-comment mode  (`/pw-ship <slug> [task-ids] comments`)
Handle review comments left on the **MR itself** — **all open threads on one task arrive as ONE fixer pass** for that task's worktree (a batched `seed-review-batch`, per-thread replies mirrored
into `task/review/T0n.review.md`; resume the task's `## Result → Session:` executor by id, cold
re-spawn only if dead), not one run per comment. And when a fix *lands* on a task whose dependents
already ran, apply the **§3.6 fan** exactly once: merge the fixed branch → re-run each already-run
dependent's own `## Verify` (clean → stays `done`; conflict/regression → that dependent's own flip,
driver-side) + ≤1 `dep-impact:T0n` review-style pass where their files/landing units actually
overlap — filed as items for the dependent's batch, never a direct edit into it. **Scope:** with task IDs, only those; **with no
task IDs, sweep EVERY task that has an open MR** (`## Result → MR:` recorded, state open) — so
`/pw-ship <slug> comments` clears review comments across all of the project's MRs in one run.

0. **Resolve the set** of tasks to process (the given IDs, or all tasks with an MR). **Check MR
   state for each task** before proceeding:
   ```bash
   {{PW_HOME}}/tooling/pw-lib.sh mr-state <slug> <task-id>
   ```
   - **If `merged`**: The MR was already merged downstream. Handle it:
     1. Update task status: `{{PW_HOME}}/tooling/pw-lib.sh task-accept <slug> <task-id>`
     2. Update dashboard task table: `{{PW_HOME}}/tooling/pw-lib.sh dashboard-task-status <slug> <task-id> "accepted (MR merged)"`
     3. Update dashboard MR table: `{{PW_HOME}}/tooling/pw-lib.sh dashboard-mr-state <slug> <task-id> merged`
     4. Remove worktree: `{{PW_HOME}}/tooling/pw-lib.sh worktree-remove <slug> <task-id>`
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
     2. Otherwise, check the local tracking table (below) for this note ID. If already recorded
        with `replied=yes`, skip it.
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
     thread, so don't assume pushing a fix closed it out; you must explicitly resolve it (below).
   - A task whose MR has no open/unrecorded threads at all is skipped (note it in the recap).
2. **One executor pass per task, not one spawn per comment** (the §4.8 batch): apply *all* the   open thread fixes in that task's **worktree**, re-run its `## Verify` once for the batch, and
   push. Resume that task's own executor session first when its `## Result → Session:` id is live —
   you are handing it a work order, not re-deriving context from a cold spawn.
   - **A landed fix on a dependency fans the §3.6 passthrough** onto tasks *already run* from it:
     each affected dependent re-merges its dependency and re-runs **its own** `## Verify` (conflict
     = that dependent's own `verify-failed`; the driver flips statuses, never the fixer); where
     file/landing-unit overlap is real, one `dep-impact` reviewer pass files items into the
     dependent's queue — no edit-backward into the fixed task, new DAG task if it needs one.
    - **Unless `--skip-build-check` was passed:** monitor the pipeline/checks to a terminal state
      right after this push (see "Build check" below), before moving on to step 3 — so a failed
      build shows up in the recap and can be mentioned in the thread reply, not discovered later.
      A **red** build → the task is **not done**: enter the build-check fix loop below (fix in the
      worktree, re-verify, push, re-monitor) until it passes or the cap is hit.
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
   - **Refresh the MR description too — every round, not just the first.** Re-fetch the current
     description (`glab mr view <iid>` / `gh pr view <number> --json body`), then update it (`glab
     mr update <iid> --description '<updated body>'` / `gh pr edit <number> --body '<updated
     body>'`) so it still matches the MR's real, current state: add a bullet under `## Low-level
     changes` for what this round changed on disk (and under `## High-level changes` only if an
     observable behavior actually changed), refresh `## Verification`'s output if it changed, and
     add/adjust `## Notes for the reviewer` if the fix introduced a new pinned-as-is/risk/follow-up.
     Do this even
     if the reply-on-thread already explains it — the description is what a reviewer (or you) reads
     first, and it goes stale fast once several review rounds have landed fixes the original
     description never mentioned.
   - Also mirror as usual: task `## Result`, a `[RESOLVED]` item in `task/review/T0n.review.md`'s
     `## Items` section (create the file first via `pw-lib.sh review-init` if it doesn't exist yet),
     and a `LOG.md` line via the helper. The project dir stays the source of truth even for
     MR-driven changes.
4. **Recap** a table — one row per task in the set: Task · Repo · MR · state (open/merged/closed) ·
   threads addressed (note how many were general/no-diff-position) · verify (green/failed) ·
   pushed? · build result (or "skipped" if `--skip-build-check` was passed). Flag any task whose
   verify failed after the fix (leave it for review) and any thread you couldn't resolve without a
   decision. For `merged` tasks, note that the worktree was removed and docs updated.

Process the set **serially by default** (each is a real edit-verify-push in a worktree); parallelize
only independent repos if you're confident. Never merge an MR as part of this command — merging is a
human decision downstream.

## Build check (on by default — `--skip-build-check` to opt out, either mode)
Runs automatically, in both modes: after the MR is opened/updated (ship mode) or after each fix is
pushed (comment mode), poll that MR's pipeline/checks until they reach a terminal state, using the
**Build/CI status invocation** column in `tooling/docs/forges.md`'s Registry (same per-repo forge
resolution as everything else here — never hardcode a host or a CLI). Pass `--skip-build-check` to
skip this entirely for the run and get the old immediate-return behavior (dashboard/`## Result`
`Build`/`Build check` fields stay `—`, recap says "skipped"). **A red build means that task is NOT
done** — it is not shipped until the pipeline passes; see the fix loop below.
- **Terminal states:** GitHub `SUCCESS`/`FAILURE`/`CANCELLED`/`SKIPPED` (via `gh pr checks`);
  GitLab `success`/`failed`/`canceled`/`skipped` (via the pipeline's `.status`). Anything else
  (`pending`/`running`/`created`) means keep polling.
- **Timeout, not an infinite wait:** poll on a short interval (~30s) up to a ~15 minute budget. Still
  not terminal at the budget → report it as **"still running — not yet resolved"** in the recap and
  the `## Result → Build check:` field, rather than blocking the rest of the run on it.
- **Build-check fix loop (a red build → the task is NOT done → keep fixing until green):**
  1. **Diagnose** — read the failing job's output (GitLab: `glab api projects/:id/pipelines/<id>/jobs`
     → the failed job's trace; GitHub: the failing check's details via `gh api`). Bounded: you need
     the failing test/compile error, not the whole log.
  2. **Attribution check** — if the failure reproduces on the untouched base branch, or is clearly
     unrelated/environmental (a job that also fails on `main`, flaky infra), do **not** churn:
     report it as "build failed — unrelated/environmental, not caused by this task" and stop the
     loop (the task is still not done until a human decides). Only fix failures your change caused.
  3. **Fix + push** — edit the task's worktree, re-run its `## Verify` locally, commit, and push to
     the same branch (the MR updates in place; no new MR, no re-confirmation — the shipment was
     already confirmed). Then re-monitor the pipeline.
  4. **Repeat until green.** Cap: **at most 3 fix rounds per task per run.** Hitting the cap still
     red → stop, report the remaining error in the recap and the task's `## Result`, and tell me the
     task is NOT done — ask whether to keep fixing or take another action. Never claim `done` on a
     failing build.
