# Cross-provider execution (how a task routes to another Agent Provider's CLI)

> **Audience:** technical — maintainer/agent reference for the invocation machinery; ordinary
> users don't need it (their peer doc is `../../docs/EXECUTION.md`). One behavioral exception:
> "Choosing a model" is safe for users to read.

**Filled by:** [🤖 maintainer] — this documents the mechanism; you never edit this file to
register a provider or a model. Adding cross-provider execution support for a new Agent Provider
means defining `<name>_headless()` in `pw.config.sh` — see
[ONBOARDING.md](../../ONBOARDING.md#register-a-new-provider) — never editing this file.

> **Not the same registry as [ONBOARDING.md](../../ONBOARDING.md)'s "Register a new provider."**
> That one is about wiring a new AI-agent CLI into this bundle at all (skills/commands/agents,
> via hooks in `pw.config.sh`). This file explains a separate, optional mechanism consulted only
> by `/pw-execute`'s cross-provider task routing — a CLI can be fully wired up with no headless
> hook at all, and a headless hook means nothing without that CLI also being a registered Agent
> Provider.
>
> **Terminology:** an **Agent Provider** is the CLI itself (`claude`, `kilo`, `opencode`,
> `cursor`, …). An
> **API Provider** is a narrower, different thing: which model *backend* a given Agent Provider
> talks to underneath (e.g. `command_code`/`openrouter` inside KiloCode). One Agent Provider can
> have several API Providers; don't conflate the two when reading this file.

> Path vars below (`$PW_HOME`/`$PW_PROJECTS`/`$PW_REPOS`) are exported by `bootstrap.sh`; see the
> bundle [README](../README.md) legend.

`Execute with:` on a task names a **model** or an **agent**. Each belongs to an **Agent Provider**
— the CLI that can actually run it. The orchestrator decides, per task: run it in-process (same
Agent Provider the orchestrator is running under) or **shell out to another Agent Provider's
CLI**. This is what lets a `/pw-execute` started in Claude Code hand specific tasks to KiloCode
(or vice-versa), and stays open for new providers.

`Execute with:` format → **`<provider>:<model-or-agent>`** — **the `<provider>:` prefix is always
required.** There's no static model→provider catalog to fall back on for an implicit mapping (and
there won't be one again — see "Choosing a model" below for why); write it explicitly every time.

## How headless invocation actually works

Each Agent Provider has an **optional** `<name>_headless()` hook — built-in for claude/kilo/
opencode/cursor in `tooling/pw-common.sh`, overridable (or added fresh, for a provider that isn't
built-in) in `pw.config.sh` — that prints the exact non-interactive invocation template plus
operational gotchas for that CLI. The orchestrator reads **that hook's output**, not a markdown
table, when routing a task to a *different* provider than its own. A provider without this hook
is still fully usable same-provider; it just can't be a cross-provider **target** (same optional
treatment as `agentdir`/`render_*_agent` for sub-agent seeding).

**What the built-in hooks currently return** (source of truth is `tooling/pw-common.sh`'s
`claude_headless`/`kilo_headless`/`opencode_headless`/`cursor_headless` — the lines below are
illustrative, kept in
sync by whoever maintains the bundle, not something you edit here to change behavior):

