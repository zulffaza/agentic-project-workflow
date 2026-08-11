# Orchestration plan: <project-slug>

- **Status:** draft | approved-for-execution
- **Based on analysis:** <link to analysis/*.md that is approved>
- **Produced by:** <provider the breakdown ran under, e.g. `kilo` / `claude`> — [🤖 agent records]
  the default `Execute with:` provider for every task below (minimises agent-switching; see routing).
- **Date:** <YYYY-MM-DD HH:MM>

> This is the entry point for the executor agent. Read this whole file before spawning anything.
> Legend: 🤖 = AI-produced/maintained · 🧑 = you fill · 🤖🧑 = both.

## Repo manifest  [🤖 agent]
Every **(repo, base branch)** this project touches. Worktrees fork off these (real dirs in
`{{PW_REPOS}}/`). **A repo may appear on more than one row** if different tasks target different base
branches — that's a normal case (e.g. a fix on `master` *and* its port on `spring3` in the same
repo). Each `(repo, base)` pair is an independent branch + MR; tasks under the same pair can run in
parallel (separate per-task branches), tasks under different pairs are independent too.

| Repo | Base branch | Tasks touching it |
|------|-------------|-------------------|
| hera | master | T01, T03 |
| hera | spring3 | T04 |
| valas-service | main | T02 |

## Global rules (apply to EVERY task)
- **Branch:** `agent/<project-slug>/<task-id>-<slug>`
- **Worktree:** `worktree/<repo>/<task-id>-<slug>/` created via `git worktree add` (never copy a repo).
- **Commits:** Conventional Commits, scoped to the task's worktree only.
- **Isolation:** an executor edits ONLY its own worktree. No cross-task edits.
- **Verify before done:** run the task's `## Verify` block; paste real output; only then report done.
- **On failure/ambiguity:** stop and report — do not improvise beyond the task's scope.
- **Reporting:** faithful — failing/ skipped steps are stated, not hidden.
- <any project-specific global rule, e.g. "bump versions via the parent BOM only">

## Breakdown rules / execution routing (project-specific)  [🤖🧑 both — you seed, agent records]
Custom rules that shaped this breakdown, and per-task routing overrides. Seed these from
`context/` or state them when you ask for the breakdown ("route the risky migration to opus",
"do the mechanical bumps in KiloCode, not Claude Code"). The orchestrator honors what's here.
- **Default provider:** the provider named in **Produced by** above — tasks execute on the same
  agent that did the breakdown unless a routing override below says otherwise. This keeps you from
  switching agents mid-workflow.
- **Default agent/model:** <e.g. `<produced-by>:sonnet` unless a task says otherwise>
- **Routing overrides:** <e.g. "T05 → KiloCode (bulk mechanical); T03 → opus (ambiguous)">
- **Sizing / splitting rules used:** <e.g. "one repo per task; split anything touching two repos">
- <other custom rule that affected how tasks were cut>

## Dependency DAG
Tasks with no unmet `depends_on` may run in parallel. Spawn a task only once its deps are done.

```
G1 (parallel):  T01   T02
                 └──────┐
G2:                     T03   (depends_on: T01, T02)
G3:                     T04   (depends_on: T03)
```

## Task table
**Filled by:** [🤖 agent] at breakdown; `Status`/`Time`/`Result` [🤖 agent] during execution,
except `Status: accepted`/`verify-failed` which are [🧑 you]. IDs link to the task file. `SP` =
story points (manual-effort estimate, set at breakdown). `Time` = actual wall-clock the executor
took; `Result` = commit short-sha / MR ref / `zero-change`.

| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |
|----|-------|------|-----------|-------|--------------|----|--------|------|--------|
| [T01](./T01.md) | … | hera | — | G1 | sonnet | 2 | todo | — | — |
| [T02](./T02.md) | … | valas-service | — | G1 | kilo:command_code/MiniMaxAI/MiniMax-M3 | 1 | todo | — | — |
| [T03](./T03.md) | … | hera | T01, T02 | G2 | opus | 3 | todo | — | — |
| [T04](./T04.md) | … | hera | T03 | G3 | code-implementation | 2 | todo | — | — |

_Status values: todo → in-progress → verify-failed / done → accepted._
_Time/Result: leave `—` until executed. Token/cost are NOT captured here — a running agent can't
measure them reliably; pull them from session telemetry afterward if you need them._

## Manual-execution estimate (if a person did this by hand)
**Filled by:** [🤖 agent] at breakdown. Story-point rule: **2 SP = 1 person-day**.
- **Total story points:** <sum of SP column> SP
- **Sequential effort:** <total SP ÷ 2> person-days (one person, one task at a time).
- **Critical-path calendar time:** <sum SP along the longest dependency chain ÷ 2> days — the DAG
  lets independent groups run in parallel, so calendar time ≤ sequential effort.
- _This estimates **manual** human effort/timeline for planning & comparison. Agent execution is
  typically much faster and parallel — the actual agent `Time` per task is recorded above._

## Model & sub-agent selection
Each task declares `Execute with:` (a **model or agent**, `<provider>:<model>` form) plus a `Why:`.
The **provider** decides which CLI runs it — see the
[provider registry]({{PW_HOME}}/tooling/docs/providers.md) (models are tied to a provider there, and
cross-provider tasks are shelled out to that provider's CLI). Rules of thumb:

| Choose | Provider | For |
|--------|----------|-----|
| `opus` | claude | complex reasoning, cross-cutting / ambiguous / high-risk changes |
| `sonnet` | claude | well-specified standard implementation (most tasks) |
| `haiku` | claude | trivial, mechanical bulk edits (renames, config bumps) |
| `kilo/<model>` | kilo | KiloCode's own built-in gateway — the **default** API Provider, no separate credential |
| `command_code/deepseek/deepseek-v4-pro`, `command_code/MiniMaxAI/MiniMax-M3`, `command_code/xiaomi/mimo-v2.5-pro`, … | kilo | open-weight/third-party models (cost/availability); needs its own credential — routed via an *additional* KiloCode API Provider — `kilo models command_code` for the full list |
| an existing agent | (its provider) | reuse one you already have (e.g. `code-implementation`) |
| `pw-executor` or a `tooling/agents/` def | (its provider) | the shipped executor, or a custom role no existing agent covers |

Headless invocation and the **effort/variant/thinking** flag mapping are documented in
`{{PW_HOME}}/tooling/docs/providers.md`; onboarding a new Agent Provider for cross-provider
execution means defining `<name>_headless()` in `pw.config.sh` (a maintainer action), never
editing that file. Claude aliases (`opus`/`sonnet`/…) track the *latest* version — **pin the full name**
(`claude-opus-4-8` vs `claude-opus-5`) on risky tasks; set each task's `Effort:` per its complexity. The orchestrator does **not**
use a bespoke executor agent; it spawns (or shells out to) whatever `Execute with:` names, and the
discipline comes from the skill + the task file. Override per task at execution time ("run T03
with opus" / "with kilo:command_code/MiniMaxAI/MiniMax-M3"); the orchestrator records it in `Actually used:`.

## Execution strategy
- Max parallelism: <n> concurrent executors.
- **Same-provider tasks run as native sub-agents** (in-process, natively monitorable); a
  different-provider task is shelled out to that CLI headlessly. Either way the executor **tees its
  output to `worktree/<T0n>.log`** so you can `tail -f` any run in a window of your choosing.
- **How work exits:** `/pw-execute` stops at *committed + verified*. Pushing branches and opening
  MRs is a separate, explicit step — **`/pw-ship <slug> [task-ids]`** — so nothing goes outward
  until you ask. Zero-change tasks never get a branch/MR.
- **Gate:** only the **PLAN** sign-off (`task/review/PLAN.review.md → approved ✅`) is required to
  execute. Per-task review is **optional** — add a `task/review/T0n.review.md` only when you want to
  send a task back.
- Rollback plan if a group fails: <…>
