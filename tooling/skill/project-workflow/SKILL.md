---
name: project-workflow
description: Run a multi-repo change through the phased AI-agent pipeline under IdeaProjects/projects/ — context → analysis → task breakdown → parallel worktree execution → review → learn. Use whenever working inside IdeaProjects/projects/<project>/ (context/, analysis/, task/, worktree/), when asked to analyze context, break analysis into tasks, write or read an orchestration PLAN.md, spawn executor sub-agents against git worktrees, or scaffold a new project from the bundle. Also use when the user mentions the "project workflow", "task breakdown", "orchestration plan", or multi-repo agentic execution.
---

# Project Workflow (multi-repo agentic pipeline)

Canonical guide + templates live in `~/IdeaProjects/projects/agentic-project-workflow/`. **Read
`agentic-project-workflow/README.md` first** — it is the source of truth; this skill is the on-demand cheat sheet.
New project: `~/IdeaProjects/projects/agentic-project-workflow/tooling/scaffold.sh <project-slug>`.
Onboarding a fresh machine or a teammate: `agentic-project-workflow/bootstrap.sh` (detects installed CLIs, installs
this skill + the `/pw-*` commands per provider) — see `agentic-project-workflow/ONBOARDING.md`.

## Structure of a project
```
<project>/  README.md(dashboard) · context/ · analysis/ · task/(PLAN.md + T0n.md) · worktree/
```
Phases are gated: a human approves after **analysis** (step 3) and after **task breakdown**
(step 5) before the next phase runs. Don't skip a gate.

## Which phase am I in? → what to produce

- **Analysis** (asked to analyze `context/`): **search memory first — only if a memory tool is
  configured** (`PW_MEMORY`; see `tooling/memory.md`) — fold in and cite what's relevant; skip
  silently if none. Then write `analysis/<topic>.md` from `analysis/_TEMPLATE.md` (record the
  authoring `Provider:`). Describe *what & why*, **confirmed** affected repos (verify real state on
  the actual base branch), risks, options + a recommendation. Do **not** cut tasks yet. **Last step:
  set the dashboard one-liner + Status via `pw-lib.sh oneliner` + `status <slug> analysis`.** Iterate
  with the human until approved.

- **Breakdown** (asked to break analysis into tasks): produce
  1. `task/PLAN.md` (from `_TEMPLATE-orchestration-plan.md`) — repo manifest, global rules,
     **Produced by** (the provider this breakdown ran under = default execution provider),
     dependency DAG, task table. **This is what the executor reads first.**
  2. `task/T01.md … Tnn.md` (from `_TEMPLATE-task.md`) — each **self-contained** (one repo, one
     branch, one worktree, linked context, a runnable `## Verify` block = its DoD). Write
     **DETAILED `## Steps`** (exact file + exact change + exact command per step) so the executor
     needs minimal independent reasoning — cheaper, more reliable. **Default each task's provider
     to "Produced by"** so the human isn't forced to switch agents; only route elsewhere with a
     `Why:`.

- **Execution** (handed `task/PLAN.md`): act as **orchestrator** — read the DAG, spawn one
  **executor** per task respecting `depends_on`, keep the dashboard status column + `LOG.md`
  current. Never edit repo code as the orchestrator. **Same-provider tasks → spawn a native
  in-process sub-agent** (natively monitorable); different-provider → shell out to that CLI
  headlessly. **Tee each run to `worktree/<T0n>.log`** so the human can tail it. Each executor
  works in its own worktree, runs Verify, reports real output, fills `## Result`. **Execution stops
  at committed + verified** — pushing branches and opening MRs is the separate `/pw-ship` step
  (nothing goes outward until asked). Reject → `Status: verify-failed` (+ optional
  `task/review/T0n.review.md`) + re-run.

