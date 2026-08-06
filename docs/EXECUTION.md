# Execution & routing

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Reference](./REFERENCE.md)

How tasks actually get run: the two roles, how a model/agent is chosen per task, cross-provider
execution, and the multi-repo worktree mechanics.

## Roles: orchestrator vs executor

- **Orchestrator** — reads `task/PLAN.md`, owns the DAG, decides *what to spawn and when*, never
  edits repo code itself. Keeps the project `README.md` dashboard's status column current.
- **Executor** — handed one task file, owns one worktree, edits code, runs Verify, reports. Does
  **not** touch files outside its worktree or pick up work from other tasks.

Both ship as **seedable agents** — `bootstrap.sh` installs `pw-orchestrator` and `pw-executor` into
each provider's agent dir, just like it installs the `/pw-*` commands (see
[`tooling/agents/`](../tooling/agents/README.md)). But execution can also **reuse an existing agent
you already have** (e.g. `code-implementation`): a task's `Execute with:` names whatever should run
it, and the discipline (worktree isolation, running Verify, faithful reporting) comes from the
`project-workflow` skill + the task file — not from a bespoke agent. `pw-executor` exists mainly for
teammates who don't already have a code agent.

## Choosing a model / sub-agent per task

Every task records **how it should be run**, so the choice is documented and reviewable — not buried
in an agent's head:
- `Execute with:` — `<provider>:<model-or-agent>` (e.g. `claude:opus`,
  `kilo:command_code/MiniMaxAI/MiniMax-M3`, `code-implementation`). The **provider** decides which
  CLI runs it. Claude aliases (`opus`/`sonnet`/…) follow the *latest* version — **pin the full
  name** (`claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters.
- `Effort:` / `Thinking:` — optional reasoning tuning (→ claude `--effort`, kilo `--variant`/`--thinking`).
- `Why:` — one line of rationale.
- `Story points:` — manual-effort estimate (2 SP = 1 person-day).
- `Actually used:` — what the orchestrator really ran it with (if it differed).

`PLAN.md`'s task table mirrors this in **Execute with** + **SP** columns. **By default a task runs
under the same provider that produced the breakdown** (`PLAN.md → Produced by`), so you're not
forced to switch agents mid-workflow — a task is routed elsewhere only with a stated `Why:`.

| Choose | Provider | For |
|--------|----------|-----|
| `opus` | claude | complex reasoning, cross-cutting / ambiguous / high-risk work |
| `sonnet` | claude | well-specified standard implementation (most tasks) |
| `haiku` | claude | trivial mechanical bulk edits |
| `command_code/MiniMaxAI/MiniMax-M3`, `openrouter/<model>`, … | kilo | open-weight — routed via any KiloCode model provider you listed in `PW_KILO_PROVIDERS` (`kilo models <provider>`) |
| an existing agent | (its provider) | reuse one you already have (e.g. `code-implementation`) |
| a `tooling/agents/` def | (its provider) | a shipped or custom role — `pw-executor`, or a new one you added |

## Agents vs sub-agents (and why the difference matters across providers)

These two words are **not** interchangeable — the distinction decides how a task can be run:

| | **Sub-agent** | **Agent** (primary / invocable) |
|---|---|---|
| What | spawned **in-process** by an orchestrator | a top-level agent invoked through a provider's **CLI** |
| How | Claude's Task tool `subagent_type`; KiloCode `mode: subagent` | `kilo run --agent <name>`, or `claude` invoked headlessly |
| Boundary | **same provider only** — a provider can spawn only its *own* sub-agents | the **only** unit that crosses a provider boundary |
| Here | `pw-executor` | `pw-orchestrator` |

**The cross-provider rule (important, and easy to get wrong):** an orchestrator on provider A that
routes a task to provider B **cannot spawn B's sub-agent** — sub-agents are same-provider-only. So a
**Claude orchestrator delegating to KiloCode does *not* name `pw-executor`** (that's a *kilo*
sub-agent it can't reach). It invokes KiloCode's CLI headlessly with the **task file + the
`project-workflow` skill as the work order**, and kilo's own default/primary agent executes it. The
executor discipline travels with the skill + task file, so no named agent is needed across the
boundary. Symmetrically, the shipped `pw-executor` is only usable **when its own provider is the
orchestrator** (Claude `pw-executor` ⇐ Claude orchestrator; kilo `pw-executor` ⇐ kilo orchestrator).

So routing a task resolves to exactly one of:
- **Same provider as the orchestrator → spawn a sub-agent in-process.** Use `pw-executor`, another
  same-provider agent named in `Execute with:` (e.g. `code-implementation`), or a plain model.
- **Different provider → shell out to that CLI headlessly**, passing the task file inline to *its*
  default/primary agent. **Do not pass `--agent <a-sub-agent>` across the boundary** — only a
  provider's own primary agents are invocable from outside, and for a single task the default agent
  + task file is enough. (If you *want* a specific primary agent on B, name a **primary** one, e.g.
  `kilo:pw-orchestrator` is primary — but a lone task normally just needs the default.)

## Providers & the registry

Which CLI runs which model lives in the [provider registry](../tooling/providers.md). Claude models
→ Claude Code; open-weight models → KiloCode, which can connect to **several model providers at
once** (list them in `PW_KILO_PROVIDERS` — e.g. `command_code`, `openrouter`, … — and reference any
as `kilo:<provider>/<model>`). It's a one-row-per-provider extension point, so new providers slot in
without code changes. When `Execute with:` names an agent, resolve its provider the same way as a
model: an explicit `<provider>:` prefix wins → else the agent def's own provider → else (a built-in
with no def) the orchestrator's own provider — then apply the same-vs-different routing above.

**Requesting a specific model/agent — three ways, all honored:**
1. **Statically** — set the task's `Execute with:` field (edit it, or ask the breakdown agent to set
   it: "make T03 use opus because it's the risky migration").
2. **At execution** — tell the orchestrator: `/pw-execute myproj T03 with opus`, or "run T03 with
   the `pw-executor` agent". It overrides and writes what it used into `Actually used:`.
3. **Default** — if unset, the orchestrator picks per the table above and records its choice + why.

## Multi-repo worktrees — how

Worktrees are `git worktree add` off the **real sibling repos** in `IdeaProjects/` — never copies.
The project's `worktree/` dir just holds the checked-out working trees, laid out per-repo/per-task
(`worktree/<repo>/<task-id>-<slug>/`) so parallel agents never collide even within one repo.

Create one for a task, **forking from the task's `Base branch:`** (`origin/<base>`) so the new
branch starts from the right place — not from whatever the repo's HEAD happens to be (paths shown
absolute for clarity):
```bash
REPO=hera; BASE=master
PROJ=$PW_PROJECTS/spring-boot-3-upgrade
git -C $PW_REPOS/$REPO fetch -q origin "$BASE"
git -C $PW_REPOS/$REPO worktree add \
  "$PROJ/worktree/$REPO/T03-bump-parent-pom" \
  -b agent/spring-boot-3-upgrade/T03-bump-parent-pom "origin/$BASE"
```

**Multiple base branches in one repo is a normal case.** Two tasks can touch the *same* repo off
*different* bases — e.g. a fix on `master` (`T03`) and its port on `spring3` (`T04`). Because each
task forks from its own `Base branch:` into its own per-task branch and worktree, they never
collide and each ships as its own MR (targeting its base). The `PLAN.md` repo manifest lists one row
per `(repo, base)` pair, so the same repo can appear more than once.

**Adopted / continuation project** (via [`/pw-adopt`](./ADOPTION.md)) — attach the **existing**
branch instead of creating one (no `-b`), one shared worktree **per adopted branch**. Tasks sharing a branch commit onto it in sequence; different adopted branches run
in parallel (each its own worktree):
```bash
git -C $PW_REPOS/$REPO worktree add \
  "$PROJ/worktree/$REPO/my-feature" my-feature       # existing in-progress branch
```
A branch can be checked out in only one worktree at a time — if it's already checked out in the main
repo, switch the main checkout to another branch first.

Tear it down after the task is merged/abandoned — at close-out prefer the safe helper, which won't
remove the worktree you're currently in (that's what once made an editor reload/close) or one with
uncommitted changes:
```bash
$PW_HOME/tooling/pw-teardown.sh $PW_PROJECTS/spring-boot-3-upgrade   # all of a project's worktrees, safely
# or one, manually:
git -C $PW_REPOS/$REPO worktree remove "$PROJ/worktree/$REPO/T03-bump-parent-pom"
```

**Run teardown from the bundle/project root, not from inside a worktree**, and close any worktree
folder still open in your editor first. List/prune stragglers:
`git -C $PW_REPOS/$REPO worktree list` / `... worktree prune`.

> ⚠️ **KiloCode + worktrees:** the KiloCode JetBrains plugin's auto-approve can fail inside
> worktrees because a worktree's `.git` is a *file*, not a directory, so some config loaders don't
> detect the git boundary. If auto-approve misbehaves during execution, that's the cause — drive the
> run from Claude Code, or approve manually. (KiloCode's CLI `kilo run --auto` is fine — this is a
> JetBrains-plugin issue, observed 2026-07-27.)
