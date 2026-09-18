# Conventions, helpers, and cross-cutting gotchas

## Who fills what
**Who fills what** (put a `Filled by:` note on every table/form so it's unambiguous): 🤖 =
AI-maintained (don't hand-edit) · 🧑 = human fills · 🤖🧑 = both. Human-owned: `context/`, review
items + QnA answers + Sign-off, `provider registry`, and the `accepted`/`verify-failed` task
states. Agent-owned: analysis/plan/task docs, the dashboard `Status:`/tables, `## Result`, `LOG.md`.

## Going back a phase (rewind)
To reopen an earlier phase, the human adds a fresh `[OPEN]` item + a new `in-review` Sign-off row
(old `approved` stays as history) and bumps the dashboard `Status:` back **with the explicit
rewind flag** (`pw-status.sh status <slug> <phase> --rewind` — a plain `status` refuses to move
backward, which is what stops accidental resets); then re-run that phase's command and re-approve.
Downstream artifacts stay on disk and get regenerated once the upstream phase is re-approved.

## Status field + audit log (commands own these — via `pw-status.sh`)
Don't hand-edit the Status line or LOG.md — use the helper `agentic-project-workflow/tooling/scripts/entities/pw-status.sh`
(deterministic, phase-validated, portable across Claude Code + shelled-out kilo executors):
- `pw-status.sh status <slug> <phase>` — set the dashboard `Status:` (`context→analysis→breakdown→
  executing→review→done`) and auto-log the change. Each `/pw-*` command runs this as its
  **mandatory last step** (analyze/breakdown/execute say "do NOT skip"); never leave Status stale or
  hand-maintained. It **refuses a backward move** (guards against accidental resets like the phase
  sliding back to `context`); pass `--rewind` to intentionally go back. `executing`↔`review` is not
  backward (re-running a task is normal).
- `pw-status.sh oneliner <slug> "<text>"` — set the dashboard **One-liner** (the agent does this during
  `/pw-analyze`, distilled from context/).
- `pw-status.sh adopted <slug> "<pointer>"` — set/insert the dashboard **Adopted:** pointer (the agent
  does this during `/pw-adopt`; inserts the line only for continuation projects).
- `pw-context.sh adopt <slug> <repo> <branch> <base> [mr]` — **deterministically append/upsert one
  adoption unit** into `context/ADOPTED.md` (keyed by `repo@branch`; new units append at EOF,
  re-adopting the same one updates it in place). In `context/INDEX.md` it also **ensures a one-time
  generic `ADOPTED.md` provenance row** (never re-enumerated per unit) **and upserts one matching
  `(repo, origin/<base>)` row into the "Repos in scope" table** (keyed by a hidden
  `<!-- pw-adopt-scope:… -->` marker). Use this in `/pw-adopt` — do NOT hand-write `ADOPTED.md` or
  hand-edit `context/INDEX.md`'s adoption rows (free-form editing is what clobbered a 2nd/3rd
  adopted branch and re-churned the provenance line each attempt). It also bumps the `Adopted:`
  count. Resolve `<base>` from the **MR's target branch** when there's an MR.
- `pw-review.sh init <slug> <review-rel-path> <doc-rel-path>` — **idempotently create a review
  file from the template** if (and only if) it doesn't exist yet. `/pw-analyze` and `/pw-breakdown`
  call this so `analysis/review/<topic>.review.md` / `task/review/PLAN.review.md` are already there
  — the human never has to copy the template themselves. Never hand-write a review file; this also
  guarantees the permanent `> **Add an item:**` / `> **Answer a question:**` format hints never get
  silently dropped. Batch catch-up for a whole project (analysis docs + PLAN + every T0n):
  `pw-review.sh init-all <slug>`.
- `pw-review.sh` — **the write side of review files** (human entry: `/pw-review <slug>
  item|answer|signoff|init-all`): `add-item` (next Rn, timestamp + `pw-item-status` marker +
  `---` + reindex, fills the template stub in place), `answer` (styled `↳ you:` line under a Qn —
  never flips status), `add-question` / `resolve` (agent-side: Qn creation; in-place tag+marker
  flip with the `↳ agent:` reply — `resolve` on a Qn refuses unless a `↳ you:` line exists),
  `signoff` (**human-triggered only, C4 — never on agent initiative**; the agent-side gate path
  stays `pw-review.sh auto-signoff`). Free text via `--text <rest-of-line>` or `--stdin`
  heredoc, stored verbatim (A-rules, `tooling/docs/conventions.md`).
- `pw-context.sh` — **deterministic context-doc writes** (human entry: `/pw-context <slug> …`):
  `req-init` (REQUIREMENTS.md from template, idempotent), `add-input` (INDEX.md inputs row —
  native A2 flag-segments, auto date, pipe escaping, placeholder-row replacement), `add-repo`
  (Repos-in-scope row, rest-of-line why; never touches `pw-adopt-scope` marker rows).
- The old frozen legacy catch-all script was fully dissolved; there is no second catch-all (S2),
  shared markdown primitives to `pw-mdlib.sh` — see `tooling/docs/conventions.md` (S/C/A-rules)
  before adding any script/operator/command.
- `pw-status.sh log <slug> <actor> <msg>` — append one audit line to **`LOG.md`** as a Markdown bullet
  (`- **YYYY-MM-DD HH:MM** · \`actor\` — what`, not a bare pipe row — reads properly in a plain
  preview view). Log phase transitions, executor spawns, commits, pushes, MRs, review passes,
  close-out.
- `pw-status.sh phase <slug>` — read the current phase (used by `/pw-review` scoping + `/pw-status`).
- `pw-config.sh ai-review <slug> [<phase> <mode>]` / `pw-config.sh ai-model <slug> [<lane> <provider:model|—>]` —
  the two dashboard config lines (see `docs/EXECUTION.md` for what they bind). `ai-model` lanes =
  researcher / analyst / writer-task / reviewer / verifier (NOT executor — that pin is the task file).
  A bare model name or an executor lane is refused.
- **Spawn bookkeeping (the §8.5 ledger):** every delegated spawn logs one line through
  `pw-status.sh log`, carrying `· session=<id> · seed=<ref> · out=<artifact>` so a later
  repair/cascade/recheck can **resume that session** instead of re-deriving it (machine-local
  pointer only — never in MR text; PLAN/dashboard/on-disk state is the durable cross-machine truth).
- `pw-ship.sh mr-state <slug> <task-id>` — query the forge (GitLab/GitHub) for an MR's current state.
  Prints `open`, `merged`, `closed`, or `unknown` (the last on any lookup/query failure — no MR
  URL/worktree/origin, or the forge query failed or returned null — with exit 1). Used by `/pw-sync`
  and `/pw-ship comments` to detect MRs that were already merged downstream before attempting to
  sync or process comments.
- `pw-status.sh task-accept <slug> <task-id>` — update a task's `Status:` field to `accepted` (used
  when an MR is already merged).
