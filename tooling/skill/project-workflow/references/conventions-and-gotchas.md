# Conventions, helpers, and cross-cutting gotchas

## Who fills what
**Who fills what** (put a `Filled by:` note on every table/form so it's unambiguous): 🤖 =
AI-maintained (don't hand-edit) · 🧑 = human fills · 🤖🧑 = both. Human-owned: `context/`, review
items + QnA answers + Sign-off, `provider registry`, and the `accepted`/`verify-failed` task
states. Agent-owned: analysis/plan/task docs, the dashboard `Status:`/tables, `## Result`, `LOG.md`.

## Going back a phase (rewind)
To reopen an earlier phase, the human adds a fresh `[OPEN]` item + a new `in-review` Sign-off row
(old `approved` stays as history) and bumps the dashboard `Status:` back **with the explicit
rewind flag** (`pw-lib.sh status <slug> <phase> --rewind` — a plain `status` refuses to move
backward, which is what stops accidental resets); then re-run that phase's command and re-approve.
Downstream artifacts stay on disk and get regenerated once the upstream phase is re-approved.

## Status field + audit log (commands own these — via `pw-lib.sh`)
Don't hand-edit the Status line or LOG.md — use the helper `agentic-project-workflow/tooling/pw-lib.sh`
(deterministic, phase-validated, portable across Claude Code + shelled-out kilo executors):
- `pw-lib.sh status <slug> <phase>` — set the dashboard `Status:` (`context→analysis→breakdown→
  executing→review→done`) and auto-log the change. Each `/pw-*` command runs this as its
  **mandatory last step** (analyze/breakdown/execute say "do NOT skip"); never leave Status stale or
  hand-maintained. It **refuses a backward move** (guards against accidental resets like the phase
  sliding back to `context`); pass `--rewind` to intentionally go back. `executing`↔`review` is not
  backward (re-running a task is normal).
- `pw-lib.sh oneliner <slug> "<text>"` — set the dashboard **One-liner** (the agent does this during
  `/pw-analyze`, distilled from context/).
- `pw-lib.sh adopted <slug> "<pointer>"` — set/insert the dashboard **Adopted:** pointer (the agent
  does this during `/pw-adopt`; inserts the line only for continuation projects).
- `pw-lib.sh adopt <slug> <repo> <branch> <base> [mr]` — **deterministically append/upsert one
  adoption unit** into `context/ADOPTED.md` (keyed by `repo@branch`; new units append at EOF,
  re-adopting the same one updates it in place). In `context/INDEX.md` it also **ensures a one-time
  generic `ADOPTED.md` provenance row** (never re-enumerated per unit) **and upserts one matching
  `(repo, origin/<base>)` row into the "Repos in scope" table** (keyed by a hidden
  `<!-- pw-adopt-scope:… -->` marker). Use this in `/pw-adopt` — do NOT hand-write `ADOPTED.md` or
  hand-edit `context/INDEX.md`'s adoption rows (free-form editing is what clobbered a 2nd/3rd
  adopted branch and re-churned the provenance line each attempt). It also bumps the `Adopted:`
  count. Resolve `<base>` from the **MR's target branch** when there's an MR.
- `pw-lib.sh review-init <slug> <review-rel-path> <doc-rel-path>` — **idempotently create a review
  file from the template** if (and only if) it doesn't exist yet. `/pw-analyze` and `/pw-breakdown`
  call this so `analysis/review/<topic>.review.md` / `task/review/PLAN.review.md` are already there
  — the human never has to copy the template themselves. Never hand-write a review file; this also
  guarantees the permanent `> **Add an item:**` / `> **Answer a question:**` format hints never get
  silently dropped.
- `pw-lib.sh log <slug> <actor> <msg>` — append one audit line to **`LOG.md`** as a Markdown bullet
  (`- **YYYY-MM-DD HH:MM** · \`actor\` — what`, not a bare pipe row — reads properly in a plain
  preview view). Log phase transitions, executor spawns, commits, pushes, MRs, review passes,
  close-out.
- `pw-lib.sh phase <slug>` — read the current phase (used by `/pw-review` scoping + `/pw-status`).
- Per-task **timing + commit/MR outcome** go in the task file's `## Result` block and the PLAN
  task table's Time/Result columns. **Token/cost are NOT captured** — a running agent can't measure
  them; leave them to external session telemetry, don't fabricate.

## Slash commands (generated — one source of truth)
Users drive phases with `/pw-*`. **Two entry workflows:** `/pw-new <slug>` (fresh) OR
`/pw-adopt <slug> <repo> <branch> [mr-url] [review]` (continuation — full guide
`agentic-project-workflow/docs/ADOPTION.md`). Adoption is a **context/baseline** action, run once per
in-progress branch (continue-on-same-branch; serial within a branch, parallel across), with two
intents: **continue-dev** (default) → lands at `context`, then analyze→breakdown→execute→ship the
*remaining* work; **review-only** (trailing `review` keyword, MR required) → lands at `review` to
service MR comments (`/pw-ship comments`, `/pw-sync`), skipping analyze/breakdown. Guards: refuse on
a `done` project; a continue-dev adopt onto a project **past `context`** records the unit and
**warns to re-run `/pw-analyze` + `/pw-breakdown`** (never rewinds `Status`). Adopting into an
existing slug yields a **mixed project** — routing is **per task by its `Branch:`**: a task extending
an adopted unit continues on that branch (serial per branch), every other task gets a fresh
`agent/…` branch off its base (parallel). Then `/pw-analyze <slug> [focus]`,
`/pw-breakdown <slug>`, `/pw-review <slug> [phase|Tid|path]` (scoped to the current phase),
`/pw-execute <slug> [task-ids | "with <model/agent>"]` (stops at committed + verified),
`/pw-ship <slug> [task-ids] [comments] [--build-check]` (push + open MRs; the outward-facing publish
step; `--build-check` optionally monitors the MR's pipeline to a terminal state),
`/pw-sync <slug> [task-ids]` (merge the moved base branch into each open MR branch, re-verify, push),
`/pw-status <slug>`, `/pw-close <slug>`,
`/pw-doctor [--fix]` (verify/repair that installed commands + agents + skill match the bundle),
`/pw-rfc <slug> [--target <ref>] [milestone|comments]` (optional side-loop — publish approved
analysis/plan content to an RFC doc, any configured backend or none; see `tooling/docs/rfc.md`).
The command files are **generated build artifacts** — the single source is
`agentic-project-workflow/tooling/commands/*.md`, emitted per provider by `agentic-project-workflow/tooling/gen-commands.sh` (Claude →
`~/.claude/commands/`, kilo → `~/.config/kilo/command/`); the sub-agents (`pw-orchestrator`,
`pw-executor`) are seeded the same way from `tooling/agents/` by `gen-agents.sh`. To change a
command's prompt or an agent, edit the canonical file and re-run the generator — never hand-edit the
per-provider copies.

## Conventions (the contract)
- **Task IDs:** `T01`, `T02`… referenced by `depends_on`.
- **Branch:** `agent/<project-slug>/<task-id>-<slug>`
- **Worktree:** `worktree/<repo>/<task-id>-<slug>/`, created by `git worktree add` off the real
  sibling repo in `$PW_REPOS/` — never a copy. Remove with `git worktree remove` when done.
- **Isolation:** an executor edits ONLY its worktree. No cross-task edits.
- **Done:** only after running the task's `## Verify` and pasting real output. Report failures
  and skips faithfully — never claim done on unverified work.
- **Commits:** Conventional Commits.

## Scaffolded project dirs are plain (not git repos)
This is by design — version history lives in the real repos, and workflow learnings go in the
project's "Decisions & learnings" section (and your memory tool at close-out, if `PW_MEMORY` names
one). The reusable **bundle itself IS a git repo** (so it's shareable + reset-recoverable via
`bootstrap.sh`); its own tooling changes are tracked there. Distil durable learnings at close-out.
