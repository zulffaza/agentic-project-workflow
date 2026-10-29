# Conventions, helpers, and cross-cutting gotchas

## Who fills what
**Who fills what** (put a `Filled by:` note on every table/form so it's unambiguous): 🤖 =
AI-maintained (don't hand-edit) · 🧑 = human fills · 🤖🧑 = both. Human-owned: `context/`, review
items + QnA answers + Sign-off, `provider registry`, and the `accepted`/`verify-failed` task
states. Agent-owned: analysis/plan/task docs, the dashboard `Status:`/tables, `## Result`, `LOG.md`.

## Going back a phase (rewind)
To reopen an earlier phase, the human adds a fresh `[OPEN]` item + a new `in-review` Sign-off row
(old `approved` stays as history) and bumps the dashboard `Status:` back **with the explicit
rewind flag** (`pw-status.sh status --project <slug> --phase <phase> --rewind` — a plain `status` refuses to move
backward, which is what stops accidental resets); then re-run that phase's command and re-approve.
Downstream artifacts stay on disk and get regenerated once the upstream phase is re-approved.

## Agent-mediated operations
The `/pw-*` commands and the matching plain-language request are the user interface. Internal
scripts and operator syntax are how the agent carries out the request; they are not instructions
for the user.

1. **A supported command exists.** Name the command path for discovery and carry out its
   mechanics within the authorization already given.
2. **No command exists.** Say what will change (records, evidence, risk) in plain terms, then use
   the supported internal helper once the request authorizes that change. Offer the help if the
   request was only a question or audit.
3. **A gate or decision is missing.** Report the exact blocker and ask for that decision. Never
   invent a command, hand-edit a load-bearing line, or propose a shell workaround.
4. **After the write.** Read the state back and report what changed, what remains, and any warning
   or partial write. Never describe a failed or partial write as success.

Do not recommend entity-script names or paths, maintainer help, or direct state edits in ordinary
plans, progress notes, recovery suggestions, or final summaries. A direct request for technical
detail ("show me the command/why it failed internally") may include mechanics; that exception does
not move execution responsibility to the user. Setup/uninstall scripts keep their documented
exception. Errors still state the concrete cause and the supported recovery action.

Use the single record operator for task and phase updates:
`pw-status.sh update --project <slug> --task <T0n> --status complete|accepted` and
`pw-status.sh update --project <slug> --status review`. `complete` records a verified result as
`done` without shipping; `accepted` records the human acceptance decision; `review` advances the
whole project only when the shared readiness rule passes. Unknown values, a missing/extra task
selector, or any `--phase` input fail before a write. The command never infers acceptance from a
clean result, never treats a closed/unmerged MR as done, and never advances a project whose PLAN
still has runnable work. Before completing an `in-progress` task, confirm no executor is still
writing it; the bounded stable-read window only detects a record that changes during the check.

## Status field + audit log (commands own these — via `pw-status.sh`)
Don't hand-edit the Status line or LOG.md — use the helper `agentic-project-workflow/tooling/scripts/entities/pw-status.sh`
(deterministic, phase-validated, portable across Claude Code + shelled-out kilo executors):
- `pw-status.sh status --project <slug> --phase <phase>` — set the dashboard `Status:` (`context→analysis→breakdown→
  executing→review→done`) and auto-log the change. Each `/pw-*` command runs this as its
  **mandatory last step** (analyze/breakdown/execute say "do NOT skip"); never leave Status stale or
  hand-maintained. It **refuses a backward move** (guards against accidental resets like the phase
  sliding back to `context`); pass `--rewind` to intentionally go back. `executing`↔`review` is not
  backward (re-running a task is normal).
- `pw-status.sh update --project <slug> --task <T0n> --status complete|accepted` and
  `pw-status.sh update --project <slug> --status review` — the only public record-update route.
  Values are a closed, case-sensitive set; `complete` maps to persisted task `done`, `accepted`
  uses the existing three-holder propagator, and `review` uses the shared whole-PLAN readiness
  predicate. Unknown values fail with exit 2 before any write. Full contract:
  [Agent-mediated operations](#agent-mediated-operations).
- `pw-status.sh oneliner --project <slug> --text "<text>"` — set the dashboard **One-liner** (the agent does this during
  `/pw-analyze`, distilled from context/).
- `pw-status.sh adopted --project <slug> --text "<pointer>"` — set/insert the dashboard **Adopted:** pointer (the agent
  does this during `/pw-adopt`; inserts the line only for continuation projects).
- `pw-context.sh adopt --project <slug> --repo <repo> --branch <branch> --base <base> [--mr <url>]` — **deterministically append/upsert one
  adoption unit** into `context/ADOPTED.md` (keyed by `repo@branch`; new units append at EOF,
  re-adopting the same one updates it in place). In `context/INDEX.md` it also **ensures a one-time
  generic `ADOPTED.md` provenance row** (never re-enumerated per unit) **and upserts one matching
  `(repo, origin/<base>)` row into the "Repos in scope" table** (keyed by a hidden
  `<!-- pw-adopt-scope:… -->` marker). Use this in `/pw-adopt` — do NOT hand-write `ADOPTED.md` or
  hand-edit `context/INDEX.md`'s adoption rows (free-form editing is what clobbered a 2nd/3rd
  adopted branch and re-churned the provenance line each attempt). It also bumps the `Adopted:`
  count. Resolve `<base>` from the **MR's target branch** when there's an MR.
- `pw-review.sh init --project <slug> --file <review-rel-path> --doc <doc-rel-path>` — **idempotently create a review
  file from the template** if (and only if) it doesn't exist yet (the legacy single-file triple,
  kept for mechanical callers like `/pw-analyze`/`/pw-breakdown` creating their OWN artifact's
  review). `pw-review.sh init-docs --project <slug> --file <artifact-rel> [--file <artifact-rel>]…` takes the selected-artifact list
  (validate-all-then-create; exactly those reviews, nothing as a side effect).
  `pw-review.sh init-all --project <slug>` is the catch-up for the **current dashboard phase only** —
  never earlier/later phases, no user override. Never hand-write a review file; these guarantee
  the permanent `> **Add an item:**` / `> **Answer a question:**` format hints never get
  silently dropped.
- `pw-review.sh` — **the write side of review files** (human entry: `/pw-review
  item|answer|signoff|init|init-all --project <slug>`): `add-item` (next Rn, timestamp + `pw-item-status` marker +
  `---` + reindex, fills the template stub in place; a first real item/answer after an approval
  also appends the attributed `pw-review (feedback)` `in-review` row in the same write), `answer`
  (styled `↳ you:` line under a Qn — never flips status), `add-question` / `resolve` (agent-side:
  Qn creation; in-place tag+marker flip with the `↳ agent:` reply — `resolve` on a Qn refuses
  unless a `↳ you:` line exists), `start --project <slug> --file <review-rel> [--phase <lane>] [--provider <actual>]
  [--model <actual>] [--confirm-earlier]` (pass entry: `changes-requested` ONLY with validated
  eligible work, repair mode unphased / AI mode phased; never `approved`), `signoff`
  (**human-triggered only, C4 — never on agent initiative**; the agent-side gate path stays
  `pw-review.sh auto-signoff`, extended with `--provider`/`--model`/`--confirm-earlier` and the
  lane/rejection guards). Free text via `--text <prose…>` (the value runs until the next `--flag`
  token) or a `--stdin` heredoc, stored verbatim (named-argument grammar — operation words first, every
  value named — `tooling/docs/conventions.md`).
- `pw-context.sh` — **deterministic context-doc writes** (human entry: `/pw-context … --project <slug>`):
  `req-init` (REQUIREMENTS.md from template, idempotent), `add-input` (INDEX.md inputs row —
  named flag values, auto date, pipe escaping, placeholder-row replacement), `add-repo`
  (Repos-in-scope row, `--why` prose value running until the next `--flag`; never touches `pw-adopt-scope` marker rows), plus
  preparation's keyed `ensure-input`/`ensure-repo` (same shapes; a repeat run updates its own
  row in place instead of duplicating, context phase only — see `references/context.md`).