- `pw-status.sh dashboard-task-status <slug> <task-id> <status>` — update a task's status in the
  dashboard README.md task status table.
- `pw-ship.sh dashboard-mr-state <slug> <task-id> <state>` — update an MR's state in the dashboard
  README.md MR table (e.g., `merged`).
- `pw-worktree.sh remove <slug> <task-id>` — safely remove a task's worktree (refuses if the
  worktree has uncommitted changes or is the current directory). Used when an MR is already merged
  to clean up the worktree.
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
`/pw-breakdown <slug>`, `/pw-review <slug> [phase|Tid(s)|path]` (scoped to the current phase; task ids can be a list),
`/pw-execute <slug> [task-ids | "with <model/agent>"]` (stops at committed + verified),
`/pw-ship <slug> [task-ids] [comments] [--skip-build-check]` (push + open MRs; the outward-facing
publish step; by default also monitors the MR's pipeline to a terminal state before returning —
`--skip-build-check` opts out),
`/pw-sync <slug> [task-ids]` (merge the moved base branch into each open MR branch, re-verify, push),
`/pw-status <slug>`, `/pw-close <slug>`,
`/pw-doctor [--fix]` (verify/repair that installed commands + agents + skill match the bundle),
`/pw-rfc <slug> [--target <ref>] [milestone|comments]` (optional side-loop — publish approved
analysis/plan content to an RFC doc, any configured backend or none; see `tooling/docs/rfc.md`).
The command files are **generated build artifacts** — the single source is
`agentic-project-workflow/tooling/commands/*.md`, emitted per provider by
`gen-commands.sh` (in `tooling/scripts/toolchain/`; Claude → `~/.claude/commands/`, kilo →
`~/.config/kilo/command/`, cursor → `~/.cursor/commands/`); the sub-agents (`pw-orchestrator`,
`pw-executor`) are seeded the same way from `tooling/agents/` by `gen-agents.sh`. To change a
command's prompt or an agent, edit the canonical file and re-run the generator — never hand-edit the
per-provider copies.

