# shellcheck shell=bash
# ============================================================================
# pw-common.sh — shared plumbing sourced by bootstrap.sh, gen-commands.sh, pw-doctor.sh.
#
# The caller sets PW_HOME first; this loads pw.config.sh and defines the built-in
# provider hooks (config-defined functions always win). Single source of provider
# truth, so the three scripts can never disagree about a provider's dirs/binary.
# ============================================================================
: "${PW_HOME:?pw-common.sh: PW_HOME must be set before sourcing}"
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"

# --- local config (enabled providers + optional overrides) -------------------
if   [ -f "$PW_HOME/pw.config.sh" ];         then . "$PW_HOME/pw.config.sh"
elif [ -f "$PW_HOME/pw.config.example.sh" ]; then . "$PW_HOME/pw.config.example.sh"
fi
# PW_PROVIDERS = your Agent Providers (the AI-agent CLI(s) you actually run: claude, kilo,
# opencode, cursor, … — see "built-in vs enabled" below). Default when unset: claude only.
declare -p PW_PROVIDERS >/dev/null 2>&1 || PW_PROVIDERS=(claude)

# Forge host overrides (see tooling/docs/forges.md) — default to empty (pure auto-detect) so a
# pw.config.sh that predates this var (or the example file) never trips `set -u` on `${#…[@]}`.
declare -p PW_FORGE_HOSTS >/dev/null 2>&1 || PW_FORGE_HOSTS=()

# RFC backend (see tooling/docs/rfc.md) — default "markdown" (zero-dependency) so an unconfigured
# pw.config.sh still runs /pw-rfc; a scalar var, so ${PW_RFC_BACKEND:-markdown} alone would be
# enough under set -u, but set it here too so every script sees the same resolved value.
: "${PW_RFC_BACKEND:=markdown}"

# Self-repair cap for the §3.5 in-run executor loop (opt-in clean mode): how many fix-and-
# re-verify rounds an executor may take on its own regression before declaring verify-failed.
# Mirrors today's ship-loop constant (`docs/WORKFLOW.md`: build fixes "up to 3 rounds"). Only a
# *floor/default* here — the per-project choice lives in PLAN's `- AI execution limit:` bullet,
# which wins over this env value. Default 3.
: "${PW_MAX_SELF_REPAIR:=3}"

# Model allowlist (see docs/EXECUTION.md's "Model allowlist" section) — one optional scalar per
# Agent Provider, a comma-separated list of glob patterns. THE RULE: empty/unset = ALL models
# allowed for that provider — the default, deliberately, so nothing is restricted unless you set
# a pattern yourself. Defaulted here (not just at point of use) so every script — including
# pw-doctor.sh's informational availability check — sees the same resolved value under `set -u`.
: "${PW_MODEL_ALLOWLIST_CLAUDE:=}"
: "${PW_MODEL_ALLOWLIST_KILO:=}"
: "${PW_MODEL_ALLOWLIST_OPENCODE:=}"
: "${PW_MODEL_ALLOWLIST_CURSOR:=}"

# Cursor — its own single gateway (api2.cursor.sh); no PW_CURSOR_API_PROVIDERS axis (the
# API-Provider concept doesn't apply to it). Model ids: `agent models` (200+ entries incl.
# per-variant ids and [param=…] syntax); `cursor:<id>` is the explicit-prefix form in tasks.
# --- Agent Provider vs API Provider — two different axes, don't conflate them ---------------
#   Agent Provider = PW_PROVIDERS above: the CLI you actually run (claude, kilo, opencode,
#                      cursor, …).
#   API Provider    = which model backend a given Agent Provider talks to underneath. Only kilo
#                      needs this today — it can route to several backends at once (command_code,
#                      openrouter, …) — hence PW_KILO_API_PROVIDERS below, scoped to kilo alone.
# (Informational — used in docs + task `Execute with:` routing, not consumed mechanically by
# these scripts.) PW_KILO_PROVIDERS (array) and PW_KILO_PROVIDER (singular) are the old names —
# folded in here for back-compat if a pw.config.sh still uses them. Prefer PW_KILO_API_PROVIDERS.
if ! declare -p PW_KILO_API_PROVIDERS >/dev/null 2>&1; then
  if declare -p PW_KILO_PROVIDERS >/dev/null 2>&1; then
    PW_KILO_API_PROVIDERS=("${PW_KILO_PROVIDERS[@]}")
  elif [ -n "${PW_KILO_API_PROVIDER:-}" ]; then
    PW_KILO_API_PROVIDERS=("$PW_KILO_API_PROVIDER")
  elif [ -n "${PW_KILO_PROVIDER:-}" ]; then
    PW_KILO_API_PROVIDERS=("$PW_KILO_PROVIDER")
  else
    PW_KILO_API_PROVIDERS=()
  fi
