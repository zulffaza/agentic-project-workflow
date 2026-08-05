# Agent provider registry (execution routing)

**Filled by:** [🧑 you] — this is config you maintain as you add agents/models. Agents READ it.

> Path vars below (`$PW_HOME`/`$PW_PROJECTS`/`$PW_REPOS`) are exported by `bootstrap.sh`; see the
> bundle [README](../README.md) legend.

`Execute with:` on a task names a **model** or an **agent**. Each belongs to a **provider** — the
CLI that can actually run it. The orchestrator uses this registry to decide, per task: run it
in-process (same provider the orchestrator is running under) or **shell out to another provider's
CLI**. This is what lets a `/pw-execute` started in Claude Code hand specific tasks to KiloCode
(or vice-versa), and stays open for new providers.

`Execute with:` format → **`<provider>:<model-or-agent>`** (the `<provider>:` prefix is optional
when the model maps to exactly one provider below).

## Registry
_Verified 2026-08-04 against the installed CLIs._

| Provider | CLI binary | Models / agents it serves | Headless (non-interactive) invocation | Notes |
|----------|-----------|---------------------------|----------------------------------------|-------|
| `claude` | `claude` | alias = **latest** of that family: `opus`, `sonnet`, `haiku`, `fable`; **pinned** full names: `claude-opus-5`, `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`, `claude-fable-5`; existing agents (`code-implementation`, …) | `claude -p "<prompt>" --model <model> [--effort <low\|medium\|high\|xhigh\|max>]` | Anthropic models. `-p`/`--print` = headless. **Alias ≠ version-stable** (`opus` follows the latest) — use a full name to pin. |
| `kilo` | `kilo` (`@kilocode/cli`) | via the **`command_code`** AI provider (NOT Kilo Gateway): `command_code/deepseek/deepseek-v4-pro`, `command_code/MiniMaxAI/MiniMax-M3`, `command_code/xiaomi/mimo-v2.5-pro`, `command_code/Qwen/Qwen3.7-Max`, `command_code/zai-org/GLM-5.2`, … (also proxies Claude/GPT/Gemini). Full list: `kilo models command_code`. | `kilo run --auto -m command_code/<model> "<prompt>" --dir <path> [--variant <high\|max\|minimal\|…>] [--thinking] [--format json]` — `--auto` is **required** headless (see below); add `--agent <name>` when using a native agent | Open-weight + proxied models. Model id (everything after `-m`) is passed verbatim. `--variant` = provider-specific reasoning effort. |
| _`<future>`_ | _`<cli>`_ | _`<models/agents>`_ | _`<invocation>`_ | Add a row — no code change needed. |

> **`Execute with:` form per provider:** `claude:<model-or-agent>` (e.g. `claude:opus` = latest, or
> pinned `claude:claude-opus-4-8`), or `kilo:<full-model-id>` where the id after `kilo:` is exactly
> what `kilo run -m` expects — e.g. `kilo:command_code/MiniMaxAI/MiniMax-M3`. The `command_code/`
> prefix is required because that's the AI provider in use inside KiloCode (confirmed:
> `command_code` credential, not Kilo Gateway).

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

## KiloCode model roster (curated — [🧑 you])
Blessed `command_code` models for this workflow. Add/remove rows freely; the full catalog is
`kilo models command_code`. Use in a task as `Execute with: <id>` (ids verified 2026-08-04).

| Label | `Execute with:` id |
|-------|--------------------|
| GPT-5.6 Luna | `kilo:command_code/gpt-5.6-luna` |
| MiMo v2.5 | `kilo:command_code/xiaomi/mimo-v2.5` |
| DeepSeek V4 Flash | `kilo:command_code/deepseek/deepseek-v4-flash` |
| Qwen 3.7 Plus | `kilo:command_code/Qwen/Qwen3.7-Plus` |

## Cross-provider execution (how the orchestrator routes)

> **Verified end-to-end 2026-08-04** (Claude Code orchestrator → `kilo run` executor, throwaway
> repo). Confirmed findings:
> - **`--auto` is mandatory headless.** Without it `kilo run` *auto-rejects* every permission
>   (it couldn't even `read` the task file). `--auto` = "auto-approve all permissions (for
>   autonomous/pipeline usage)". (`--dangerously-skip-permissions` also exists; prefer `--auto`.)
> - **Git worktrees work headlessly** — the executor ran `git worktree add`, wrote the file, and
>   committed inside the worktree. The documented "KiloCode auto-approve breaks in worktrees"
>   gotcha is a *JetBrains-plugin* issue and does **not** affect the CLI.
> - **The discipline travels:** the kilo run auto-invoked its `skill` tool (project-workflow) — the
>   skill (and any configured memory MCP) reaches the shelled-out executor.
> - **Result capture:** with `--format json`, the final `text` event part is the clean answer to
>   scrape (e.g. `jq -r 'select(.part.type=="text").part.text' | tail -1`). Always also confirm
>   the real git artifacts (branch/commit/Verify), not just the self-report.
> - **Model capability matters:** a tiny model (`gemini-3.5-flash-lite`) stopped after one step;
>   `MiniMaxAI/MiniMax-M3` completed the whole task. Route executor tasks to a capable model.


0. If `Execute with:` names an **agent** (not a bare model), resolve its provider first: explicit
   `<provider>:` prefix → else the agent's `Provider:` in `sub-agent/<name>.md` → else (built-in
   agent, no def) the orchestrator's own provider. Its `Default model`/`Default effort` apply
   unless the task overrides. (See `sub-agent/README.md`.)
1. Otherwise resolve each task's provider from its `Execute with:` (explicit `<provider>:` prefix, else the
   unique provider serving that model in the table above).
2. **Same provider** as the orchestrator → spawn a normal in-process sub-agent (the usual path).
3. **Different provider** → invoke that provider's **CLI headlessly**, passing the *task file* as
   the work order. The discipline travels with the task, not the provider — the other CLI still
   follows the `project-workflow` skill + the task file. Concretely:
   ```bash
   # Claude-Code orchestrator → hand a kilo:* task to KiloCode (command_code provider):
   PROMPT="Follow the project-workflow skill (executor role). Execute the task in \
   $PW_PROJECTS/<slug>/task/<T0n>.md in its own git worktree, run its \
   ## Verify block, paste real output, fill its ## Result block. Do not touch other worktrees."
   kilo run --auto -m command_code/MiniMaxAI/MiniMax-M3 --dir $PW_REPOS \
     --format json "$PROMPT"      # --auto required; scrape final text part for the result

   # KiloCode orchestrator → hand a claude:* task to Claude Code:
   claude -p "$PROMPT" --model opus
   ```
   Capture that CLI's output into the task's `## Result` and append a `LOG.md` line naming the
   provider used. Record it in the task's `Actually used:` (e.g. `kilo:command_code/MiniMaxAI/MiniMax-M3`).

## Adding a provider (extensibility)

Add one row to the Registry with its CLI binary, the models/agents it serves, and its headless
invocation. Keep each **model listed under exactly one provider** so a bare `Execute with: <model>`
resolves unambiguously; if a model is served by two providers, always write `<provider>:<model>`.
No generator or code change is required — the orchestrator reads this file at execution time.