## Discovery without reading the whole toolkit

- **Help first (agents).** "What exists / how do I invoke it exactly" is answered in one bounded,
  exit-coded call: `pw-help.sh overview --json`, `pw-help.sh command <name> [<slug>] --json`,
  `pw-help.sh operators <name> [<operator>]`, `pw-help.sh project <slug> [<name>]`,
  `pw-help.sh find <term> --json`. It renders from the live sources (frontmatter + usage headers +
  phase map), so it cannot be a stale snapshot — cheaper than reading command files end to end.
  Only the `--json` shapes are stable contracts; human table layout may reflow. And help is
  introspection: it never decides gates, signs off, or replaces the command-file doctrine.

## Conventions (the contract)

- **Tooling edits follow the test protocol**: work only in the bundle's canonical sources
  (`tooling/`, `template/`, never installed provider copies) and run
  `tooling/tests/pw_test.sh all` before considering the change done — change-type → required
  tiers in `tooling/docs/testing.md` (`pw-doctor.sh --test` is the same harness).
- **Task IDs:** `T01`, `T02`… referenced by `depends_on`.
- **Branch:** `agent/<project-slug>/<task-id>-<slug>`
- **Worktree:** `worktree/<repo>/<task-id>-<slug>/`, created by `git worktree add` off the real
  sibling repo in `$PW_REPOS/` — never a copy. Remove with `git worktree remove` when done.
- **Isolation:** an executor edits ONLY its worktree. No cross-task edits.
- **Done:** only after running the task's `## Verify` and pasting real output. Report failures
  and skips faithfully — never claim done on unverified work.
- **Commits:** Conventional Commits.
- **Comments are for the global team:** write a code comment (and commit-message detail) only when
  it helps a future maintainer or an external reviewer who has NO access to this project's internal
  docs. Never cite internal pipeline IDs (`Rn`/`Qn`/`Pn`, review-file item anchors,
  `task/T0n.md` headings) in committed code, commit messages, or MR-visible text — internal
  cross-references belong in the project record (`## Result`, `LOG.md`), never in the artifact.
  When a comment would only make sense to whoever filed the review item, don't write it — explain in
  the `↳ agent:` reply instead.

## Scaffolded project dirs are plain (not git repos)
This is by design — version history lives in the real repos, and workflow learnings go in the
project's "Decisions & learnings" section (and your memory tool at close-out, if `PW_MEMORY` names
one). The reusable **bundle itself IS a git repo** (so it's shareable + reset-recoverable via
`bootstrap.sh`); its own tooling changes are tracked there. Distil durable learnings at close-out.

## LOG.md spawn lines (the resume spine)

Every **delegated** spawn gets one line via `pw-status.sh log <slug> <actor> "<msg>"` — free text by
design, with one fixed spine so a resume can find it later:
`spawned <lane-or-T0n> (<provider>:<model>) · session=<id> · seed=<seed ref> · out=<artifact> · <outcome>`.
A resume/repair/cascade appends its **own** line and updates the prior line's outcome — the trail
reads as a chain, every link resumable. Rules (§Spawn lanes + references/review.md): resume by
that recorded id first, cold-spawn only when dead; session ids never leave the workspace and never
into MR text (they're machine-local; on-disk PLAN/dashboard/worktree state is the cross-machine
recovery).
