# Orchestration plan: <project-slug>

- **Status:** draft | approved-for-execution
- **Based on analysis:** <link to analysis/*.md that is approved>
- **Produced by:** <provider the breakdown ran under, e.g. `kilo` / `claude` / `cursor`> — [🤖 agent records]
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
- **Comments are for the global team:** code comments (and commit-message detail) exist only to help
  a future maintainer or an external reviewer who has no access to this project's internal docs —
  never cite internal pipeline IDs (`Rn`/`Qn`/`Pn`, review anchors, task-file headings) in committed
  code, commit messages, or MR-visible text.
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

## Landing units (must-land-together sets)  [🤖 agent — only when present]
Tasks whose MRs must merge **as a set** (one logical change that repos force across several
worktrees — not independently shippable pieces) share a `Landing unit:` name. The default is that
**every MR is independently shippable** — a landing unit is the exception, only when a change can't
be one task/MR. Name the set here so ship marks each MR description and reviewers review it as one
unit:
- `cdc-sync → T02 (api change), T03 (consumer wiring)`: must land together — cross-repo; each MR
  description names the unit + sibling MRs.
- <none — every MR stands alone>   ← keep it this way wherever the repos allow one task per change

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
| [T04](./T04.md) | … | hera | T03 | G3 | kilo:command_code/<model> | 2 | todo | — | — |

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
| `command_code/<model>` | kilo | open-weight/third-party models — needs its own credential; `kilo models command_code` for the full list |
| `cursor-grok-4.5-high` / `…-low-fast`, `claude-opus-5-thinking-xhigh` | cursor | Cursor's own single gateway — effort/thinking are catalog-id variants (or `[context=1m,effort=…]` bracket params); `agent models` for the list |
| a registered agent / a model | (its provider) | same-provider reuse only — e.g. `pw-executor`; a cross-provider task always routes as `provider:model` (a *sub-agent* name is unreachable from the other CLI's headless path; `--agent` accepts **primary** defs only, verified 2026-09-04) |
| `pw-executor` / a `tooling/agents/` def | (its provider) | the shipped executor, or a custom role no existing agent covers |

- **Pin risky tasks:** claude aliases (`opus`/`sonnet`/…) track the *latest* version — use the full  name (`claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters. Cursor ids from
  `agent models` are already exact — pin the full variant (`cursor:claude-opus-5-thinking-high`);
  `cursor:auto` routes by Cursor's own router — avoid it for risky tasks.
- **Phase lanes are separate pins:** the dashboard's `- **AI Models:**` line binds the *lane* agents
  the phases spawn (researcher/analyst/writer-task/reviewer/verifier), never this task table. The
  row is what the executor-side `Actually used:`/`Session:` ledger compares against — an unset row
  means provider default, not "anything goes".
- **No bespoke executor agent** — the orchestrator spawns/shells out to whatever `Execute with:`
  names; the discipline comes from the skill + task file, not a special agent.
- **Override at run time:** "run T03 with opus" — the orchestrator records what it actually used in
  `Actually used:`.
- Headless invocation + the `Effort`/`Thinking` flag mapping: `{{PW_HOME}}/tooling/docs/providers.md`
  (onboarding a new Agent Provider is a `pw.config.sh` edit, never that file).

## Execution strategy
- Max parallelism: <n> concurrent executors.
- **Results acceptance:** <manual — the human flips `accepted` at review (default, matches
  `/pw-review`'s gate discipline) | auto — at the end of a clean run the driver flips every task
  that is `done`, green on `## Verify`, and with zero open review items via `pw-lib.sh task-accept`;
  anything else stays visible for the human. `--acceptance` overrides per invocation — but the
  PLAN line is what the next reader assumes (a hidden run flag is how a project drifts).
- **AI execution limit:** <n> (default 3 — `PW_MAX_SELF_REPAIR`) self-repair rounds an executor may
  take on its own verify failure before declaring `verify-failed`; environmental pre-existing
  failures never loop (they follow today's `done`-with-caveat rule).
- **Same-provider tasks run as native sub-agents** (in-process, natively monitorable); a
  different-provider task is shelled out to that CLI headlessly. Either way the executor **tees its
  output to `worktree/<T0n>.log`** so you can `tail -f` any run in a window of your choosing.
- **How work exits:** `/pw-execute` stops at *committed + verified*. Pushing branches and opening
  MRs is a separate, explicit step — **`/pw-ship <slug> [task-ids]`** — so nothing goes outward
  until you ask. Zero-change tasks never get a branch/MR.
- **Gate:** only the **PLAN** sign-off (`task/review/PLAN.review.md → approved`) is required to
  execute. Per-task review is **optional** — add a `task/review/T0n.review.md` only when you want to
  send a task back.
- **Ledger:** every spawn logs one `LOG.md` line (`spawned <lane/T0n> (<provider>:<model>) ·
  session=<id> · seed=<ref> · out=<artifact> · <outcome>`) and a task's `## Result → Session:`
  records its own run — fixes/repairs **resume those ids** (§Spawn ledger; docs/EXECUTION.md).
- **A fix that lands after dependents ran** triggers the one capped §3.6 cascade: each already-run
  dependent re-merges + re-runs *its own* `## Verify`; only file-overlap dependents also get ≤1
  `dep-impact` reviewer pass filed into their queues (statuses are the driver's flips; no edits
  backward into the dependency).
- Rollback plan if a group fails: <…>
