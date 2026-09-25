# Cross-provider execution (how a task routes to another Agent Provider's CLI)

> **Audience:** technical — maintainer/agent reference for the invocation machinery; ordinary
> users don't need it (their peer doc is `../../docs/EXECUTION.md`). One behavioral exception:
> "Choosing a model" is safe for users to read.

**Filled by:** [🤖 maintainer] — this documents the mechanism; you never edit this file to
register a provider or a model. Adding cross-provider execution support for a new Agent Provider
means defining `<name>_headless()` in `pw.config.sh` — see
[§Registering a new Agent Provider](#registering-a-new-agent-provider-hook-contract) below — never
editing this file.

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

> **This file is machine/account-specific reference, not code** — model IDs and available providers
> differ per person. Treat the committed version as a sensible starting point; each person tunes
> their own. It is maintained with the bundle: you never edit it to register a provider (the
> hook contract below is what you edit — in `pw.config.sh`).

## Registering a new Agent Provider (hook contract)

The full mechanics of wiring a CLI that isn't one of the four built-ins (`claude`, `kilo`,
`opencode`, `cursor`) into the bundle — previously inline in `ONBOARDING.md`, moved here 2026-09-25
so the user layer carries only the behavior (ONBOARDING §"Register a new provider" keeps the facts;
this section owns the contract). **You don't edit any script** — everything goes in
**`pw.config.sh`** (created on first bootstrap; gitignored, so it stays yours):