- **claude** — `claude --print --dangerously-skip-permissions --model <model> [--effort <low|
  medium|high|xhigh|max>]`. `--dangerously-skip-permissions` is **required** headless (no TTY to
  answer a permission prompt otherwise). **Pipe the prompt via stdin, never a trailing
  argument** — a long inline argument can vanish entirely across a shell-out boundary; stdin is
  immune (see [Verification notes](#verification-notes-historical)). Model aliases (`opus`/
  `sonnet`/`haiku`/`fable`) follow the *latest* of that family — pin a full name
  (`claude-opus-4-8` vs `claude-opus-5`) for reproducibility on risky tasks.
- **kilo** — `kilo run --auto -m <api-provider>/<model> "<prompt>" --dir <path> [--variant <low|
  medium|high|max|minimal>] [--thinking] [--format json]`. `--auto` is **required** headless
  (without it, `kilo run` auto-*rejects* every permission — it can't even read the task file).
  Add `--agent <name>` only when targeting a **primary** agent, never a sub-agent: verified    2026-09-04, `--agent pw-executor` prints *"agent 'pw-executor' is a subagent, not a primary
    agent. Falling back to default agent"* and runs the fallback model anyway (unknown names likewise
    fall back silently) — so cross-provider *execution* always carries the **task file as the work
    order** on a `<api-provider>/<model>`, never a sub-agent name. Two related kilo facts from the
    same probe session (`kilo agent list` / `kilo debug agent <name>`): an `agent/*.md` file with
    `mode:` + `options:` registers on its own (no map block needed), and a `model:` line *in that md*
    binds — outranking a `kilo.jsonc` map block if both set it. So a dashboard `- **AI Models:**` row
    can reach kilo's md path without any user-config edit once `render_kilo_agent` prints a canonical
    `model:`. `<api-provider>` is
  one of `PW_KILO_API_PROVIDERS` (`pw.config.sh`) — e.g. `kilo`, `command_code`, `openrouter`.
- **opencode** — `opencode run --auto -m <api-provider>/<model> "<prompt>" [--format json]
  [--attach <url>]`. `--auto` is required headless. **Not yet run end-to-end in this bundle**
  (unlike claude/kilo/cursor — see Verification notes); confirmed against OpenCode's own docs only.
- **cursor** — `agent -p --force [--trust] --model <id> [--output-format json] [--resume
  <session_id>] [--workspace <path>]`. `--force` (alias `--yolo`) is **required headless** (no TTY
  for approvals; `--trust` clears the per-folder gate when needed). **Pipe the prompt via a plain
  stdin redirect; never pass `-` as the argument** — `-` is sent as the literal prompt (verified
  2026-09-09); stdin itself carries long prompts fine, same doctrine as claude. `--output-format
  json` closes with ONE final event `{result, session_id, is_error, usage}` — `session_id` is the
  ledger/resume handle (`--resume <session_id>` round-trip verified). Blocked or plan-gated model
  ids exit non-zero with `ActionRequiredError` **text, not JSON** — treat unparsable output as an
  error, never blank success. No `PW_CURSOR_API_PROVIDERS` axis: one gateway (`agent models` =
  the catalog). Like kilo's rule: cross-provider `cursor:*` tasks carry the **task file as work
  order** on a `--model <id>`; a named sub-agent can't cross the boundary (cursor has no primary
  CLI slot at all).

## Effort / variant / thinking (per-task tuning)
A task may carry two optional fields alongside `Execute with:` — the orchestrator maps them to the
right CLI flag by provider:

| Task field | `claude` maps to | `kilo` maps to | `cursor` maps to |
|------------|------------------|----------------|----------------|
| `Effort:` (`low`/`medium`/`high`/`xhigh`/`max`) | `--effort <level>` | `--variant <level>` (provider-specific: `high`/`max`/`minimal`/…; nearest match) | nearest `cursor:<id>-<level>[-fast]` catalog id (e.g. `claude-opus-5-thinking-xhigh`); bracket `[effort=…]` params per-run |
| `Thinking:` (`on`/`off`) | (n/a — omit; effort covers reasoning) | `--thinking` when `on` | encoded in catalog ids (`-thinking-<level>` variants); no standalone flag |

- **Version pinning (Claude):** `opus`/`sonnet`/`haiku`/`fable` resolve to the *latest* of that
  family. To pin, use the full name — `claude:claude-opus-4-8` vs `claude:claude-opus-5`,
  `claude:claude-sonnet-5`, etc. Prefer pinning for reproducibility on risky tasks.
- Omit `Effort:`/`Thinking:` to use each CLI's default. Values are validated at execution — an
  unknown effort/variant for a given provider is reported, not silently dropped.

## Choosing a model — no fixed roster, model-agnostic by default

There's deliberately no fixed "blessed models" list, and no static model→provider catalog either
— any model any configured API Provider serves is fair game, for kilo, opencode, cursor, or
claude alike.
An agent (during `/pw-breakdown`) or you can pick whatever fits the task, but **always write the
explicit `<provider>:` prefix** — this is exactly why: a static catalog goes stale (a display name
can differ from the real id — verified case: KiloCode's own "Kilo Gateway" credential resolves
under the id `kilo`, not `kilo_gateway`), so there's nothing here to infer a provider from.

**If you don't want that fully open** — e.g. to keep an agent from reaching for an unexpectedly
expensive model — set an optional **model allowlist** per Agent Provider in `pw.config.sh`
(`PW_MODEL_ALLOWLIST_CLAUDE` / `_KILO` / `_OPENCODE` / `_CURSOR`, comma-separated glob
  patterns). **The