- The old frozen legacy catch-all script was fully dissolved; there is no second catch-all (S2),
  shared markdown primitives to `pw-mdlib.sh` — see `tooling/docs/conventions.md` (S/C/A-rules)
  before adding any script/operator/command.
- `pw-status.sh log --project <slug> --actor <actor> --message <msg>` — append one audit line to **`LOG.md`** as a Markdown bullet
  (`- **DD MMMM YYYY - HH.mm WIB** · \`actor\` — what`, not a bare pipe row — reads properly in a plain
  preview view). Log phase transitions, executor spawns, commits, pushes, MRs, review passes,
  close-out.
- `pw-status.sh phase --project <slug>` — read the current phase (used by `/pw-review` scoping + `/pw-status`).
- `pw-status.sh --all [--attention] [--phase <phase>] [--json]` — READ-ONLY cross-project
  overview (no slug): per-project phase, attention conditions, accepted counts, last LOG event,
  and the inspection command. Local records only — never writes (no config-line insertion, no
  forge/auth/model calls). Exit `1` = partial scan (unreadable/malformed records; rows kept).
- `pw-config.sh get|set --project <slug> --key ai-review|ai-model` —
  the two dashboard config lines (`get` prints; `set` takes `--value <v>` or `--set <member>=<value>` pairs,
  plus `--variant/--reasoning/--effort` for exactly one `ai-model` role; see `docs/EXECUTION.md` for
  what they bind). Read `ai-model` with `--json` for the complete binding and resolve dispatch with
  `spawn-args --role <role>`. `ai-model` lanes =
  researcher / analyst / writer-task / reviewer / verifier / ship-comment-analyst / explorer (NOT executor —
  that pin is the task file). A bare model name or an executor lane is refused.
