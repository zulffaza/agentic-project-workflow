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
(`pw-lib.sh ai-model <slug> <lane> <provider:model|—>`, also shown/set by `/pw-review <slug> config`)
— because a lane is spawned by a phase, not by a task file. Four rungs, highest wins; what a run
actually used is *recorded*, so a pin silently failing becomes visible drift, not folklore:
**(1)** run-time override this call → **(2)** the project's `AI Models:` row for that lane →
**(3)** the registered def's own model (kilo map block or generated md; **claude per-agent only via
the def** — see §Providers & the registry) → **(4)** the provider/session floor (`small_model`/
`subagent_model` on kilo; session `/model` on claude). On kilo the in-process `Task`-tool spawn can't
carry a model at all, so a lane row there is served as a **headless session of that model over the
same work order** (`kilo run --auto -m <api>/<model> … --dir <path>`) — a row that can't bind in an
in-process spawn says so in the ledger instead of lying (docs: §Spawning phase work below; provider
table: [`tooling/docs/providers.md`](../tooling/docs/providers.md)). The `AI Models` lane set is
`researcher analyst writer-task reviewer verifier` — no executor row by design. `verify`-lane work is
plan 02's typed-verification surface: it *resolves* to the same binding question, so the row exists
already so plan 02 never grows its second model-source.

## Choosing a model / sub-agent per task

Every task records **how it should be run**, so the choice is documented and reviewable — not buried
in an agent's head:
- `Execute with:` — `<provider>:<model-or-agent>` (e.g. `claude:opus`,
    `kilo:command_code/MiniMaxAI/MiniMax-M3`; or a same-provider def name like `pw-executor`). The    **provider** decides which
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
| `kilo/<model>` | kilo | KiloCode's own built-in gateway — the **default** API Provider, no separate credential (proxies Claude/GPT/Gemini/etc. through KiloCode itself) |
| `command_code/MiniMaxAI/MiniMax-M3`, `openrouter/<model>`, … | kilo | open-weight/third-party models — needs its own credential; routed via any *additional* KiloCode API Provider you've listed in `PW_KILO_API_PROVIDERS` (`kilo models <provider>`) |
| a same-provider def (`pw-executor`) | (that provider) | reuse a registered executor natively; across providers a **model + task file** is the portable form (sub-agent names don't cross) || a custom `tooling/agents/` def | (its provider) | a genuinely new recurring role. Note (verified): `kilo run --agent <name>` targets **primary** agents only — hand it a `mode: subagent` def and it says so and runs the default agent anyway; on claude, `--agents '<json>'` injects custom defs into the session — route by model, and don't assume cross-provider names resolve |

**How the agent knows what's actually available:** claude's models are the fixed set in the table
above — nothing to look up. kilo and opencode both have a real, changeable catalog, so
`/pw-breakdown` is instructed to **query it live** (`kilo models <api-provider>` /
`opencode models`) rather than recall an id from memory before writing a task's `Execute with:` —
a plausible-looking id can simply not exist, or a display name can differ from the actual id
(verified case: KiloCode's own credential list shows "Kilo Gateway," but the usable id is `kilo`,
not `kilo_gateway`). This is a separate concern from the allowlist below — discovery is about
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
you can pick any model any configured API Provider serves, for claude, kilo, or opencode alike.

**If you want to rule some OUT** — typically to stop an agent reaching for an unexpectedly
expensive model — set an allowlist per Agent Provider in `pw.config.sh`
(`PW_MODEL_ALLOWLIST_CLAUDE` / `_KILO` / `_OPENCODE`), a comma-separated list of glob patterns
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
`--resume <id>`), not a cold re-spawn. N review items on ONE artifact (human / `pw-reviewer` /
verifier / `dep-impact` items share that queue) get ONE batched fix spawn, per-item replies intact
— never one spawn per comment.

**Model lanes vs executor pins are different axes.** A task's `Execute with:` binds the EXECUTOR
per unit (above). A *lane* spawns on the provider default unless the project's
`- **AI Models:** researcher=… analyst=… writer-task=… verifier=… reviewer=…` row binds it
(`/pw-review <slug> config model <lane> <provider:model|—>`; unset = provider/session default;
`pw-lib.sh ai-model` — same anchored-line config idiom as `AI Review`). Per-provider honesty: **claude**
can start a session per model and per-spawn override is real; **kilo**'s Task-tool has no model arg
— its levers are a map-block pin (user's own config) or running the lane **headless**:
`kilo run --auto -m <provider/model> [--dir <repo/path>]` with the task file/work order + skill
inline (`--dir` carries the cwd — no local path needed if the driver runs elsewhere). A spawn records
`Model used:` (row vs floor vs actual) so a row that couldn't fire is visible, not folklore. A
provider without a main-agent slot carries the *orchestrator* the same way the lanes are carried
elsewhere: run the row/role as a headless session — Flow B/C in
[`../tooling/agents/README.md`](../tooling/agents/README.md) (Claude Code has no custom
**primary** agent: only sub-agents + the built-in main), or drive from Kilo with `pw-orchestrator`.

## The per-spawn ledger (why it exists: resume > re-derive)

Every delegated spawn writes one line where the pipeline already logs, so later fixes resume the
**warm** session instead of re-deriving from a cold start (`LOG.md` line, via `pw-lib.sh log`,
carries `· session=<id> · seed=<ref> · out=<artifact> · <outcome>`; the task's `## Result →
Session:` records its run's id, and the executor writes `session <id>` as the first line of
`worktree/<T0n>.log` when the provider exposes one — `-` if not). A Row-8 rejection, an MR-comment
batch, or a dependency's §3.6 recheck **resumes that id** (`kilo run -s <id>`) when live; cold —
spawn with the task file / recorded seed — is the fallback, because session stores are
machine-local (never cross-machine) and a dead id must not strand the work. Session ids are
**machine-local pointers** — they stay in the workspace; nothing goes into MR text. State that
*must* survive machines stays on disk (PLAN / dashboard / worktree commits).

## Providers & the registry

Which CLI runs which model lives in the [Agent Provider registry](../tooling/docs/providers.md).
Claude models → Claude Code; open-weight models → KiloCode, which can connect to **several API
Providers at once** (list them in `PW_KILO_API_PROVIDERS` — e.g. `command_code`, `openrouter`, …
— and reference any as `kilo:<provider>/<model>`). It's a one-row-per-Agent-Provider extension
point, so new providers slot in without code changes.

When `Execute with:` names an agent, resolve its provider the same way as a model: an explicit
`<provider>:` prefix wins → else the agent def's own provider → else (a built-in with no def) the
orchestrator's own provider — then apply the same-vs-different routing above.

**Requesting a specific model/agent — three ways, all honored:**
1. **Statically** — set the task's `Execute with:` field (edit it, or ask the breakdown agent to set
   it: "make T03 use opus because it's the risky migration").
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
