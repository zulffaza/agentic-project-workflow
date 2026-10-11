---
description: Onboard existing in-progress branch(es) into the workflow — the continuation workflow (with or without an MR); one repo per call, or several in one call for a multi-repo continuation
args: "--project <project-slug> --repo <repo> --branch <existing-branch> [--mr <url>] [--intent review-only]  |  --project <project-slug> --unit <repo>:<branch>[:<mr-url>] --unit … [--intent review-only]"
scope: project
---
Follow the `project-workflow` skill. Arguments: {{ARGS}} — one of two named-argument forms; the
**batch form** is for a multi-repo continuation in one call. This is the **continuation
workflow**: instead of a fresh start (`/pw-new --project <slug>`), you build on work that's
**already underway on real branches** (with or without an MR).

- **`/pw-adopt --project <project-slug> --repo <repo> --branch <existing-branch> [--mr <url>] [--intent review-only]`** — single-unit form: adopt one in-progress branch.
- **`/pw-adopt --project <project-slug> --unit <repo>:<branch>[:<mr-url>] --unit … [--intent review-only]`** — **batch form**: repeat `--unit` once per colon-joined `repo:branch[:mr-url]` value (detect batch mode by the presence of `--unit`; a call carries `--repo`/`--branch` or `--unit`s, never both). `--intent review-only` (default intent: continue-dev) applies to every unit in the call.

**Batch form mechanics** — same rules as single-unit, just looped: run steps 1–4 below **once per
`--unit` value, in order** (each unit is its own independent `pw-context.sh adopt` call —
already safe to call repeatedly, per "Appending a unit is deterministic" below, so one unit
failing validation doesn't corrupt units already recorded before it; STOP and report which units
succeeded vs. the one that failed rather than rolling anything back). `--intent review-only`
applies to the **whole batch** — all units land at the same intent/phase; if some branches need a
different intent, adopt those separately. Run step 5 (set phase) and step 6 (recap) **once**, for
the whole batch — one phase transition, one combined recap listing every adopted unit.

Project dir: `{{PW_PROJECTS}}/<slug>`. Repo: `{{PW_REPOS}}/<repo>`.

<!-- Pre-flight: snapshot git state before adoption -->
```bash
{{PW_HOME}}/tooling/scripts/entities/pw-context.sh adopt-snapshot --project <slug> --repo <repo> --branch <branch> [--mr <url>]
```
**Reading the snapshot:** flat `key: value` fields — `base:` shows *how* the base branch was
resolved (`(mr-target)` / `(default)`; pass `--mr <url>` whenever you have one so the base is the
real MR target), `commits:`/`files-changed:` are the unit's size (0 is legitimate — fresh
branch, not a failure). Exit 2 + `pw-context:` names the bad input (repo dir, branch
name, or no derivable base) — fix the argument or fetch, then retry.
(`{{PW_HOME}}/tooling/docs/scripts/workflow-automation.md`)

## Two intents — which phase the adopt lands at
Adoption is a **baseline/input action** (that's why `ADOPTED.md` lives in `context/`). It's only
meaningful at two moments, chosen by *why* you're adopting — never to sit in a mid-pipeline phase:
- **Continue development (default)** — the branch needs *more work*. Lands the project at
  **`context`** so `/pw-analyze` → `/pw-breakdown` → `/pw-execute` → `/pw-ship` run on the
  **remaining** work. MR optional.
- **Review-only (`--intent review-only`)** — the branch is essentially **done and already has an
  MR**; you're adopting it just to run the MR-comment review loop (`/pw-ship comments --project <slug>`,
  `/pw-sync --project <slug>`), not to add tasks. Lands the project straight at **`review`**, skipping
  analyze/breakdown. **An MR is required** — refuse and ask for it if `--mr <url>` is missing.

