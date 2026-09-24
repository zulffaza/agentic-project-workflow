# Execution & routing

← [back to README](../README.md) · related: [Workflow](./WORKFLOW.md) · [Reference](./REFERENCE.md)

How tasks actually get run: the two roles, how a model/agent is chosen per task, cross-provider
execution, and the multi-repo worktree mechanics.

## Roles: orchestrator vs executor

- **Orchestrator** — reads `task/PLAN.md`, owns the DAG, decides *what to spawn and when*, never
  edits repo code itself. Keeps the project `README.md` dashboard's status column current.
- **Executor** — handed one task file, owns one worktree, edits code, runs Verify, reports. Does
  **not** touch files outside its worktree or pick up work from other tasks.

Six roles ship as **seedable agents** — `bootstrap.sh` installs `pw-orchestrator`, `pw-executor`,
`pw-reviewer`, `pw-researcher`, `pw-analyst` and `pw-writer-task` into each provider's agent dir,
(`pw-verifier`'s def activates with the independent-verification work in the next plan — it is
already reachable today as `/pw-verify`),
just like it installs the `/pw-*` commands (see
[`tooling/agents/`](../tooling/agents/README.md)). But execution can also **reuse whatever you
already have**: a task's `Execute with:` names the model or a registered def, and the discipline
(worktree isolation, running Verify, faithful reporting) comes from the `project-workflow` skill +
the task file — not from a bespoke agent. So `pw-executor` is the *named* lane def when the
orchestrator's provider shares it, and a plain `provider:model` (default = the plan's produced-by
provider) runs a session with the task file as its work order — the **portable form**. The
implementer concept is single on purpose: ad-hoc (non-pw) code work runs on the main agent (or a
generic session), never a second executor agent def.

## Full resume vs one wave at a time

