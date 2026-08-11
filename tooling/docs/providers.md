# Cross-provider execution (how a task routes to another Agent Provider's CLI)

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
> **Terminology:** an **Agent Provider** is the CLI itself (`claude`, `kilo`, `opencode`, …). An
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
opencode in `tooling/pw-common.sh`, overridable (or added fresh, for a provider that isn't
built-in) in `pw.config.sh` — that prints the exact non-interactive invocation template plus
operational gotchas for that CLI. The orchestrator reads **that hook's output**, not a markdown
table, when routing a task to a *different* provider than its own. A provider without this hook
is still fully usable same-provider; it just can't be a cross-provider **target** (same optional
treatment as `agentdir`/`render_*_agent` for sub-agent seeding).

**What the built-in hooks currently return** (source of truth is `tooling/pw-common.sh`'s
`claude_headless`/`kilo_headless`/`opencode_headless` — the lines below are illustrative, kept in
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
  Add `--agent <name>` when targeting a native agent instead of a bare model. `<api-provider>` is
  one of `PW_KILO_API_PROVIDERS` (`pw.config.sh`) — e.g. `kilo`, `command_code`, `openrouter`.
- **opencode** — `opencode run --auto -m <api-provider>/<model> "<prompt>" [--format json]
  [--attach <url>]`. `--auto` is required headless. **Not yet run end-to-end in this bundle**
  (unlike claude/kilo — see Verification notes); confirmed against OpenCode's own CLI docs only.

## Effort / variant / thinking (per-task tuning)
A task may carry two optional fields alongside `Execute with:` — the orchestrator maps them to the
right CLI flag by provider:

| Task field | `claude` maps to | `kilo` maps to |
|------------|------------------|----------------|
| `Effort:` (`low`/`medium`/`high`/`xhigh`/`max`) | `--effort <level>` | `--variant <level>` (provider-specific: `high`/`max`/`minimal`/…; nearest match) |
| `Thinking:` (`on`/`off`) | (n/a — omit; effort covers reasoning) | `--thinking` when `on` |

- **Version pinning (Claude):** `opus`/`sonnet`/`haiku`/`fable` resolve to the *latest* of that
  family. To pin, use the full name — `claude:claude-opus-4-8` vs `claude:claude-opus-5`,
  `claude:claude-sonnet-5`, etc. Prefer pinning for reproducibility on risky tasks.
- Omit `Effort:`/`Thinking:` to use each CLI's default. Values are validated at execution — an
  unknown effort/variant for a given provider is reported, not silently dropped.

## Choosing a model — no fixed roster, model-agnostic by default

There's deliberately no fixed "blessed models" list, and no static model→provider catalog either
— any model any configured API Provider serves is fair game, for kilo, opencode, or claude alike.
An agent (during `/pw-breakdown`) or you can pick whatever fits the task, but **always write the
explicit `<provider>:` prefix** — this is exactly why: a static catalog goes stale (a display name
can differ from the real id — verified case: KiloCode's own "Kilo Gateway" credential resolves
under the id `kilo`, not `kilo_gateway`), so there's nothing here to infer a provider from.

**If you don't want that fully open** — e.g. to keep an agent from reaching for an unexpectedly
expensive model — set an optional **model allowlist** per Agent Provider in `pw.config.sh`
(`PW_MODEL_ALLOWLIST_CLAUDE` / `_KILO` / `_OPENCODE`, comma-separated glob patterns). **The
rule: empty/unset = ALL models allowed — the default.** Nothing is restricted unless you set a
pattern yourself. `/pw-breakdown` checks a task's chosen model against it while filling `Execute
with:`; `/pw-execute` checks again right before running it.

**To see what's actually available, and whether your allowlist patterns match anything real, run
`/pw-doctor`** — its "Model availability" section queries each provider's live catalog and flags
a configured pattern that matches zero models (a likely typo, a deprecated id, or a model your
authenticated API Providers don't cover). It's informational only — never something you check by
running a provider's CLI by hand, and never blocks `/pw-doctor` itself. (kilo's own catalog is
browsable directly via `kilo models [provider-id]`, opencode's via `opencode models [provider-id]`,
if you want to look yourself — but `/pw-doctor` is the one that actually validates your config.)

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
   Concretely (note: `-m <model>`, **no** `--agent`):
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