**Phase guard (check `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh phase --project <slug>` first):**
- Project is `done` (closed) → **refuse**; tell me to reopen deliberately (a closed project has been
  torn down). Only proceed if I explicitly say to reopen.
- Default (continue-dev) adopt onto a project **already past `context`** (analysis/breakdown/
  executing/review) → still record the unit, but **do NOT rewind the global `Status`** (that would
  falsely imply the in-flight units regressed). Instead **warn**: the new unit isn't analyzed/planned
  yet — I must re-run `/pw-analyze --project <slug>` then `/pw-breakdown --project <slug>` to fold it in.
- Never set `Status` to `analysis`/`breakdown`/`executing` from here — those aren't adoption targets.

## Adoption unit + the two rules
An **adoption unit** is a tuple `(repo, in-progress-branch, [mr])`. A project can adopt **one or
many** — run this command **once per in-progress branch** (multi-repo work in progress = several
units). **Appending a unit is deterministic** (`pw-context.sh adopt`, below), so adopting a 2nd branch
**never clobbers the 1st** — re-adopting the same `repo@branch` just updates that unit in place.
Two rules follow from adopting real branches:
- **Continue-on-the-same-branch** — a task that extends an adopted unit commits onto the existing
  branch (and its MR, if any); no fresh `agent/…` branch for that task.
- **Serialization is per-branch** — tasks on the *same* adopted branch run **serially** in that
  branch's one shared worktree; tasks on *different* adopted branches run **in parallel**.

**The slug may already exist.** `/pw-adopt` isn't only for starting a project — run it against a
slug created by `/pw-new` (or one already carrying adopted units) to **fold a branch into it**. If
the project dir exists, step 1 skips scaffolding and just appends the unit; the fresh tasks and
earlier units are untouched. The result is a **mixed project** where adoption is decided per task
(a task extends an adopted branch, else it gets a fresh `agent/…` branch) — see the WORKFLOW
"mixed projects" note. Keep unrelated in-progress work in its own slug instead.

