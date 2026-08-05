---
description: Push verified task branches and open MRs with rich descriptions
args: <project-slug> [task-ids] [comments]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} (first token = project slug; optional
task IDs to ship a subset; the word `comments` = go into MR-comment mode, below).

Project dir: `{{PW_PROJECTS}}/<slug>`.

Publishing is **outward-facing** — this is the explicit "make it public" step, kept separate from
`/pw-execute` so nothing pushes until you run it. `/pw-execute` already committed + verified each
task; here we push branches and open MRs.

## Ship mode (default)
1. Determine which tasks are shippable: `Status: done`/`accepted`, verify passed, a real commit on
   their branch. **Skip zero-change tasks** (note "zero-change — no branch/MR" in their Result) and
   any already-shipped task (Result → MR already set).
2. **Confirm before anything goes out.** List, for each shippable task: repo, branch
   (`agent/<slug>/<T0n>-<slug>`), target base branch, and the MR title. Ask me to confirm the list.
   Only after I say go:
3. For each confirmed task, from its worktree
   (`{{PW_PROJECTS}}/<slug>/worktree/<repo>/<T0n>-<slug>`):
   - Push the branch to origin.
   - Open an MR **targeting the task's Base branch** with a rich description (template below). For
     GitLab: `glab` run from inside the worktree with `GITLAB_HOST=source.golabs.io` (adjust host
     per repo). For GitHub: `gh pr create`.
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

## MR-comment mode  (`/pw-ship <slug> T0n comments`)
Handle review comments left on the **MR itself**:
1. Fetch the open review threads — GitLab:
   `glab api projects/:id/merge_requests/<iid>/discussions` (or `glab mr diff`), run from inside the
   repo with `GITLAB_HOST=source.golabs.io`; GitHub: `gh pr view --comments`.
2. Apply the fixes in that task's **worktree**, re-run its `## Verify`, and push.
3. **Reply to each MR thread** summarizing the fix, AND **mirror it into the internal record** —
   task `## Result`, `task/review/T0n.review.md` (create it if needed), and a `LOG.md` line via the
   helper. The project dir stays the source of truth even for MR-driven changes.

Never merge an MR as part of this command — merging is a human decision downstream.
