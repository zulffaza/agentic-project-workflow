# Agentic Multi-Repo Project Workflow

This is the **template + reference guide** for running a piece of work through the AI-agent
pipeline: gather context → analyze → break into tasks → execute in isolated worktrees → review →
learn.

Every project lives in its own directory under `IdeaProjects/projects/<project-slug>/` and is a
copy of this `base/` structure. Spin one up with [`scaffold.sh`](./scaffold.sh):

```bash
$PW_HOME/scaffold.sh spring-boot-3-upgrade
```

> **Path variables used throughout these docs** (so nothing is tied to one machine/username):
> `$PW_HOME` = this bundle's dir (where `scaffold.sh` lives) · `$PW_PROJECTS` = its parent (where
> `<slug>` projects go) · `$PW_REPOS` = the repos root (where your sibling git repos live). Run
> [`./bootstrap.sh`](./bootstrap.sh) once and it exports these (and stamps the real paths into the
> generated slash-commands). New here or on a fresh machine? See [ONBOARDING.md](./ONBOARDING.md).

> The workflow spans two agents by design: **Claude Code** for the thinking phases (analysis,
> task breakdown, review) and **Claude Code or KiloCode** for the execution phase (spawning
> sub-agents against worktrees). The `project-workflow` skill teaches any agent these
> conventions on demand.

---

## Directory anatomy

```
<project-slug>/
├── README.md        ← the project DASHBOARD (status, links). Start here.
├── context/         ← raw inputs you feed in: tickets, docs, code refs, transcripts
│   └── INDEX.md     ← provenance table (what each input is, where it came from)
├── analysis/        ← agent-produced analysis docs (the "what & why")
├── task/            ← the breakdown (the "how"):
│   ├── PLAN.md      ← orchestration plan: repos, global rules, dependency DAG  ← executor reads THIS
│   └── T01…Tnn.md   ← one self-contained task file each (each is a spawnable prompt)
├── worktree/        ← isolated git worktrees, laid out per-repo/per-task
│   └── <repo>/<task-id>-<slug>/
└── sub-agent/       ← custom sub-agent definitions used during execution (optional)
```

**Why the phases are separate dirs:** each phase has a human review gate before the next starts.
Keeping inputs, reasoning, and plans in distinct places makes the gate cheap — you review one
artifact type at a time, and a failed run is resumable because state lives on disk, not in an
agent's head.

**Who fills what (legend).** Every table/form in a project carries a `Filled by:` marker so it's
unambiguous who owns it:
- 🤖 **AI-maintained** — agents keep it current; don't hand-edit (analysis/plan/task docs, the
  dashboard `Status:` + task/MR tables, each task's `## Result`, `LOG.md`).
- 🧑 **You fill** — `context/` + `INDEX.md`, review items, QnA answers, the Sign-off row, the
  provider registry, and flipping a task to `accepted` / `verify-failed`.
- 🤖🧑 **Both** — e.g. the decisions log, breakdown routing rules.

---

## The workflow (8 steps)

| # | Step | Who | Produces | Gate | Command |
|---|------|-----|----------|------|---------|
| 1 | Drop context | You | files in `context/` + a row in `context/INDEX.md` | — | `/pw-new` |
| 2 | Analyze | Claude Code | `analysis/<topic>.md` | — | `/pw-analyze` |
| 3 | Review analysis | You + CC | `analysis/review/<t>.review.md` + fixes | ✅ analysis approved | `/pw-review` |
| 4 | Break down | Claude Code | `task/PLAN.md` + `task/T01…Tnn.md` | — | `/pw-breakdown` |
| 5 | Review tasks | You | `task/review/*.review.md` + fixes | ✅ plan approved | `/pw-review` |
| 6 | Execute | Executor agent | commits/branches in `worktree/*`, pushed + MRs | per-task DoD | `/pw-execute` |
| 7 | Review results | You + agent | verified work, MRs merged | ✅ you accept each task | `/pw-review` |
| 8 | Learn + close | You + CC | EverOS memory, worktrees torn down, Status→done | — | `/pw-close` |