- **Spawn bookkeeping (the §8.5 ledger):** every delegated spawn logs one line through
  `pw-status.sh log`, carrying `· session=<id> · seed=<ref> · out=<artifact>` so a later
  repair/cascade/recheck can **resume that session** instead of re-deriving it (machine-local
  pointer only — never in MR text; PLAN/dashboard/on-disk state is the durable cross-machine truth).
- `pw-ship.sh mr-state --project <slug> --task <task-id>` — query the forge (GitLab/GitHub) for an MR's current state.
  Prints `open`, `merged`, `closed`, or `unknown` (the last on any lookup/query failure — no MR
  URL/worktree/origin, or the forge query failed or returned null — with exit 1). Used by `/pw-sync`
  and `/pw-ship comments` to detect MRs that were already merged downstream before attempting to
  sync or process comments.
- `pw-status.sh task-accept --project <slug> --task <task-id> [--observed-merged]` — the acceptance flow: ONE call sets all
  three acceptance holders (task-file `Status:` field, the PLAN task-table Status cell the close
  gate reads, and the dashboard task row — best-effort), with a single LOG line; idempotent.
  Pass `--observed-merged` only when the call follows an observed merged state; without it the
  LOG says the task was accepted, not that an MR merged.
- `pw-status.sh dashboard-task-status --project <slug> --task <task-id> --status <status>` — update a task's status in the
  dashboard README.md task status table.
- `pw-ship.sh dashboard-mr-state --project <slug> --task <task-id> --state <state>` — update an MR's state in the dashboard
  README.md MR table (e.g., `merged`).
- `pw-worktree.sh remove --project <slug> --task <task-id>` — safely remove a task's worktree (refuses if the
  worktree has uncommitted changes or is the current directory). Used when an MR is already merged
  to clean up the worktree.
- Per-task **timing + commit/MR outcome** go in the task file's `## Result` block and the PLAN
  task table's Time/Result columns. **Token/cost are NOT captured** — a running agent can't measure
  them; leave them to external session telemetry, don't fabricate.

