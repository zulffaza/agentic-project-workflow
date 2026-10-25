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
# PW_CONFIG_FILE lets a test (or a second machine profile) point at an alternate config
# without moving PW_HOME — same shape as PW_PROJECTS_DIR. Default: the bundle's pw.config.sh.
if   [ -f "${PW_CONFIG_FILE:-$PW_HOME/pw.config.sh}" ]; then . "${PW_CONFIG_FILE:-$PW_HOME/pw.config.sh}"
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

# Request-review frame file (see tooling/docs/scripts/ship-and-sync.md): the human-owned
# outer message frame for /pw-ship request-review --project <slug>. Unset resolves the default under
# $PW_HOME/user/templates/ (the pre-2026-10 legacy location user-templates/ migrates through
# the doctor); a relative configured path resolves against $PW_HOME so the effective file
# never depends on the current working directory. Never source the file.
: "${PW_REVIEW_REQUEST_TEMPLATE_FILE:=}"

# Request-review generation prompts (see tooling/docs/scripts/ship-and-sync.md): editable
# writing instructions for the optional --summary/--mr-summary and --note prose. Unset or
# empty resolves the default under $PW_HOME/user/prompts/; a relative configured path
# resolves against $PW_HOME. Read as UTF-8 text on every generation pass; never sourced,
# executed, or shell-expanded. AI flags enable generation independently of these settings.
: "${PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE:=}"
: "${PW_REVIEW_REQUEST_NOTE_PROMPT_FILE:=}"

# Self-repair cap for the §3.5 in-run executor loop (opt-in clean mode): how many fix-and-
# re-verify rounds an executor may take on its own regression before declaring verify-failed.
# Mirrors today's ship-loop constant (`docs/WORKFLOW.md`: build fixes "up to 3 rounds"). Only a
# *floor/default* here — the per-project choice lives in PLAN's `- AI execution limit:` bullet,
# which wins over this env value. Default 3.
: "${PW_MAX_SELF_REPAIR:=3}"

# --- Global project-setting defaults ---------------------------------------------------------
# Values written by `/pw-config global set` and copied into a NEW project's dashboard. They are
# creation-time defaults, never live inheritance: an existing project keeps its captured values.
# Empty means "use the compatibility fallback" (the matching floor or built-in default).
: "${PW_PROJECT_DEFAULT_ROUTING:=}"
: "${PW_PROJECT_DEFAULT_EXECUTION_LIMIT:=}"
: "${PW_PROJECT_DEFAULT_MAX_PARALLEL:=}"
: "${PW_PROJECT_DEFAULT_REVIEW_TRIGGER:=}"
: "${PW_PROJECT_DEFAULT_REVIEW_REPAIR:=}"
: "${PW_PROJECT_DEFAULT_REVIEW_ROUNDS:=}"
: "${PW_PROJECT_DEFAULT_AI_REVIEW:=}"

# Role model defaults + optional tuning. Tuning is stored per role so a binding keeps its
# variant/reasoning/effort when it is copied into a project.
PW_PROJECT_AI_MODEL_ROLES="researcher analyst writer-task reviewer verifier ship-comment-analyst"
for _pw_role in $PW_PROJECT_AI_MODEL_ROLES; do
  _pw_ru="$(printf '%s' "$_pw_role" | tr '[:lower:]-' '[:upper:]_')"
  for _pw_axis in MODEL VARIANT REASONING EFFORT; do
    _pw_var="PW_PROJECT_DEFAULT_AI_MODEL_${_pw_ru}_${_pw_axis}"
    if ! declare -p "$_pw_var" >/dev/null 2>&1; then printf -v "$_pw_var" '%s' ""; fi
  done
done
unset _pw_role _pw_ru _pw_axis _pw_var

# Resolve one global project default with its compatibility fallback.
#   pw_project_default_value <routing|execution-limit|max-parallel|review-rounds>
pw_project_default_value() {
  case "$1" in
    routing)         printf '%s' "${PW_PROJECT_DEFAULT_ROUTING:-$PW_ROUTE_DEFAULT}" ;;
    execution-limit) printf '%s' "${PW_PROJECT_DEFAULT_EXECUTION_LIMIT:-$PW_MAX_SELF_REPAIR}" ;;
    max-parallel)    printf '%s' "${PW_PROJECT_DEFAULT_MAX_PARALLEL:-}" ;;
    review-rounds)   printf '%s' "${PW_PROJECT_DEFAULT_REVIEW_ROUNDS:-3}" ;;
    *) return 1 ;;
  esac
}

# Resolve a per-role model default and its tuning fields (empty tuning = provider default).
#   pw_project_default_role <role> -> model
#   pw_project_default_tuning <role> -> variant=<v>,reasoning=<r>,effort=<e> (empty fields omitted)
pw_project_default_role() {
  local u; u="$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
  local v="PW_PROJECT_DEFAULT_AI_MODEL_${u}_MODEL"
  local legacy="PW_AI_MODEL_DEFAULT_${u}"
  if [ -n "${!v:-}" ]; then printf '%s' "${!v}"; else printf '%s' "${!legacy:-—}"; fi
}
pw_project_default_tuning() {
  local u; u="$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
  local out="" axis var
  for axis in VARIANT REASONING EFFORT; do
    var="PW_PROJECT_DEFAULT_AI_MODEL_${u}_${axis}"
    [ -n "${!var:-}" ] || continue
    [ -n "$out" ] && out="$out,"
    out="$out$(printf '%s' "$axis" | tr '[:upper:]' '[:lower:]'):${!var}"
  done
  printf '%s' "$out"
}

# Model allowlist (see docs/EXECUTION.md's "Model allowlist" section) — one optional scalar per
# Agent Provider, a comma-separated list of glob patterns. THE RULE: empty/unset = ALL models
# allowed for that provider — the default, deliberately, so nothing is restricted unless you set
# a pattern yourself. Defaulted here (not just at point of use) so every script — including
# pw-doctor.sh's informational availability check — sees the same resolved value under `set -u`.
: "${PW_MODEL_ALLOWLIST_CLAUDE:=}"
: "${PW_MODEL_ALLOWLIST_KILO:=}"
: "${PW_MODEL_ALLOWLIST_OPENCODE:=}"
: "${PW_MODEL_ALLOWLIST_CURSOR:=}"
: "${PW_MODEL_ALLOWLIST_CODEX:=}"

# Cursor — its own single gateway (api2.cursor.sh); no PW_CURSOR_API_PROVIDERS axis (the
# API-Provider concept doesn't apply to it). Model ids: `agent models` (200+ entries incl.
# per-variant ids and [param=…] syntax) PLUS the ids in ~/.cursor/cli-config.json →
# `modelParameters` (desktop-only ids such as glm-5p3-flash are absent from `agent models`,
# verified 2026-10-22). That file is CLI-owned — written on first run, so no desktop install is
# required; a missing file just means one source fewer. `cursor:<id>` is the explicit-prefix
# form in tasks; `<id>[reasoning=low]` tunes a parameterized model.
# Codex — same single-gateway shape (ChatGPT auth); no PW_CODEX_API_PROVIDERS axis. Model ids
# are BARE SLUGS from `codex debug models` (no effort/variant/fast suffixes — reasoning effort
# and the Fast service tier are per-run flags, not id segments); `codex:<slug>` in tasks.
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

# Routing default (plan-22 ladder): task `Route:` field > PLAN `- Routing:` line > this value >
# auto. Values: auto | subagent | headless (strict model binding, resume-first internally).
# Headless supervision budgets (§3.7): kill a child whose log has not grown for PW_HEADLESS_STALL
# minutes, and cap any single headless spawn at PW_HEADLESS_TIMEOUT minutes.
: "${PW_ROUTE_DEFAULT:=auto}"
: "${PW_HEADLESS_STALL:=10}"
: "${PW_HEADLESS_TIMEOUT:=90}"

# --- API-provider scope helpers (plan-22 §3.5) ------------------------------------------
# A PW_<PROVIDER>_API_PROVIDERS entry is a MODEL-ID PREFIX FILTER, not a provider-list
# argument: entries may contain any number of slashes (`kilo`, `kilo/alibaba-token-plan`,
# `command_code`, `openrouter` all valid) because nested BYOK models are listed by the CLI
# catalogs as full ids WITH slashes (`kilo models` prints `kilo/alibaba-token-plan/<m>`),
# while `kilo models kilo/alibaba-token-plan` errors ("Provider not found" — verified
# 2026-09-22). Empty/unset array = full catalog (no filtering). Providers without the axis
# (claude: no catalog; cursor: one gateway) simply have no entries defined.
pw_api_entries() {  # <agent-provider> -> one entry per line (nothing when no scope is set)
  local upper var _n _i
  # Charset gate at the sink: the provider token becomes a variable NAME below, and an
  # unchecked token (`kilo[$(cmd)]`, backticks) would reach eval/declare as program text.
  # Invalid -> same empty result as an unknown provider; callers see "no scope set".
  case "${1:-}" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  var="PW_${upper}_API_PROVIDERS"
  declare -p "$var" >/dev/null 2>&1 || return 0
  eval "_n=\${#$var[@]}" 2>/dev/null || _n=0
  [ "${_n:-0}" -gt 0 ] || return 0
  for _i in $(seq 0 $((_n - 1))); do eval "printf '%s\n' \"\${$var[$_i]}\""; done
  return 0
}

pw_api_bin() {  # <agent-provider> -> its CLI binary name (hook-resolved), or the provider name
  local prov="$1"
  declare -f "${prov}_bin" >/dev/null 2>&1 && { "${prov}_bin"; return 0; }
  printf '%s\n' "$prov"
}