**Who owns the dashboard `Status:` field?** The `/pw-*` commands do — each runs
`workflow/pw-lib.sh status <slug> <phase>` as its last step (analyze→`analysis`,
breakdown→`breakdown`, execute→`executing`/`review`, close→`done`). It is not something you
maintain by hand (that's the "why is it still `planned`?" trap), and the helper validates the
phase + auto-logs the change to [`LOG.md`](#audit-log--logmd).

### Step 1 — Context
Put anything the agent needs to reason well into `context/`: PRD/RFC excerpts, ticket text,
relevant code paths, error logs, Slack/Lark threads. Record provenance in `context/INDEX.md` so
later steps (and future-you) know what each file is and can be trusted. Prefer links + short
excerpts over dumping huge files.

### Step 2–3 — Analysis
Ask Claude Code to analyze against `context/`. Output goes to `analysis/` using
[`analysis/_TEMPLATE.md`](./analysis/_TEMPLATE.md). Analysis answers *what needs to change and
why*, surfaces unknowns/risks, and lists affected repos — it does **not** yet decide task
boundaries. Iterate here until you approve; this is the cheapest place to fix misunderstandings.

### Step 4–5 — Task breakdown
Ask Claude Code to turn approved analysis into a breakdown:

- **`task/PLAN.md`** — the orchestration plan ([template](./task/_TEMPLATE-orchestration-plan.md)).
  This is the artifact the executor reads first. It carries the **repo manifest**, **global
  rules**, and the **dependency DAG** (which tasks are parallel, which block which).
- **`task/T01.md … Tnn.md`** — one file per task ([template](./task/_TEMPLATE-task.md)). Each is
  **self-contained** — an agent handed only `T03.md` must be able to do the work: it names the
  repo, branch, files, links to needed context, and its **Verify / Definition of Done**.

### Step 6–7 — Execution
Hand `task/PLAN.md` to one **orchestrator** agent. It reads the DAG and spawns **executor**
sub-agents — one per task, respecting dependencies (only spawn a task once its `depends_on` are
done). Each executor works in its **own worktree** (see below), runs the task's `Verify` block,
reports the actual command output, and fills the task file's `## Result` block (time, commit, MR,
verify outcome).

**Publish — commit is not the finish line.** After a task verifies, the executor **pushes its
branch and opens an MR** (title + description per convention), then records the MR in the task's
`## Result` and the dashboard's **Merge requests** table. Opening an MR is outward-facing, so the
orchestrator **confirms with you before pushing/opening** unless you've said "push and MR as you
go." Zero-change tasks produce no branch/MR — that's noted, not left blank.

**Rejecting a result** goes through the review loop: add items to `task/review/T0n.review.md`, set
the task `Status: verify-failed`, `/pw-review`, then re-run that one task. See "Review & feedback".

### Step 8 — Learn + close (`/pw-close`)
After the run, `/pw-close` verifies every task is `accepted`, **tears down the worktrees**
(`git worktree remove` + `prune`), captures what changed about the *workflow itself* (not the
code — the repos record that) into EverOS `personal` memory (domain facts → `midtrans`), sets the
dashboard Status → `done`, and summarizes MRs/leftovers. This is the loop that makes the next
project faster. It does **not** delete branches or the project dir.

<a id="audit-log--logmd"></a>
### Audit log — `LOG.md`
Every project has a `LOG.md` — an append-only audit trail, one line per meaningful action (phase
transition, sub-agent spawn, commit, push, MR, review pass, close-out), newest at the bottom:
```
YYYY-MM-DD HH:MM | <phase/actor> | <what happened>
```
The `/pw-*` commands append to it via `workflow/pw-lib.sh log …` (deterministic format); you can
add manual notes too. It answers "what did the agents actually do, and when?" without
reconstructing it from chat.

### Going back a phase (rewind)
Phases aren't one-way. To reopen an earlier phase after you've moved on (e.g. breakdown revealed
the analysis was wrong):
1. Add a fresh `🔴 open` item to that phase's review file (`analysis/review/…` or
   `task/review/…`) describing what needs to change, and add a new `in-review` Sign-off row
   (leave the old `approved ✅` row — it's history).
2. Set the dashboard `Status:` back to that phase.
3. Re-run the phase command (`/pw-analyze` / `/pw-breakdown`), then `/pw-review`, then re-approve.
Downstream artifacts already produced stay on disk; regenerate them once the upstream phase is
re-approved.

---

## Conventions (the contract every agent follows)

**Task IDs** — `T01`, `T02`, … Stable, zero-padded, referenced by `depends_on` in `PLAN.md`.

**Branch naming** — `agent/<project-slug>/<task-id>-<short-slug>`
e.g. `agent/spring-boot-3-upgrade/T03-bump-parent-pom`

**Worktree path** — `worktree/<repo>/<task-id>-<short-slug>/` (per-repo, per-task, so parallel
agents never collide even within the same repo).

**Commits** — Conventional Commits (`feat:`, `fix:`, `chore:`…), scoped to one task's worktree.

**Definition of Done** — every task file has a `## Verify` block with **runnable commands and
expected result**. An agent may only report a task done after running it and pasting real output.
No verify block → the task is not ready to execute.

**Reporting** — agents report outcomes faithfully: failing verify = say so with output; skipped
step = say so. "Done" is claimed only after Verify passes.

---

## Review & feedback (how you comment on agent output)

Feedback does **not** go inline in the doc being reviewed — the agent rewrites that doc when it
applies fixes and would clobber your notes. Instead, each reviewed artifact gets its own review
file in a **`review/` subdir** beside it, which is the durable record of what you asked for:

| Reviewing | Review file |
|-----------|-------------|
| `analysis/spring-boot-3.md` | `analysis/review/spring-boot-3.review.md` |
| `task/PLAN.md` | `task/review/PLAN.review.md` |
| `task/T03.md` | `task/review/T03.review.md` |

(The `review/` subdir keeps reviews from cluttering the result docs — `task/` can hold a dozen
`T0n.md` files, so their reviews live under `task/review/`.) Start one by copying
[`_REVIEW.template.md`](./_REVIEW.template.md) into the phase's `review/` dir. Each item has an
**ID + section anchor** (`R1 · §2`) and a status dot: 🔴 open / 🟢 resolved.

**The contract:**
- You write items. The agent **never edits or deletes your text** — it appends a `↳ agent:` reply
  and flips 🔴→🟢. Your words stay the source of truth for what was asked.
- **How you know what the agent did:** the `↳ agent:` reply is a concrete summary per item (which
  section, what changed) — no diff, just the summary. The agent also recaps the resolved items in
  chat after each pass. Read one item's `↳` line to see exactly what it did for that review.
- Before editing any doc, the agent reads its `.review.md` first.
- Only **you** write the Sign-off row. An agent cannot self-approve a gate — an `approved ✅`
  row is what clears a phase.
- For an **execution** result you're rejecting, add items to `task/review/T0n.review.md` **and**
  set that task's `Status: verify-failed` so it gets re-run in its worktree. Then `/pw-review`
  applies the fixes and `/pw-execute <slug> T0n` re-runs just that task and re-verifies.

List everything still needing work across a project:
```bash
rtk grep -rln "🔴 open" projects/<project-slug>/
```

Keep this separate from the dashboard's **decision log** (that's "why we chose X", durable
rationale) — review files are the transient back-and-forth that empties out as items resolve.