fi

# --- built-in provider hooks (a function defined in pw.config.sh overrides these) ---
# Each Agent Provider needs the four REQUIRED hooks (bin/skilldir/commanddir/
# render_*_command; cursor adds cursor_* to the family), plus the optional agent-seeding
# pair (agentdir/render_*_agent) and headless template (<prov>_headless). See ONBOARDING.md's
# "Register a new provider" for the full contract — including exactly which variables each
# render_* hook receives — before writing a new one from scratch.
declare -f claude_bin        >/dev/null 2>&1 || claude_bin()        { echo claude; }
declare -f claude_skilldir   >/dev/null 2>&1 || claude_skilldir()   { echo "$HOME/.claude/skills"; }
declare -f claude_commanddir >/dev/null 2>&1 || claude_commanddir() { echo "$HOME/.claude/commands"; }
declare -f claude_agentdir   >/dev/null 2>&1 || claude_agentdir()   { echo "$HOME/.claude/agents"; }
# render_<prov>_command: gen-commands.sh sets $desc $args $agent $bodytext (from the canonical
# tooling/commands/*.md file) before calling this — print the finished command file to stdout.
declare -f render_claude_command >/dev/null 2>&1 || render_claude_command() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
# render_<prov>_agent: gen-agents.sh sets $agentname (basename) $desc $displayName $role
# $claude_tools $model $bodytext (from the canonical tooling/agents/*.md file) before calling
# this — print the finished agent file to stdout, wrapping $bodytext in this provider's frontmatter.
declare -f render_claude_agent >/dev/null 2>&1 || render_claude_agent() {
  printf -- '---\nname: %s\ndescription: %s\n' "$agentname" "$desc"
  [ -n "$claude_tools" ] && printf -- 'tools: %s\n' "$claude_tools"
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  printf -- '---\n%s' "$bodytext"
}
# <prov>_headless: OPTIONAL. Prints the exact headless (non-interactive) invocation template for
# this Agent Provider's CLI, for the orchestrator to read and adapt when routing a task to a
# DIFFERENT provider than its own (cross-provider execution — see tooling/docs/providers.md).
# Same-provider execution (spawning a normal in-process sub-agent) never calls this at all.
declare -f claude_headless >/dev/null 2>&1 || claude_headless() {
  cat <<'EOF'
claude --print --dangerously-skip-permissions --model <model> [--effort <low|medium|high|xhigh|max>]
Pipe the prompt via STDIN, never a trailing argument — printf '%s' "$PROMPT" | claude ...
(a long inline argument can vanish entirely across a shell-out boundary; stdin is immune).
--dangerously-skip-permissions is REQUIRED headless — without it a permission prompt has no TTY
to answer and the process hangs producing no output.
EOF
}