1. Add its name to `PW_PROVIDERS=(…)`.
2. Define its **required** hooks in the same file (the scripts only supply defaults for the
   built-ins, so yours win — this is also why you should never redefine `claude_*`/`kilo_*`/
   `opencode_*`/`cursor_*` here: your version would silently replace the working built-in one):
   - `<name>_bin()` — the command to detect on `PATH`
   - `<name>_skilldir()` — where it reads skills (these are plain files/dirs, copied or
     symlinked as-is — no rendering involved)
   - `<name>_commanddir()` — where its generated slash-commands go
   - `render_<name>_command()` — **prints one finished command file to stdout.** Before calling
     it, `gen-commands.sh` sets four plain shell variables it inherits (no arguments are
     passed): `$desc` (one-line description), `$args` (argument hint, may be empty), `$agent`
     (optional provider-agent name, may be empty), `$bodytext` (the prompt body, with
     `{{PW_*}}` tokens already stamped to real paths, and `{{ARGS}}` still literal — map that to
     your CLI's own argument-placeholder syntax). Your function's only job is to `printf` the
     complete frontmatter + body to stdout — `gen-commands.sh` redirects that into the real
     file; the function itself never opens a file, and it never runs or invokes anything.
     Minimal shape (mirrors `render_claude_command` in `tooling/scripts/lib/pw-common.sh`):
     ```sh
     render_myprov_command() {
       printf -- '---\ndescription: %s\n---\n%s' "$desc" "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
     }
     ```
 3. *(Optional)* `<name>_agentdir()` + `render_<name>_agent()` to also seed the sub-agents
    (`pw-orchestrator`, `pw-executor`, `pw-reviewer`) for it. Same idea as `render_<name>_command`,
    but `gen-agents.sh` sets a different variable set beforehand: `$agentname` (the file's
    basename), `$desc`, `$displayName`, `$role`, `$claude_tools`, `$model`, `$bodytext` — see
    `render_claude_agent`/`render_kilo_agent`/`render_cursor_agent` in `tooling/scripts/lib/pw-common.sh`.
    Providers without these two hooks just skip agent-seeding — the `/pw-*` commands still work.
 4. *(Optional)* `<name>_headless()` — makes the provider a cross-provider execution **target**;
    contract below in §"Adding cross-provider execution for a new Agent Provider". Without it the
    provider is fully usable same-provider.
 5. Re-run `./bootstrap.sh`.

### Worked example: registering Cline

Say you want to add [Cline](https://cline.bot/cli)'s CLI (`npm i -g cline`; binary is just `cline`).
This is the shape of what goes in `pw.config.sh` — verify the exact frontmatter Cline's workflow
loader expects before relying on this, it's a starting point, not tested code:

```sh
PW_PROVIDERS+=(cline)

cline_bin()        { echo cline; }
cline_skilldir()   { echo "$HOME/.cline/skills"; }             # Cline's global skills dir
cline_commanddir() { echo "$HOME/Documents/Cline/Workflows"; } # global custom slash-commands ("workflows")

render_cline_command() {
  # Cline turns a workflow's FILENAME into its slash command (pw-new.md -> /pw-new) and only
  # reads a `description` frontmatter field — there's no {{ARGS}}-placeholder convention like
  # Claude's $ARGUMENTS, so the body just states "arguments follow the command" in prose instead
  # of substituting a token.
  printf -- '---\ndescription: %s\n---\n%s' "$desc" "${bodytext//\{\{ARGS\}\}/the arguments given}"
}

# OPTIONAL — only needed for cross-provider execution (an orchestrator on another provider
# handing a task to Cline headlessly). Skip this and Cline still works fully for same-provider use.
cline_headless() {
  cat <<'EOF'
cline "<prompt>" --yolo --json   (or piped: <prompt> | cline --yolo --json)
--yolo/--no-interactive auto-approves every action (required headless, same spirit as kilo's
--auto); --json gives structured output to scrape.
EOF
}
```

No `<name>_agentdir`/`render_<name>_agent` shown here either — skip those and Cline just won't
get the seeded sub-agents; the `/pw-*` commands still work.

## How headless invocation actually works
— the CLI that can actually run it. The orchestrator decides, per task: run it in-process (same
Agent Provider the orchestrator is running under) or **shell out to another Agent Provider's
CLI**. This is what lets a `/pw-execute` started in Claude Code hand specific tasks to KiloCode
(or vice-versa), and stays open for new providers.

`Execute with:` format → **`<provider>:<model-or-agent>`** — **the `<provider>:` prefix is always
required.** There's no static model→provider catalog to fall back on for an implicit mapping (and
there won't be one again — see "Choosing a model" below for why); write it explicitly every time.

## How headless invocation actually works

Each Agent Provider has an **optional** `<name>_headless()` hook — built-in for claude/kilo/
opencode/cursor in `tooling/scripts/lib/pw-common.sh`, overridable (or added fresh, for a provider that isn't
built-in) in `pw.config.sh` — that prints the exact non-interactive invocation template plus
operational gotchas for that CLI. The orchestrator reads **that hook's output**, not a markdown
table, when routing a task to a *different* provider than its own. A provider without this hook
is still fully usable same-provider; it just can't be a cross-provider **target** (same optional
treatment as `agentdir`/`render_*_agent` for sub-agent seeding).

**What the built-in hooks currently return** (source of truth is `tooling/scripts/lib/pw-common.sh`'s
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
- **kilo** — `kilo run --auto -m <canonical-catalog-id> "<prompt>" --dir <path> [--variant <low|
  medium|high|max|minimal>] [--thinking] [--format json]`. `--auto` is **required** headless
  (without it, `kilo run` auto-*rejects* every permission — it can't even read the task file).
  Add `--agent <name>` only when targeting a **primary** agent, never a sub-agent: verified    2026-09-04, `--agent pw-executor` prints *"agent 'pw-executor' is a subagent, not a primary
    agent. Falling back to default agent"* and runs the fallback model anyway (unknown names likewise
    fall back silently) — so cross-provider *execution* always carries the **task file as the work
    order** on a `<canonical-catalog-id>`, never a sub-agent name. Two related kilo facts from the
    same probe session (`kilo agent list` / `kilo debug agent <name>`): an `agent/*.md` file with
    `mode:` + `options:` registers on its own (no map block needed), and a `model:` line *in that md*
    binds — outranking a `kilo.jsonc` map block if both set it. So a dashboard `- **AI Models:**` row
    can reach kilo's md path without any user-config edit once `render_kilo_agent` prints a canonical
    `model:`. `<canonical-catalog-id>` is the exact line `kilo models` prints — resolve a row's model
    to it with `pw-config.sh model-resolve kilo <model-id>` (it also enforces the
    `PW_KILO_API_PROVIDERS` **prefix-filter** scope: entries may contain slashes — a BYOK nested
    under the gateway is `kilo/alibaba-token-plan/<model>` — but are never `kilo models`
    *arguments*, which error "Provider not found" for sub-provider paths; verified 2026-09-22).
    Matching is **exact-first**: `alibaba-token-plan/<model>` as a row model names a *direct*
    provider line — a different connection than the gateway's `kilo/alibaba-token-plan/<model>` —
    and falls back to the gateway line only when no direct line exists, announced on stderr.
- **opencode** — `opencode run --auto -m <canonical-catalog-id> "<prompt>" [--format json]
  [--attach <url>]`. `--auto` is required headless. **Not yet run end-to-end in this bundle**
  (unlike claude/kilo/cursor — see Verification notes); confirmed against OpenCode's own docs only.
  `PW_OPENCODE_API_PROVIDERS` (if set) uses the same prefix-filter semantics as the kilo axis.
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
`/pw-doctor`** — its "Model availability" section queries each provider's live catalog (fetched
once per provider, then filtered locally against the `PW_<PROVIDER>_API_PROVIDERS` **prefix**
entries — never as catalog-query arguments) and flags a configured pattern that matches zero
models (a likely typo, a deprecated id, or a model your
authenticated API Providers don't cover). It's informational only — never something you check by
running a provider's CLI by hand, and never blocks `/pw-doctor` itself. (kilo's own catalog is
browsable directly via `kilo models` (full list; sub-provider paths are NOT valid filter
arguments — filter the output yourself), opencode's via `opencode models
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
- **`kilo run` headless surface**: `-m <apiProvider>/<model>` binds the model (use the canonical
  catalog line — `pw-config.sh model-resolve` prints it); `--agent <name>` resolves **only primary**
  agents (probed: a `mode: subagent` def prints "…is a subagent, not a
  primary agent. Falling back to default agent" with no error exit — it silently *continues* with
  the default agent, so never treat a headless `--agent` on a sub-agent as "worked"); **`-c` /
  `-s <ses_…>` / `--fork`** resume sessions — and whether an id is still resumable is answered
  deterministically by `pw-session.sh session-check` (`kilo session list --format json -a`), never
  by attempting the resume and reading the error; **`--dir <path>`** runs in another directory (see
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
  here (docs-claimed feature — noted as a risk when Cursor was onboarded 2026-09-09).
- **`~/.cursor/{skills,commands,agents}` fully self-sufficient (cross-provider quarantine proof, 2026-09-09):**
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
   prefix** — always present, never inferred — then apply the availability gate + route
   (`pw-config.sh model-resolve` → canonical id or hard stop; task `Route:` > PLAN `- Routing:` >
   `PW_ROUTE_DEFAULT` > `auto`, values `auto|subagent|headless` — full ladder:
   `tooling/skill/project-workflow/references/execution-and-routing.md`).
   Scope note: `model-check`/`model-resolve` are deliberately **global, slug-less validators**
   (they answer machine-level questions); per-project settings live behind `pw-config.sh project …`
   and delegate here rather than duplicating the check.
2. **Same provider** as the orchestrator → spawn a normal in-process **sub-agent** (the usual path):
   `pw-executor`, another same-provider agent, or a bare model. Sub-agents are same-provider only.
   Where the CLI can't bind the row's model in-session (kilo), run on the parent model and record
   `model-degraded <row>→<used>` — unless `Route: headless` demands strict binding.
3. **Different provider** → read that provider's `<name>_headless()` hook output, and invoke its
   **CLI headlessly** per that template, passing the *task file* as the work order to its
   **default/primary** agent, on the **canonical catalog id** `model-resolve` printed. Resume an
   existing session first iff `pw-session.sh session-check` reports the recorded id live. Every
   headless run is supervised to a terminal state (ladder §Headless supervision — `success`/`failed`/`stalled`,
   stall/timeout budgets, no run-end with a live child). You **cannot** name the other provider's
   *sub-agent* here (e.g. a Claude orchestrator can't use kilo's `pw-executor` sub-agent) —
   sub-agents don't cross a provider boundary; only a provider's own primary agents are invocable
   from outside, and a lone task just needs the default agent + task file. The discipline travels
   with the task, not the provider — the other CLI still follows the `project-workflow` skill + the
   task file.
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
[§Registering a new Agent Provider](#registering-a-new-agent-provider-hook-contract) above (needed
once, regardless of whether you ever add a `_headless()` hook).

## Verification notes (historical)

Provenance for the operational rules stated above — kept for reference and future debugging, not
required reading to just use this mechanism. **This section is the dated record owner** for the
cross-provider gotchas (stdin-vs-argument vanish, `--auto`, JetBrains-vs-CLI worktree
auto-approve, display-name-vs-id, nested-BYOK/exact-first): the user-facing known-issues page was
retired 2026-09-25 — settled records live with the mechanism that owns them (D2 routing,
[`conventions.md`](./conventions.md) D-rules); user-reachable symptoms stay in
[`docs/TROUBLESHOOTING.md`](../../docs/TROUBLESHOOTING.md).

**Built-in headless hooks** — verified 2026-08-04 against the installed CLIs.

**Cursor CLI, verified end-to-end 2026-09-09** (probes bundled with the Cursor onboarding;
kilo→cursor pairing
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