---

## Multi-repo worktrees — how

Worktrees are `git worktree add` off the **real sibling repos** in `IdeaProjects/` — never copies.
The project's `worktree/` dir just holds the checked-out working trees.

Create one for a task (run from anywhere; paths shown absolute for clarity):

```bash
REPO=hera
PROJ=$PW_PROJECTS/spring-boot-3-upgrade
git -C $PW_REPOS/$REPO worktree add \
  "$PROJ/worktree/$REPO/T03-bump-parent-pom" \
  -b agent/spring-boot-3-upgrade/T03-bump-parent-pom
```

Tear it down after the task is merged/abandoned:

```bash
git -C $PW_REPOS/$REPO worktree remove \
  "$PROJ/worktree/$REPO/T03-bump-parent-pom"
```

List/prune stragglers: `git -C $PW_REPOS/$REPO worktree list` /
`... worktree prune`.

> ⚠️ **KiloCode + worktrees:** the KiloCode JetBrains plugin's auto-approve can fail inside
> worktrees because a worktree's `.git` is a *file*, not a directory, so some config loaders
> don't detect the git boundary. If auto-approve misbehaves during execution, that's the cause —
> drive the run from Claude Code, or approve manually. (See EverOS `personal` memory,
> 2026-07-27.)

---

## Roles: orchestrator vs executor

- **Orchestrator** — reads `task/PLAN.md`, owns the DAG, decides *what to spawn and when*, never
  edits repo code itself. Keeps the project `README.md` dashboard's status column current.
- **Executor** — handed one task file, owns one worktree, edits code, runs Verify, reports. Does
  **not** touch files outside its worktree or pick up work from other tasks.

Custom variants of either live in [`sub-agent/`](./sub-agent/README.md).

---

## Choosing a model / sub-agent per task