declare -f kilo_bin        >/dev/null 2>&1 || kilo_bin()        { echo kilo; }
declare -f kilo_skilldir   >/dev/null 2>&1 || kilo_skilldir()   { echo "$HOME/.kilocode/skills"; }
declare -f kilo_commanddir >/dev/null 2>&1 || kilo_commanddir() { echo "$HOME/.config/kilo/command"; }
declare -f kilo_agentdir   >/dev/null 2>&1 || kilo_agentdir()   { echo "$HOME/.config/kilo/agent"; }
declare -f render_kilo_command >/dev/null 2>&1 || render_kilo_command() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_kilo_agent >/dev/null 2>&1 || render_kilo_agent() {  local mode="subagent"; [ "$role" = "orchestrator" ] && mode="primary"
  printf -- '---\nmode: %s\ndescription: %s\n' "$mode" "$desc"
  # A canonical `model:` now renders through to kilo as well (verified 2026-09-04 with a probe md:
  # an `agent/*.md` file with `mode:`+`options:` registers without any kilo.jsonc map block, and a
  # `model:` line in that md binds the agent — outranking a map block for the same name if both
  # carry one). Bundle defs still ship `model:` UNSET (provider ids in canonical files are false
  # pins across providers; docs/EXECUTION.md §Spawning phase work). If a user mirror exists in
  # kilo.jsonc and sets a different model, the md wins here — pw-doctor's drift check reports it.
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  printf -- 'options:\n  displayName: %s\n  id: %s\n' "${displayName:-$agentname}" "$agentname"
  printf -- 'permission:\n  read: allow\n'
  # Do not put a worktree edit denial on the orchestrator session. Kilo propagates
  # session permissions to child agents, which would prevent implementation agents
  # from editing their assigned worktrees. The orchestrator's no-source-edit rule
  # is enforced by its prompt and workflow instructions instead.
  printf -- '  edit:\n    "*": allow\n'
  printf -- '  bash: allow\n  grep: allow\n  glob: allow\n  task: allow\n  skill: allow\n'
  printf -- '---\n%s' "$bodytext"
}
declare -f kilo_headless >/dev/null 2>&1 || kilo_headless() {
  cat <<'EOF'
kilo run --auto -m <api-provider>/<model> "<prompt>" --dir <path> [--variant <low|medium|high|max|minimal>] [--thinking] [--format json]
--auto is REQUIRED headless — without it kilo run auto-REJECTS every permission (it can't even
read the task file). Add --agent <name> when targeting a native agent instead of a bare model.
<api-provider> is one of PW_KILO_API_PROVIDERS (pw.config.sh) — e.g. kilo, command_code, openrouter.
EOF
}

declare -f opencode_bin        >/dev/null 2>&1 || opencode_bin()        { echo opencode; }
declare -f opencode_skilldir   >/dev/null 2>&1 || opencode_skilldir()   { echo "$HOME/.config/opencode/skills"; }
declare -f opencode_commanddir >/dev/null 2>&1 || opencode_commanddir() { echo "$HOME/.config/opencode/commands"; }
declare -f opencode_agentdir   >/dev/null 2>&1 || opencode_agentdir()   { echo "$HOME/.config/opencode/agents"; }
declare -f render_opencode_command >/dev/null 2>&1 || render_opencode_command() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_opencode_agent >/dev/null 2>&1 || render_opencode_agent() {
  local mode="subagent"; [ "$role" = "orchestrator" ] && mode="primary"
  printf -- '---\ndescription: %s\nmode: %s\n' "$desc" "$mode"
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  # Same defensive stance as render_kilo_agent: never deny the orchestrator worktree edits.
  # Unconfirmed whether OpenCode propagates session permissions to spawned sub-agents the way
  # Kilo does, but a blanket allow here costs nothing and sidesteps the same bug if it does.
  printf -- 'permission:\n  edit: allow\n  bash: allow\n  read: allow\n'
  printf -- '---\n%s' "$bodytext"
}
declare -f opencode_headless >/dev/null 2>&1 || opencode_headless() {
  cat <<'EOF'
opencode run --auto -m <api-provider>/<model> "<prompt>" [--format json] [--attach <url>]
--auto is REQUIRED headless — auto-approves permissions not explicitly denied.
--attach <url> connects to an already-running server, avoiding a cold-boot delay.
EOF
}

