---
description: Onboard existing in-progress branch(es) into the workflow — the continuation workflow (with or without an MR)
args: <project-slug> <repo> <existing-branch> [mr-url]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} — `<project-slug> <repo> <existing-branch>
[mr-url]`. This is the **continuation workflow**: instead of a fresh start (`/pw-new`), you build on
work that's **already underway on real branches** (with or without an MR).

Project dir: `{{PW_PROJECTS}}/<slug>`. Repo: `{{PW_REPOS}}/<repo>`.

## Adoption unit + the two rules
An **adoption unit** is one tuple `(repo, in-progress-branch, [mr])`. A project can adopt **one or
many** — run this command **once per in-progress branch** (multi-repo work in progress = several
units). Each run **appends/updates** a unit; it never clobbers units already recorded. Two rules
that follow from adopting real branches:
- **Continue-on-the-same-branch** — task commits extend the existing branch (and its MR, if any);
  no fresh `agent/…` branches are cut.
- **Serialization is per-branch** — tasks on the *same* adopted branch run **serially** in that
  branch's one shared worktree; tasks on *different* adopted branches are independent and run **in
  parallel**. So multiple units keep cross-unit parallelism while staying continue-on within a unit.

## Steps
1. **Validate.** Confirm `{{PW_REPOS}}/<repo>` is a git repo and `<existing-branch>` exists
   (`git -C {{PW_REPOS}}/<repo> rev-parse --verify <existing-branch>`, else `origin/<existing-branch>`).
   If the slug's project dir doesn't exist yet, scaffold it first:
   `{{PW_HOME}}/tooling/scaffold.sh <slug>`.
2. **Snapshot this unit's starting point.** From `{{PW_REPOS}}/<repo>`, work out the base branch the
   dev branch forked from (best-effort: `git merge-base <existing-branch> origin/master` /
   `origin/main` / the repo's default; if ambiguous, ASK me which base). Then capture what's already
   done on it:
   - `git log --oneline <base>..<existing-branch>`   (commits so far)
   - `git diff --stat <base>...<existing-branch>`     (files touched)
   - the MR state if `[mr-url]` was given (`glab mr view <url>` / `gh pr view <url>` — title, target
     branch, open/draft, review-thread count).
3. **Record the unit in `context/ADOPTED.md`** (create it on the first adopt; **append/upsert** on
   later ones — match on `repo@branch`, update in place if it's already there, else add a new unit).
   Structure:
   ```markdown
   # Adopted work — <slug>   (CONTINUATION workflow)

   Builds on existing in-progress branches. Serialization is PER-BRANCH: tasks on the same branch
   run serially in its shared worktree; tasks on different branches run in parallel. [🧑🤖 both]

   | Unit | Repo | Branch | Base | MR |
   |------|------|--------|------|-----|
   | A1 | <repo> | <existing-branch> | <base> | <url> (open) — or "none yet" |

   ## A1 — <repo> @ <existing-branch>
   ### Already done   [🤖 snapshot]
   <commit list + diffstat summary, in prose>
   ### Remaining work   [🧑 you]
   <fill: what you want changed on top of the existing work>
   ```
   Give each unit a stable ID `A1`, `A2`, … (distinct from task IDs `T0n`). Add the INDEX row once:
   `context/INDEX.md` → `ADOPTED.md` (Source = "git state snapshot, gathered by /pw-adopt";
   Trust = "authoritative — live repo state").
4. **Update the dashboard pointer deterministically** (don't hand-edit the dashboard) — after
   writing/updating `ADOPTED.md`, set the count:
   ```bash
   {{PW_HOME}}/tooling/pw-lib.sh adopted <slug> "<N> unit(s) — continuation; see context/ADOPTED.md"
   {{PW_HOME}}/tooling/pw-lib.sh log     <slug> adopt "adopted A<k>: <repo>@<existing-branch> (base <base>, MR <url|none>)"
   ```
   `<N>` = the number of unit rows now in `ADOPTED.md`. Leave Status at `context` (a fresh scaffold
   is already there; no `--rewind`).
5. **Tell me the next actions**, concretely: fill each unit's `## Remaining work` in `ADOPTED.md`
   (and drop any other inputs into `context/`); adopt more branches with another `/pw-adopt` run if
   the work spans more repos; then run **`/pw-analyze <slug>`** — analysis reads `ADOPTED.md` + each
   unit's existing diff as the baseline and proposes only the *remaining* changes.

## What changes downstream (vs a fresh `/pw-new` project)
- **Breakdown:** every task's `Branch:` = the adopted branch of the unit/repo it touches (not a new
  `agent/…` branch). Tasks sharing a branch get a **linear dependency chain**; tasks on different
  adopted branches stay independent. PLAN's global rules state "**continuation — per-branch serial;
  cross-branch parallel**".
- **Execution:** one shared worktree **per adopted branch**, attaching the existing branch —
  `git -C {{PW_REPOS}}/<repo> worktree add {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug> <existing-branch>`
  (no `-b`). Serial within a branch, parallel across branches. If git refuses because the branch is
  checked out in the main repo, switch the main checkout off it first.
- **Ship:** each adopted branch is **one shipment**. If it already has an MR, `/pw-ship` **updates
  it — no duplicate**; if not, it opens one. `/pw-sync` and `/pw-ship … comments` work as normal.
