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
declare -p PW_PROVIDERS >/dev/null 2>&1 || PW_PROVIDERS=(claude kilo)

# Forge host overrides (see tooling/forges.md) — default to empty (pure auto-detect) so a
# pw.config.sh that predates this var (or the example file) never trips `set -u` on `${#…[@]}`.
declare -p PW_FORGE_HOSTS >/dev/null 2>&1 || PW_FORGE_HOSTS=()

# RFC backend (see tooling/rfc.md) — default "markdown" (zero-dependency) so an unconfigured
# pw.config.sh still runs /pw-rfc; a scalar var, so ${PW_RFC_BACKEND:-markdown} alone would be
# enough under set -u, but set it here too so every script sees the same resolved value.
: "${PW_RFC_BACKEND:=markdown}"

# KiloCode model providers: prefer the array PW_KILO_PROVIDERS; fold in the legacy
# singular PW_KILO_PROVIDER for back-compat. (Informational — used in docs + task
# `Execute with:` routing, not consumed mechanically by these scripts.)
if ! declare -p PW_KILO_PROVIDERS >/dev/null 2>&1; then
  if [ -n "${PW_KILO_PROVIDER:-}" ]; then PW_KILO_PROVIDERS=("$PW_KILO_PROVIDER"); else PW_KILO_PROVIDERS=(); fi
fi

# --- built-in provider hooks (a function defined in pw.config.sh overrides these) ---
declare -f claude_bin      >/dev/null 2>&1 || claude_bin()      { echo claude; }
declare -f claude_skilldir >/dev/null 2>&1 || claude_skilldir() { echo "$HOME/.claude/skills"; }
declare -f claude_outdir   >/dev/null 2>&1 || claude_outdir()   { echo "$HOME/.claude/commands"; }
declare -f claude_agentdir >/dev/null 2>&1 || claude_agentdir() { echo "$HOME/.claude/agents"; }
declare -f render_claude   >/dev/null 2>&1 || render_claude() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
# render_<prov>_agent: wrap a canonical agent body (in $bodytext) in this provider's frontmatter.
# gen-agents.sh sets: $agentname (basename) $desc $displayName $role $claude_tools $model $bodytext
declare -f render_claude_agent >/dev/null 2>&1 || render_claude_agent() {
  printf -- '---\nname: %s\ndescription: %s\n' "$agentname" "$desc"
  [ -n "$claude_tools" ] && printf -- 'tools: %s\n' "$claude_tools"
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  printf -- '---\n%s' "$bodytext"
}

declare -f kilo_bin      >/dev/null 2>&1 || kilo_bin()      { echo kilo; }
declare -f kilo_skilldir >/dev/null 2>&1 || kilo_skilldir() { echo "$HOME/.kilocode/skills"; }
declare -f kilo_outdir   >/dev/null 2>&1 || kilo_outdir()   { echo "$HOME/.config/kilo/command"; }
declare -f kilo_agentdir >/dev/null 2>&1 || kilo_agentdir() { echo "$HOME/.config/kilo/agent"; }
declare -f render_kilo   >/dev/null 2>&1 || render_kilo() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_kilo_agent >/dev/null 2>&1 || render_kilo_agent() {
  local mode="subagent"; [ "$role" = "orchestrator" ] && mode="primary"
  printf -- '---\nmode: %s\ndescription: %s\n' "$mode" "$desc"
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

# has_hooks <provider> -> 0 if the four command generation/detection hooks exist
pw_provider_has_hooks() {
  local p="$1" fn
  for fn in "${p}_bin" "${p}_skilldir" "${p}_outdir" "render_${p}"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  return 0
}

# has_agent_hooks <provider> -> 0 if the two agent-seeding hooks exist
pw_provider_has_agent_hooks() {
  local p="$1" fn
  for fn in "${p}_agentdir" "render_${p}_agent"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  return 0
}
