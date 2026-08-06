---
description: Onboard existing in-progress branch(es) into the workflow — the continuation workflow (with or without an MR)
args: <project-slug> <repo> <existing-branch> [mr-url]
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} — `<project-slug> <repo> <existing-branch>
[mr-url]`. This is the **continuation workflow**: instead of a fresh start (`/pw-new`), you build on
work that's **already underway on real branches** (with or without an MR).

Project dir: `{{PW_PROJECTS}}/<slug>`. Repo: `{{PW_REPOS}}/<repo>`.

## Adoption unit + the two rules
An **adoption unit** is a tuple `(repo, in-progress-branch, [mr])`. A project can adopt **one or
many** — run this command **once per in-progress branch** (multi-repo work in progress = several
units). **Appending a unit is deterministic** (`pw-lib.sh adopt`, below), so adopting a 2nd branch
**never clobbers the 1st** — re-adopting the same `repo@branch` just updates that unit in place.
Two rules follow from adopting real branches:
- **Continue-on-the-same-branch** — task commits extend the existing branch (and its MR, if any);
  no fresh `agent/…` branches.
- **Serialization is per-branch** — tasks on the *same* adopted branch run **serially** in that
  branch's one shared worktree; tasks on *different* adopted branches run **in parallel**.

## Steps
1. **Validate.** Confirm `{{PW_REPOS}}/<repo>` is a git repo and `<existing-branch>` exists
   (`git -C {{PW_REPOS}}/<repo> rev-parse --verify <existing-branch>`, else `origin/<existing-branch>`).
   If the slug's project dir doesn't exist yet, scaffold it first:
   `{{PW_HOME}}/tooling/scaffold.sh <slug>`.
2. **Resolve the base branch — from the MR target first.** The authoritative base for an adopted
   branch is **its MR's target branch**, not a guess:
   - **MR url given** → fetch the MR's target branch and use it as the base. GitLab:
     `glab mr view <url> -F json` (run with `GITLAB_HOST=<host>`) → `.target_branch`; GitHub:
     `gh pr view <url> --json baseRefName -q .baseRefName`. Also capture MR title + open/draft state.
   - **No MR yet** → do NOT silently guess. Best-effort infer with `git merge-base` against the
     repo's default branch, but **mark it as unconfirmed**: pass the base you inferred AND tell me
     in the recap that the base needs my confirmation. Add/flag the `context/INDEX.md` row for
     `ADOPTED.md` with Trust = "⚠️ base unconfirmed — human to verify (no MR target)". (If you can't
     infer at all, ASK me for the base before proceeding.)
3. **Snapshot this unit** from `{{PW_REPOS}}/<repo>` against the resolved base:
   `git log --oneline <base>..<existing-branch>` (commits) and
   `git diff --stat <base>...<existing-branch>` (files) — plus the MR state from step 2.
4. **Record the unit deterministically — do NOT hand-write `ADOPTED.md`.** Call:
   ```bash
   {{PW_HOME}}/tooling/pw-lib.sh adopt <slug> <repo> <existing-branch> <base> "<mr-url|none yet>"
   ```
   This appends a new `## A<k> · <repo> @ <existing-branch>` section (or updates it in place if that
   repo@branch was already adopted), records its `Base`/`MR`, updates the dashboard `Adopted:`
   pointer + count, and logs it. It prints the unit id `A<k>`. Then **fill only that unit's prose**:
   replace the `<!-- pw-adopt A<k> already-done … -->` comment with your step-3 snapshot summary,
   and leave the `🧑 … remaining` line for me. Editing is scoped to that unit's section — never
   rewrite the file or touch other units. Add the one-time `context/INDEX.md` row for `ADOPTED.md`
   if missing (Source = "git state snapshot, gathered by /pw-adopt"; Trust per step 2).
5. **Recap + next actions:** report the unit id, repo@branch, resolved base **and whether it came
   from the MR target or is unconfirmed**, and the MR state. Then: fill each unit's
   `### Remaining work` in `ADOPTED.md`; adopt more branches with another `/pw-adopt` run if the
   work spans more repos; then run **`/pw-analyze <slug>`** — analysis reads `ADOPTED.md` + each
   unit's existing diff as the baseline and proposes only the *remaining* changes.

## What changes downstream (vs a fresh `/pw-new` project)
- **Breakdown:** every task's `Branch:` = the adopted branch of the unit/repo it touches (not a new
  `agent/…` branch). Tasks sharing a branch get a **linear dependency chain**; tasks on different
  adopted branches stay independent. PLAN's global rules state "**continuation — per-branch serial;
  cross-branch parallel**".
- **Execution:** one shared worktree **per adopted branch**, attaching the existing branch —
  `git -C {{PW_REPOS}}/<repo> worktree add {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug> <existing-branch>`
  (no `-b`). Serial within a branch, parallel across branches. If git refuses because the branch is
  checked out in the main repo, switch that main checkout off it first.
- **Ship:** each adopted branch is **one shipment**. If it already has an MR, `/pw-ship` **updates
  it — no duplicate**; if not, it opens one. `/pw-sync` and `/pw-ship … comments` work as normal.