`/pw-execute <slug>` with no task IDs is a **resume of the whole run** — it walks every task not
yet `accepted` to the end of what's currently ready, in one invocation. For a long plan, `/pw-execute
<slug> --wave` instead runs **only the tasks immediately runnable right now** (every `depends_on`
already `done`/`accepted`), then stops and reports rather than cascading into whatever it just
unblocked — a checkpoint-sized chunk, so a misbehaving orchestrator or a lost session only costs one
wave's blast radius, not the whole remaining DAG. Naming specific task IDs (`/pw-execute <slug>
T03`) is a third, narrower mode: run exactly those tasks and stop, regardless of what else is
pending. Full semantics: [`tooling/commands/pw-execute.md`](../tooling/commands/pw-execute.md).

## Choosing a model / sub-agent per task — two axes, not one
**The executor's model** is per-task and lives in the PLAN's task table (`Execute with:`) — it is
*never* overridden by the dashboard (below), because a task file is the executor's contract.
**The spawn lanes'** models are per-project and live on the dashboard's `- **AI Models:**` row
(shown/set by `/pw-config <slug>`)
— because a lane is spawned by a phase, not by a task file. Four rungs, highest wins; what a run
actually used is *recorded*, so a pin silently failing becomes visible drift, not folklore:
**(1)** run-time override this call → **(2)** the project's `AI Models:` row for that lane →
**(3)** the registered def's own model (kilo map block/generated md, cursor seeded def's `model:`,
**claude per-agent only via the def** — see §Providers & the registry) → **(4)** the provider/session
floor (`small_model`/`subagent_model` on kilo; session `/model` on claude; the `auto` router or
`cli-config.json → selectedModel` on cursor). On kilo — and likewise on cursor, whose named spawns
carry no per-run model parameter — the in-process spawn can't
carry a model at all, so a lane row there is served as a **headless session of that model over the
same work order** (`kilo run --auto -m <api>/<model> … --dir <path>`) — a row that can't bind in an
in-process spawn says so in the ledger instead of lying (docs: §Spawning phase work below; provider
table: [`tooling/docs/providers.md`](../tooling/docs/providers.md)). The `AI Models` lane set is
`researcher analyst writer-task reviewer verifier` — no executor row by design. `verify`-lane work is
the pipeline's typed-verification surface: it *resolves* to the same binding question, so the row
exists already and never grows a second model-source.

## Choosing a model / sub-agent per task

Every task records **how it should be run**, so the choice is documented and reviewable — not buried
in an agent's head:
- `Execute with:` — `<provider>:<model-or-agent>` (e.g. `claude:opus`,
    `kilo:command_code/MiniMaxAI/MiniMax-M3`; or a same-provider def name like `pw-executor`). The    **provider** decides which
  CLI runs it. Claude aliases (`opus`/`sonnet`/…) follow the *latest* version — **pin the full
  name** (`claude-opus-4-8` vs `claude-opus-5`) when reproducibility matters.
- `Effort:` / `Thinking:` — optional reasoning tuning (→ claude `--effort`, kilo
  `--variant`/`--thinking`; cursor: nearest catalog-id variant (`…-thinking-xhigh`, `…-high-fast`) or
  a `[effort=…]` bracket param — full mapping in `tooling/docs/providers.md`'s effort table).
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
| `kilo/<model>` | kilo | KiloCode's own built-in gateway — the **default** API Provider, no separate credential (proxies Claude/GPT/Gemini/etc. through KiloCode itself) |
| `command_code/MiniMaxAI/MiniMax-M3`, `openrouter/<model>`, `kilo/alibaba-token-plan/<model>`, … | kilo | open-weight/third-party/BYOK models — each needs its own credential; routed via any *additional* KiloCode API Provider you've listed in `PW_KILO_API_PROVIDERS` (a BYOK registered *under* the gateway is addressed by its catalog path, e.g. `kilo/alibaba-token-plan/<model>`; entries are model-id **prefix filters**, so they may contain slashes — but you list the catalog with plain `kilo models`, not `kilo models <that-path>`, which errors) |
| a same-provider def (`pw-executor`, etc.) | (that provider) | reuse a registered executor natively; across providers a **model + task file** is the portable form (sub-agent names don't cross — `kilo run --agent` takes **primary** defs only and silently continues on the default agent otherwise; claude `--agents '<json>'` injects session defs that carry only a model) |
| `cursor:cursor-grok-4.5-high`, `cursor:claude-opus-5-thinking-xhigh[context=1m]` | cursor | Cursor's own single model gateway — no API-Provider axis; ids from `agent models`; effort/fast/thinking are **catalog-id variants** (or bracket params), not flags |
| a custom `tooling/agents/` def | (its provider) | a genuinely new recurring role — same cross-provider caveat: a `mode: subagent` def is not addressable from the other CLI |

**How the agent knows what's actually available:** claude's models are the fixed set in the table
above — nothing to look up. kilo, opencode, and cursor each have a real, changeable catalog,
so `/pw-breakdown` is instructed to **query it live** (`kilo models` /
`opencode models` / `agent models`) rather than recall an id from memory before writing a task's `Execute with:` —
a plausible-looking id can simply not exist, or a display name can differ from the actual id
(verified case: KiloCode's own credential list shows "Kilo Gateway," but the usable id is `kilo`,
not `kilo_gateway`). A row's model is then resolved to its **canonical** catalog id (the exact line
the catalog prints, matched **exact-first** — the agent-provider prefix is a *connection*
distinction: `kilo:alibaba-token-plan/<model>` names a *direct* BYOK provider and binds
`alibaba-token-plan/<model>` when the catalog lists it; it reaches the gateway-nested
`kilo/alibaba-token-plan/<model>` line only as a fallback, announced on stderr. Write
`kilo:kilo/alibaba-token-plan/<model>` to pin the gateway explicitly). That canonical id
is what a headless `-m`/`--model` receives. This is a separate concern from the allowlist below — discovery is about
*what exists*, the allowlist is about *what you'll permit*.

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
  are readable prompt bodies (`tooling/agents/<name>.md`) — play the role yourself, or hand a
  session the task file as its work order (exactly what `/pw-execute <slug> <T0n>`'s
  `provider:model` default already is; see [`../tooling/agents/README.md`](../tooling/agents/README.md)
  §Spawn-less alternatives). The commands' `agent:` frontmatter that starts a *Kilo* session with a
  primary role is **Kilo-only sugar** — on Claude-like providers it does nothing.

Same rule as model lanes (above): document per-provider capability where it bites, not in prose
that implies symmetry.

## Model allowlist (optional — a cost guard, not a routing mechanism)

There's no fixed, pre-approved model list in this bundle — an agent (during `/pw-breakdown`) or
you can pick any model any configured API Provider serves, for claude, kilo, opencode, or
cursor alike.

**If you want to rule some OUT** — typically to stop an agent reaching for an unexpectedly
expensive model — set an allowlist per Agent Provider in `pw.config.sh`
(`PW_MODEL_ALLOWLIST_CLAUDE` / `_KILO` / `_OPENCODE` / `_CURSOR`), a comma-separated list of glob
patterns
matched against the model id (everything after the `<provider>:` prefix, e.g. `sonnet` or
`command_code/deepseek/*`).

**The rule, stated plainly: empty or unset = ALL models allowed.** That's the default for every
provider — nothing is restricted until you explicitly set a pattern. This is deliberately
opt-in, matching how every other optional knob in `pw.config.sh` works (off/unrestricted by
default, e.g. `PW_AI_REVIEW_DEFAULT`).

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
| How | Claude's Task tool `subagent_type`; KiloCode `mode: subagent`; Cursor auto-delegation on def `description` (or explicit `/pw-<agent>` — and a **direct** cursor sub-agent can itself fan out one more level, verified 2026-09-09) | that provider's CLI: `kilo run --agent <primary-agent>` / `claude -p` / cursor `agent -p --force --model <id>`+task file (a sub-agent def is NOT nameable from across the boundary; cursor has no CLI primary-agent slot at all) |
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
    same-provider def named in `Execute with:` (`pw-executor`, a custom `tooling/agents/` role), or a    plain `provider:model` (the default — a session on the task file).
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

Seeds are a contract, not a vibe (lane defs + `tooling/skill/…/references/execution-and-routing.md`
§Seed contracts): a dense executive summary + pointer list, **pre-flight before spawn** (a seed gap
is fixed at the producer — a cheap researcher pass — never by spawning a floundering analyst),
pointers-as-menu, never raw dumps/credentials. After a draft, an **exit check**: diff result vs the
brief's scope list; a gap means a **resume with a seed patch** (`kilo run -s <id>` / claude
`--resume <id>` / cursor `agent -p --force --resume <session_id>`) — iff the liveness check reports
that id resumable — not a cold re-spawn. N review items on ONE artifact (human / `pw-reviewer` /
verifier / `dep-impact` items share that queue) get ONE batched fix pass, per-item replies intact
— never one spawn per comment; who runs the pass (in-process fixer / supervised headless / the
driver inline) is the routing ladder's call — §The per-spawn ledger below.

**Model lanes vs executor pins are different axes.** A task's `Execute with:` binds the EXECUTOR
per unit (above). A *lane* spawns on the provider default unless the project's
`- **AI Models:** researcher=… analyst=… writer-task=… verifier=… reviewer=…` row binds it
(`/pw-config <slug> set ai-model <lane> <provider:model|—>`; unset = provider/session default;
the `AI Models:` dashboard line — same anchored-line config idiom as `AI Review`). Per-provider honesty: **claude**
can start a session per model and per-spawn override is real; **kilo**'s Task-tool has no model arg
— its levers are a map-block pin (user's own config) or running the lane **headless**:
`kilo run --auto -m <provider/model> [--dir <repo/path>]` with the task file/work order + skill
inline (`--dir` carries the cwd — no local path needed if the driver runs elsewhere). A spawn records
`Model used:` (row vs floor vs actual) so a row that couldn't fire is visible, not folklore. A
provider without a main-agent slot carries the *orchestrator* the same way the lanes are carried
elsewhere: run the row/role as a headless session — Flow B/C in
[`../tooling/agents/README.md`](../tooling/agents/README.md) (Claude Code has no custom
**primary** agent: only sub-agents + the built-in main), or drive from Kilo with `pw-orchestrator`.

## The per-spawn ledger (why it exists: resume > re-derive) and the routing ladder

Every delegated spawn writes one line where the pipeline already logs, so later fixes can reuse the
**warm** session instead of re-deriving from a cold start (`LOG.md` line, via the flow's log step,
carries `· via=subagent|headless · session=<id> · seed=<ref> · out=<artifact> · state=…`; the task's
`## Result → Session:` records its run's id, and the executor writes `session <id>` as the first line
of `worktree/<T0n>.log` when the provider exposes one — `-` if not). A Row-8 rejection, an MR-comment
batch, or a dependency's §3.6 recheck **resumes that id** (`kilo run -s <id>` / cursor
`agent -p --force --resume <id>`; ids are `ses_…` on kilo, plain UUIDs on cursor) *only when a
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

Which CLI runs which model lives in the [Agent Provider registry](../tooling/docs/providers.md).
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
# run /pw-close (it tears down all of a project's worktrees safely), or see
# tooling/docs/scripts/ for the teardown helper when working from the bundle
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
