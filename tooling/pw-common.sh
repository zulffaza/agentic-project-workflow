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

# --- built-in provider hooks (a function defined in pw.config.sh overrides these) ---
declare -f claude_bin      >/dev/null 2>&1 || claude_bin()      { echo claude; }
declare -f claude_skilldir >/dev/null 2>&1 || claude_skilldir() { echo "$HOME/.claude/skills"; }
declare -f claude_outdir   >/dev/null 2>&1 || claude_outdir()   { echo "$HOME/.claude/commands"; }
declare -f render_claude   >/dev/null 2>&1 || render_claude() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}

declare -f kilo_bin      >/dev/null 2>&1 || kilo_bin()      { echo kilo; }
declare -f kilo_skilldir >/dev/null 2>&1 || kilo_skilldir() { echo "$HOME/.kilocode/skills"; }
declare -f kilo_outdir   >/dev/null 2>&1 || kilo_outdir()   { echo "$HOME/.config/kilo/command"; }
declare -f render_kilo   >/dev/null 2>&1 || render_kilo() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}

# has_hooks <provider> -> 0 if the four generation/detection hooks exist
pw_provider_has_hooks() {
  local p="$1" fn
  for fn in "${p}_bin" "${p}_skilldir" "${p}_outdir" "render_${p}"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  return 0
}
