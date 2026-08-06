# Reference — layout, conventions, commands

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) ·
[Execution & routing](./EXECUTION.md)

## Bundle layout (this repo)

Grouped so it's obvious what's machinery vs. what becomes a project:

```
agentic-project-workflow/        ← this bundle ($PW_HOME)
├── AGENTS.md · CLAUDE.md        ← AI-agent entrypoint (CLAUDE.md just imports AGENTS.md)
├── README.md · ONBOARDING.md    ← guides (human + agent)
├── docs/                        ← the detailed guides (WORKFLOW · REVIEW · EXECUTION · REFERENCE)
├── bootstrap.sh                 ← one-shot onboarding — run this first
├── pw.config.example.sh         ← copy → pw.config.sh; the one file YOU edit (providers + memory)
├── template/                    ← what a scaffolded project is MADE OF (copied per project)
│   ├── PROJECT.template.md · _REVIEW.template.md
│   └── context/ (+_REQUIREMENTS.template.md) · analysis/ · task/ · worktree/
└── tooling/                     ← the MACHINERY (never copied into a project)
    ├── scaffold.sh · gen-commands.sh · gen-agents.sh · pw-lib.sh · pw-doctor.sh
    ├── pw-common.sh · pw-teardown.sh
    ├── commands/                ← canonical /pw-* sources (generated per provider)
    ├── agents/                  ← canonical sub-agents (seeded per provider): pw-orchestrator, pw-executor
    ├── providers.md             ← provider registry
    ├── memory.md                ← optional/pluggable memory policy (works with none)
    └── skill/project-workflow/SKILL.md
```

## Project anatomy (a scaffolded `<slug>/`)

```
<project-slug>/
├── README.md        ← the project DASHBOARD (status, links). Start here.
├── context/         ← raw inputs you feed in: tickets, docs, code refs, transcripts
│   ├── INDEX.md     ← provenance table (what each input is, where it came from)
│   └── _REQUIREMENTS.template.md  ← optional one-page brief (copy to REQUIREMENTS.md to use)
├── analysis/        ← agent-produced analysis docs (the "what & why")
│   └── review/      ← your analysis review files (<topic>.review.md)
├── task/            ← the breakdown (the "how"):
│   ├── PLAN.md      ← orchestration plan: repos, global rules, dependency DAG  ← executor reads THIS
│   ├── T01…Tnn.md   ← one self-contained task file each (each is a spawnable prompt)
│   └── review/      ← your plan/task review files (PLAN.review.md, T0n.review.md)
└── worktree/        ← isolated git worktrees, laid out per-repo/per-task
    └── <repo>/<task-id>-<slug>/
```

Reusable sub-agents are **not** per-project — they're seeded globally from
[`tooling/agents/`](../tooling/agents/README.md).

**Why the phases are separate dirs:** each phase has a human review gate before the next starts.
Keeping inputs, reasoning, and plans in distinct places makes the gate cheap — you review one
artifact type at a time, and a failed run is resumable because state lives on disk.

## Who fills what (legend)

Every table/form in a project carries a `Filled by:` marker so it's unambiguous who owns it:
- 🤖 **AI-maintained** — agents keep it current; don't hand-edit (analysis/plan/task docs, the
  dashboard `Status:` + task/MR tables, each task's `## Result`, `LOG.md`).
- 🧑 **You fill** — `context/` + `INDEX.md`, review items, QnA answers, the Sign-off row, the
  provider registry, and flipping a task to `accepted` / `verify-failed`.
- 🤖🧑 **Both** — e.g. the decisions log, breakdown routing rules.

## Conventions (the contract every agent follows)

- **Task IDs** — `T01`, `T02`, … Stable, zero-padded, referenced by `depends_on` in `PLAN.md`.
- **Base branch** — each task declares a `Base branch:`; its worktree forks from `origin/<base>` and
  its MR targets that base. A repo can appear under **multiple bases** (one `(repo, base)` row each
  in the PLAN manifest) — e.g. a change on `master` and its port on `spring3`.
- **Branch naming** — `agent/<project-slug>/<task-id>-<short-slug>`
  (e.g. `agent/spring-boot-3-upgrade/T03-bump-parent-pom`).
- **Worktree path** — `worktree/<repo>/<task-id>-<short-slug>/` (per-repo, per-task, so parallel
  agents never collide even within the same repo).
- **Commits** — Conventional Commits (`feat:`, `fix:`, `chore:`…), scoped to one task's worktree.
- **Definition of Done** — every task file has a `## Verify` block with **runnable commands and
  expected result**. An agent may only report a task done after running it and pasting real output.
  No verify block → the task is not ready to execute.
- **Reporting** — agents report outcomes faithfully: failing verify = say so with output; skipped
  step = say so. "Done" is claimed only after Verify passes.

## Slash commands & the generator (one source of truth)

You drive each phase with a `/pw-*` command instead of retyping prompts:

| Command | Phase |
|---------|-------|
| `/pw-new <slug>` | scaffold |
| `/pw-adopt <slug> <repo> <branch> [mr-url]` | onboard an existing in-progress branch (continue-on) |
| `/pw-analyze <slug> [focus]` | analysis |
| `/pw-review <slug> [phase\|Tid\|path]` | apply review comments (defaults to current phase's review) |
| `/pw-breakdown <slug>` | task breakdown |
| `/pw-execute <slug> [task-ids \| "with <model/agent>"]` | execution (stops at committed + verified) |
| `/pw-ship <slug> [task-ids] [comments]` | push branches + open MRs (publish); `comments` = handle MR review threads |
| `/pw-sync <slug> [task-ids]` | update open MR branches — merge base in, re-verify, push |
| `/pw-status <slug>` | status |
| `/pw-close <slug>` | learn + close-out |
| `/pw-doctor [--fix]` | check (or repair) that installed commands + agents + skill match this bundle |

These exist for multiple agent tools (Claude Code, kilo, …) but are **not** maintained per tool. The
single source is [`tooling/commands/*.md`](../tooling/) (provider-neutral, `{{ARGS}}` placeholder).
[`tooling/gen-commands.sh`](../tooling/gen-commands.sh) stamps them into each provider's format and
location; [`tooling/gen-agents.sh`](../tooling/gen-agents.sh) does the same for the sub-agents:

```bash
$PW_HOME/tooling/gen-commands.sh    # commands → ~/.claude/commands/, ~/.config/kilo/command/
$PW_HOME/tooling/gen-agents.sh      # agents   → ~/.claude/agents/,   ~/.config/kilo/agent/
```

The per-provider files are **build artifacts — never hand-edit them.** Change a prompt → edit the
canonical file → re-run the generator (or `./bootstrap.sh`). Enable/disable or add a provider → edit
[`pw.config.sh`](../pw.config.example.sh) (never the scripts). See
[`tooling/README.md`](../tooling/README.md) and [ONBOARDING.md](../ONBOARDING.md).