## Slash commands (generated — one source of truth)
Users drive phases with `/pw-*`. **Two entry workflows:** `/pw-new --project <slug>` (fresh) OR
`/pw-adopt --project <slug> --repo <repo> --branch <branch> [--mr <url>] [--intent review-only]` (continuation — full guide
`agentic-project-workflow/docs/ADOPTION.md`). Adoption is a **context/baseline** action, run once per
in-progress branch (continue-on-same-branch; serial within a branch, parallel across), with two
intents: **continue-dev** (default) → lands at `context`, then analyze→breakdown→execute→ship the
*remaining* work; **review-only** (`--intent review-only`; MR required) → lands at `review` to
service MR comments (`/pw-ship comments`, `/pw-sync`), skipping analyze/breakdown. Guards: refuse on
a `done` project; a continue-dev adopt onto a project **past `context`** records the unit and
**warns to re-run `/pw-analyze` + `/pw-breakdown`** (never rewinds `Status`). Adopting into an
existing slug yields a **mixed project** — routing is **per task by its `Branch:`**: a task extending
an adopted unit continues on that branch (serial per branch), every other task gets a fresh
`agent/…` branch off its base (parallel). Then `/pw-analyze --project <slug> [--focus <prose…>]`,
`/pw-breakdown --project <slug>`, `/pw-review --project <slug> [--phase <phase> | --task <T0n>… | --file <path>]` (scoped to the current phase; repeat `--task` for a list),
`/pw-execute --project <slug> [--task <T0n>… | --model <provider:model|agent>]` (stops at committed + verified),
`/pw-ship --project <slug> [--task <T0n>]… [--skip-build-check]` (push + open MRs; the outward-facing
publish step; by default also monitors the MR's pipeline to a terminal state before returning —
`--skip-build-check` opts out) or `/pw-ship comments --project <slug> [--task <T0n>]…` (the MR-comment mode),
`/pw-ship request-review --project <slug> [--all | --task <T0n>…] [--to …] [--summary]
[--mr-summary] [--note] [--no-reviewers] [--prose <file>]` (read-only: one copyable teammate
review request; never pushes or comments),
`/pw-sync --project <slug> [--task <T0n>]…` (merge the moved base branch into each open MR branch, re-verify, push),
`/pw-status --project <slug>`, `/pw-close --project <slug>`,
`/pw-doctor [--fix]` (verify/repair that installed commands + agents + skill match the bundle),
`/pw-rfc --project <slug> [--target <ref>]` (Wave 1), `/pw-rfc milestone --project <slug>` (Wave 2) and
`/pw-rfc comments --project <slug>` (comment pull) — the optional side-loop that publishes approved
analysis/plan content to an RFC doc, any configured backend or none; see `tooling/docs/rfc.md`.
The command files are **generated build artifacts** — the single source is
`agentic-project-workflow/tooling/skills/human/*/SKILL.md`, emitted per provider by
`gen-commands.sh` (in `tooling/scripts/toolchain/`; Claude → `~/.claude/commands/`, kilo →
`~/.config/kilo/command/`, cursor → `~/.cursor/commands/`, codex → `~/.codex/skills/<name>/SKILL.md`
— codex has NO native command surface (custom prompts removed upstream in codex-cli 0.117.0), so
its commands are generated explicit-only skill dirs sharing the skills namespace; a bundle skill
colliding with a command name is skipped at install and the command-skill owns the name); the seven worker sub-agents
(`pw-executor`, `pw-reviewer`, `pw-researcher`, `pw-analyst`, `pw-writer-task`,
`pw-ship-comment-analyst`, `pw-explorer`) are seeded the same way from `tooling/agents/` by `gen-agents.sh`. To change a
command's prompt or an agent, edit the canonical file and re-run the generator — never hand-edit the
per-provider copies.

## Discovery without reading the whole toolkit

- **Help first (agents).** "What exists / how do I invoke it exactly" is answered in one bounded,
  exit-coded call: `pw-help.sh overview --json`, `pw-help.sh command --name <name> [--project <slug>] --json`,
  `pw-help.sh operators --name <name> [--operator <op>]`, `pw-help.sh project --project <slug> [--name <command>]`,
  `pw-help.sh find --term <term…> --json`. It renders from the live sources (frontmatter + usage headers +
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
- **Comment necessity test (policy source of truth):** default to self-explanatory code with no new
  comment. Add one only when it supplies a non-obvious reason, constraint, invariant, or externally
  imposed behavior that clear names and structure cannot express. Keep it local and brief. Omit
  implementation diaries, obvious step headings, generic TODOs, and unsupported claims such as
  "safe" or "robust". Keep review IDs, task IDs, model identity, and who requested a fix in the
  project record. Preserve required license/generated markers, API documentation, lint/type
  directives, and justified security or concurrency warnings. Before committing, inspect newly
  added or modified comments in the task diff: if a future maintainer learns nothing beyond the
  surrounding code, remove it or improve the naming. Review fixers apply the same rule; a resolved
  item does not need a source comment describing it. Reviewers flag specific redundant, stale, or
  misleading comments with a file/line and one concrete correction, grouped per nearby instance —
  never a comment-count gate.

## Scaffolded project dirs are plain (not git repos)
This is by design — version history lives in the real repos, and workflow learnings go in the
project's "Decisions & learnings" section (and your memory tool at close-out, if `PW_MEMORY` names
one). The reusable **bundle itself IS a git repo** (so it's shareable + reset-recoverable via
`bootstrap.sh`); its own tooling changes are tracked there. Distil durable learnings at close-out.

## LOG.md spawn lines (the resume spine)

Every **delegated** spawn gets one line via `pw-status.sh log --project <slug> --actor <actor> --message "<msg>"` — free text by
design, with one fixed spine so a resume can find it later:
`spawned <lane-or-T0n> (<provider>:<model>) · session=<id> · seed=<seed ref> · out=<artifact> · <outcome>`.
A resume/repair/cascade appends its **own** line and updates the prior line's outcome — the trail
reads as a chain, every link resumable. Rules (§Spawn lanes + references/review.md): resume by
that recorded id first, cold-spawn only when dead; session ids never leave the workspace and never
into MR text (they're machine-local; on-disk PLAN/dashboard/worktree state is the cross-machine
recovery).