rule: empty/unset = ALL models allowed — the default.** Nothing is restricted unless you set a
pattern yourself. `/pw-breakdown` checks a task's chosen model against it while filling `Execute
with:`; `/pw-execute` checks again right before running it.

**To see what's actually available, and whether your allowlist patterns match anything real, run
`/pw-doctor`** — its "Model availability" section queries each provider's live catalog and flags
a configured pattern that matches zero models (a likely typo, a deprecated id, or a model your
authenticated API Providers don't cover). It's informational only — never something you check by
running a provider's CLI by hand, and never blocks `/pw-doctor` itself. (kilo's own catalog is
browsable directly via `kilo models [provider-id]`, opencode's via `opencode models
[provider-id]`, cursor's via `agent models`, if you want to look yourself — but `/pw-doctor` is the one that actually validates your config.)

## Verified agent/session facts (probed 2026-09-04 kilo/claude + 2026-09-09 cursor, this machine — re-run before trusting elsewhere)

- **Registered set = ground truth via `kilo agent list`** (prints `name (mode)` + resolved
  permission JSON); `kilo debug agent <name>` prints the **effective config incl. the model a
  resolution landed on**. Use these instead of guessing from files, and *after* editing either
  surface — a client reload is what applies config edits.
- **Kilo reads agent definitions from BOTH surfaces** — the generated `~/.config/kilo/agent/*.md`
  (mode/description/options/permission + body) **and** a `kilo.jsonc → agent` mirror block (the
  mirror can carry `model:` and `prompt:`). md-only registers too (`options:` + `mode:` are what
  makes a bare md resolve). **When both exist and set `model:`, the md's model wins** (probed).
- **`kilo run` headless surface**: `-m <apiProvider>/<model>` binds the model; `--agent <name>`
  resolves **only primary** agents (probed: a `mode: subagent` def prints "…is a subagent, not a
  primary agent. Falling back to default agent" with no error exit — it silently *continues* with
  the default agent, so never treat a headless `--agent` on a sub-agent as "worked"); **`-c` /
  `-s <ses_…>` / `--fork`** resume sessions; **`--dir <path>`** runs in another directory (see
  `PW_KILO_WORKDIR` below).
- **`claude -p` headless surface**: `--model` binds; `--agents '<json>'` injects *session-level*
  custom defs (probed to work for a headless `-p` run); `--permission-mode` is real
  (`choices: … auto …` — `auto` = the background classifier, best for unattended nested spawns);
  session resume is the CLI's own (`-c`/`/resume`).
- **Both CLIs take a working-directory flag** (`kilo run --dir <path>`; `pw-common.sh` wires the
  same idea for claude as `-C <path>` via the `PW_CLAUDE_WORKDIR` env — the config hook is
  `*_bin()`/`*_headless` envs; there is no `PW_KILO_BIN`/`PW_CLAUDE_BIN` variable set anywhere in
  this bundle: the binaries are the `kilo`/`claude`/`cursor` hooks and the headless *shape* is the
  `<name>_headless` doc-block). A machine that lacks a repo locally can still run an executor headless
  against ITS own dir.

- **`agent -p` (Cursor) headless surface** — probed live 2026-09-09 on build `2026.09.02-c22c1a3`
  with `--output-format json`: exactly one final result event; `session_id` is a plain UUID (not
  kilo's `ses_…` shape) — ledger `Provider`-conditional; **`--resume <uuid>` round-trips context**
  (verified). A second probe proved **separate `-p` runs in the SAME `--workspace` do NOT
  auto-continue** each other (per-run sessions; only `--resume` reconnects).
- **Model observability is zero at the surface**: no json field, `agent ls`, or status line names
  what actually ran (the `--model` floor equals `cli-config.json → selectedModel`, e.g.
  `grok-4.6[effort=high,fast=true]` here), so the `Model used:` discipline (EXECUTION.md) can only
  record what was **requested** on GOTO-team accounts. Blocked/gated ids (`(NO ZDR)` rows;
  `claude-fable-5-*`) fail loud — `ActionRequiredError: Model Blocked`, exit 1, non-JSON — so
  admin-block ≠ silent-fallback; the *silent* case is plan-gated models per Cursor docs, unprobed
  here (docs-claimed feature, plan-12 §Risk).
- **`~/.cursor/{skills,commands,agents}` fully self-sufficient (D9 quarantine proof, 2026-09-09):**
  with `~/.claude/{agents,skills}` moved to quarantine, `/pw-hello` still expanded (from
  `~/.cursor/commands` — the CLI has **no** `.claude/commands` compat read at all, verified by
  bundle grep) and the skills palette still resolved — every surface cursor used came from its own
  native install. `~/.claude` was restored afterward; the 20 claude artifacts stayed byte-identical
  across the whole plan (md5 baseline) and the 3 `~/.claude/skills/*` bundle symlinks stayed live.
- **Naming caveat:** the Cursor CLI binary is `agent` (`cursor-agent` is the same thing; both are
  symlinks the installer drops next to it). In this bundle's docs a backticked `agent` in a CLI
  context means the Cursor binary; sub-agent roles are always written `pw-*` or "sub-agent".
  `cursor_bin()` → `agent` — a machine where something shadows that name overrides the hook in
  `pw.config.sh`.

## Cross-provider execution (how the orchestrator routes)

This is how a task written in one provider's format gets handed to another provider's CLI
headlessly. The two operational gotchas that make this reliable — `--auto`/
`--dangerously-skip-permissions` being mandatory, and piping the prompt via stdin instead of a
trailing argument — are asserted in the steps below; their provenance (which run surfaced each one
and why) is in [Verification notes](#verification-notes-historical) at the end of this file rather
than inline here.

0. If `Execute with:` names an **agent** (not a bare model), resolve its provider first: explicit
   `<provider>:` prefix → else the agent's own provider in `tooling/agents/<name>.md` → else
   (built-in agent, no def) the orchestrator's own provider. Its `model`/effort defaults apply
   unless the task overrides. (See `tooling/agents/README.md`.)
1. Otherwise resolve each task's provider from its `Execute with:` **explicit `<provider>:`
   prefix** — always present, never inferred.
2. **Same provider** as the orchestrator → spawn a normal in-process **sub-agent** (the usual path):
   `pw-executor`, another same-provider agent, or a bare model. Sub-agents are same-provider only.
3. **Different provider** → read that provider's `<name>_headless()` hook output, and invoke its
   **CLI headlessly** per that template, passing the *task file* as the work order to its
   **default/primary** agent. You **cannot** name the other provider's *sub-agent* here (e.g. a
   Claude orchestrator can't use kilo's `pw-executor` sub-agent) — sub-agents don't cross a
   provider boundary; only a provider's own primary agents are invocable from outside, and a lone
   task just needs the default agent + task file. The discipline travels with the task, not the
   provider — the other CLI still follows the `project-workflow` skill + the task file.
      Concretely (`-m <model>` always carries the routing; `--agent` is optional and names **primary**
   agents only — a `mode: subagent` def is rejected headless, verified 2026-09-04 — so the portable
   invocation passes the task file as the work order and lets that CLI's default agent run it):
   ```bash
   # Claude-Code orchestrator → hand a kilo:* task to KiloCode (command_code API Provider):
   PROMPT="Follow the project-workflow skill (executor role). Execute the task in \
   $PW_PROJECTS/<slug>/task/<T0n>.md in its own git worktree, run its \
   ## Verify block, paste real output, fill its ## Result block. Do not touch other worktrees."
   kilo run --auto -m command_code/MiniMaxAI/MiniMax-M3 --dir $PW_REPOS \
     --format json "$PROMPT"      # --auto required; scrape final text part for the result

   # KiloCode orchestrator → hand a claude:* task to Claude Code — pipe the prompt via stdin, NOT
   # a trailing argument (a long inline argument can vanish entirely across the shell-out boundary
   # — confirmed 2026-08-08; stdin is immune). --dangerously-skip-permissions is required headless,
   # same spirit as kilo's --auto:
   printf '%s' "$PROMPT" | claude --print --dangerously-skip-permissions --model opus
   ```
   Capture that CLI's output into the task's `## Result` and append a `LOG.md` line naming the
   provider used. Record it in the task's `Actually used:` (e.g. `kilo:command_code/MiniMaxAI/MiniMax-M3`).

## Adding cross-provider execution for a new Agent Provider (extensibility)

Define `<name>_headless()` in `pw.config.sh` — the exact non-interactive invocation template plus
any operational gotchas (an auto-approve flag, a stdin-vs-argument quirk, etc.), same shape as
the built-ins above. No edit to this file is required, and none of this even needs to exist if
you only ever want same-provider execution for that CLI — cross-provider routing is the only
thing it enables. **This is a separate, optional step from registering the CLI itself** — that's
[ONBOARDING.md](../../ONBOARDING.md#register-a-new-provider) (needed once, regardless of whether
you ever add a `_headless()` hook).

## Verification notes (historical)

Provenance for the operational rules stated above — kept for reference and future debugging, not
required reading to just use this mechanism. A dated symptom/root-cause/mitigation summary lives in
[`docs/KNOWN-ISSUES.md`](../../docs/KNOWN-ISSUES.md) — read that instead of this whole section.

**Built-in headless hooks** — verified 2026-08-04 against the installed CLIs.

**Cursor CLI, verified end-to-end 2026-09-09** (bundled probes for plan-12; kilo→cursor pairing
below): `agent -p --force --trust` writes/loops headlessly; `/pw-*` and `$ARGUMENTS` expand in
print mode; workspace `.cursor/commands` + `~/.cursor/agents` both load (defs win over same-named
commands on name-collision, and **workspace def wins over global** — probe-4); `argument-hint`
renders fine. Gotchas recorded: `-` is a literal prompt (see cursor hook bullet); non-JSON output
means error (blocked model / not-logged-in); nested two-level sub-agent delegation works but is
**unreliable on fast-tier ids** (e.g. `cursor-grok-4.6-low-fast` confabulated NO-SPAWN/“already
completed” once while succeeding on retry) — route executor/orchestrator roles to capable models
per the MiniMax doctrine above. `.claude`-compat bleed noted by `pw-doctor` (informational; the
native install is verified complete — see quarantine proof above).

**Claude stdin-vs-argument bug** — confirmed 2026-08-08, kilo→claude: `claude` reported "Input must
be provided either through stdin or as a prompt argument" with the prompt right there in the
command. A long inline CLI argument can vanish entirely across a shell-out boundary; piping the
prompt via stdin is immune. This is why `claude_headless`'s output and the routing steps above
both say to always pipe.

**Cross-provider execution, verified end-to-end 2026-08-04** (Claude Code orchestrator → `kilo run`
executor, throwaway repo). Confirmed findings:
- **`--auto` is mandatory headless.** Without it `kilo run` *auto-rejects* every permission
  (it couldn't even `read` the task file). `--auto` = "auto-approve all permissions (for
  autonomous/pipeline usage)". (`--dangerously-skip-permissions` also exists; prefer `--auto`.)
- **Git worktrees work headlessly** — the executor ran `git worktree add`, wrote the file, and
  committed inside the worktree. The documented "KiloCode auto-approve breaks in worktrees"
  gotcha is a *JetBrains-plugin* issue and does **not** affect the CLI.
- **The discipline travels:** the kilo run auto-invoked its `skill` tool (project-workflow) — the
  skill (and any configured memory MCP) reaches the shelled-out executor.
- **Result capture:** with `--format json`, the final `text` event part is the clean answer to
  scrape (e.g. `jq -r 'select(.part.type=="text").part.text' | tail -1`). Always also confirm
  the real git artifacts (branch/commit/Verify), not just the self-report.
- **Model capability matters:** a tiny model (`gemini-3.5-flash-lite`) stopped after one step;
  `MiniMaxAI/MiniMax-M3` completed the whole task. Route executor tasks to a capable model.

**Confirmed 2026-08-08** (KiloCode orchestrator → `claude --print` executor, real project): a
long inline prompt argument can vanish entirely across the shell-out boundary — `claude` reported
`Error: Input must be provided either through stdin or as a prompt argument when using --print`
even though the prompt was right there in the command. Reproduced the CLI's own flags/quoting in
isolation (they're fine); the loss happens somewhere inside the calling tool's own command
construction for a long inline argument, not in `claude` itself. **Fix: pipe the prompt via
stdin instead of a trailing argument** — verified working both standalone and through kilo's own
Bash tool. Apply this defensively to *any* cross-provider handoff, not just this pairing — a long
inline argument is a generic risk regardless of which two CLIs are involved. Separately: running
`claude --print` **without** `--dangerously-skip-permissions` headless hangs producing zero
output (a tool-approval prompt has no TTY to answer it) — always include it for a headless
executor invocation, same spirit as kilo's `--auto`.