# --- Cursor model sources: CLI catalog, desktop config, opt-in live probe ------------------
# `agent models` is NOT the complete Cursor model set (verified 2026-10-22): the desktop app
# exposes ids the CLI catalog omits. On the maintainer machine `agent models` listed only
# glm-5.2 while the desktop offered glm-5.3 flash as `glm-5p3-flash`; the id is a key in
# ~/.cursor/cli-config.json → modelParameters and runs fine through `agent -p`. Read that file
# as a second source. A live probe is the third source — one real model call, therefore opt-in
# (PW_CURSOR_PROBE=1 or `model-resolve --probe`), never a default in preflight paths.
# cli-config.json is app/user-owned: this bundle only READS it, never writes it.
: "${PW_CURSOR_CLI_CONFIG:=$HOME/.cursor/cli-config.json}"
: "${PW_CURSOR_PROBE_TIMEOUT:=90}"
: "${PW_CURSOR_PROBE:=0}"

pw_cursor_cli_models() {  # -> ids from `agent models` (header + description tail stripped)
  local bin; bin="$(pw_api_bin cursor)"
  command -v "$bin" >/dev/null 2>&1 || return 0
  # Real shape: "Available models" header, a blank line, then "<id> - <description>" rows.
  # Drop the header/blank lines and the tail so consumers match ids, never descriptions.
  "$bin" models 2>/dev/null | sed -e '/^Available models$/d' -e 's/ - .*//' | awk 'NF' || true
}

pw_cursor_config_models() {  # -> ids from cli-config modelParameters (+ model/selectedModel ids)
  [ -f "$PW_CURSOR_CLI_CONFIG" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$PW_CURSOR_CLI_CONFIG" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(0)
ids = []
mp = d.get("modelParameters")
if isinstance(mp, dict):
    ids.extend(mp.keys())
for key in ("model", "selectedModel"):
    v = d.get(key)
    if isinstance(v, dict) and isinstance(v.get("modelId"), str):
        ids.append(v["modelId"])
hist = d.get("modelSelectionHistory")
if isinstance(hist, list):
    ids.extend(i for i in hist if isinstance(i, str))
v = d.get("exploreSubagentModel")
if isinstance(v, str):
    ids.append(v)
for mid in dict.fromkeys(ids):
    if mid and mid != "default":
        print(mid)
PY
}

pw_cursor_probe_model() {  # <model-id> -> 0 when a one-shot headless ask gets a reply
  local bin out rc=0
  case "${1:-}" in ''|-*) return 1 ;; esac
  bin="$(pw_api_bin cursor)"
  command -v "$bin" >/dev/null 2>&1 || return 1
  # --mode ask keeps the probe tool-free; --trust clears the per-folder gate. The prompt rides
  # stdin (the documented cursor shape); the id is one quoted argv value, never eval'd.
  if command -v timeout >/dev/null 2>&1; then
    out="$(printf 'Reply with OK' | timeout "$PW_CURSOR_PROBE_TIMEOUT" "$bin" -p --trust --mode ask --model "$1" 2>&1)" || rc=$?
  else
    out="$(printf 'Reply with OK' | "$bin" -p --trust --mode ask --model "$1" 2>&1)" || rc=$?
  fi
  [ "$rc" -eq 0 ] || return "$rc"
  case "$out" in
    *"Cannot use this model"*|*"ActionRequiredError"*|*"Workspace Trust Required"*) return 1 ;;
  esac
  return 0
}

pw_api_catalog() {  # <agent-provider> -> live catalog lines (provider prefix included), nothing on failure
  local prov="$1" bin
  case "$prov" in
    kilo|opencode|cursor)
      bin="$(pw_api_bin "$prov")"
      command -v "$bin" >/dev/null 2>&1 || return 0
      if [ "$prov" = cursor ]; then
        # Two sources, deduped CLI-first: `agent models` is incomplete — desktop-only ids
        # live as cli-config modelParameters keys (see the Cursor sources block above).
        { pw_cursor_cli_models; pw_cursor_config_models; } | awk 'NF && !seen[$0]++' || true
      else
        # kilo/opencode print bare ids; normalize centrally so every exact-line consumer
        # (model-resolve, provider-audit, the spawn availability gate, doctor allowlist counts)
        # matches ids, not descriptions (corpus 09-28: every cursor pin read false-unbound).
        "$bin" models 2>/dev/null | sed 's/ - .*//' || true
      fi ;;
    codex)
      bin="$(pw_api_bin "$prov")"
      command -v "$bin" >/dev/null 2>&1 || return 0
      # Codex has no `models` subcommand — `codex debug models` prints ONE-LINE JSON
      # {"models":[{…}]}. Split on model-object boundaries (nested objects never start with
      # {"slug"), keep only visibility:"list" rows (hidden slugs like gpt-reserve still RUN
      # silently — verified 2026-10-04 — so the visible catalog + allowlist are the real gate),
      # print bare slugs. Shape pinned by a real-CLI fixture in the T1 suite.
      "$bin" debug models 2>/dev/null \
        | sed 's/{"slug"/\n{"slug"/g' \
        | grep '"visibility":"list"' \
        | sed 's/.*"slug":"\([^"]*\)".*/\1/' || true ;;
  esac
  return 0
}

pw_api_in_scope() {  # <agent-provider> <catalog-line> -> 0 when no scope set or line matches an entry prefix
  local prov="$1" line="$2" e any=0 found=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    any=1
    case "$line" in "$e"*) found=1; break ;; esac
  done <<EOF
$(pw_api_entries "$prov")
EOF
  [ "$any" = 0 ] || [ "$found" = 1 ]
}

pw_api_filter() {  # stdin catalog lines -> keep those in scope for <agent-provider>
  local prov="$1" line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pw_api_in_scope "$prov" "$line" && printf '%s\n' "$line"
  done
  return 0
}

# --- YAML frontmatter safety (strict-parser regression, 2026-10-08) ----------
# Kilo 7.8.8 (js-yaml) made a bad command frontmatter FATAL: a plain (unquoted) value that
# starts with `[` or `{` is parsed as a flow collection — two bracket groups are a parse
# error ("failed to load command"), one bracket group silently becomes an array. Generated
# `argument-hint:` values are exactly that shape, so render hooks MUST quote them; canonical
# `args:` values stay readable unquoted and are quoted here on the way out.
pw_yaml_quote() {  # <value> -> value as a safe single-line YAML scalar (quotes only when needed)
  local v="$1" first needs=0
  case "$v" in
    \"*\"|\'*\') printf '%s' "$v"; return 0 ;;   # already quoted by the canonical author — trust as-is
  esac
  [ -n "$v" ] || { printf '""'; return 0; }
  first="${v:0:1}"
  case "$first" in
    "["|"{"|"&"|"*"|"!"|"%"|"@"|"|"|">"|","|"]"|"}"|"'"|'"'|"#"|"-"|"?"|":") needs=1 ;;
  esac
  case "$v" in
    " "*|*" ") needs=1 ;;
    *": "*|*" #"*) needs=1 ;;
    true|false|yes|no|on|off|null|~|True|False|Yes|No|On|Off|NULL|Null) needs=1 ;;
    *[!0-9.]*) ;;                     # contains a non-numeric char — not a number
    *) needs=1 ;;                     # digits/dots only — parses as a number; keep it a string
  esac
  if [ "$needs" -eq 1 ]; then
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    printf '"%s"' "$v"
  else
    printf '%s' "$v"
  fi
}