## Steps
1. **Parse mode + guard the phase.** First, detect **batch vs. single-unit** from the flags:
   `--unit` values = the batch form — split each value on `:` into `(repo, branch, mr-url?)`;
   `--repo` + `--branch` = the single-unit form. `--intent review-only` makes this a
   **review-only** adopt for the whole call (each unit's `--mr` / `:mr-url` is then required) —
   otherwise it's the default **continue-dev** adopt. Read the current phase
   (`{{PW_HOME}}/tooling/scripts/entities/pw-status.sh phase --project <slug>`, if the project already exists) and apply the phase
   guard above ONCE, for the whole call: refuse on `done` (unless I say reopen); for a continue-dev
   adopt past `context`, plan to warn (not rewind) once at the end, not per unit. **Validate each
   unit**: confirm `{{PW_REPOS}}/<repo>` is a git repo and `<existing-branch>` exists (`git -C
   {{PW_REPOS}}/<repo> rev-parse --verify <existing-branch>`, else `origin/<existing-branch>`) —
   if the slug's project dir doesn't exist yet, scaffold it first (once, before the first unit):
   `{{PW_HOME}}/tooling/scripts/toolchain/scaffold.sh --project <slug>`.
2. **Resolve the base branch — from the MR target first.** The authoritative base for an adopted
   branch is **its MR's target branch**, not a guess:
   - **`--mr <url>` given** → fetch the MR's target branch and use it as the base. GitLab:
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
   {{PW_HOME}}/tooling/scripts/entities/pw-context.sh adopt --project <slug> --repo <repo> --branch <existing-branch> --base <base> [--mr <url>]
   ```
   (omit `--mr` when there is no MR yet — the script records `none yet`).
   This appends a new `## A<k> · <repo> @ <existing-branch>` section (or updates it in place if that
   repo@branch was already adopted), records its `Base`/`MR`, updates the dashboard `Adopted:`
   pointer + count, and — in `context/INDEX.md` — **ensures a one-time generic `ADOPTED.md`
   provenance row AND upserts one `(repo, origin/<base>)` row into the "Repos in scope" table**
   (keyed by a hidden `<!-- pw-adopt-scope:<repo>@<branch> -->` marker), and logs it. It prints the
   unit id `A<k>`. Then **fill only that unit's prose**: replace the `<!-- pw-adopt A<k>
   already-done … -->` comment with your step-3 snapshot summary, and leave the `🧑 … remaining`
   line for me. Editing is scoped to that unit's section — never rewrite `ADOPTED.md` or touch
   other units.
   - **Do NOT hand-edit `context/INDEX.md` for adoption** — the helper owns both the generic
     `ADOPTED.md` provenance row (inserted once, kept generic — never re-enumerate units into it)
     and the "Repos in scope" marker rows, so adopting the Nth branch can't clobber earlier rows or
     re-churn that provenance line (the reported bugs).
5. **Set the phase for this intent, ONCE for the whole call** (per the phase guard above) — repeat
   steps 2–4 per unit first, then do this exactly once:
   - **Review-only adopt** → `{{PW_HOME}}/tooling/scripts/entities/pw-status.sh status --project <slug> --phase review`. Mark each
     adopted unit's `### Remaining work` as `none — review-only (servicing MR comments)`.
   - **Continue-dev adopt on a fresh/context project** → leave `Status` at `context` (don't touch it).
   - **Continue-dev adopt on a project already past `context`** → do NOT change `Status`; you'll warn
     in the recap instead.
6. **Recap + next actions:** for a single-unit call, report the unit id, repo@branch, resolved
   base **and whether it came from the MR target or is unconfirmed**, the MR state, and the
   **intent/landing phase**. For a **batch call, report one line per adopted unit** (same fields)
   plus which units (if any) failed validation and were skipped, then the shared intent/phase
   once at the end. Then:
   - **Continue-dev:** fill each unit's `### Remaining work` in `ADOPTED.md`; adopt more branches with
     another `/pw-adopt` run if the work spans more repos; then run **`/pw-analyze --project <slug>`** — analysis
     reads `ADOPTED.md` + each unit's existing diff as the baseline and proposes only the *remaining*
     changes. If this adopt landed on a project already past `context`, **warn** that the new unit is
     not yet analyzed/planned and I must re-run `/pw-analyze` + `/pw-breakdown` to fold it in.
   - **Review-only:** skip analyze/breakdown; go straight to **`/pw-ship comments --project <slug>`** to work
     the MR's review threads, and **`/pw-sync --project <slug>`** to merge the moved base in + re-verify.

## What changes downstream (continue-dev intent; vs a fresh `/pw-new` project)
Review-only adopts skip breakdown/execution entirely — they go straight to `/pw-ship comments --project <slug>`.
For a continue-dev adopt, routing is **per task** (a project can be mixed — fresh tasks + adopted):
- **Breakdown:** a task that extends an adopted unit gets `Branch:` = that adopted branch (not a new
  `agent/…` branch); every other task gets a fresh `agent/…` branch off its base. Tasks sharing an
  adopted branch get a **linear dependency chain**; tasks on different adopted branches and all fresh
  tasks stay independent.
- **Execution:** for adopted-branch tasks, one shared worktree **per adopted branch**, attaching the
  existing branch — `git -C {{PW_REPOS}}/<repo> worktree add {{PW_PROJECTS}}/<slug>/worktree/<repo>/<branch-slug> <existing-branch>`
  (no `-b`). Serial within a branch, parallel across branches and fresh tasks. If git refuses because
  the branch is checked out in the main repo, switch that main checkout off it first.
- **Ship:** each adopted branch is **one shipment**. If it already has an MR, `/pw-ship` **updates
  it — no duplicate**; if not, it opens one. `/pw-sync --project <slug>` and `/pw-ship comments --project <slug>` work as normal.