Every task records **how it should be run**, so the choice is documented and reviewable — not
buried in an agent's head:
- `Execute with:` — `<provider>:<model-or-agent>` (e.g. `claude:opus`,
  `kilo:command_code/MiniMaxAI/MiniMax-M3`, `code-implementation`). The **provider** decides which
  CLI runs it. Claude aliases (`opus`/`sonnet`/…) follow the *latest* version — **pin the full
  name** (`claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters.
- `Effort:` / `Thinking:` — optional reasoning tuning (→ claude `--effort`, kilo `--variant`/`--thinking`).
- `Why:` — one line of rationale.
- `Story points:` — manual-effort estimate (2 SP = 1 person-day).
- `Actually used:` — what the orchestrator really ran it with (if it differed).

`PLAN.md`'s task table mirrors this in **Execute with** + **SP** columns.

| Choose | Provider | For |
|--------|----------|-----|
| `opus` | claude | complex reasoning, cross-cutting / ambiguous / high-risk work |
| `sonnet` | claude | well-specified standard implementation (most tasks) |
| `haiku` | claude | trivial mechanical bulk edits |
| `command_code/deepseek/deepseek-v4-pro`, `command_code/MiniMaxAI/MiniMax-M3`, `command_code/xiaomi/mimo-v2.5-pro`, … | kilo | open-weight — routed via KiloCode's `command_code` provider (`kilo models command_code`) |
| an existing agent | (its provider) | reuse one you already have (e.g. `code-implementation`) — the executor role is **not** a bespoke agent |
| a `sub-agent/` def | (its provider) | only for a genuinely new role no existing agent covers ([`sub-agent/`](./sub-agent/README.md)) |

**Providers & cross-agent execution** — which CLI runs which model lives in the
[provider registry](./workflow/providers.md). Claude models → Claude Code, open-weight → KiloCode,
and it's a one-row-per-provider extension point. When a task's provider differs from the
orchestrator's, the orchestrator **shells out to that provider's CLI headlessly** with the task
file as the work order — so a `/pw-execute` run in Claude Code can delegate specific tasks to
KiloCode (or vice-versa), and new providers slot in without code changes.

**Requesting a specific model/agent — three ways, all honored:**
1. **Statically** — set the task's `Execute with:` field (edit it, or ask CC to set it during
   breakdown: "make T03 use opus because it's the risky migration").
2. **At execution** — tell the orchestrator: `/pw-execute myproj T03 with opus`, or "run T03 with
   the `executor-java` sub-agent". It overrides and writes what it used into `Actually used:`.
3. **Default** — if unset, the orchestrator picks per the table above and records its choice + why.

The orchestrator spawns whatever `Execute with:` names — an **existing agent** (like
`code-implementation`) or a model. There is **no bespoke executor agent**: the executor's
discipline (worktree isolation, running Verify, faithful reporting) comes from the
`project-workflow` skill + the task file, so any capable implementation agent qualifies.

## Slash commands & the generator (one source of truth)

You drive each phase with a `/pw-*` command instead of retyping prompts:

| Command | Phase |
|---------|-------|
| `/pw-new <slug>` | scaffold |
| `/pw-analyze <slug> [focus]` | analysis |
| `/pw-review <slug> [phase\|path]` | apply review comments (defaults to current phase's review) |
| `/pw-breakdown <slug>` | task breakdown |
| `/pw-execute <slug> [task-ids \| "with <model/agent>"]` | execution |
| `/pw-status <slug>` | status |
| `/pw-close <slug>` | learn + close-out |

These exist for multiple agent tools (Claude Code, kilo, …) but are **not** maintained per tool.
The single source is [`workflow/commands/*.md`](./workflow/) (provider-neutral, `{{ARGS}}`
placeholder). [`workflow/gen-commands.sh`](./workflow/gen-commands.sh) stamps them into each
provider's format and location:

```bash
$PW_HOME/workflow/gen-commands.sh
```

Claude → `~/.claude/commands/`, kilo → `~/.config/kilo/command/`. The per-provider files are
**build artifacts — never hand-edit them.** Change a prompt → edit the canonical file → re-run the
generator. Add a new agent provider → add one profile in the generator, re-run. See
[`workflow/README.md`](./workflow/README.md).

## Quick start

```bash
# 1. scaffold
$PW_HOME/scaffold.sh my-project

# 2. add context, then in Claude Code:
#    "analyze the context in projects/my-project/context and write analysis/"
# 3. review, then:
#    "break analysis into task/PLAN.md + task files"
# 4. review, then hand task/PLAN.md to the executor.
```

Invoke the `project-workflow` skill any time an agent needs these conventions restated.
