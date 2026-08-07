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
     **Resolve the forge + CLI per `tooling/forges.md`** (host from this repo's own `origin`
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
1. Fetch the open review threads. **Resolve the forge + CLI per `tooling/forges.md`** (same
   per-repo resolution as ship mode) — GitLab: `glab api projects/:id/merge_requests/<iid>/discussions`
   (or `glab mr diff`), run from inside the repo with `GITLAB_HOST=<resolved-host>`; GitHub:
   `gh pr view --comments`. A task whose MR has no open threads is skipped (note it in the recap).
2. Apply the fixes in that task's **worktree**, re-run its `## Verify`, and push.
3. **Reply to each MR thread** summarizing the fix, AND **mirror it into the internal record** —
   task `## Result`, `task/review/T0n.review.md` (create it if needed), and a `LOG.md` line via the
   helper. The project dir stays the source of truth even for MR-driven changes.
4. **Recap** a table — one row per task in the set: Task · Repo · MR · threads addressed ·
   verify (green/failed) · pushed?. Flag any task whose verify failed after the fix (leave it for
   review) and any thread you couldn't resolve without a decision.

Process the set **serially by default** (each is a real edit-verify-push in a worktree); parallelize
only independent repos if you're confident. Never merge an MR as part of this command — merging is a
human decision downstream.