pw_frontmatter_error() {  # <file> -> prints the first strict-YAML frontmatter problem (empty = ok)
  # Minimal, dependency-free detector for the classes strict parsers (kilo 7.8.8 js-yaml)
  # reject in flat command frontmatter:
  #   - a plain value starting with a flow indicator `[` / `{` (parse error or array)
  #   - a plain `key: value: rest` (colon-space inside an unquoted value)
  #   - frontmatter opened with `---` but never closed
  # Single-line `key: value` shapes only — that is what the hub/pw generators emit.
  awk '
    BEGIN { started=0; closed=0; pending=0; err="" }
    NR==1 {
      if ($0 != "---") exit
      started=1; next
    }
    started && !closed && $0=="---" { closed=1; exit }
    started && !closed {
      v=$0
      if (v ~ /^[ \t]*$/) next
      if (v ~ /^[ \t]*#/) { pending=0; next }
      if (v ~ /^[ \t]/) {                       # indented continuation of a pending key value
        if (pending && v ~ /^[ \t]*[[{]/) { err="line " NR ": flow indicator on an own-line value (quote it)"; exit }
        pending=0; next
      }
      if (v !~ /^[A-Za-z_][A-Za-z0-9_-]*:/) { pending=0; next }
      val=v; sub(/^[A-Za-z_][A-Za-z0-9_-]*:[ \t]*/, "", val)
      if (val=="") { pending=1; next }
      pending=0
      head=substr(val,1,1)
      if (head=="\"" || head=="\047") next      # quoted — fine
      if (head=="[" || head=="{") { err="line " NR ": plain value starts with a flow indicator (quote it): " val; exit }
      if (val ~ /: / || val ~ /:$/) { err="line " NR ": colon-space in an unquoted value (quote it): " val; exit }
    }
    END { if (err!="") print err; else if (started && !closed) print "frontmatter opened with --- but never closed" }
  ' "$1"
}

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
# entry_format: "skill" = the 19 human entry points install as invocable skills ONLY;
# "command" = they install as native commands ONLY. Never both for one provider.
declare -f claude_entry_format >/dev/null 2>&1 || claude_entry_format() { echo skill; }
# render_<prov>_entry_skill: gen-commands.sh sets $name $desc $args $bodytext before calling
# this — print a human-entry SKILL.md. Explicit-only invocation is mandatory: the human starts
# the operation; the model must not select it on its own.
declare -f render_claude_entry_skill >/dev/null 2>&1 || render_claude_entry_skill() {
  printf -- '---\nname: %s\ndescription: %s\n' "$name" "$(pw_yaml_quote "$desc")"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$(pw_yaml_quote "$args")"
  printf -- 'disable-model-invocation: true\n---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
# render_<prov>_command: gen-commands.sh sets $desc $args $agent $bodytext (from the canonical
# tooling/skills/human/*/SKILL.md file) before calling this — print the finished command file to stdout.
declare -f render_claude_command >/dev/null 2>&1 || render_claude_command() {
  printf -- '---\ndescription: %s\n' "$(pw_yaml_quote "$desc")"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$(pw_yaml_quote "$args")"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
# render_<prov>_agent: gen-agents.sh sets $agentname (basename) $desc $displayName $role
# $claude_tools $model $bodytext (from the canonical tooling/agents/*.md file) before calling
# this — print the finished agent file to stdout, wrapping $bodytext in this provider's frontmatter.
declare -f render_claude_agent >/dev/null 2>&1 || render_claude_agent() {
  printf -- '---\nname: %s\ndescription: %s\n' "$agentname" "$(pw_yaml_quote "$desc")"
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
  printf -- '---\ndescription: %s\n' "$(pw_yaml_quote "$desc")"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_kilo_agent >/dev/null 2>&1 || render_kilo_agent() {
  # Worker sub-agents only: the bundle no longer installs a primary orchestrator agent.
  printf -- '---\nmode: subagent\ndescription: %s\n' "$(pw_yaml_quote "$desc")"
  # A canonical `model:` now renders through to kilo as well (verified 2026-09-04 with a probe md:
  # an `agent/*.md` file with `mode:`+`options:` registers without any kilo.jsonc map block, and a
  # `model:` line in that md binds the agent — outranking a map block for the same name if both
  # carry one). Bundle defs still ship `model:` UNSET (provider ids in canonical files are false
  # pins across providers; docs/EXECUTION.md §Spawning phase work). If a user mirror exists in
  # kilo.jsonc and sets a different model, the md wins here — pw-doctor's drift check reports it.
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  printf -- 'options:\n  displayName: %s\n  id: %s\n' "${displayName:-$agentname}" "$agentname"
  printf -- 'permission:\n  read: allow\n'
  # Never deny worktree edits in a generated worker definition: Kilo propagates session
  # permissions to child agents, which would block an executor inside its own worktree.
  printf -- '  edit:\n    "*": allow\n'
  printf -- '  bash: allow\n  grep: allow\n  glob: allow\n  task: allow\n  skill: allow\n'
  printf -- '---\n%s' "$bodytext"
}
declare -f kilo_headless >/dev/null 2>&1 || kilo_headless() {
  cat <<'EOF'
kilo run --auto -m <canonical-catalog-id> "<prompt>" --dir <path> [--variant <low|medium|high|max|minimal>] [--thinking] [--format json]
NOTE: the prompt rides argv here (visible to `ps` on this host) — keep prompts free of
secrets; the double-quoted single-argument form is still REQUIRED (word-splitting breaks it).
--auto is REQUIRED headless — without it kilo run auto-REJECTS every permission (it can't even
read the task file). Add --agent <name> when targeting a native agent instead of a bare model.
-m receives the CANONICAL catalog id — the exact line `kilo models` prints (resolve it with
`pw-config.sh model-resolve --provider kilo --model <model-id>`). PW_KILO_API_PROVIDERS entries are model-id
PREFIX FILTERS (slashes allowed, e.g. `kilo/alibaba-token-plan` for a nested BYOK), never
`kilo models` arguments — `kilo models kilo/alibaba-token-plan` errors "Provider not found".
EOF
}

declare -f opencode_bin        >/dev/null 2>&1 || opencode_bin()        { echo opencode; }
declare -f opencode_skilldir   >/dev/null 2>&1 || opencode_skilldir()   { echo "$HOME/.config/opencode/skills"; }
declare -f opencode_commanddir >/dev/null 2>&1 || opencode_commanddir() { echo "$HOME/.config/opencode/commands"; }
declare -f opencode_agentdir   >/dev/null 2>&1 || opencode_agentdir()   { echo "$HOME/.config/opencode/agents"; }
declare -f render_opencode_command >/dev/null 2>&1 || render_opencode_command() {
  printf -- '---\ndescription: %s\n' "$(pw_yaml_quote "$desc")"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_opencode_agent >/dev/null 2>&1 || render_opencode_agent() {
  # Worker sub-agents only: no primary orchestrator agent is installed.
  printf -- '---\ndescription: %s\nmode: subagent\n' "$(pw_yaml_quote "$desc")"
  [ -n "$model" ] && printf -- 'model: %s\n' "$model"
  # Same defensive stance as render_kilo_agent: never deny a worker its worktree edits.
  # Unconfirmed whether OpenCode propagates session permissions to spawned sub-agents the way
  # Kilo does, but a blanket allow here costs nothing and sidesteps the same bug if it does.
  printf -- 'permission:\n  edit: allow\n  bash: allow\n  read: allow\n'
  printf -- '---\n%s' "$bodytext"
}
declare -f opencode_headless >/dev/null 2>&1 || opencode_headless() {
  cat <<'EOF'
opencode run --auto -m <canonical-catalog-id> "<prompt>" [--format json] [--attach <url>]
NOTE: the prompt rides argv here (visible to `ps` on this host) — keep prompts free of
secrets; the double-quoted single-argument form is still REQUIRED (word-splitting breaks it).
--auto is REQUIRED headless — auto-approves permissions not explicitly denied.
--attach <url> connects to an already-running server, avoiding a cold-boot delay.
-m receives the CANONICAL id `opencode models` prints (resolve with
`pw-config.sh model-resolve --provider opencode --model <model-id>`); PW_OPENCODE_API_PROVIDERS entries, if set,
are model-id prefix filters — same semantics as the kilo axis.
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
declare -f cursor_entry_format >/dev/null 2>&1 || cursor_entry_format() { echo skill; }
declare -f render_cursor_entry_skill >/dev/null 2>&1 || render_cursor_entry_skill() {
  # Manual-only skill: Cursor's documented command-migration policy. $ARGUMENTS is the documented
  # command-compatibility token; arguments otherwise arrive as the invocation text.
  printf -- '---\nname: %s\ndescription: %s\n' "$name" "$(pw_yaml_quote "$desc")"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$(pw_yaml_quote "$args")"
  printf -- 'disable-model-invocation: true\n---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_cursor_command >/dev/null 2>&1 || render_cursor_command() {
  # Command name derives from the FILENAME (pw-status.md -> /pw-status); `agent:` is Kilo-only
  # sugar and has no cursor equivalent — omitted (inline lane-persona bodies self-execute).
  # $ARGUMENTS + positional $1..$n expansion and `argument-hint` verified in the CLI bundle.
  # Values go through pw_yaml_quote: an unquoted `[...] [...]` argument-hint is a strict-YAML
  # parse error (kilo 7.8.8 regression) / array instead of string.
  printf -- '---\ndescription: %s\n' "$(pw_yaml_quote "$desc")"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$(pw_yaml_quote "$args")"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_cursor_agent >/dev/null 2>&1 || render_cursor_agent() {
  # No `mode:`/primary slot on Cursor (Claude-code class; Flow B main-session orchestration +
  # Flow C direct-spawn, see docs/EXECUTION.md). Spawn permission is ambient — no tools: key;
  # $claude_tools intentionally ignored here. `model:` passes through when set (verified
  # accepted + nested spawn still works 2026-09-09); canonical defs ship it unset (false-pin
  # rule — docs/EXECUTION.md §Spawning phase work).
  printf -- '---\nname: %s\ndescription: %s\n' "$agentname" "$(pw_yaml_quote "$desc")"
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
success. Model ids from `agent models` PLUS ~/.cursor/cli-config.json → modelParameters (the CLI
catalog omits desktop-only ids such as glm-5p3-flash, verified 2026-10-22; per-variant ids, e.g.
claude-opus-5-thinking-xhigh; bracket params like '[context=1m,effort=high]' also accepted).
--workspace targets a tree different from the invocation cwd (verified).
EOF
}

# --- Codex CLI (ChatGPT) — native surfaces verified against the installed build (codex-cli
# 0.160.0 via ChatGPT.app, 2026-10-04). FIRST PROVIDER WITH NO NATIVE COMMAND SURFACE: custom
# prompts (~/.codex/prompts) were removed upstream in 0.117.0 ("convert custom prompts to
# skills"), so /pw-* commands ship AS SKILL DIRS — command_style=skill makes gen-commands.sh
# write <name>/SKILL.md (+ agents/openai.yaml policy) into the skills root instead of flat
# <name>.md files. Skills and commands therefore share ONE namespace on codex: a bundle skill
# whose name collides with a canonical command is SKIPPED at install (pw_skill_skips_for) —
# the generated command-skill owns the name. Codex has no user-facing sub-agent surface
# (`codex agents` browses sessions, not defs) → no agentdir/render_agent hooks: agent seeding
# is skipped and codex drives Flow B (main session orchestrates; inline lane personas).
# Hooks/generators NEVER write ~/.codex/config.toml — app-managed user config (the
# generator-never-writes-user-config rule spans kilo.jsonc, cli-config.json, and config.toml).
declare -f codex_bin        >/dev/null 2>&1 || codex_bin()        { echo codex; }
declare -f codex_skilldir   >/dev/null 2>&1 || codex_skilldir()   { echo "$HOME/.codex/skills"; }
declare -f codex_commanddir >/dev/null 2>&1 || codex_commanddir() { echo "$HOME/.codex/skills"; }  # commands ARE skills on codex
declare -f codex_command_style >/dev/null 2>&1 || codex_command_style() { echo skill; }
declare -f codex_entry_format >/dev/null 2>&1 || codex_entry_format() { echo skill; }
declare -f render_codex_entry_skill >/dev/null 2>&1 || render_codex_entry_skill() {
  # Codex skills have no argument-expansion token: arguments arrive as the invocation text.
  printf -- '---\nname: %s\ndescription: %s\n---\n%s' "$name" "$(pw_yaml_quote "$desc")" "${bodytext//\{\{ARGS\}\}/<arguments>}"
}
declare -f render_codex_skill_policy >/dev/null 2>&1 || render_codex_skill_policy() {
  # agents/openai.yaml — product policy read by the harness, not the model (spec: the built-in
  # skill-creator's references/openai_yaml.md). Explicit-only invocation: the phase-driver bodies
  # must never auto-inject into unrelated turns (parity with the typed /pw-* command UX elsewhere).
  printf 'policy:\n  allow_implicit_invocation: false\n'
}
declare -f codex_headless >/dev/null 2>&1 || codex_headless() {
  cat <<'EOF'
codex exec --dangerously-bypass-approvals-and-sandbox -m <slug> [-c model_reasoning_effort="<low|medium|high|xhigh>"] [-c service_tier="priority"] [-C <worktree-path>] [--json] [-o <last-message-file>]
Pipe the prompt via STDIN — printf '%s' "$PROMPT" | codex exec … ; NEVER pass a task-shaped prompt
as a trailing argument: an 18KB arg degrades the run to exit 0 + "no filesystem tool" + nothing
written (verified 2026-10-04 — stronger than claude's vanish-bug: it exits SUCCESS having done
nothing, so artifact checks, not exit codes, prove the run). Short args are fine; stdin is the rule.
--dangerously-bypass-approvals-and-sandbox is REQUIRED headless (no TTY for approvals). The tighter
--approve-for-me (workspace-write + auto-review, conflicts with -s) also completes headless but
BLOCKS NETWORK — use it only for network-free tasks.
Model ids are BARE catalog slugs (`codex debug models`; resolve with `pw-config.sh model-resolve
codex <id>`). Fast tier = -c service_tier="priority" on the SAME slug — requested tier is NOT
verifiable from output (invalid values are silently ignored), so record the REQUESTED tier in
`Model used:`. Unknown slugs fail loud (ERROR event + exit 1); hidden slugs (gpt-reserve) run
silently — the allowlist/catalog gate is the real control.
Session id for the ledger: --json first event {"type":"thread.started","thread_id":"<uuid>"}.
Resume: cd <worktree> FIRST — `codex exec resume <thread_id>` has NO -C flag and runs in the
invocation cwd: printf '%s' "$PROMPT" | codex exec resume <thread_id>
  --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check -
EOF
}

# entry_format <provider> -> "skill" (human entries install as invocable skills only) or
# "command" (native command files only). Built-in providers declare it explicitly; a custom
# provider inherits its legacy command_style so existing hooks keep working.
pw_provider_entry_format() {
  declare -f "${1}_entry_format" >/dev/null 2>&1 && { "${1}_entry_format"; return 0; }
  [ "$(pw_provider_command_style "$1")" = "skill" ] && { echo skill; return 0; }
  printf 'command\n'
}

# command_style <provider> -> "flat" (default: commands are <name>.md files in commanddir) or
# "skill" (commands are <name>/SKILL.md skill dirs). Kept as the custom-provider compatibility
# and codex-layout hook; human-entry output type is decided by pw_provider_entry_format.
pw_provider_command_style() {
  declare -f "${1}_command_style" >/dev/null 2>&1 && { "${1}_command_style"; return 0; }
  printf 'flat\n'
}

# Canonical human-entry names — one directory per entry under tooling/skills/human/.
pw_canonical_command_names() {
  local d
  for d in "$PW_HOME"/tooling/skills/human/*/; do
    [ -f "${d}SKILL.md" ] || continue
    basename "${d%/}"
  done
}

# Bundle skill names skipped at install. The old collision workaround is retired: human entry
# names and shared guide names are now disjoint (pw-review vs pw-guide-review-method), and each
# entry is emitted in exactly one format. Kept as a no-op for custom hooks that still call it.
pw_skill_skips_for() {
  return 0
}

# has_hooks <provider> -> 0 if the required hooks exist: bin/skilldir/commanddir plus the
# renderer for the provider's selected entry format. Command format needs render_<p>_command;
# skill format needs render_<p>_entry_skill (generic fallback allowed, so a legacy
# render_<p>_command also satisfies it).
pw_provider_has_hooks() {
  local p="$1" fn
  for fn in "${p}_bin" "${p}_skilldir" "${p}_commanddir"; do
    declare -f "$fn" >/dev/null 2>&1 || return 1
  done
  if [ "$(pw_provider_entry_format "$p")" = "skill" ]; then
    declare -f "render_${p}_entry_skill" >/dev/null 2>&1 && return 0
    declare -f "render_${p}_command" >/dev/null 2>&1 && return 0
    return 1
  fi
  declare -f "render_${p}_command" >/dev/null 2>&1
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

# --- named-argument grammar (one flag grammar for every external operator) --------------------
# Operation words stay positional and first; every VALUE is named (--project <slug>, --file <f>,
# --decision <d>, ...), so a missing or reordered value can never silently change meaning.
# Each script's own die() supplies the prefix; these helpers keep the refusal wording uniform.
_pw_missing() { die "$1 needs a value → fix: pass $1 <value> (quote values with spaces)"; }
_pw_unknown() { die "unknown option: $1 → fix: $2"; }
_pw_positional() { die "unexpected argument: $1 → fix: $2"; }
# _pw_dup <flag> — a second occurrence of a single-value flag is a usage error, never a race.
_pw_dup() { die "duplicate option: $1 → fix: pass it once"; }

# --- task-file field readers -------------------------------------------------
# The canonical task template writes one bold bullet per field
# ("- **Repo:** svc"); pre-2026-09-15 templates packed two per line
# ("- **Repo:** svc   **Base branch:** master"), and older projects use the
# line-start form ("Repo: svc"). pw_field prints the first non-empty value in
# ANY shape: it cuts the value at the next "**" (packed-line safety) and trims
# surrounding whitespace.
pw_field() {
  awk -v l="$2" '
    BEGIN { b = "**" l ":**" }
    {
      v = ""
      p = index($0, b)
      if (p) { v = substr($0, p + length(b)); got = 1 }
      else if ($0 ~ ("^[ \t]*" l ":")) { sub(("^[ \t]*" l ":[ \t]*"), "", $0); v = $0; got = 1 }
      else got = 0
      if (got) {
        q = index(v, "**"); if (q) v = substr(v, 1, q - 1)
        gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
        if (v != "") { print v; exit }
      }
    }' "$1"
}
pw_has_field() { [ -n "$(pw_field "$1" "$2")" ]; }

# --- phase reading (canonical machine token) -----------------------------------
# The dashboard's `- **Status:**` line must START with one token of the lifecycle;
# real projects have drifted into free prose (e.g. "Status: executed — 11/11 done
# (verify ✓) awaiting acceptance…"), which every phase gate must handle honestly.
# pw_phase_token cuts the leading token; pw_phase_hint is the uniform remediation
# line gates append when the token is missing/unknown.
PW_VALID_PHASES="context analysis breakdown executing review done"
pw_phase_token() { printf '%s\n' "${1%%[[:space:]—-]*}"; }
pw_phase_valid() { case " $PW_VALID_PHASES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
pw_phase_hint() { printf 'fix the Status line: it must start with one of %s (free prose may follow the token) — repair with: pw-status.sh status --project <slug> --phase <phase> [--rewind]' "$PW_VALID_PHASES"; }

# pw_trim strips surrounding whitespace from stdin. NEVER use `| xargs` for this:
# xargs parses quotes, so a title/path containing an unbalanced apostrophe
# ("adapter's Redis…") fails the trim outright (found via mm-spring-redis-sentinel T01).
pw_trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# --- request-review frame reader (shared by pw-ship.sh and pw-doctor.sh) --------
# Effective frame path: PW_REVIEW_REQUEST_TEMPLATE_FILE when set (absolute stays put,
# relative resolves under PW_HOME), else the default user file. The file is plain
# Markdown, never sourced or executed.
# The implicit default moved from user-templates/ to user/templates/ (2026-10): the
# legacy file migrates byte-for-byte through pw_review_template_migrate when the new
# default is absent; an explicit configured path is never migrated or rewritten.
PW_REVIEW_REQUEST_TEMPLATE_LEGACY="$PW_HOME/user-templates/review-request.md"
pw_review_template_path() {
  local p="${PW_REVIEW_REQUEST_TEMPLATE_FILE:-}"
  case "$p" in
    "") printf '%s\n' "$PW_HOME/user/templates/review-request.md" ;;
    /*) printf '%s\n' "$p" ;;
    *)  printf '%s\n' "$PW_HOME/$p" ;;
  esac
}
pw_review_template_source() {  # default | custom
  if [ -n "${PW_REVIEW_REQUEST_TEMPLATE_FILE:-}" ]; then printf 'custom\n'; else printf 'default\n'; fi
}
pw_review_template_legacy_path() { printf '%s\n' "$PW_REVIEW_REQUEST_TEMPLATE_LEGACY"; }

# pw_review_template_migrate <new-default> <legacy-file> [--report] — the preservation-first
# legacy template migration. When <new-default> is absent: a readable legacy file is copied
# byte-for-byte (create-only; existing customization included, validated later by the normal
# frame checks); an unreadable legacy file is a reported migration problem, never a reason to
# seed over it; no legacy file means seed from the tracked template. When the new default
# already exists it wins and both files are preserved. rc 0 = nothing left to do (migrated,
# seeded, or already present); rc 1 = migration problem left for the caller to report.
# --report prints one status line without writing; bootstrap --check and doctor check-only use it.
pw_review_template_migrate() {
  local dest="${1:-}" legacy="${2:-}" report=0
  [ "${3:-}" = "--report" ] && report=1
  [ -n "$dest" ] || return 1
  if [ "$report" = 1 ]; then
    if [ -e "$dest" ]; then
      printf 'new default present (both files preserved)\n'
    elif [ -e "$legacy" ]; then
      if [ -r "$legacy" ] && [ -f "$legacy" ]; then
        printf 'pending migration: legacy default %s would move to %s\n' "$legacy" "$dest"
      else
        printf 'migration problem: legacy default %s exists but cannot be read\n' "$legacy"
      fi
    else
      printf 'missing default: would seed %s from the tracked template\n' "$dest"
    fi
    return 0
  fi
  [ -e "$dest" ] && return 0
  if [ -e "$legacy" ]; then
    if [ -r "$legacy" ] && [ -f "$legacy" ]; then
      mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
      ( set -o noclobber; cat "$legacy" > "$dest" ) 2>/dev/null || return 1
      printf 'migrated %s -> %s (legacy file kept for rollback)\n' "$legacy" "$dest"
      return 0
    fi
    printf 'migration problem: legacy default %s exists but cannot be read — fix the file, then re-run\n' "$legacy"
    return 1
  fi
  pw_review_template_seed "$dest" >/dev/null 2>&1 || return 1
  printf 'seeded %s from the tracked template\n' "$dest"
  return 0
}

# pw_user_file_seed <dest> <seed> — create-only copy of a tracked seed to <dest>. The one
# seeding primitive bootstrap/doctor share: rc 0 = created, 1 = destination already exists
# (never overwritten, including a concurrent creation), 2 = could not create. Only ever called
# for a DEFAULT destination — a custom configured path is reported, never materialized.
pw_user_file_seed() {
  local dest="${1:-}" seed="${2:-}"
  [ -n "$dest" ] && [ -n "$seed" ] || return 2
  [ -e "$dest" ] && return 1
  [ -f "$seed" ] || return 2
  mkdir -p "$(dirname "$dest")" 2>/dev/null || return 2
  ( set -o noclobber; cat "$seed" > "$dest" ) 2>/dev/null || return 2
  return 0
}
pw_review_template_seed() {  # <dest> — template flavor (legacy callers, shared seed path)
  pw_user_file_seed "${1:-}" "$PW_HOME/tooling/templates/review-request.md"
}

# pw_review_template_error <file> — the first frame problem as one line (empty output = valid).
# A valid frame carries each system block placeholder exactly once, {{PROJECT}} at most once,
# and no other {{…}} token; it is non-empty, readable UTF-8 text otherwise untouched. The
# single implementation both the read-only generator and the doctor validate against.
pw_review_template_error() {
  local f="${1:-}" opens closes tokens t c unknown="" req
  [ -n "$f" ] || { printf 'template path is empty\n'; return 0; }
  [ -e "$f" ] || { printf 'file not found: %s\n' "$f"; return 0; }
  [ -f "$f" ] || { printf 'not a regular file: %s\n' "$f"; return 0; }
  [ -r "$f" ] || { printf 'not readable: %s\n' "$f"; return 0; }
  [ -s "$f" ] || { printf 'file is empty: %s\n' "$f"; return 0; }
  opens="$(grep -o '{{' "$f" 2>/dev/null | wc -l | pw_trim || true)"
  closes="$(grep -o '}}' "$f" 2>/dev/null | wc -l | pw_trim || true)"
  tokens="$(grep -oE '\{\{[A-Za-z0-9_]+\}\}' "$f" 2>/dev/null || true)"
  c="$(printf '%s\n' "$tokens" | grep -c . 2>/dev/null || true)"
  if [ "$opens" != "$closes" ] || [ "$opens" != "$c" ]; then
    printf 'malformed {{…}} placeholder syntax (allowed: {{TO_BLOCK}} {{SUMMARY_BLOCK}} {{MR_BLOCKS}} {{NOTE_BLOCK}} {{PROJECT}})\n'
    return 0
  fi
  if [ -n "$tokens" ]; then
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$t" in
        '{{TO_BLOCK}}'|'{{SUMMARY_BLOCK}}'|'{{MR_BLOCKS}}'|'{{NOTE_BLOCK}}'|'{{PROJECT}}') ;;
        *) unknown="$unknown $t" ;;
      esac
    done <<EOF
$tokens
EOF
  fi
  [ -z "$unknown" ] || { printf 'unknown placeholder(s):%s\n' "$unknown"; return 0; }
  for req in TO_BLOCK SUMMARY_BLOCK MR_BLOCKS NOTE_BLOCK; do
    c="$(printf '%s\n' "$tokens" | grep -c "^{{$req}}$" 2>/dev/null || true)"
    [ "$c" = "1" ] || { printf 'placeholder {{%s}} must appear exactly once (found %s)\n' "$req" "$c"; return 0; }
  done
  c="$(printf '%s\n' "$tokens" | grep -c '^{{PROJECT}}$' 2>/dev/null || true)"
  [ "$c" -le 1 ] 2>/dev/null || { printf 'placeholder {{PROJECT}} must appear at most once (found %s)\n' "$c"; return 0; }
  return 0
}

# --- request-review generation prompts (shared by pw-ship.sh and pw-doctor.sh) --
# Effective prompt path: PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE / PW_REVIEW_REQUEST_NOTE_PROMPT_FILE
# when set (absolute stays put, relative resolves under PW_HOME), else the editable default under
# $PW_HOME/user/prompts/. Read as UTF-8 text per generation pass; never sourced or executed.
pw_review_prompt_path() {  # <summary|note>
  local p=""
  case "$1" in
    summary) p="${PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE:-}" ;;
    note)    p="${PW_REVIEW_REQUEST_NOTE_PROMPT_FILE:-}" ;;
    *) return 1 ;;
  esac
  case "$p" in
    "") printf '%s\n' "$PW_HOME/user/prompts/review-request-$1.md" ;;
    /*) printf '%s\n' "$p" ;;
    *)  printf '%s\n' "$PW_HOME/$p" ;;
  esac
  return 0
}
pw_review_prompt_source() {  # <summary|note> -> default | custom
  case "$1" in
    summary) [ -n "${PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE:-}" ] && printf 'custom\n' || printf 'default\n' ;;
    note)    [ -n "${PW_REVIEW_REQUEST_NOTE_PROMPT_FILE:-}" ] && printf 'custom\n' || printf 'default\n' ;;
    *) return 1 ;;
  esac
  return 0
}
pw_review_prompt_seed() {  # <summary|note> <dest> — create-only copy of that prompt's tracked seed
  case "$1" in
    summary) pw_user_file_seed "${2:-}" "$PW_HOME/tooling/prompts/review-request-summary.md" ;;
    note)    pw_user_file_seed "${2:-}" "$PW_HOME/tooling/prompts/review-request-note.md" ;;
    *) return 2 ;;
  esac
}

# pw_review_prompt_error <file> — the first generation-prompt problem as one line (empty = valid).
# A valid prompt is a readable, nonempty UTF-8 text file at most 16 KiB — file health only, never
# a semantic judgment about custom instructions. The single implementation both the read-only
# generator and the doctor validate against.
PW_REVIEW_PROMPT_MAX_BYTES=16384
pw_review_prompt_error() {
  local f="${1:-}" sz
  [ -n "$f" ] || { printf 'prompt path is empty\n'; return 0; }
  [ -e "$f" ] || { printf 'file not found: %s\n' "$f"; return 0; }
  [ -f "$f" ] || { printf 'not a regular file: %s\n' "$f"; return 0; }
  [ -r "$f" ] || { printf 'not readable: %s\n' "$f"; return 0; }
  [ -s "$f" ] || { printf 'file is empty: %s\n' "$f"; return 0; }
  if ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
    printf 'not valid UTF-8 text: %s\n' "$f"; return 0
  fi
  sz="$(wc -c < "$f" 2>/dev/null | pw_trim || printf '0')"
  [ "${sz:-0}" -le "$PW_REVIEW_PROMPT_MAX_BYTES" ] 2>/dev/null \
    || { printf 'file exceeds the %s-byte prompt limit (%s bytes): %s\n' "$PW_REVIEW_PROMPT_MAX_BYTES" "$sz" "$f"; return 0; }
  return 0
}

# --- PLAN.md task-table readers (column-NAME driven) ---------------------------
# Two task-table generations exist: legacy (Task|Repo|Branch|SP|Execute with|
# Depends on|Status) and current (ID|Title|Repo|depends_on|Group|Execute with|
# SP|Status|Time|Result). Never read PLAN task rows by positional index again —
# map the header row's cell names and pull values by that map.
_pw_plan_map() {
  awk -F'|' '
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ {
      n = split($0, c, "|")
      for (i = 1; i <= n; i++) {
        v = c[i]; gsub(/[ \t`*]/, "", v); V = tolower(v)
        if (V == "id" || V == "task") idi = i
        if (V == "status") sti = i
        if (V == "executewith") bei = i
      }
      if (idi || sti || bei) { print (idi+0) " " (sti+0) " " (bei+0); exit }
    }' "$1"
}
# pw_plan_pairs <plan> — "T0n|status" per task row
pw_plan_pairs() {
  local spec idi sti bei
  spec="$(_pw_plan_map "$1")"
  idi="${spec%% *}"; rest="${spec#* }"; sti="${rest%% *}"; bei="${rest##* }"
  [ "${idi:-0}" -gt 0 ] 2>/dev/null || return 0
  [ "${sti:-0}" -gt 0 ] 2>/dev/null || return 0
  awk -F'|' -v idi="$idi" -v sti="$sti" '
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) {
      id = $(idi + 0); gsub(/[ \t]/, "", id)
      if (match(id, /T[0-9]+/)) { id = substr(id, RSTART, RLENGTH) } else { id = "" }
      st = $(sti + 0); gsub(/^[ \t]+/, "", st); gsub(/[ \t]+$/, "", st)
      if (id ~ /^T[0-9]+/) print id "|" st
    }' "$1"
}
# pw_plan_execs <plan> — Execute-with column value per task row
pw_plan_execs() {
  local spec idi sti bei
  spec="$(_pw_plan_map "$1")"
  idi="${spec%% *}"; rest="${spec#* }"; sti="${rest%% *}"; bei="${rest##* }"
  [ "${bei:-0}" -gt 0 ] 2>/dev/null || return 0
  awk -F'|' -v idi="$idi" -v bei="$bei" '
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) {
      split($0, c, "|")
      id = c[idi + 0]; gsub(/[ \t]/, "", id)
      if (match(id, /T[0-9]+/)) { id = substr(id, RSTART, RLENGTH) } else { id = "" }
      v = $(bei + 0); gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
      if (id ~ /^T[0-9]+/) print v
    }' "$1"
}
# pw_plan_rows <plan> — "T0n|status|depends_on" per task row (column-name driven).
# One shared reader for review readiness; never positional, never a whole-file status grep.
pw_plan_rows() {
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) {
      n = split($0, c, "|")
      if (!hdr) {
        for (i = 1; i <= n; i++) {
          v = trim(c[i]); gsub(/[`*]/, "", v); V = tolower(v); gsub(/[ \t]/, "", V)
          if (V == "id" || V == "task") idi = i
          if (V == "status") sti = i
          if (V == "dependson" || V == "depends_on" || V == "depends") depi = i
        }
        if (idi && sti) hdr = 1
        next
      }
      id = trim(c[idi + 0])
      if (match(id, /T[0-9]+/)) { id = substr(id, RSTART, RLENGTH) } else { next }
      st = trim(c[sti + 0]); gsub(/[`*]/, "", st); st = trim(st)
      dep = depi ? trim(c[depi + 0]) : ""
      print id "|" st "|" dep
    }' "$1"
}

# pw_plan_review_ready <plan> — rc 0 when the WHOLE PLAN may enter review, else rc 1 with one
# blocker line on stdout. A task counts as finished at done/accepted. Any other status must be
# demonstrably blocked through a verify-failed task in its transitive depends_on chain; a bare
# todo, in-progress, or verify-failed label alone is not enough. This is the single readiness
# predicate shared by execution/orchestration and the status update route.
pw_plan_review_ready() {
  local plan="$1" rows failed=" " id st dep frontier seen next recheck="" d x found
  rows="$(pw_plan_rows "$plan")" || { printf 'PLAN task table unreadable\n'; return 1; }
  [ -n "$rows" ] || { printf 'PLAN task table has no task rows\n'; return 1; }
  while IFS='|' read -r id st dep; do
    [ "$st" = "verify-failed" ] && failed="$failed$id "
  done <<EOF
$rows
EOF
  while IFS='|' read -r id st dep; do
    case "$st" in done|accepted) continue ;; esac
    # bounded transitive walk: this task's deps must reach a verify-failed task
    frontier="$id"; seen=" "; found=0
    while [ -n "$frontier" ] && [ "$found" = 0 ]; do
      next=""
      for d in $frontier; do
        case "$seen" in *" $d "*) continue ;; esac
        seen="$seen$d "
        case "$failed" in *" $d "*) found=1; break ;; esac
        dep="$(printf '%s\n' "$rows" | awk -F'|' -v i="$d" '$1==i{print $3; exit}')"
        for x in $(printf '%s' "$dep" | tr ',;' '  '); do
          case "$x" in T[0-9]*) next="$next $x" ;; esac
        done
      done
      frontier="$next"
    done
    [ "$found" = 1 ] || recheck="$recheck $id($st)"
  done <<EOF
$rows
EOF
  if [ -n "$recheck" ]; then
    printf 'not review-ready — unfinished task(s):%s\n' "$recheck"
    return 1
  fi
  return 0
}

_pw_url_from_line() {  # $1=line from a Result MR: bullet -> plain URL (falls back to sentinel text)
  local u
  u="$(printf '%s' "$1" | grep -oE "https?://[^ )>|\"\`]+" | head -1)"
  if [ -n "$u" ]; then printf '%s' "$u"; return 0; fi
  printf '%s' "$1" | sed -E "s/^[-*[:space:]]*[*]*MR[*]*:[[:space:]]*//; s/^[*_[:space:]]+//; s/[[:space:]]+$//"
}

# --- stacked-MR readers (plan 35) ----------------------------------------------
# The task field `Stacked on:` holds exactly one parent task id (T0n) or `none`. An absent or
# `none` value means legacy independent behavior; a reader NEVER infers a stack from `depends_on`
# (a scheduling dependency is not branch inheritance). `Base branch:` keeps the ULTIMATE
# destination; the effective review target is derived (nearest unmerged ancestor's branch, else
# base) and lives in the ship-owned state record, never by rewriting the task field.

# pw_stack_parent <taskfile> -> parent task id, or empty for none/absent/invalid.
pw_stack_parent() {
  [ -f "$1" ] || return 0
  local v
  v="$(pw_field "$1" 'Stacked on' 2>/dev/null || true)"
  v="${v//\`/}"
  v="${v%%[[:space:]]*}"          # first token only; trailing annotation prose is ignored
  case "$v" in
    ""|none|None|NONE|—|-|"<"*) return 0 ;;
  esac
  # Full task-id validation, not a prefix glob: `T1/../../foo` matches `T[0-9]*` but must
  # never flow into `task/<id>.md` path builds (pw_task_id_ok rejects any non-alnum tail).
  if pw_task_id_ok "$v"; then printf '%s\n' "$v"; fi
}

# pw_plan_col <plan> <normalized-col-name> -> "T0n|value" per data row of the ## Task table.
# Column-NAME driven (both PLAN generations); empty when the column is absent (legacy projects
# carry no `Stacked on` column and must stay independent). Never positional.
pw_plan_col() {
  awk -F'|' -v want="$2" '
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) {
      n = split($0, c, "|")
      if (!hdr) {
        for (i = 1; i <= n; i++) { v = c[i]; gsub(/[ \t`*]/, "", v); V = tolower(v)
          if (V == "id" || V == "task") idi = i; if (V == want) ti = i }
        hdr = 1; next
      }
      if (ti > 0 && idi > 0) {
        id = c[idi]; gsub(/[ \t]/, "", id)
        if (match(id, /T[0-9]+/)) id = substr(id, RSTART, RLENGTH); else id = ""
        val = c[ti]; gsub(/^[ \t]+/, "", val); gsub(/[ \t]+$/, "", val)
        if (id != "") print id "|" val
      }
    }' "$1"
}
pw_plan_stacked() { pw_plan_col "$1" stackedon; }

# Validate a task id at a trust boundary (never build paths/refs from an unchecked token).
pw_task_id_ok() { case "${1:-}" in T[0-9]*) case "$1" in *[!A-Za-z0-9]*) return 1 ;; esac; return 0 ;; *) return 1 ;; esac; }

# --- stack state record (task/stack.tsv) ---------------------------------------
# ONE minimal ship-owned state row per affected branch/MR: bindings, observed targets, verification
# tuple, freshness debt, and navigation. Machine TSV (header row); comments start with '#'. Writes
# happen ONLY through pw_stack_state_upsert (a shared primitive) — never a hand edit.
PW_STACK_COLS="task parent branch base fork_sha consumed_parent_sha consumed_parent_branch target head_sha landed landed_into parent_mr child_mrs verified_head verified_parent verified_target verified_at ci_sha ci_target freshness verified_evidence"
pw_stack_state_file() { printf '%s/task/stack.tsv' "$1"; }
pw_stack_state_col() {  # <colname> -> 1-based column index
  local c i=1
  for c in $PW_STACK_COLS; do [ "$c" = "$1" ] && { printf '%s' "$i"; return 0; }; i=$((i+1)); done
  return 1
}
_pw_stack_ncol() { local n=0 c; for c in $PW_STACK_COLS; do n=$((n+1)); done; printf '%s' "$n"; }
_pw_stack_tab=$(printf '\t')
_stack_val_bad() {  # rc 0 when a value carries a reserved character (pipe, TAB, newline, backslash)
  case "$1" in *"|"*|*"$_pw_stack_tab"*|*"$IFS_NL"*|*'\'*) return 0 ;; esac
  return 1
}
IFS_NL='
'

# pw_path_within <dir> <path> — rc 0 when <path> resolves physically inside <dir> (no symlink
# escape). Used to refuse a stack write that would land outside the project tree.
pw_path_within() {
  local dir="$1" path="$2" rdir pdir
  [ -n "$dir" ] && [ -n "$path" ] || return 1
  rdir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  pdir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
  case "$pdir/" in "$rdir/"*) return 0 ;; esac
  return 1
}

# --- trust-boundary validators (the sink gates; see tooling/docs/SECURITY.md) ----------------
# pw_proj_slug_ok <slug> — a project slug is exactly ONE path component (the pw-review
# contract): no empty/dot/traversal components, no separators, no control whitespace.
pw_proj_slug_ok() {
  case "${1:-}" in ''|.|..|*/*|*"$IFS_NL"*|*$'\r'*|*$'\t'*) return 1 ;; esac
  return 0
}

# pw_proj_dir <slug> — physical project directory, or empty on refusal. Shape-gated by
# pw_proj_slug_ok, then pinned physically (pwd -P both sides): the canonical project
# directory must remain inside the projects root, so a symlinked slug resolving outward
# is refused too. Entities wrap this with their own die message.
pw_proj_dir() {
  local slug="$1" base d
  pw_proj_slug_ok "$slug" || return 1
  [ -d "$PROJECTS_DIR/$slug" ] || return 1
  base="$(cd "$PROJECTS_DIR" 2>/dev/null && pwd -P)" || return 1
  d="$(cd "$PROJECTS_DIR/$slug" && pwd -P)" || return 1
  case "$d/" in "$base/"*) printf '%s' "$d" ;; *) return 1 ;; esac
}

# pw_branch_ok <branch> — the branch charset guard the stack paths already enforce:
# ref-safe characters ([A-Za-z0-9._/-]) only, never a leading dash (git would parse the
# value as an option at positional refspec sites like `git push origin "$branch"`).
pw_branch_ok() {
  case "${1:-}" in ''|*[!A-Za-z0-9._/-]*|-*) return 1 ;; esac
  return 0
}

# pw_hook_dir_ok <dir> — provider hook outputs (skilldir/commanddir/agentdir) must be a
# non-empty absolute path (S14): an empty or relative hook return steered rm/ln/cmp at
# '/name' or the CWD. Absolute — not strictly $HOME-prefixed — because custom install
# roots outside $HOME are legitimate operator choices.
pw_hook_dir_ok() {
  [ -n "${1:-}" ] || return 1
  case "$1" in /*) return 0 ;; *) return 1 ;; esac
}

# pw_dir_within <base> <dir> — rc 0 when <dir> is an existing directory that resolves
# physically inside <base> (the final component included, so a symlinked dir is refused
# when it points outside). For task-file `Repo:`/`Worktree:` values before any git/cd use.
pw_dir_within() {
  local base="$1" dir="$2" rbase rdir
  [ -n "$base" ] && [ -n "$dir" ] && [ -d "$dir" ] || return 1
  rbase="$(cd "$base" 2>/dev/null && pwd -P)" || return 1
  rdir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  case "$rdir/" in "$rbase/"*) return 0 ;; esac
  return 1
}

# pw_stamp_tokens <file> — rewrite the scaffold tokens {{PW_HOME}}/{{PW_PROJECTS}}/{{PW_REPOS}}
# in place with the current paths. Bash string replacement, never a sed/perl program string:
# install paths are operator config and must not become program text (a `}` inside $PW_HOME
# previously broke out of the perl s{...}{...} delimiters). Staged via pw_tmpfile + mv, and
# every line is printed exactly once (trailing-newline behavior unchanged).
pw_stamp_tokens() {
  local f="$1" tmp
  tmp="$(pw_tmpfile "$(dirname "$f")")" || return 1
  if while IFS= read -r _stl || [ -n "$_stl" ]; do
       _stl="${_stl//\{\{PW_HOME\}\}/$PW_HOME}"
       _stl="${_stl//\{\{PW_PROJECTS\}\}/$PW_PROJECTS}"
       _stl="${_stl//\{\{PW_REPOS\}\}/${PW_REPOS:-}}"
       printf '%s\n' "$_stl"
     done < "$f" > "$tmp"; then
    if mv "$tmp" "$f"; then return 0; fi
  fi
  rm -f "$tmp"
  return 1
}

# pw_lock <lockdir> [tries] — exclusive advisory lock via atomic `mkdir` (macOS/Bash 3.2 has no
# flock). The shipped history lock's contract (pw-shiplib.sh) mirrored in shell: the holder writes
# a PID/token record, release validates the token, and a stale lock is NEVER auto-reclaimed — a
# dead-pid `rm -rf` race could delete a replacement lock out from under a live writer, so a bounded
# wait fails closed instead and names the holder. Remove a stale lock by hand only after
# confirming no writer is active. rc 0 = acquired (release with pw_unlock), 1 = timed out.
pw_lock() {
  local ld="$1" tries="${2:-100}" i=0 pid tok key
  while ! mkdir "$ld" 2>/dev/null; do
    i=$((i+1))
    if [ "$i" -ge "$tries" ]; then
      pid="$(cat "$ld/pid" 2>/dev/null || true)"
      echo "pw_lock: could not acquire $ld${pid:+ (held by pid $pid)} → fix: retry after the writer exits; a crashed writer can leave a stale lock — remove that directory by hand only after confirming no writer is active (it is never auto-reclaimed)" >&2
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  tok="$$.$(date +%s 2>/dev/null || printf '0').$RANDOM$RANDOM"
  printf '%s\n' "$$" > "$ld/pid" 2>/dev/null || true
  printf '%s\n' "$tok" > "$ld/token" 2>/dev/null || true
  key="_PW_LOCK_TOK_$(printf '%s' "$ld" | cksum | tr -dc '0-9')"
  eval "$key=\"\$tok\""
  return 0
}
pw_unlock() {  # remove the lock ONLY when this process holds its token (never another writer's)
  local ld="$1" key tok cur
  key="_PW_LOCK_TOK_$(printf '%s' "$ld" | cksum | tr -dc '0-9')"
  eval "tok=\${$key:-}"
  cur="$(cat "$ld/token" 2>/dev/null || true)"
  if [ -n "$tok" ] && [ "$tok" = "$cur" ] && [ "$(cat "$ld/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "$ld" 2>/dev/null || true
  fi
  eval "unset $key" 2>/dev/null || true
}

# pw_tmpfile <dir> — a UNIQUE temp path inside <dir> (never a fixed .tmp; concurrent writers can
# never clobber each other's staged file).
pw_tmpfile() { mktemp "$1/.pwtmp.XXXXXX" 2>/dev/null || printf '%s' "$1/.pwtmp.$$.$RANDOM"; }

# pw_stack_state_get <projdir> <task> <col> -> value or empty (missing file/row/col = empty).
pw_stack_state_get() {
  local f ci; f="$(pw_stack_state_file "$1")"; [ -f "$f" ] || return 0
  ci="$(pw_stack_state_col "$3")" || return 0
  awk -F'\t' -v t="$2" -v c="$ci" '$1 == t { print $c; exit }' "$f" 2>/dev/null || true
}
pw_stack_state_has() { [ -f "$(pw_stack_state_file "$1")" ] && [ -n "$(pw_stack_state_get "$1" "$2" task)" ]; }

# pw_stack_state_validate <projdir> — schema/version gate for task/stack.tsv before any read or
# write that matters. rc 0 = absent or valid; rc 1 = malformed (loud reason). A state file whose
# version tag, column header, or row shapes drifted is rejected instead of being half-read into a
# gate decision (refs/targets from a malformed row could point anywhere).
pw_stack_state_validate() {
  local f; f="$(pw_stack_state_file "$1")"
  [ -e "$f" ] || return 0
  [ -L "$f" ] && { echo "pw-stack-state: refusing to read through a symlink: $f" >&2; return 1; }
  [ -f "$f" ] || { echo "pw-stack-state: not a regular file: $f → fix: repair task/stack.tsv (machine-owned)" >&2; return 1; }
  local line1 line2 ncol
  line1="$(sed -n '1p' "$f" 2>/dev/null || true)"
  case "$line1" in
    '# pw-stack-state v1'*) : ;;
    *) echo "pw-stack-state: unsupported state version in $f (want a '# pw-stack-state v1 …' first line) → fix: restore or rebuild the record; it is machine-owned" >&2; return 1 ;;
  esac
  line2="$(sed -n '2p' "$f" 2>/dev/null || true)"
  ncol="$(_pw_stack_ncol)"
  [ "$line2" = "$(printf '%s' "$PW_STACK_COLS" | tr ' ' '\t')" ] \
    || { echo "pw-stack-state: column header mismatch in $f → fix: restore task/stack.tsv from its writer (never hand-edit the columns)" >&2; return 1; }
  awk -F'\t' -v n="$ncol" 'NR>2 && NF>0 && (NF!=n || $1 !~ /^T[0-9]/) {bad=1} END{exit bad}' "$f" \
    || { echo "pw-stack-state: malformed row(s) in $f (field-count/task-id) → fix: repair via the stack writers; malformed records are rejected before any operation" >&2; return 1; }
  return 0
}

# pw_stack_state_upsert <projdir> <task> <col=value>… — create/update one row in place. Column
# names are validated; an unknown one is a usage error. The assignments travel to awk as a
# `|`-joined `index:value` list (no embedded newlines — BSD awk rejects -v values with newlines).
pw_stack_state_upsert() {
  [ $# -ge 3 ] || { echo "pw_stack_state_upsert: usage: <projdir> <task> <col=value>…" >&2; return 2; }
  local proj="$1" task="$2"; shift 2
  pw_task_id_ok "$task" || { echo "pw_stack_state_upsert: invalid task id '$task'" >&2; return 2; }
  local dir="$proj/task" f; f="$dir/stack.tsv"; mkdir -p "$dir"
  # Containment: never write through a symlink or outside the project tree. The symlink/version/
  # row-shape refusal lives in pw_stack_state_validate (called below, before the lock), so reads and
  # writes share exactly one guard.
  pw_path_within "$proj" "$f" || { echo "pw_stack_state_upsert: refusing to write outside $proj ($f)" >&2; return 2; }
  pw_stack_state_validate "$proj" || return 2
  local assign="" kv col v ci
  for kv in "$@"; do
    col="${kv%%=*}"; v="${kv#*=}"
    ci="$(pw_stack_state_col "$col")" || { echo "pw_stack_state_upsert: unknown column '$col' → fix: see pw-ship.sh --help" >&2; return 2; }
    _stack_val_bad "$v" && { echo "pw_stack_state_upsert: value for '$col' contains a reserved character (pipe/TAB/newline)" >&2; return 2; }
    assign="$assign${assign:+|}${ci}:${v}"
  done
  local ncol tmp ld="$dir/.stack.tsv.lock"
  ncol="$(_pw_stack_ncol)"
  pw_lock "$ld" || { echo "pw_stack_state_upsert: could not acquire $ld (another writer active)" >&2; return 2; }
  if [ ! -f "$f" ]; then
    { printf '# pw-stack-state v1 — machine-owned; edit via pw-ship.sh stack-* operators\n'
      printf '%s\n' "$(printf '%s' "$PW_STACK_COLS" | tr ' ' '\t')"; } > "$f" || { pw_unlock "$ld"; return 2; }
  fi
  tmp="$(pw_tmpfile "$dir")"
  awk -F'\t' -v task="$task" -v ncol="$ncol" -v assigns="$assign" '
    BEGIN { n = split(assigns, A, "|"); for (i = 1; i <= n; i++) { if (A[i] == "") continue; p = index(A[i], ":"); C[substr(A[i], 1, p - 1)] = substr(A[i], p + 1) } found = 0 }
    /^#/ { print; next }
    !hdr { hdr = 1; print; next }
    {
      if ($1 == task) { found = 1; for (i = 1; i <= ncol; i++) row[i] = $i }
      else print
    }
    END {
      row[1] = task
      for (i in C) row[i + 0] = C[i]
      line = ""
      for (i = 1; i <= ncol; i++) line = line (i > 1 ? "\t" : "") (row[i] == "" ? "" : row[i])
      print line
    }' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; pw_unlock "$ld"; echo "pw_stack_state_upsert: rewrite failed" >&2; return 2; }
  if ! awk -F'\t' -v ncol="$ncol" 'NR>1 && NF>0 && NF!=ncol{bad=1} END{exit bad}' "$tmp"; then
    rm -f "$tmp"; pw_unlock "$ld"; echo "pw_stack_state_upsert: refusing to install a malformed row (field-count mismatch)" >&2; return 2
  fi
  mv "$tmp" "$f" || { rm -f "$tmp"; pw_unlock "$ld"; return 2; }
  pw_unlock "$ld"
}

# pw_stack_parent_id <projdir> <task> — parent task id from the task file (empty = none).
pw_stack_parent_id() { pw_stack_parent "$1/task/$2.md"; }

# pw_stack_chain <projdir> <task> — ancestors NEAREST-FIRST (immediate parent first), one per
# line. Returns non-zero and prints nothing on a cycle.
pw_stack_chain() {
  local proj="$1" cur seen=" "
  cur="$(pw_stack_parent_id "$proj" "$2")"
  while [ -n "$cur" ]; do
    case "$seen" in *" $cur "*) return 1 ;; esac
    seen="$seen$cur "
    printf '%s\n' "$cur"
    cur="$(pw_stack_parent_id "$proj" "$cur")"
  done
  return 0
}

# pw_stack_ancestors <projdir> <task> — ancestors ROOT-FIRST (outermost first), one per line.
pw_stack_ancestors() {
  local chain; chain="$(pw_stack_chain "$1" "$2")" || return 1
  [ -n "$chain" ] || return 0
  printf '%s\n' "$chain" | sed '1!G;h;$!d'
}

# pw_stack_descendants <projdir> <task> — transitive stack descendants, PARENT-FIRST (BFS), one
# per line, excluding the task itself. Cycle-safe via a seen set.
pw_stack_descendants() {
  local proj="$1" frontier="$2" next out="" seen=" " n f cur
  while [ -n "$frontier" ]; do
    next=""
    for n in $frontier; do
      for f in "$proj"/task/T*.md; do
        [ -f "$f" ] || continue
        cur="$(basename "$f" .md)"
        [ "$(pw_stack_parent "$f")" = "$n" ] || continue
        case "$seen" in *" $cur "*) continue ;; esac
        seen="$seen$cur "; out="$out$cur
"; next="$next $cur"
      done
    done
    frontier="$next"
  done
  [ -n "$out" ] && printf '%s' "$out"
  return 0
}

# pw_stack_cycle <projdir> — the id that re-enters a cycle (stack edges only), or empty.
pw_stack_cycle() {
  local proj="$1" f cur seen
  for f in "$proj"/task/T*.md; do
    [ -f "$f" ] || continue
    cur="$(basename "$f" .md)"; seen=" "
    while [ -n "$cur" ]; do
      case "$seen" in *" $cur "*) printf '%s\n' "$cur"; return 0 ;; esac
      seen="$seen$cur "
      cur="$(pw_stack_parent_id "$proj" "$cur")"
    done
  done
  return 1
}

# pw_stack_effective_target <projdir> <task> <base> — the derived review target: the nearest
# ancestor that has NOT landed, else the ultimate base. A landed ancestor's recorded destination is
# honored: a merge into the ultimate base keeps scanning outward, a merge into another OPEN ancestor
# branch targets that branch, and any other or unverifiable destination FAILS CLOSED (rc 1, no
# output) so a caller never promotes a child to a base that does not carry the inherited code.
pw_stack_effective_target() {
  local proj="$1" base="$3" cur landed li kind dest br a abr alanded
  local chain; chain="$(pw_stack_chain "$proj" "$2" 2>/dev/null || true)"
  [ -n "$chain" ] || { printf '%s\n' "$base"; return 0; }
  while IFS= read -r cur; do
    [ -n "$cur" ] || continue
    landed="$(pw_stack_state_get "$proj" "$cur" landed 2>/dev/null || true)"
    if [ "$landed" != "yes" ]; then
      br="$(pw_field "$proj/task/$cur.md" Branch 2>/dev/null || true)"
      br="${br//\`/}"; br="${br%%[[:space:]]*}"
      [ -n "$br" ] || return 1                 # fail closed: an open ancestor with no Branch
      printf '%s\n' "$br"; return 0
    fi
    li="$(pw_stack_state_get "$proj" "$cur" landed_into 2>/dev/null || true)"
    kind="${li%%:*}"; dest="${li#*:}"
    case "$kind" in
      merge|ff|fast-forward) : ;;
      *) return 1 ;;                           # squash/rebase/closed/unknown: ancestry unprovable
    esac
    [ -n "$dest" ] || return 1
    if [ "$dest" = "$base" ]; then continue; fi # merged into the ultimate destination; outer ancestor governs
    a=""
    for a in $chain; do
      abr="$(pw_field "$proj/task/$a.md" Branch 2>/dev/null || true)"; abr="${abr//\`/}"; abr="${abr%%[[:space:]]*}"
      if [ "$abr" = "$dest" ]; then
        alanded="$(pw_stack_state_get "$proj" "$a" landed 2>/dev/null || true)"
        [ "$alanded" != "yes" ] && { printf '%s\n' "$dest"; return 0; }
        a="__landed__"; break
      fi
    done
    [ "$a" = "__landed__" ] && continue
    return 1                                    # destination is neither the base nor an open ancestor
  done <<EOF
$chain
EOF
  printf '%s\n' "$base"
}

pw_task_mr_url() {  # $1 = task file -> MR URL (or sentinel text like `(none)`) scoped to ## Result;
  # empty when there is no Result section or nothing URL-like in it (caller decides the fallback).
  # Resolution order INSIDE the `## Result` block:
  #   1. the MR field line (`- **MR:** <url>` or bare `- MR: <url>`; the value is cut at the next
  #      bold key the way pw_field does, so packed lines cannot leak the following field's text)
  #      -> that value's URL, else the trimmed value (the sentinel).
  #   2. no field line -> first http(s) URL anywhere in the Result block (the "bare URL" case).
  # The section-scoping is the whole point: a file-wide `grep 'https://' | head -1` lets a decoy
  # literal URL earlier in the task (## Steps quoting placeholder URLs) beat the real field — seen
  # 2026-09: one such Steps URL made pw-lib's mr-state resolve-but-fail ("unknown" forever) on a
  # task whose `- **MR:**` line sat correctly in its own ## Result. the old pw-lib.sh could not source this
  # file (standalone doctrine) and carries the mirror _resolve_task_mr_url — update both together.
  local sec line val url
  [ -f "$1" ] || return 0
  sec="$(awk '/^## Result/{p=1; next} /^## /{p=0} p' "$1" 2>/dev/null)" || return 0
  [ -n "$sec" ] || return 0
  line="$(printf '%s\n' "$sec" | grep -m1 -E '^[[:space:]]*([-*][[:space:]]*)?\*{0,2}MR\*{0,2}[[:space:]]*:' || true)"
  if [ -n "$line" ]; then
    val="$(printf '%s' "$line" | sed -E \
      -e 's/^[[:space:]]*([-*][[:space:]]*)?\*{0,2}MR\*{0,2}[[:space:]]*:[[:space:]]*//' \
      -e 's/^[*_[:space:]]+//' -e 's/[[:space:]]+\*\*.*$//' -e 's/[[:space:]]+$//')"
    if [ -n "$val" ]; then
      url="$(printf '%s' "$val" | grep -oE "https?://[^ )>|\"\`]+" | head -1 || true)"
      [ -n "$url" ] && { printf '%s' "$url"; return 0; }
      printf '%s' "$val"; return 0
    fi
  fi
  printf '%s\n' "$sec" | grep -oE "https?://[^ )>|\"\`]+" | head -1 || true
}