## Review feedback (per-artifact `.review.md`, in a `review/` subdir)
Human feedback on any doc lives in a review file under a **`review/` subdir** beside it, NOT inline
(you rewrite the doc when applying fixes and would clobber the notes):
`analysis/x.md`→`analysis/review/x.review.md`, `task/PLAN.md`→`task/review/PLAN.review.md`,
`task/T0n.md`→`task/review/T0n.review.md` (from `agentic-project-workflow/template/_REVIEW.template.md`). Rules you MUST follow:
- **`/pw-review` is scoped to the current phase** (resolved from the dashboard `Status:`), not the
  whole project — process only that phase's `review/` dir, don't open every `.review.md`.
- **`/pw-review` NEVER changes the dashboard `Status:`** — reviewing is not a phase transition.
- **Task review is OPTIONAL.** Only the PLAN sign-off gates execution; per-task `T0n.review.md`
  files exist only when the human sends a task back. If a task is flipped to `verify-failed` but has
  **no** review file, create it from `_REVIEW.template.md` using the human's chat feedback, then
  apply it — don't silently do nothing (a frequent confusion). If there's no feedback anywhere, ask.
- Before editing any doc, read its `.review.md` first.
- Apply each `🔴 open` item, append a `↳ agent:` reply, flip it to `🟢 resolved`. **Never edit or
  delete the human's comment text** — it's the source of truth for what was asked.
- The `↳ agent:` reply IS how the human sees what you did — make it a **concrete summary** (name
  the section + what changed), never a bare "fixed"/"done". No diff expected; the summary is it.
- After a review pass, **recap the resolved items back in chat** (one line each) so the human
  sees the changes without opening the file.
- **Never** write the Sign-off row — only the human clears a gate (`approved ✅`, date-time to the minute).
- Rejected execution result → the human adds items to `task/review/T0n.review.md` and sets the task
  `Status: verify-failed`; re-run it in its worktree and re-verify.
- **Open questions (QnA):** when you can't resolve something during analysis, don't guess — list
  it in the doc (`❓ Qn`) AND seed a `Qn` row in the review file's "## Open questions" section. The
  human answers with `↳ you:`; the next `/pw-review` folds the answer into the doc and flips the
  row to ✅ answered. Report unanswered `Qn` as blocking.
- **MR feedback:** review comments left on the *MR itself* are handled by `/pw-ship <slug> [task-ids]
  comments` (fetch via `glab`/`gh`, fix in the worktree, reply on the thread). **Task IDs are
  optional — with none it sweeps EVERY open MR** in the project in one run (serially). Always
  **mirror the change into the internal record** (task `## Result` + `task/review/` + `LOG.md`); the
  project dir stays the source of truth even for MR-driven fixes.
- After a pass, report how many `🔴 open` items remain: `rtk grep -rln "🔴 open" <project>/`.

