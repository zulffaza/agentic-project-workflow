# Execution & routing

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Reference](./REFERENCE.md)

How tasks actually get run: the two roles, how a model/agent is chosen per task, cross-provider
execution, and the multi-repo worktree mechanics.

## Start with the execution scope

Use `/pw-execute <slug>` to resume the remaining plan, `--wave` to stop after the current ready group, or task IDs to select work.
Read task diffs and `## Result` after execution. By default, execution stops at local commits and verification.

| You need… | Read |
|---|---|
| Copyable execution and model commands | [Recipes](RECIPES.md#resume-or-limit-execution) |
| Full resume behavior | [Resume and waves](#full-resume-vs-one-wave-at-a-time) |
| Automatic result acceptance or chained shipping | [Clean execution](#opt-in-clean-execution-pre-reviewed-plans) |
| Routing and model selection | [Task model choices](#choosing-a-model--sub-agent-per-task) |
| A failed or stalled run | [Troubleshooting](TROUBLESHOOTING.md) |

The remaining sections explain advanced execution behavior. You can run a first project through the [walkthrough](WALKTHROUGH.md).

## Roles: orchestrator vs executor

- **Orchestrator** — reads `task/PLAN.md`, owns the DAG, decides *what to spawn and when*, never
  edits repo code itself. Keeps the project `README.md` dashboard's status column current.
- **Executor** — handed one task file, owns one worktree, edits code, runs Verify, reports. Does
  **not** touch files outside its worktree or pick up work from other tasks.

The bundle supplies six seedable roles: `pw-orchestrator`, `pw-executor`, `pw-reviewer`,
`pw-researcher`, `pw-analyst`, and `pw-writer-task`. Installation depends on the provider's agent support.
Independent verification is available through `/pw-verify`.

Tasks can use either:

- A registered agent definition, such as `pw-executor`, on the same provider.
- A `provider:model` choice, which runs a session with the task file as its work order. This is the portable form across providers.

The task file and `project-workflow` skill supply the worktree, verification, and reporting rules.
You can reuse an existing registered agent. Ad-hoc code work uses the main agent or a generic session.

## Full resume vs one wave at a time

| Execution scope | Command | Where it stops |
|---|---|---|
| Remaining plan | `/pw-execute <slug>` | Continues through ready tasks and newly unblocked dependencies |
| Current ready group | `/pw-execute <slug> --wave` | Runs tasks whose dependencies are already `done`/`accepted`, then reports a checkpoint |
| Selected tasks | `/pw-execute <slug> T03` | Runs the named scope and stops |

Use full resume after an interrupted run. Use a wave when you want to inspect progress before the next group.
Full operator semantics: `/pw-help command pw-execute`.

<a id="choosing-a-model--sub-agent-per-task--two-axes-not-one"></a>
## Task executors and project roles
### Task executors

Each task's `Execute with:` field selects its executor. The PLAN task table mirrors that choice.
The dashboard's role settings never override this task contract.

### Project roles

The dashboard's `AI Models` row selects models for these project roles:
`researcher`, `analyst`, `writer-task`, `reviewer`, and `verifier`.
There is no executor row; executors use their task settings.
Inspect or change role choices through `/pw-config <slug>`.

### Model precedence for project roles

The first available setting wins:

1. **Run-time override:** a model explicitly requested for this invocation.

2. **Project role setting:** the corresponding role on the dashboard's `AI Models` row.

3. **Registered agent definition:** the model in that agent's definition. Claude uses per-agent definitions; Kilo and Cursor use their registered model fields. This rung is absent for Codex, which has no seeded definitions.

4. **Provider or session default:** the model selected by the provider when the earlier settings do not apply.

| Provider | Default model source |
|---|---|
| Kilo | `small_model` / `subagent_model` settings |
| Claude | Session `/model` selection |
| Cursor | `auto` routing or `selectedModel` in its CLI configuration |
| Codex | Its configured default |

### When the role needs a headless session

A headless session runs the work order through the provider's CLI rather than an in-process agent.

- Kilo and Cursor named spawns cannot carry a per-run model parameter. A project role pin uses a headless session to bind that model.
- Codex workflow roles use headless `codex exec` sessions because this bundle has no in-process spawn surface there.
- The run ledger records what actually ran. If a requested model cannot bind, the ledger reports that limitation.

See [provider settings](REFERENCE.md#inspect-configure-and-recover) or run `/pw-config global show`.

<a id="choosing-a-model--sub-agent-per-task"></a>
## Task model fields and available choices

Each task records its execution choices before it runs:

| Field | What it tells you |
|---|---|
| `Execute with:` | Provider and model or registered agent, such as `claude:opus` or `pw-executor` |
| `Effort:` / `Thinking:` | Optional reasoning settings supported by that provider |
| `Why:` | Rationale for the execution choice |
| `Story points:` | Estimated manual effort; the bundle uses 2 SP for one person-day |
| `Actually used:` | The choice used during execution, including any difference from the request |

Ask the agent to validate reasoning settings against the enabled provider before changing them.

`PLAN.md`'s task table mirrors this in **Execute with** + **SP** columns. **By default a task runs
under the same provider that produced the breakdown** (`PLAN.md → Produced by`), so you're not
forced to switch agents mid-workflow — a task is routed elsewhere only with a stated `Why:`.

| Task choice | Example syntax | Where the model comes from |
|---|---|---|
| Claude model | `claude:opus` or `claude:sonnet` | Configured Claude aliases or a full model ID |
| Kilo model | `kilo:<catalog-id>` | Kilo's configured gateways/backends |
| OpenCode model | `opencode:<catalog-id>` | OpenCode's configured backends |
| Cursor model | `cursor:<catalog-id>` | Cursor's gateway catalog |
| Codex model | `codex:<slug>` | Codex's gateway through your ChatGPT login |
| Registered agent | `pw-executor` | A definition available on the same provider |

Use the exact model ID from your enabled provider. Aliases can follow newer versions; use a full ID when reproducibility matters.
Cursor effort/thinking variants can be catalog IDs or bracket parameters. Codex uses bare model slugs; effort and Fast are per-run settings.

Agent definitions are provider-specific. For cross-provider work, use an explicit model and the task file as the work order.
A custom definition is useful for a recurring role with distinct instructions. See [agents and sub-agents](#agents-vs-sub-agents-and-why-the-difference-matters-across-providers).

### Check the model catalog before pinning

During breakdown, the agent queries the live catalog for Kilo, OpenCode, Cursor, and Codex.
Claude uses the configured alias set described above.

| Provider | Catalog command |
|---|---|
| Kilo | `kilo models` |
| OpenCode | `opencode models` |
| Cursor | `agent models` |
| Codex | `codex debug models` |

Use the exact catalog ID when setting a pin. Display names can differ from usable IDs:
for example, Kilo's credential label “Kilo Gateway” uses the ID `kilo`, not `kilo_gateway`.

### Kilo connections with similar names

A direct BYOK connection and one registered under the gateway can have different catalog paths:

- `kilo:alibaba-token-plan/<model>` first matches the direct `alibaba-token-plan/<model>` catalog entry.
- If that direct entry is absent, resolution can fall back to `kilo/alibaba-token-plan/<model>`, with a notice on stderr.
- `kilo:kilo/alibaba-token-plan/<model>` explicitly pins the gateway connection.

The resolved canonical ID is passed to the headless session's model argument.
Catalog discovery checks availability. The allowlist separately checks which models you permit.

## Opt-in clean execution (pre-reviewed plans)

Baseline doctrine stands: execution stops at committed + verified, `accepted` is a human call, and
nothing pushes without `/pw-ship`. Teams that *pre-review* the PLAN + task files can optionally
tighten that in `PLAN.md → ## Execution strategy`:

- **Executor self-repair (in-run)** — a `## Verify` failure that is a regression from the task's own
  change re-enters the executors's worktree: diagnose → fix → re-verify → new commit, capped
  (`- AI execution limit:`, floor `PW_MAX_SELF_REPAIR`=3 — same constant as the ship loop's
  ≤3 rounds) before it reports `verify-failed`. Pre-existing/environmental failures keep today's
  `done`-with-caveat rule and never loop. Removes the manual `/pw-execute <slug> T0n` re-trigger for
  fixable cases.
- **`- Results acceptance: <manual|auto>`** (default `manual`) — in `auto`, at the end of a run the
  **driver** flips clean tasks (`done`, required kinds green, zero open review/dep-impact items) to
  `accepted` — the automated analog of Step-8, reversible by the human; everything not cleanly
  closed stays visible as an explicit leftover list. The PLAN gate is still re-checked on every
  invocation.
- **`--then-ship`** (on `/pw-execute`) — the same invocation continues outward into Ship after the
  run (your push confirmation still gates the actual push). Ship stays a deliberate flag — it's the
  only outward step. When a run is clean end-to-end it ends `execute → verified → accepted → shipped`
  with one human review checkpoint, not three.
- **`--acceptance <manual|auto>`** overrides the PLAN bullet for one invocation (per-run choice → a
  named value, per the bundle's knob rule; it does not rewrite the bullet).

All three default OFF so any existing project behaves exactly as before.

## A dependency that lands a late fix re-checks what already ran

The DAG protects **not-yet-started** dependents (they fork the fixed branch). A **post-first-pass
fix** (row-8 rejection, a repair round, a post-ship MR fix) on task T0n leaves already-run
dependents branched from stale state. The driver fans **one capped pass** per cascade:
1. **Mechanical** — merge T0n's branch into each already-run dependent's worktree, re-run **that
   dependent's** `## Verify`, push. Clean → stays `done`; conflict/regression → the dependent's own
   `verify-failed` (driver flips statuses, always). In clean-auto mode an accepted dependent drops
   back to review-visible instead of silently staying accepted.
2. **Judgement** — where their `## Files`/landing units actually overlap, one cheap
   `pw-reviewer`-style **dep-impact pass** per dependent ("is T0m still coherent given T0n's
   delta?"), filed as `dep-impact:T0n` items in T0m's review queue — never a direct edit into
   another task's file. Surviving items become normal capped fix rounds like any other; nothing
   loops, nothing edits the dependency backward (that's a new DAG task/PLAN change).

## Advanced routing and provider behavior

The sections below explain how the workflow runs agents, binds model choices, and records sessions.
For everyday execution, the scopes and model settings above are enough to start.

## Running the pipeline on a provider without a main-agent slot (Claude Code class)

`pw-orchestrator` renders `mode: primary` where the provider has a selectable primary agent — Kilo
does; **Claude Code does not** (its main is always the built-in default; custom defs are
*sub-agents* under `~/.claude/agents/`). "Primary" is therefore provider-bound, never a universal
capability. How a Claude-only session still runs the phases:

- **Flow B (default):** the main session *is* the orchestrator per the `project-workflow` skill +
  `/pw-*` commands — it spawns `claude:pw-executor` sub-agents in-process and **must not edit repo
  code itself**. The long-lived-driver benefit is replaced by disk state + bounded units: one
  `--wave` per invocation, human gate between waves, `/compact` between waves; resumed work is a
  plain `/pw-execute <slug>` walking the PLAN (the on-disk PLAN/dashboard/worktree commits are the
  resumable state; session ids are machine-local only).
- **Flow C (bulk wave):** spawn `pw-orchestrator` as a *sub-agent* for **one bounded wave** — it
  fans out to its own `pw-executor` sub-agents and reports; it works today because the canonical def
  carries `claude_tools: … Task` (keep it there). Nested sub-agents can't surface approvals usefully
  → run with `--permission-mode auto` (or `acceptEdits`). A sub-agent runs to completion in one
  turn → waves must be atomic; seeds stay tight (§Seeds, cost §) since nested spawns don't share the
  parent's context.
- **Spawn-less fallbacks everywhere:** if even a spawn is unavailable/denied, the `pw-*` role defs
  are readable prompt bodies (installed as each provider's agent files) — play the role yourself, or
  hand a session the task file as its work order (exactly what `/pw-execute <slug> <T0n>`'s
  `provider:model` default already is). The commands' `agent:` frontmatter that starts a *Kilo* session with a
  primary role is **Kilo-only sugar** — on Claude-like providers it does nothing.
- **Codex twist (Flow B only):** codex has **no sub-agent surface at all** — no defs are seeded and
  no in-process spawn exists. A codex driver session plays the orchestrator inline (the `/pw-*`
  command bodies are self-contained lane personas), and every delegated or bulk run is a
  **supervised headless `codex exec` session over the work order** — the same machinery as a
  cross-provider handoff, aimed at itself — ledger-recorded like any headless spawn (prompt via
  stdin; the `thread_id` is the resume handle). There is no Flow C on codex; role defs it can't
  spawn stay readable-as-file prompt bodies (the spawn-less fallback, as its normal mode).

Same rule as model lanes (above): document per-provider capability where it bites, not in prose
that implies symmetry.

## Model allowlist (optional — a cost guard, not a routing mechanism)

There's no fixed, pre-approved model list in this bundle — an agent (during `/pw-breakdown`) or
you can pick any model any configured API Provider serves, for claude, kilo, opencode, cursor, or
codex alike.

**If you want to rule some OUT** — typically to stop an agent reaching for an unexpectedly
expensive model — set an allowlist per Agent Provider in `pw.config.sh`
(`PW_MODEL_ALLOWLIST_CLAUDE` / `_KILO` / `_OPENCODE` / `_CURSOR` / `_CODEX`), a comma-separated list of glob
patterns
matched against the model id (everything after the `<provider>:` prefix, e.g. `sonnet` or
`command_code/deepseek/*`).

**The rule, stated plainly: empty or unset = ALL models allowed.** That's the default for every
provider — nothing is restricted until you explicitly set a pattern. This is deliberately
opt-in, matching how every other optional knob in `pw.config.sh` works (unrestricted until set,
e.g. the `PW_MODEL_ALLOWLIST_*` patterns).

**Where it's enforced:** `/pw-breakdown` checks a task's chosen model against the allowlist while
filling `Execute with:`; `/pw-execute` checks again right before invoking it (catches a
hand-edited task file too). Both refuse rather than silently substituting a different model.

**Checking your allowlist is actually valid — run `/pw-doctor`, not a CLI command by hand.** Its
"model allowlist" line reports, per configured pattern, how many real models in the provider's
live catalog it matches — a pattern with zero matches usually means a typo, a deprecated id, or a
model your authenticated API Providers don't cover. This is purely informational: a ⚠ never
blocks `/pw-doctor` or fails its exit code, since availability can legitimately change over time.
One exception — **Claude Code has a fixed alias set (`opus`/`sonnet`/`haiku`/`fable` + pinned full
names), not a queryable catalog**, so `/pw-doctor` can't verify a claude allowlist pattern
live; cross-check it against the table above yourself.

## Agents vs sub-agents (and why the difference matters across providers)

These two words are **not** interchangeable — the distinction decides how a task can be run:

| | **Sub-agent** | **Agent** (primary / invocable) |
|---|---|---|
| What | spawned **in-process** by an orchestrator | a top-level agent invoked through a provider's **CLI** |
| How | Claude's Task tool `subagent_type`; KiloCode `mode: subagent`; Cursor auto-delegation on def `description` (or explicit `/pw-<agent>` — and a **direct** cursor sub-agent can itself fan out one more level, verified 2026-09-09); **codex: this bundle uses inline lanes or headless sessions** (inline lane personas, or a headless `codex exec` session as the spawn) | that provider's CLI: `kilo run --agent <primary-agent>` / `claude -p` / cursor `agent -p --force --model <id>`+task file / codex `codex exec -m <slug>`+task file via stdin (a sub-agent def is NOT nameable from across the boundary; cursor has no CLI primary-agent slot at all; codex has no agent defs at all) |
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
  same-provider def named in `Execute with:` (`pw-executor`, a custom role def), or a plain
  `provider:model` (the default — a session on the task file).
- **Different provider → shell out to that CLI headlessly**, passing the task file inline to *its*
  default/primary agent. **Do not pass `--agent <a-sub-agent>` across the boundary** — only a
  provider's own primary agents are invocable from outside, and for a single task the default agent
  + task file is enough. (If you *want* a specific primary agent on B, name a **primary** one, e.g.
  `kilo:pw-orchestrator` is primary — but a lone task normally just needs the default.)

## Spawning phase work (the `pw-*` lanes)
Not every phase step needs the orchestrator slot: analysis grounding, analysis drafting, and task
authoring are lane spawns from whichever driver is running the phase (rows 2/4 of the workflow table):

- **`pw-researcher`** answers a scoped question with `file:line` evidence (Mode A) or grounds a
  scope of human-dropped inputs — a `context/` pack, fetched links, repo state on their base
  branches — into a **ground-truth pack + seed** (Mode B, the analysis pre-step). It gathers
  evidence; it never decides.
- **`pw-analyst`** drafts an analysis doc from that seed + a brief (its caller owns the doc — the
  options are its decisions on review). Read-only except its draft file.
- **`pw-writer-task`** turns the *caller's* boundary decisions into task docs — detailed `## Steps`
  + a runnable `## Verify`. Decisions stay with the caller; batching is per task (parallelizable —
  the writer doesn't edit shared state).

Seeds are a contract, not a vibe (lane defs + the `project-workflow` skill's
execution-and-routing reference, §Seed contracts): a dense executive summary + pointer list, **pre-flight before spawn** (a seed gap
is fixed at the producer — a cheap researcher pass — never by spawning a floundering analyst),
pointers-as-menu, never raw dumps/credentials. After a draft, an **exit check**: diff result vs the
brief's scope list; a gap means a **resume with a seed patch** (`kilo run -s <id>` / claude
`--resume <id>` / cursor `agent -p --force --resume <session_id>` / codex `codex exec resume
<thread_id>` — cd to the worktree first, resume has no directory flag) — iff the liveness check reports
that id resumable — not a cold re-spawn. N review items on ONE artifact (human / `pw-reviewer` /
verifier / `dep-impact` items share that queue) get ONE batched fix pass, per-item replies intact
— never one spawn per comment; who runs the pass (in-process fixer / supervised headless / the
driver inline) is the routing ladder's call — §The per-spawn ledger below.

**Model lanes vs executor pins are different axes.** A task's `Execute with:` binds the EXECUTOR
per unit (above). A *lane* spawns on the provider default unless the project's
`- **AI Models:** researcher=… analyst=… writer-task=… verifier=… reviewer=…` row binds it
(`/pw-config <slug> set ai-model <lane>=<provider:model|—>`; unset = provider/session default;
the `AI Models:` dashboard line — same anchored-line config idiom as `AI Review`). Per-provider honesty: **claude**
can start a session per model and per-spawn override is real; **kilo**'s Task-tool has no model arg
— its levers are a map-block pin (user's own config) or running the lane **headless**:
`kilo run --auto -m <provider/model> [--dir <repo/path>]` with the task file/work order + skill
inline (`--dir` carries the cwd — no local path needed if the driver runs elsewhere). A spawn records
`Model used:` (row vs floor vs actual) so a row that couldn't fire is visible, not folklore. A
provider without a main-agent slot carries the *orchestrator* the same way the lanes are carried
elsewhere: run the row/role as a headless session — Flow B/C above
(Claude Code has no custom
**primary** agent: only sub-agents + the built-in main), or drive from Kilo with `pw-orchestrator`.

## The per-spawn ledger (why it exists: resume > re-derive) and the routing ladder

Every delegated spawn writes one line where the pipeline already logs, so later fixes can reuse the
**warm** session instead of re-deriving from a cold start (`LOG.md` line, via the flow's log step,
carries `· via=subagent|headless · session=<id> · seed=<ref> · out=<artifact> · state=…`; the task's
`## Result → Session:` records its run's id, and the executor writes `session <id>` as the first line
of `worktree/<T0n>.log` when the provider exposes one — `-` if not). A Row-8 rejection, an MR-comment
batch, or a late-fix dependent recheck (above) **resumes that id** (`kilo run -s <id>` / cursor
`agent -p --force --resume <id>` / codex `codex exec resume <id>`; ids are `ses_…` on kilo, plain
UUIDs on cursor and codex — codex's is the `thread_id` from its JSONL event stream) *only when a
deterministic liveness check says it is still resumable* — the pipeline never blind-resumes an id
and reads the error to find out it was dead; when the check says dead/unverifiable, it takes the
ladder's cold path instead (spawn with the task file / recorded seed), because session stores are
machine-local (never cross-machine) and a dead id must not strand the work. Session ids are
**machine-local pointers** — they stay in the workspace; nothing goes into MR text. State that
*must* survive machines stays on disk (PLAN / dashboard / worktree commits).

**One ladder for execute and repair (post-execution).** The same routing rule governs a task's first
spawn and every later fix, so a repair is as monitorable as an execution:

- **Same provider as the orchestrator → an in-process sub-agent** (natively monitorable). Where the
  CLI can't bind the row's model in-session (kilo's spawn has no model arg), the parent model runs
  and the ledger records `model-degraded <row>→<used>` — unless the row opts into strict binding.
- **Different provider → a supervised headless session** of that CLI, **resuming the live id first**
  when the liveness check reports one.
- **Per-task `Route:` field** (default `auto`) overrides the branch: `subagent` forces in-process
  (errors on a cross-provider row); `headless` forces exact-model binding (and still resumes a live
  session first when the row is unchanged). Precedence: task `Route:` → PLAN `- Routing:` →
  `PW_ROUTE_DEFAULT` → `auto`. It's plain text, editable between spawns — so a provider that dies
  mid-project (subs ended, auth failed) is survivable by editing the row or the config, not by
  re-planning.
- **Availability gate, on every path including resume:** before any spawn the row's model is
  resolved against the provider's *live* catalog and the configured API-Provider scope; a row that
  pins a model/provider no longer available is a hard stop naming the re-pin candidates — never a
  detached run that fails mid-flight.
- **Headless runs are supervised to a terminal state** (`success`/`failed`/`stalled`) with the log +
  stall/timeout budgets enforced; a stalled child is killed and the task flips `verify-failed` with
  a `headless-stall` note (the next pass is a seed-patched re-spawn, not a resume of the killed id),
  and a run never ends while a headless child is still live.
- **Repair fan-out:** ≥2 tasks with open items get one fixer **per task, in parallel** (independent
  worktrees); a single same-provider task may be fixed **inline by the driver** (bounded to the
  batch's items, run its `## Verify`, commit, reply per item) — the maximally visible, zero-spawn
  form; `headless` on a single task tries resume and falls back to inline rather than cold-detach.
  Batch discipline is unchanged: one pass per artifact, never one per item.
- **Pre-execution doc fixes** (analysis / PLAN / task docs) are driver-inline — the review file is
  the seed; no spawn, no resume. The ladder's spawn machinery is for post-execution task fixes only.

## Providers & the registry

Use `/pw-config global show` to inspect enabled providers and model restrictions.
Claude models → Claude Code; open-weight models → KiloCode, which can connect to **several API
Providers at once** (list them in `PW_KILO_API_PROVIDERS` — e.g. `command_code`, `openrouter`, …
— and reference any as `kilo:<provider>/<model>`). A BYOK you register *under* the gateway is
addressed by its catalog path — row `kilo:kilo/alibaba-token-plan/<model>`, bind id
`kilo/alibaba-token-plan/<model>` (the same BYOK wired up *directly* is its own line
`alibaba-token-plan/<model>` — a different connection; row matching is exact-first) — so an
array entry may itself
contain a slash; entries are **model-id prefix filters** over the live catalog, not catalog-query
arguments (querying the catalog *by* a sub-provider path errors — the CLI lists it only under the
top-level provider). It's a one-row-per-Agent-Provider extension
point, so new providers slot in without code changes.

When `Execute with:` names an agent, resolve its provider the same way as a model: an explicit
`<provider>:` prefix wins → else the agent def's own provider → else (a built-in with no def) the
orchestrator's own provider — then apply the same-vs-different routing above.

**Requesting a specific model/agent — three ways, all honored:**
1. **Statically** — set the task's `Execute with:` field. Preferred: `/pw-config <slug> set pin
   T03=claude:opus` (batches: several `T0n=<provider:model>` pairs in one call, `—` clears;
   validated at write time and written to BOTH holders — the task file and the PLAN cell — so
   they can't drift). Asking the breakdown agent also works ("make T03 use opus because it's the
   risky migration"); a raw hand-edit must keep the task file and its PLAN cell in sync yourself.
2. **At execution** — tell the orchestrator: `/pw-execute myproj T03 with opus`, or "run T03 with
   the `pw-executor` agent". It overrides and writes what it used into `Actually used:`.
3. **Default** — if unset, the orchestrator picks per the table above and records its choice + why.

## Multi-repo worktrees — how

Worktrees are `git worktree add` off the **real sibling repos** in `$PW_REPOS/` — never copies.
The project's `worktree/` dir just holds the checked-out working trees, laid out per-repo/per-task
(`worktree/<repo>/<task-id>-<slug>/`) so parallel agents never collide even within one repo.

The execution command creates fresh task worktrees from the declared base branch.
For a stacked task, it starts from the parent's verified commit instead.
For adopted work, it attaches the existing branch and serializes tasks that share that branch.
Different adopted branches can run independently.

Use `/pw-execute <slug>` to create or resume the required worktrees.
Use `/pw-status <slug>` to inspect task state and `/pw-doctor --project <slug>` for consistency problems.
If Git reports that a branch is already checked out, follow [worktree troubleshooting](TROUBLESHOOTING.md).

One repository can have tasks against different base branches. PLAN records each `(repo, base)` pair.
Each task keeps its own branch and worktree so those changes remain separate.

Run `/pw-close <slug>` after accepting results to clean eligible worktrees.
Run it from the bundle or project root, and close worktree folders in your editor first.
Dirty worktrees and the worktree you occupy remain protected and appear as leftovers.

> ⚠️ **KiloCode + worktrees:** the KiloCode JetBrains plugin's auto-approve can fail inside
> worktrees because a worktree's `.git` is a *file*, not a directory, so some config loaders don't
> detect the git boundary. If auto-approve misbehaves during execution, that's the cause — drive the
> run from Claude Code, or approve manually. (KiloCode's CLI `kilo run --auto` is fine — this is a
> JetBrains-plugin issue, observed 2026-07-27.)