# --- Cursor CLI (.cursor) — native surfaces, verified against the installed CLI on
# 2026-09-09. Provider-independence (D9): everything below installs ONLY under ~/.cursor;
# Cursor's vendor compat read of ~/.claude/* is never a dependency (pw-doctor flags it as
# informational bleed). Hooks/generators never touch ~/.cursor/cli-config.json — the
# generator-never-writes-user-config rule spans kilo.jsonc AND cli-config.json.
declare -f cursor_bin        >/dev/null 2>&1 || cursor_bin()        { echo agent; }
declare -f cursor_skilldir   >/dev/null 2>&1 || cursor_skilldir()   { echo "$HOME/.cursor/skills"; }   # never skills-cursor/ (Cursor's own built-ins)
declare -f cursor_commanddir >/dev/null 2>&1 || cursor_commanddir() { echo "$HOME/.cursor/commands"; }
declare -f cursor_agentdir   >/dev/null 2>&1 || cursor_agentdir()   { echo "$HOME/.cursor/agents"; }
declare -f render_cursor_command >/dev/null 2>&1 || render_cursor_command() {
  # Command name derives from the FILENAME (pw-status.md -> /pw-status); `agent:` is Kilo-only
  # sugar and has no cursor equivalent — omitted (inline lane-persona bodies self-execute).
  # $ARGUMENTS + positional $1..$n expansion and `argument-hint` verified in the CLI bundle.
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_cursor_agent >/dev/null 2>&1 || render_cursor_agent() {
  # No `mode:`/primary slot on Cursor (Claude-code class; Flow B main-session orchestration +
  # Flow C direct-spawn, see docs/EXECUTION.md). Spawn permission is ambient — no tools: key;
  # $claude_tools intentionally ignored here. `model:` passes through when set (verified
  # accepted + nested spawn still works 2026-09-09); canonical defs ship it unset (false-pin
  # rule — docs/EXECUTION.md §Spawning phase work).
  printf -- '---\nname: %s\ndescription: %s\n' "$agentname" "$desc"
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  printf -- '---\n%s' "$bodytext"
}
declare -f cursor_headless >/dev/null 2>&1 || cursor_headless() {
  cat <<'EOF'
agent -p --force [--trust] --model <model-id> [--resume <session_id>] [--workspace <path>]
Pipe the prompt via STDIN as a plain redirect — printf '%s' "$PROMPT" | agent -p ... ; do NOT pass
`-` as the prompt (it is sent literally, verified 2026-09-09). --force is REQUIRED headless (alias
--yolo; without it tool approvals have no TTY). --trust clears the untrusted-folder gate.
--output-format json emits ONE final event: {result, session_id, is_error, usage} — the session_id
resumes with --resume (live round-trip verified 2026-09-09). Blocked/gated models exit non-zero
with "ActionRequiredError" text (no JSON event) — treat unparsable output as an error, never blank
success. Model ids from `agent models` (per-variant ids, e.g. claude-opus-5-thinking-xhigh; bracket
params like '[context=1m,effort=high]' also accepted). --workspace targets a tree different from
the invocation cwd (verified).
EOF
}

# has_hooks <provider> -> 0 if the four REQUIRED hooks exist (bin/skilldir/commanddir/render_*_command)
pw_provider_has_hooks() {
  local p="$1" fn
  for fn in "${p}_bin" "${p}_skilldir" "${p}_commanddir" "render_${p}_command"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  return 0
}

# has_agent_hooks <provider> -> 0 if the two OPTIONAL agent-seeding hooks exist
pw_provider_has_agent_hooks() {
  local p="$1" fn
  for fn in "${p}_agentdir" "render_${p}_agent"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  return 0
}

# has_headless_hook <provider> -> 0 if the OPTIONAL cross-provider-execution hook exists. Without
# it, a provider is still fully usable same-provider; it just can't be a cross-provider target.
pw_provider_has_headless_hook() {
  declare -f "${1}_headless" >/dev/null 2>&1
}

# pw_usage — print the invoking script's own header comment (its usage block) and exit 0.
# Every automation script routes -h/--help here so help works uniformly everywhere,
# including scripts whose positional args would otherwise mistake "-h" for a slug.
pw_usage() {
  grep '^#' "$0" | grep -v '^#!' | sed -E 's/^# =+$/====/; s/^# ?//'
  exit 0
}