**Who fills what** (put a `Filled by:` note on every table/form so it's unambiguous): 🤖 =
AI-maintained (don't hand-edit) · 🧑 = human fills · 🤖🧑 = both. Human-owned: `context/`, review
items + QnA answers + Sign-off, `provider registry`, and the `accepted`/`verify-failed` task
states. Agent-owned: analysis/plan/task docs, the dashboard `Status:`/tables, `## Result`, `LOG.md`.

**Going back a phase (rewind):** to reopen an earlier phase, the human adds a fresh `🔴 open` item
+ a new `in-review` Sign-off row (old `approved ✅` stays as history) and bumps the dashboard
`Status:` back **with the explicit rewind flag** (`pw-lib.sh status <slug> <phase> --rewind` — a
plain `status` refuses to move backward, which is what stops accidental resets); then re-run that
phase's command and re-approve. Downstream artifacts stay on disk and get regenerated once the
upstream phase is re-approved.

## Status field + audit log (commands own these — via `pw-lib.sh`)
Don't hand-edit the Status line or LOG.md — use the helper `agentic-project-workflow/tooling/pw-lib.sh` (deterministic,
phase-validated, portable across Claude Code + shelled-out kilo executors):
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
- `pw-lib.sh log <slug> <actor> <msg>` — append one audit line to **`LOG.md`**
  (`YYYY-MM-DD HH:MM | actor | what`). Log phase transitions, executor spawns, commits, pushes,
  MRs, review passes, close-out.
- `pw-lib.sh phase <slug>` — read the current phase (used by `/pw-review` scoping + `/pw-status`).
- Per-task **timing + commit/MR outcome** go in the task file's `## Result` block and the PLAN
  task table's Time/Result columns. **Token/cost are NOT captured** — a running agent can't measure
  them; leave them to external session telemetry, don't fabricate.

## Model / agent per task + provider routing
Every task carries `Execute with: <provider>:<model-or-agent>` + `Why:` + `Story points:`, and
optional `Effort:` (`low`/`medium`/`high`/`xhigh`/`max` → claude `--effort`, kilo `--variant`) +
`Thinking:` (kilo `--thinking`). `PLAN.md` mirrors it in **Execute with** + **SP** columns.
**Default the provider to the plan's "Produced by"** (the agent that did the breakdown) so a run
doesn't force an agent switch; route a task to a different provider only with a stated `Why:`.
**Claude aliases (`opus`/`sonnet`/…) follow the latest version — pin the full name
(`claude-opus-4-8` vs `claude-opus-5`) for reproducibility.** Defaults: `claude:opus`=complex/risky,
`claude:sonnet`=standard (most), `claude:haiku`=trivial mechanical; open-weight models route to
`kilo` via **whichever KiloCode model providers you configured** (`PW_KILO_PROVIDERS` array in
`pw.config.sh` — KiloCode can serve several at once; the maintainer's is `command_code`), e.g.
`kilo:command_code/MiniMaxAI/MiniMax-M3` or `kilo:openrouter/<model>` (`kilo models <provider>` for
each provider's list).
- **Provider registry** = `agentic-project-workflow/tooling/providers.md`: maps each model/agent → the CLI that runs
  it, and gives that CLI's **headless invocation**. It's the extension point — add a row to
  onboard a new model/provider; nothing hard-codes the list.
- **Cross-provider execution:** if a task's provider ≠ the orchestrator's own, the orchestrator
  **shells out to that provider's CLI headlessly**, passing the task file as the work order (Claude
  Code ⇄ KiloCode, and any future provider). The discipline travels with the task (skill + task
  file), not the provider. Unverified headless flags → check `--help` or ask; don't guess.
- The orchestrator spawns (or shells out to) whatever `Execute with:` names — an existing agent
  (e.g. `code-implementation`), the shipped `pw-executor`, or a `provider:model`. Two agents ship
  and are seeded per provider from `tooling/agents/` (`pw-orchestrator`, `pw-executor`); add a def
  there only for a genuinely new role no existing agent covers.
- **Agent vs sub-agent — the distinction is load-bearing across providers.** A **sub-agent** is
  spawned *in-process* by an orchestrator of the **same provider** (Claude Task `subagent_type`;
  kilo `mode: subagent`) — a provider can spawn only its OWN sub-agents. `pw-executor` is a
  sub-agent. An **agent** (primary/invocable) is invoked through a provider's CLI — the only unit
  that crosses a provider boundary. `pw-orchestrator` is primary.
- **Cross-provider rule (get this right):** an orchestrator on provider A routing a task to provider
  B **cannot spawn B's sub-agent**. A Claude orchestrator delegating to kilo does NOT name
  `pw-executor` (a kilo sub-agent it can't reach) — it invokes kilo's CLI headlessly with the **task
  file + `project-workflow` skill** as the work order and lets kilo's default agent run it (the
  discipline travels with skill+task, no named agent needed). So `pw-executor` is usable only when
  its own provider is the orchestrator. Routing resolves to exactly one of: **same provider → spawn
  the sub-agent in-process**; **different provider → shell out to that CLI passing the task file
  inline to its default/primary agent** (never `--agent <a-sub-agent>` across the boundary; only a
  provider's own *primary* agents are invocable from outside). When `Execute with:` names an agent,
  resolve its provider: explicit `<provider>:` prefix → else the agent def's own provider → else
  (built-in, no def) the orchestrator's own provider.
- During **breakdown**, set each task's `Execute with:` + `Why:` + `Story points:` (2 SP = 1
  person-day; PLAN carries the manual-effort/timeline estimate). During **execution**, honor any
  override ("run T03 with kilo:command_code/MiniMaxAI/MiniMax-M3") and write it to `Actually used:`.

## Slash commands (generated — one source of truth)
Users drive phases with `/pw-*`. **Two entry workflows:** `/pw-new <slug>` (fresh start) OR
`/pw-adopt <slug> <repo> <branch> [mr-url]` (continuation — onboard existing in-progress branch(es),
run once per branch; continue-on-same-branch; serial within a branch, parallel across branches).
Then `/pw-analyze <slug> [focus]`,
`/pw-breakdown <slug>`, `/pw-review <slug> [phase|Tid|path]` (scoped to the current phase),
`/pw-execute <slug> [task-ids | "with <model/agent>"]` (stops at committed + verified),
`/pw-ship <slug> [task-ids] [comments]` (push + open MRs; the outward-facing publish step),
`/pw-sync <slug> [task-ids]` (merge the moved base into each open MR branch, re-verify, push),
`/pw-status <slug>`, `/pw-close <slug>`,
`/pw-doctor [--fix]` (verify/repair that installed commands + agents + skill match the bundle).
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
  sibling repo in `IdeaProjects/` — never a copy. Remove with `git worktree remove` when done.
- **Isolation:** an executor edits ONLY its worktree. No cross-task edits.
- **Done:** only after running the task's `## Verify` and pasting real output. Report failures
  and skips faithfully — never claim done on unverified work.
- **Commits:** Conventional Commits.

## Create a worktree
```bash
git -C ~/IdeaProjects/<repo> worktree add \
  ~/IdeaProjects/projects/<project-slug>/worktree/<repo>/<task-id>-<slug> \
  -b agent/<project-slug>/<task-id>-<slug>
```

## Gotchas
- **KiloCode headless needs `--auto`** — `kilo run` without it auto-*rejects* every permission
  (can't even read the task file). Worktrees are fine via the CLI (`kilo run --auto` verified
  end-to-end); the "auto-approve breaks in worktrees" issue is the **JetBrains plugin**, not the CLI.
- **Scaffolded project dirs** (`$PW_PROJECTS/<slug>/`) are **plain (not git repos)** by design —
  version history lives in the real repos, and workflow learnings go in the project's "Decisions &
  learnings" section (and your memory tool at close-out, if `PW_MEMORY` names one). The reusable
  **bundle itself IS a git repo** (so it's shareable + reset-recoverable via `bootstrap.sh`); its
  own tooling changes are tracked there. Distil durable learnings at close-out.

## Learn + close (step 8 — `/pw-close`)
After a run, `/pw-close`: verify all tasks `accepted`, **tear down worktrees with the safe helper**
(`tooling/pw-teardown.sh <project-dir>` — it won't remove the worktree you're standing in or a
dirty one, the guard that stops an editor closing on you; don't delete branches/project dir), seed
workflow-level learnings **if a memory tool is configured** (`PW_MEMORY`; mark superseded facts
`[SUPERSEDED]`), improve the bundle's `template/` files or this skill, set `Status: done`, and
summarize MRs/leftovers. Don't save what the repos/commits already record. **`accepted` ≠ merged**
— a project closes on verified + MR opened + human sign-off; open/on-hold MRs don't block close-out
(record their state in the dashboard). Don't delete branches or the project dir.
