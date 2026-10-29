#!/usr/bin/env bash
# ============================================================================
# pw-config.sh — the per-project config entity: which models and which review
# modes a project runs with (dashboard config lines, get-or-set semantics).
#
#   pw-config.sh show --project <slug> [--json]
#       every axis: kind | stored | source | effective floor
#       (read-only — includes state/data rows, which have no set)
#   pw-config.sh get --project <slug> --key <key>
#       one config key's stored value (or "(unset — effective: …)")
#   pw-config.sh set --project <slug> --key <key> [--value <v> | --set <member=value>]…
#       validated write through the single owner location
#       (keys: routing | execution-limit | max-parallel |
#              produced-by | ai-review | ai-model | pin | rfc-target |
#              review-trigger | review-repair | review-rounds)
#       Scalar keys (routing, execution-limit, max-parallel, produced-by, rfc-target,
#       review-rounds) take --value <v> — vocabulary: routing auto|subagent|headless
#       (headless = strict binding); ai-review surfaces context|analysis|plan|task-plan|
#       task-exec|ship|rfc|close with modes advisory|auto; review-trigger values
#       manual|completion; review-repair values manual|bounded; ai-model roles
#       researcher|analyst|writer-task|reviewer|verifier|ship-comment-analyst|explorer.
#       ai-review/ai-model/review-trigger/review-repair accept BATCH
#       --set pairs (`--set plan=auto --set ship=advisory`) and an
#       `--set all=<value>` baseline that expands over every supported surface,
#       with explicitly named surfaces overriding it (in either
#       argument order): every pair validated first
#       (all-or-nothing), then ONE write + ONE LOG line.
#       review-rounds --value <n> takes one integer 1..3 (the bounded
#       review→repair cycle's total reviewer passes).
#       pin accepts BATCH task pins (`--set T01=kilo:prov/model
#       --set T02=claude:sonnet`, `—` clears): same all-or-nothing
#       validation (membership + model-check + model-resolve),
#       written to BOTH holders — task file `Execute with:` +
#       PLAN cell — by one propagator, ONE LOG line.
#       With --key ai-model, one role assignment may also carry
#       --variant/--reasoning/--effort; replacing a model without tuning
#       resets that role's companion tuning instead of carrying it forward.
#   pw-config.sh ensure --project <slug>
#       insert any missing explicit dashboard config lines
#       (AI Models: / AI Review: / Review Trigger: /
#       Review Repair: / Review Budget: — `—`/`manual`/`3` are
#       legal explicit values; an absent line is a defect,
#       never a style choice). Getters stay READ-ONLY: a read
#       of an absent line returns the effective defaults and
#       says so on stderr without writing; `ensure` (or any
#       `--set`) is the only door that persists the line. Also
#       the one migration door for legacy `off` outcome rows:
#       they become effective `advisory` on every read WITHOUT
#       a write; ensure persists that normalization.
#   pw-config.sh global <show|get|set|unset> …
#       The ONE global operator family. `show` reports machine floors AND every inherited project
#       default with `inherited: yes|no`, destination, effective value, and source. `get` reads one;
#       `set`/`unset` edit a bounded managed assignment block in the existing pw.config.sh (no
#       second config file), preserving every unrelated byte and refusing unsafe values. These
#       defaults are copied into NEW projects only — never live inheritance.
#   pw-config.sh materialize --project <slug>
#       Internal /pw-breakdown step: copy the dashboard `Project Defaults` seed into a newly
#       created PLAN once. Explicit PLAN values always win and the seed is never re-read.
#   pw-config.sh spawn-args --project <slug> --role <role> [--json]
#       Deterministic role dispatch: the complete stored binding plus the provider-native
#       argument array (or an explicit refusal when the route cannot bind the tuning).
#   pw-config.sh validate-defaults
#       Internal creation gate: validate the resolved global snapshot before a staged project
#       is published. Refuses a removed/mistyped/forbidden binding instead of substituting.
#   get/set on state/data keys (status, adopted, base-branches, landing-units) is REFUSED with the
#   owning flow's command — those are derived facts, not configuration.
#   The ai-model / ai-review / review-trigger / review-repair / review-rounds ops are
#   DEPRECATED shims (named args only) — the same writers as `set --key …`, and they
#   announce the pointer on stderr; use the `set --key …` form in new invocations.
#   pw-config.sh ai-model --project <slug> [--set <role=value>]…
#       Get (no --set) or set spawn-lane model rows (roles: researcher analyst
#       writer-task reviewer verifier ship-comment-analyst). — clears to provider/session default. Several
#       --set role=<value> pairs in one call = batch (validated all-or-nothing, one write/log).
#   pw-config.sh ai-review --project <slug> [--set <surface=mode>]…
#       Get (no --set) or set AI-review OUTCOME modes. Two values only: advisory|auto (auto is
#       what lets pw-review.sh auto-signoff ever succeed). The removed `off` value
#       reads as effective `advisory` (missing rows too), so an explicit AI pass is
#       always callable; SCHEDULING lives on review-trigger, never here. `--set all=<mode>`
#       sets every surface, named surfaces override it. Surfaces:
#       context analysis plan task-plan task-exec ship rfc close.
#   pw-config.sh review-trigger --project <slug> [--set <surface=value>]…
#       Get (no --set) or set WHEN an AI pass starts: manual (only an explicit /pw-review … ai
#       request) | completion (after a successful producing command's verification).
#       completion never disables explicit requests; missing rows mean manual.
#   pw-config.sh review-repair --project <slug> [--set <surface=value>]…
#       Get (no --set) or set whether a completion review may run the BOUNDED repair cycle:
#       manual (findings stop for the owner) | bounded (review→repair→verify→fresh
#       review within the budget). Missing rows mean manual.
#   pw-config.sh review-rounds --project <slug> [--value <n>]
#       Get (no --value) or set the bounded cycle's total reviewer passes (1..3; default 3 —
#       three passes allow at most two intervening verified repairs).
#   pw-config.sh model-check --provider <p> --model <m> [--variant <v>] [--reasoning <v>] [--effort <v>] [--json]
#       Pass/refuse a model against PW_MODEL_ALLOWLIST_<PROVIDER> from pw.config.sh
#       (empty/unset = all allowed — the default rule). Also lists the local, documented tuning
#       capability table per control (`unsupported` / `unknown` / explicit values), validates a
#       requested combination, and never spends a model request.
#   pw-config.sh model-resolve --provider <p> --model <m> [--probe]
#       AVAILABILITY check (the sibling of model-check's PERMISSION check): match the model
#       against the provider's catalog, verify it sits inside the
#       PW_<PROVIDER>_API_PROVIDERS prefix scope, and print the CANONICAL catalog id that a
#       headless `-m`/`--model` must receive. Cursor reads TWO catalog sources — `agent models`
#       plus the desktop app's ~/.cursor/cli-config.json → modelParameters (desktop-only ids
#       such as glm-5p3-flash are absent from the CLI catalog) — and `--probe` (or
#       PW_CURSOR_PROBE=1) additionally accepts an id neither source lists when one live
#       `agent -p … --model <id>` ask succeeds (a real model call; opt-in). A bracket override
#       (`glm-5p3-flash[reasoning=low]`) resolves on its BASE id and is printed whole. exit 0
#       resolved / 1 not in catalog / 2 matched but out of configured scope. Providers with no
#       queryable catalog (claude) or no catalog reachable (CLI off PATH) exit 0 "unverified" —
#       never a false dead.
#   pw-config.sh models [--provider <p>]… [--api-provider <prefix>]… [--search <term>]
#                      [--limit <n>] [--all] [--details] [--format table|tsv] [--json]
#       Bounded catalog discovery. Reports the source honestly (live CLI catalog, Claude's fixed
#       alias set, unavailable CLI, empty result, unsupported surface). API-provider filters apply
#       locally and only to providers with that axis. No live model request.
#   pw-config.sh agent-model --provider <p> --agent <pw-name> [--json]
#   pw-config.sh agent-model-set --provider <p> --agent <pw-name> --value '<model>[k=v,…]'|—
#   pw-config.sh agent-model-unset --provider <p> --agent <pw-name>
#       Read, set, or clear one provider-by-worker model cell. The key derives from the canonical
#       filename (PW_<PROVIDER>_AGENT_MODELS_<AGENT>). A write validates prefix, permission,
#       availability, and tuning capability, then publishes ONE quoted managed assignment.
#   pw-config.sh agent-models [--provider <p>]… [--json]
#       The complete provider × canonical-worker matrix with model, parameters, and source.
#   pw-config.sh spawn-args [--project <slug>] (--role <role> | --agent <pw-name>) [--provider <p>] [--json]
#       Resolve the complete binding and provider argv. Project role > provider worker default >
#       canonical/provider default; task pins remain the executor's authority. --provider is
#       required for a named worker and for role fallback.
#
# Named-argument grammar: operation words stay first and positional; every value is
# named. Scalar values are ONE token (quote spaces); --flag=value carries one literal
# value (needed when a value starts with --).
# Merged from pw-lib's config block (plan 20 entity consolidation); semantics
# unchanged. (was pw-lib.sh ai-model / ai-review / model-check)
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
ST="$HERE/pw-status.sh"

die() { echo "pw-config: $*" >&2; exit 2; }
proj_dir() { local d; d="$(pw_proj_dir "$1")" || die "no such project: $1 ($PROJECTS_DIR/$1) → fix: check the slug under the projects dir (new project? create it with: /pw-new --project $1)"; printf '%s' "$d"; }

# --- AI Models (per-lane model row for the spawned sub-agent lanes — plan 01 §5.1) -----------
# The model sibling of the AI Review config block below: which model a *lane* should run on when a
# phase spawns it, per project. Roles = spawn lanes (researcher / analyst / writer-task / reviewer /
# verifier / ship-comment-analyst). The **executor is never a row** — a task's `Execute with:` already pins its per-unit
# model (a dashboard copy would only drift from it) — and clean-execution choices (`Results
# acceptance`, `- AI execution limit`) live in PLAN's Execution strategy, not the dashboard.
# `—` = no row = provider/session default (the kilo `small_model`/`subagent_model` floor, or
# claude's session/def model). Values are `<provider>:<model>`-shaped — the same syntax as
# `Execute with:` (tooling/docs/providers.md). Where a provider can't bind the row at spawn time
# (kilo's Task-tool spawn has no model arg), the driver runs the row as a **headless session** of
# that model over the same work order, and records what actually ran — a pin that can't fire says
# so in the result, instead of silently running the floor model while the row claims a pin.
AI_MODEL_ROLES="researcher analyst writer-task reviewer verifier ship-comment-analyst explorer"

# Remove one member from a k=v config line (no-op when absent); other members survive.
_line_pairs_drop() { # <file> <line-label> <member>…
  local f="$1" label="$2"; shift 2
  local cur kv kk drop new
  cur="$(grep -m1 "^- \*\*${label}:\*\*" "$f" | sed "s|^- \*\*${label}:\*\*[[:space:]]*||" || true)"
  [ -n "$cur" ] || return 0
  for drop in "$@"; do
    new=""
    for kv in $cur; do
      kk="${kv%%=*}"
      [ "$kk" = "$drop" ] && continue
      new="$new $kv"
    done
    cur="${new# }"
  done
  if [ -z "$cur" ]; then
    _line_drop "$f" "$label"
  else
    _line_pairs_set "$f" "$label" $cur
  fi
}

_line_drop() { # <file> <line-label>
  local f="$1" label="$2"
  grep -q "^- \*\*${label}:\*\*" "$f" || return 0
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1
  awk -v pre="- **${label}:** " 'index($0, pre) != 1 { print }' "$f" > "$_pwstage" && mv "$_pwstage" "$f"
}

# Idempotent: insert the dashboard line, all-—, if it doesn't exist yet (covers projects scaffolded
# before this feature existed — same ensure-if-missing idiom as _ai_review_line_ensure).
_ai_models_line_ensure() {
  local f="$1"
  grep -q '^- \*\*AI Models:\*\*' "$f" && return 0
  local default="" r
  for r in $AI_MODEL_ROLES; do default="$default $r=—"; done
  default="${default# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor AI Models: after in $f"
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;   awk -v t="$default" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **AI Models:** " t; d=1}' \
    "$f" > "$_pwstage" && mv "$_pwstage" "$f"
}

# Get (no --set) or set (--set <role>=<value>; — clears to no-row).
#   ai-model --project <slug>                        -> "researcher=— analyst=— writer-task=— reviewer=— verifier=— ship-comment-analyst=—"
#   ai-model --project <slug> --set <role>=<provider:model|—>   -> sets just that lane, leaves the other four untouched
_line_pairs_set() {  # <file> <line-label> <k>=<v>… — batch-update a one-line k=v config line
  local f="$1" label="$2"; shift 2
  local cur pair k v new kv kk found
  cur="$(grep -m1 "^- \*\*${label}:\*\*" "$f" | sed "s|^- \*\*${label}:\*\*[[:space:]]*||" || true)"
  for pair in "$@"; do
    k="${pair%%=*}"; v="${pair#*=}"
    new=""; found=0
    for kv in $cur; do
      kk="${kv%%=*}"
      if [ "$kk" = "$k" ]; then new="$new $k=$v"; found=1; else new="$new $kv"; fi
    done
    [ "$found" = 1 ] || new="$new $k=$v"
    cur="${new# }"
  done
  # Row-integrity gate: `cur` is re-emitted via awk -v (backslash-escape processing), so a
  # reserved character would corrupt or forge the dashboard line.
  case "$cur" in *"|"*|*$'\t'*|*$'\n'*|*'\'*)
    die "_line_pairs_set: value for '${label}:' carries a reserved character (|, TAB, newline, backslash) → fix: strip it" ;; esac
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;   awk -v pre="- **${label}:** " -v t="$cur" '
    !d && index($0, pre) == 1 { print pre t; d=1; next }
    { print } END { if (!d) exit 3 }' "$f" > "$_pwstage" && mv "$_pwstage" "$f"
}

# Creation seed for PLAN settings whose real owner (`task/PLAN.md`) does not exist yet. It is
# creation history, not a second live config: once PLAN exists, the PLAN field is authoritative.
_project_defaults_line_ensure() { # <file>
  local f="$1"
  grep -q '^- \*\*Project Defaults:\*\*' "$f" && return 0
  local seed
  seed="routing=$(pw_project_default_value routing) execution-limit=$(pw_project_default_value execution-limit)"
  [ -n "$(pw_project_default_value max-parallel)" ] && seed="$seed max-parallel=$(pw_project_default_value max-parallel)"
  _axis_line_ensure "$f" "Project Defaults" "Review Budget" $seed \
    || die "cannot insert the Project Defaults: line in $f → fix: repair the dashboard config lines first (/pw-config ensure --project <slug>)"
}

_project_defaults_has_line() { # <file>
  grep -q '^- \*\*Project Defaults:\*\*' "$1" 2>/dev/null
}

_project_defaults_member() { # <file> <member>
  local f="$1" m="$2" kv
  for kv in $(grep -m1 '^- \*\*Project Defaults:\*\*' "$f" 2>/dev/null | sed 's/^- \*\*Project Defaults:\*\*[[:space:]]*//' || true); do
    [ "${kv%%=*}" = "$m" ] && { printf '%s' "${kv#*=}"; return 0; }
  done
  return 0   # absent seed is not an error: legacy projects follow their own/built-in defaults
}

# Companion tuning line. It is machine-owned and holds whitespace-safe `role=variant:x,...` tokens;
# the base model stays in the existing AI Models row so older readers keep working unchanged.
_ai_model_tuning_line_ensure() { # <file>
  local f="$1"
  grep -q '^- \*\*AI Model Tuning:\*\*' "$f" && return 0
  grep -q '^- \*\*AI Models:\*\*' "$f" || _ai_models_line_ensure "$f"
  _axis_line_ensure "$f" "AI Model Tuning" "AI Models" \
    || die "cannot insert the AI Model Tuning: line in $f → fix: repair the AI Models: dashboard line first"
}

# _ai_review_validate now lives with the review-axis block below (surface registry + two-mode enum).

_ai_model_validate() { # <role> <provider:model|—>
  case " $AI_MODEL_ROLES " in *" $1 "*) ;; *) die "invalid role '$1' (allowed: $AI_MODEL_ROLES)" ;; esac
  _model_pin_validate "ai-model '$1=$2'" "$2"
}

# Shared write-time gate for every <provider:model> pin (plan 04 rev-c semantics; plan 23 made it
# a shared primitive so task pins ride the SAME validation, never a second implementation):
# a pin that can't bind must be caught at WRITE time (same lesson as the pre-spawn availability
# gate): membership (enabled Agent Provider), permission = allowlist (model-check), availability
# = live catalog + configured API-provider scope (model-resolve). "unverified" (no catalog
# surface, CLI off PATH) passes fail-open — a non-zero here is a positive determination.
#   _model_pin_validate <context-label> <provider:model|—>
_model_pin_validate() {
  local context="$1" value="$2"
  case "$value" in
    —|-) return 0 ;;  # clearing to no-pin/no-row is always valid
    *:*)
      local _prov="${value%%:*}" _mdl="${value#*:}" _mres _mrc=0 _pp _pin=0
      [ -n "$_prov" ] && [ -n "$_mdl" ] \
        || die "invalid value '$value' ($context) — write <provider>:<model> (e.g. kilo:command_code/<m>, claude:sonnet) or — to clear"
      for _pp in "${PW_PROVIDERS[@]}"; do [ "$_pp" = "$_prov" ] && _pin=1; done
      [ "$_pin" = 1 ] || die "$context refused at write time — provider '$_prov' is not an enabled Agent Provider (pw.config.sh PW_PROVIDERS: ${PW_PROVIDERS[*]})"
      cmd_model_check --provider "$_prov" --model "$_mdl" >/dev/null
      _mres="$(cmd_model_resolve --provider "$_prov" --model "$_mdl" 2>&1)" || _mrc=$?
      if [ "$_mrc" = 1 ] || [ "$_mrc" = 2 ]; then
        die "$context refused at write time — $_mres"
      fi ;;
    *) die "invalid value '$value' ($context) — write <provider>:<model> (e.g. kilo:command_code/<m>, claude:sonnet) or — to clear" ;;
  esac
}

# --- model tuning capability table -----------------------------------------------------------
# Capability metadata is LOCAL and documented, never a guessed equivalence between providers.
# "unknown" means the provider exposes no trustworthy metadata; an explicit tuning request is then
# refused instead of silently dropped. `model-check` performs no inference request.
_model_capability() { # <provider> <variant|reasoning|effort>
  local prov="$1" control="$2"
  case "$prov:$control" in
    claude:effort)        printf 'low,medium,high,xhigh,max' ;;
    claude:variant|claude:reasoning) printf 'unsupported' ;;
    codex:reasoning|codex:effort)    printf 'low,medium,high,xhigh' ;;
    codex:variant)        printf 'unsupported' ;;
    kilo:variant)         printf 'low,medium,high,xhigh,max,minimal' ;;
    kilo:reasoning|kilo:effort)      printf 'unknown' ;;
    cursor:reasoning)     printf 'low,medium,high,xhigh' ;;
    cursor:effort)        printf 'low,medium,high' ;;
    cursor:variant)       printf 'catalog-id-suffix' ;;
    opencode:*)           printf 'unknown' ;;
    *:*)                  printf 'unknown' ;;
  esac
}

_model_is_one_of() { # <value> <comma-list> -> 0 when present or list is catalog-id-suffix
  local v="$1" list="$2" e
  [ "$list" = "catalog-id-suffix" ] && return 0
  case ",$list," in *",$v,"*) return 0 ;; esac
  return 1
}

_model_tuning_summary() { # <provider> <model> -> human capability lines
  local prov="$1" model="$2" c vals
  for c in variant reasoning effort; do
    vals="$(_model_capability "$prov" "$c")"
    printf '  %-10s: %s\n' "$c" "$vals"
  done
  printf '  %-10s: %s\n' "evidence" "local documented adapter constraints (no model request; catalog availability is separate)"
}

_model_tuning_validate() { # <context> <provider> <model> <variant> <reasoning> <effort>
  local ctx="$1" prov="$2" model="$3" variant="$4" reasoning="$5" effort="$6"
  local c val list
  for c in variant reasoning effort; do
    case "$c" in variant) val="$variant" ;; reasoning) val="$reasoning" ;; effort) val="$effort" ;; esac
    [ -n "$val" ] || continue
    list="$(_model_capability "$prov" "$c")"
    case "$list" in
      unsupported) die "$ctx — provider '$prov' has no verified '$c' control (unsupported) → fix: remove --$c" ;;
      unknown)     die "$ctx — '$prov $c' capability is unverified; refusing to guess → fix: remove --$c or use a provider with documented $c support" ;;
      catalog-id-suffix)
        if printf '%s\n' "$(pw_api_catalog "$prov")" | grep -Fx -- "${model}-${val}" >/dev/null 2>&1; then
          :
        else
          die "$ctx — Cursor variant '$val' is not a catalog id for base '$model' → fix: use a catalog-listed variant id, or an inline '<id>[param=value]' form" 
        fi ;;
      *)
        _model_is_one_of "$val" "$list" \
          || die "$ctx — invalid $c '$val' for $prov (allowed: $list) → fix: choose one of the documented values" ;;
    esac
  done
}

# Serialize a role binding's tuning as the dashboard-safe token `variant:x,reasoning:y,effort:z`.
_model_tuning_token() { # <variant> <reasoning> <effort>
  local out="" v
  v="${1:-}"; [ -n "$v" ] && out="variant:$v"
  v="${2:-}"; [ -n "$v" ] && out="${out:+$out,}reasoning:$v"
  v="${3:-}"; [ -n "$v" ] && out="${out:+$out,}effort:$v"
  printf '%s' "$out"
}

_ai_model_json() { # <file> — complete per-role bindings, including companion tuning
  local f="$1" line tune r v t m first=1 prov vv rv ev
  line="$(grep -m1 '^- \*\*AI Models:\*\*' "$f" 2>/dev/null | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//' || true)"
  tune="$(grep -m1 '^- \*\*AI Model Tuning:\*\*' "$f" 2>/dev/null | sed 's/^- \*\*AI Model Tuning:\*\*[[:space:]]*//' || true)"
  printf '{"schema_version":1,"roles":{'
  for r in $AI_MODEL_ROLES; do
    v="—"
    for kv in $line; do [ "${kv%%=*}" = "$r" ] && v="${kv#*=}"; done
    t=""
    for kv in $tune; do [ "${kv%%=*}" = "$r" ] && t="${kv#*=}"; done
    [ "$first" = 1 ] || printf ','
    first=0
    m="${v#*:}"; [ "$v" = "—" ] && m=""
    prov="${v%%:*}"; [ "$v" = "—" ] && prov=""
    vv="$(_tuning_field "$t" variant)"
    rv="$(_tuning_field "$t" reasoning)"
    ev="$(_tuning_field "$t" effort)"
    printf '"%s":{"model":"%s","provider":"%s","variant":"%s","reasoning":"%s","effort":"%s","tuning":"%s"}' \
      "$r" "$m" "$prov" "$vv" "$rv" "$ev" "$t"
  done
  printf '}}\n'
}

# One axis out of the stored `variant:x,reasoning:y,effort:z` token (empty when absent).
_tuning_field() { # <token> <variant|reasoning|effort>
  local kv
  for kv in $(printf '%s' "${1:-}" | tr ',' ' '); do
    [ "${kv%%:*}" = "$2" ] && { printf '%s' "${kv#*:}"; return 0; }
  done
  return 0
}

cmd_ai_model() {
  local slug="" a v s json=0 variant="" reasoning="" effort="" tuning_given=0
  local -a sets; sets=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --set=*)     v="${a#*=}"; a="--set" ;;
      --variant=*) v="${a#*=}"; a="--variant" ;;
      --reasoning=*) v="${a#*=}"; a="--reasoning" ;;
      --effort=*)  v="${a#*=}"; a="--effort" ;;
    esac
    case "$a" in
      --project|--set|--variant|--reasoning|--effort)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --project) slug="$v" ;;
          --set) sets+=("$v") ;;
          --variant) variant="$v"; tuning_given=1 ;;
          --reasoning) reasoning="$v"; tuning_given=1 ;;
          --effort) effort="$v"; tuning_given=1 ;;
        esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "ai-model --project <slug> [--set <role=value>]… [--variant <v> --reasoning <v> --effort <v>] [--json]   (roles: $AI_MODEL_ROLES)" ;;
      *) _pw_positional "$a" "ai-model --project <slug> [--set <role=value>]… [--json]   (roles: $AI_MODEL_ROLES)" ;;
    esac
  done
  [ -n "$slug" ] || die "ai-model: --project is required → fix: ai-model --project <slug> [--set <role=value>]…   (roles: $AI_MODEL_ROLES)"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  # Read-only by contract (S23): the ensure (a WRITE) runs only for a set; a missing line on
  # read shows the all-— defaults without writing.
  if [ ${#sets[@]} -gt 0 ]; then
    _ai_models_line_ensure "$f"
  elif ! grep -q '^- \*\*AI Models:\*\*' "$f"; then
    printf 'pw-config: note: AI Models line missing from the README — showing defaults; nothing was written (persist with: /pw-config set --project %s --key ai-model --set <role>=<value>)\n' "$slug" >&2
  fi
  if [ ${#sets[@]} -eq 0 ]; then
    if [ "$json" = 1 ]; then _ai_model_json "$f"; return 0; fi
    if grep -q '^- \*\*AI Models:\*\*' "$f"; then
      grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//'
    else
      local r out=""; for r in $AI_MODEL_ROLES; do out="$out $r=—"; done
      printf '%s\n' "${out# }"
    fi
    return 0
  fi
  [ "$json" = 0 ] || die "ai-model: --json is read-only; drop --set"
  if [ "$tuning_given" = 1 ]; then
    [ ${#sets[@]} -eq 1 ] \
      || die "ai-model: named tuning applies to exactly ONE role per invocation → fix: give one --set <role>=<provider:model> (set roles separately, each with its own tuning)"
  fi
  for s in "${sets[@]}"; do
    case "$s" in *=*) ;; *) die "ai-model: --set expects <role>=<provider:model|—>, got '$s' (roles: $AI_MODEL_ROLES)" ;; esac
    _ai_model_validate "${s%%=*}" "${s#*=}"
    if [ "$tuning_given" = 1 ]; then
      local pv="${s#*=}"
      [ "$pv" != "—" ] && [ "$pv" != "-" ] \
        || die "ai-model: tuning needs a real <provider:model> binding, not a cleared role"
      case "$pv" in *:*) ;; *) die "ai-model: tuning needs <provider:model>, got '$pv'" ;; esac
      _model_tuning_validate "ai-model '${s%%=*}'" "${pv%%:*}" "${pv#*:}" "$variant" "$reasoning" "$effort"
    fi
  done
  _line_pairs_set "$f" "AI Models" "${sets[@]}"
  if [ "$tuning_given" = 1 ]; then
    local role="${sets[0]%%=*}" token
    token="$(_model_tuning_token "$variant" "$reasoning" "$effort")"
    _ai_model_tuning_line_ensure "$f"
    if [ -n "$token" ]; then
      _line_pairs_set "$f" "AI Model Tuning" "$role=$token"
    else
      _line_pairs_drop "$f" "AI Model Tuning" "$role"
    fi
  else
    # A model replacement owns the whole binding: omitted tuning resets the role's companion
    # controls instead of carrying a possibly invalid setting forward to a different model.
    for s in "${sets[@]}"; do _line_pairs_drop "$f" "AI Model Tuning" "${s%%=*}"; done
  fi
  if [ ${#sets[@]} -eq 1 ]; then
    local detail="${sets[0]#*=}" detail_token
    detail_token="$(_model_tuning_token "$variant" "$reasoning" "$effort")"
    [ "$tuning_given" = 1 ] && [ -n "$detail_token" ] && detail="$detail ($detail_token)"
    "$ST" log --project "$slug" --actor "ai-model" --message "${sets[0]%%=*} -> $detail"
    echo "$slug: AI Model ${sets[0]%%=*} -> $detail"
  else
    "$ST" log --project "$slug" --actor "ai-model" --message "set: ${sets[*]}"
    echo "$slug: AI Models set: ${sets[*]}"
  fi
}

# --- AI-assisted review (optional delegated review pass — see docs/REVIEW.md + the pw-review
# skill) -----------------------------------------------------------------------------------------
# FOUR per-project review axes over the same surface registry (context analysis plan task-plan
# task-exec ship rfc close):
#   ai-review      <surface>=advisory|auto — OUTCOME only. advisory keeps approval with the
#                  human; auto lets ONE guarded tool call (pw-review.sh auto-signoff) approve a
#                  genuinely clean pass. The removed legacy `off` value reads as effective
#                  `advisory` (missing rows too) — an explicit /pw-review … ai request is never
#                  silently dead; /pw-config ensure --project <slug> persists the normalization.
#   review-trigger <surface>=manual|completion — SCHEDULING only. completion runs a pass after
#                  a successful producing command's verification; explicit requests stay
#                  available under BOTH values. Missing rows mean manual.
#   review-repair  <surface>=manual|bounded — whether a completion review may run the bounded
#                  review→repair→verify→fresh-review cycle. Missing rows mean manual.
#   review-rounds  n (1..3, default 3) — total reviewer passes in that cycle; with 3, at most
#                  TWO intervening verified repairs (review 1 → repair 1 → review 2 → repair 2
#                  → review 3 → stop).
# Outcome alone never schedules a pass; scheduling never approves; repair is its own permission;
# a clean EXTERNAL report import stays advisory regardless of outcome.
AI_REVIEW_PHASES="context analysis plan task-plan task-exec ship rfc close"
REVIEW_TRIGGER_VALUES="manual completion"
REVIEW_REPAIR_VALUES="manual bounded"

# Effective outcome of a stored value: legacy `off` (and a missing row) reads `advisory`.
# Every read path normalizes through here so the migration never blocks manual review.
_review_mode_effective() {
  case "${1:-}" in off|""|—|-) printf 'advisory' ;; *) printf '%s' "$1" ;; esac
}

# Bundle-wide default for NEW rows: PW_AI_REVIEW_DEFAULT, with legacy/unknown values normalized
# to advisory (an old floor of `off` must not resurrect a dead review surface).
_review_default_mode() {
  local v="${PW_AI_REVIEW_DEFAULT:-advisory}"
  case "$v" in advisory|auto) printf '%s' "$v" ;; *) printf 'advisory' ;; esac
}

# Default k=v string for an axis line when it is absent from the README. Read-only getters
# show these WITHOUT writing (S23); the set path persists via the ensure chain.
_axis_default_kvs() { # <axis>
  local p out=""
  case "$1" in
    ai-review)
      local d; d="$(_review_default_mode)"
      for p in $AI_REVIEW_PHASES; do out="$out $p=$d"; done ;;
    review-trigger|review-repair)
      for p in $AI_REVIEW_PHASES; do out="$out $p=manual"; done ;;
  esac
  printf '%s\n' "${out# }"
}

# Idempotent: insert one review-axis line if missing, after the line whose bold label is
# <anchor-label> (fixed-string prefix match — never an ERE, backslash escapes differ across
# awks). Requires the One-liner floor; rc 1 when the anchor line is absent.
_axis_line_ensure() { # <file> <label> <anchor-label> <k=v…>
  local f="$1" label="$2" anchorlabel="$3"; shift 3
  grep -q "^- \*\*${label}:\*\*" "$f" && return 0
  local t="" kv
  for kv in "$@"; do t="$t $kv"; done
  t="${t# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || return 1
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;   if awk -v pre="- **${label}:** " -v t="$t" -v apre="- **${anchorlabel}:** " '
      {print}
      !d && index($0, apre) == 1 {print pre t; d=1}
      END { if (!d) exit 3 }' "$f" > "$_pwstage"; then
    mv "$_pwstage" "$f" || { rm -f "$_pwstage"; return 1; }
    return 0
  fi
  rm -f "$_pwstage"
  return 1
}

# Idempotent line inserts — explicit-line doctrine: absence is a defect, not silence.
_ai_review_line_ensure() {
  local f="$1" d p line=""
  grep -q '^- \*\*AI Review:\*\*' "$f" && return 0
  d="$(_review_default_mode)"
  for p in $AI_REVIEW_PHASES; do line="$line $p=$d"; done
  _axis_line_ensure "$f" "AI Review" "One-liner" ${line# } \
    || die "cannot insert the AI Review: line in $f (no One-liner: anchor) → fix: repair the dashboard or re-scaffold an empty project"
}
_review_trigger_line_ensure() {
  local f="$1" p line=""
  grep -q '^- \*\*Review Trigger:\*\*' "$f" && return 0
  for p in $AI_REVIEW_PHASES; do line="$line $p=manual"; done
  _ai_review_line_ensure "$f"
  _axis_line_ensure "$f" "Review Trigger" "AI Review" ${line# } \
    || die "cannot insert the Review Trigger: line in $f → fix: repair the dashboard AI Review: line first"
}
_review_repair_line_ensure() {
  local f="$1" p line=""
  grep -q '^- \*\*Review Repair:\*\*' "$f" && return 0
  for p in $AI_REVIEW_PHASES; do line="$line $p=manual"; done
  _review_trigger_line_ensure "$f"
  _axis_line_ensure "$f" "Review Repair" "Review Trigger" ${line# } \
    || die "cannot insert the Review Repair: line in $f → fix: repair the dashboard Review Trigger: line first"
}
_review_budget_line_ensure() {
  local f="$1"
  grep -q '^- \*\*Review Budget:\*\*' "$f" && return 0
  _review_repair_line_ensure "$f"
  _axis_line_ensure "$f" "Review Budget" "Review Repair" 'rounds=3' \
    || die "cannot insert the Review Budget: line in $f → fix: repair the dashboard Review Repair: line first"
}

# ensure-only migration: persist legacy off → advisory in the AI Review line.
# rc 0 = migrated, 1 = nothing to migrate (both idempotent; no other value is touched).
_ai_review_line_migrate() {
  local f="$1" cur kv pairs=""
  cur="$(grep -m1 '^- \*\*AI Review:\*\*' "$f" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//' || true)"
  for kv in $cur; do
    case "${kv#*=}" in off) pairs="$pairs ${kv%%=*}=advisory" ;; esac
  done
  [ -n "$pairs" ] || return 1
  _line_pairs_set "$f" "AI Review" $pairs
  return 0
}

# ensure-only: append missing surface rows to an existing axis line (idempotent).
# rc 0 = rows added, 1 = nothing missing.
_axis_line_fill() { # <file> <label> <default-value>
  local f="$1" label="$2" dflt="$3" cur kv pairs="" p have
  cur="$(grep -m1 "^- \*\*${label}:\*\*" "$f" | sed "s|^- \*\*${label}:\*\*[[:space:]]*||" || true)"
  [ -n "$cur" ] || return 1
  for p in $AI_REVIEW_PHASES; do
    have=0
    for kv in $cur; do [ "${kv%%=*}" = "$p" ] && have=1; done
    [ "$have" = 1 ] || pairs="$pairs $p=$dflt"
  done
  [ -n "$pairs" ] || return 1
  _line_pairs_set "$f" "$label" $pairs
  return 0
}

_ai_review_validate() { # <surface> <mode> — die on anything illegal (validate-all-first for batches)
  case " $AI_REVIEW_PHASES " in *" $1 "*) ;; *) die "invalid surface '$1' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$2" in
    advisory|auto) ;;
    off)  die "'off' was removed from ai-review — outcome is advisory|auto; keep review manual with review-trigger=manual instead (explicit AI review stays available). → fix: /pw-config set --project <slug> --key ai-review --set all=advisory" ;;
    *)    die "invalid mode '$2' (allowed: advisory auto) → fix: use advisory (human still approves) or auto (guarded self-approval on a clean pass)" ;;
  esac
}
_review_trigger_validate() {
  case " $AI_REVIEW_PHASES " in *" $1 "*) ;; *) die "invalid surface '$1' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$2" in
    manual|completion) ;;
    both) die "'both' was removed — 'completion' already keeps explicit review available → fix: /pw-config set --project <slug> --key review-trigger --set all=completion (or manual)" ;;
    *)    die "invalid value '$2' (allowed: manual completion) → fix: manual = review only when explicitly requested; completion = also after a successful producing command" ;;
  esac
}
_review_repair_validate() {
  case " $AI_REVIEW_PHASES " in *" $1 "*) ;; *) die "invalid surface '$1' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$2" in
    manual|bounded) ;;
    *) die "invalid value '$2' (allowed: manual bounded) → fix: manual = findings stop for the owner; bounded = completion reviews may repair+re-review within review-rounds" ;;
  esac
}

# Expand an `all=<value>` baseline over the surface registry; explicitly named surfaces override
# the baseline regardless of argument order. Duplicates, unknown surfaces, and a duplicate `all`
# are rejected BEFORE any validation/write. Prints the final ordered pair list (overrides last).
_expand_axis_pairs() { # <axis> <pair…>
  local axis="$1"; shift
  local allv="" s pair seen=" " out="" count=0
  local -a explicit
  explicit=()
  for pair in "$@"; do
    case "$pair" in *=*) ;; *) die "$axis: --set expects <surface>=<value> or all=<value>, got '$pair'" ;; esac
    s="${pair%%=*}"
    if [ "$s" = "all" ]; then
      [ -z "$allv" ] || die "$axis: duplicate all= — give exactly one baseline"
      allv="${pair#*=}"
      continue
    fi
    case " $AI_REVIEW_PHASES " in *" $s "*) ;; *) die "$axis: unknown surface '$s' (allowed: all or $AI_REVIEW_PHASES)" ;; esac
    case "$seen" in *" $s "*) die "$axis: duplicate surface '$s' — name each surface once" ;; esac
    seen="$seen$s "
    explicit+=("$pair")
  done
  if [ -n "$allv" ]; then
    for s in $AI_REVIEW_PHASES; do
      case "$seen" in *" $s "*) continue ;; esac
      out="$out $s=$allv"
    done
  fi
  for pair in ${explicit[@]+"${explicit[@]}"}; do out="$out $pair"; done
  printf '%s\n' "${out# }"
}

# One get/set implementation for the three per-surface review axes (ai-review / review-trigger /
# review-repair): parse --project/--set, ensure line → get (normalized for ai-review) or
# expand+validate+write+log. No --set = read.
_review_axis_cmd() { # <axis> <line-label> <validator-fn> <values-help> <"--project/--set" flags…>
  local axis="$1" label="$2" vfn="$3" vhelp="$4"; shift 4
  local slug="" a v s
  local -a sets; sets=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --set=*)     v="${a#*=}"; a="--set" ;;
    esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --set) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --set; v="$1"; shift; }; sets+=("$v") ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "$axis --project <slug> [--set <surface>=<value>]…   ($vhelp)" ;;
      *) _pw_positional "$a" "$axis --project <slug> [--set <surface>=<value>]…   ($vhelp)" ;;
    esac
  done
  [ -n "$slug" ] || die "$axis: --project is required → fix: $axis --project <slug> [--set <surface>=<value>]…   ($vhelp)"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  # Read-only by contract (S23): the ensure chain (a WRITE) runs only when a set was
  # requested; a missing line on read is reported with its effective defaults, never written.
  if [ ${#sets[@]} -eq 0 ]; then
    local line out kv norm=0
    if grep -q "^- \*\*${label}:\*\*" "$f"; then
      line="$(grep -m1 "^- \*\*${label}:\*\*" "$f" | sed "s|^- \*\*${label}:\*\*[[:space:]]*||" || true)"
    else
      line="$(_axis_default_kvs "$axis")"
      printf 'pw-config: note: %s line missing from the README — showing effective defaults; nothing was written (persist with: /pw-config set --project %s --key %s --set <k>=<v>)\n' "$label" "$slug" "$axis" >&2
    fi
    if [ "$axis" = "ai-review" ]; then
      out=""
      for kv in $line; do
        case "${kv#*=}" in
          off) out="$out ${kv%%=*}=advisory"; norm=1 ;;
          *)   out="$out $kv" ;;
        esac
      done
      [ "$norm" = 1 ] && printf 'pw-config: note: stored legacy off row(s) read as effective advisory — persist with: /pw-config ensure --project %s\n' "$slug" >&2
      printf '%s\n' "${out# }"
      return 0
    fi
    printf '%s\n' "$line"
    return 0
  fi
  local argc=${#sets[@]} expanded pair
  # Set path: persist the anchoring lines before writing (the ensures are WRITE actions).
  case "$axis" in
    ai-review)      _ai_review_line_ensure "$f" ;;
    review-trigger) _review_trigger_line_ensure "$f" ;;
    review-repair)  _review_repair_line_ensure "$f" ;;
  esac
  expanded="$(_expand_axis_pairs "$axis" "${sets[@]}")" || exit 2
  for pair in $expanded; do "$vfn" "${pair%%=*}" "${pair#*=}"; done
  _line_pairs_set "$f" "$label" $expanded
  if [ "$argc" = 1 ] && [ "$(printf '%s' "$expanded" | wc -w | tr -d ' ')" = 1 ]; then
    "$ST" log --project "$slug" --actor "$axis" --message "${expanded%%=*} -> ${expanded#*=}"
    echo "$slug: ${label} ${expanded%%=*} -> ${expanded#*=}"
  else
    "$ST" log --project "$slug" --actor "$axis" --message "set: $expanded"
    echo "$slug: ${label} set: $expanded"
  fi
}

# Get (no --set) or set (--set <surface>=<mode>) this project's per-surface AI-review OUTCOME mode.
#   ai-review --project <slug>                        -> effective rows, legacy off normalized to advisory
#   ai-review --project <slug> --set <surface>=<mode> -> sets just that surface
#   ai-review --project <slug> --set all=<mode> [--set <s>=<mode>] -> baseline + named overrides
cmd_ai_review() {
  _review_axis_cmd ai-review "AI Review" _ai_review_validate "modes: advisory|auto" "$@"
}
cmd_review_trigger() {
  _review_axis_cmd review-trigger "Review Trigger" _review_trigger_validate "values: manual|completion" "$@"
}
cmd_review_repair() {
  _review_axis_cmd review-repair "Review Repair" _review_repair_validate "values: manual|bounded" "$@"
}
# Get/set the bounded cycle's total reviewer passes (1..3, default 3).
#   review-rounds --project <slug>            -> "rounds=3"
#   review-rounds --project <slug> --value <n> -> sets n
cmd_review_rounds() {
  local slug="" val="" hasval=0 a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --value=*)   v="${a#*=}"; a="--value" ;;
    esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --value) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --value; v="$1"; shift; }; val="$v"; hasval=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "review-rounds --project <slug> [--value <n>]   (n: 1..3 — total reviewer passes in a bounded review→repair cycle; default 3)" ;;
      *) _pw_positional "$a" "review-rounds --project <slug> [--value <n>]   (n: 1..3 — total reviewer passes in a bounded review→repair cycle; default 3)" ;;
    esac
  done
  [ -n "$slug" ] || die "review-rounds: --project is required → fix: review-rounds --project <slug> [--value <n>]   (n: 1..3 — total reviewer passes in a bounded review→repair cycle; default 3)"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  # Read-only by contract (S23): the ensure (a WRITE) runs only for a value write.
  if [ "$hasval" -gt 0 ]; then
    _review_budget_line_ensure "$f"
  elif ! grep -q '^- \*\*Review Budget:\*\*' "$f"; then
    printf 'pw-config: note: Review Budget line missing from the README — showing the default; nothing was written (persist with: /pw-config set --project %s --key review-rounds --value <n>)\n' "$slug" >&2
  fi
  if [ "$hasval" = 0 ]; then
    if grep -q '^- \*\*Review Budget:\*\*' "$f"; then
      grep -m1 '^- \*\*Review Budget:\*\*' "$f" | sed 's/^- \*\*Review Budget:\*\*[[:space:]]*//'
    else
      printf 'rounds=3\n'
    fi
    return 0
  fi
  _require_int review-rounds "$val" 1 3
  _line_pairs_set "$f" "Review Budget" "rounds=$val"
  "$ST" log --project "$slug" --actor review-rounds --message "rounds -> $val"
  echo "$slug: Review Budget rounds -> $val"
}



# Guard against an agent picking an unexpectedly expensive model. Reads PW_MODEL_ALLOWLIST_<PROVIDER>
# (uppercased) from pw.config.sh — a comma-separated list of glob patterns matched against the
# model id (the part after the provider prefix, e.g. "opus" or "command_code/deepseek/*").
# Cursor bracket overrides (`glm-5p3-flash[reasoning=low]`) tune the same model, so matching uses
# the BASE id — one allowlist entry permits every tuning of it.
# THE RULE: empty or unset = ALL models allowed for that provider — this is the default, and it's
# deliberate: nothing is restricted unless you explicitly configure a pattern. Never taken on the
# caller's word — this re-reads the config itself, same spirit as auto-signoff re-checking its own
# gate rather than trusting the reviewer. Called by /pw-breakdown (while filling a task's `Execute
# with:`) and /pw-execute (again, right before invoking — catches a hand-edited PLAN.md too); not
# meant to be run directly by a human — see docs/EXECUTION.md's "Model allowlist" section.
#   model-check --provider <p> --model <m>
_model_permission_check() { # <provider> <model> -> 0 allowed; dies on a positive refusal
  local prov="$1" model="$2"
  local upper var allow pats pat matched=0 match_model="$model"
  case "$prov" in *[!A-Za-z0-9_-]*) die "model-check: invalid provider token '$prov' → fix: use a provider name (letters, digits, dash, underscore)" ;; esac
  if [ "$prov" = cursor ]; then
    case "$match_model" in *'['*']') match_model="${match_model%%\[*}" ;; esac
  fi
  upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
  var="PW_MODEL_ALLOWLIST_${upper}"
  allow="${!var:-}"
  if [ -z "$allow" ]; then
    printf 'allowed (PW_MODEL_ALLOWLIST_%s is empty = all models allowed, the default)' "$upper"
    return 0
  fi
  IFS=',' read -ra pats <<< "$allow"
  for pat in "${pats[@]}"; do
    pat="$(printf '%s' "$pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$match_model" in
      $pat) matched=1; break ;;
    esac
  done
  [ "$matched" -eq 1 ] \
    || die "model-check: $prov:$model — refused. Not in PW_MODEL_ALLOWLIST_${upper} (\"$allow\"). Add a matching pattern to pw.config.sh, or choose an allowed model."
  printf 'allowed (matched allowlist pattern "%s")' "$pat"
}

cmd_model_check() {
  local prov="" model="" a v variant="" reasoning="" effort="" json=0
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --provider=*) v="${a#*=}"; a="--provider" ;;
      --model=*)    v="${a#*=}"; a="--model" ;;
      --variant=*)  v="${a#*=}"; a="--variant" ;;
      --reasoning=*) v="${a#*=}"; a="--reasoning" ;;
      --effort=*)   v="${a#*=}"; a="--effort" ;;
    esac
    case "$a" in
      --provider|--model|--variant|--reasoning|--effort)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --provider) prov="$v" ;; --model) model="$v" ;;
          --variant) variant="$v" ;; --reasoning) reasoning="$v" ;; --effort) effort="$v" ;;
        esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "model-check --provider <p> --model <m> [--variant <v>] [--reasoning <v>] [--effort <v>] [--json]" ;;
      *) _pw_positional "$a" "model-check --provider <p> --model <m> [--tuning] [--json]" ;;
    esac
  done
  [ -n "$prov" ] || die "model-check: --provider is required → fix: model-check --provider <p> --model <m>   (empty PW_MODEL_ALLOWLIST_<PROVIDER> = all models allowed)"
  [ -n "$model" ] || die "model-check: --model is required → fix: model-check --provider <p> --model <m>   (empty PW_MODEL_ALLOWLIST_<PROVIDER> = all models allowed)"
  # Sink gate: the provider token becomes a variable NAME below (`${!var}` indirect expansion),
  # so it must be a plain token — never an unchecked string from a PLAN cell (a crafted
  # `kilo[$(cmd)]` would evaluate its subscript as arithmetic). Provider membership is enforced
  # where pins are WRITTEN (_model_pin_validate); model-check itself keeps its documented
  # semantics (an unset/empty PW_MODEL_ALLOWLIST_<PROVIDER> = all models allowed).
  case "$prov" in *[!A-Za-z0-9_-]*) die "model-check: invalid provider token '$prov' → fix: use a provider name (letters, digits, dash, underscore)" ;; esac
  local permission allowvar allow
  allowvar="PW_MODEL_ALLOWLIST_$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
  allow="${!allowvar:-}"
  permission="$(_model_permission_check "$prov" "$model")"
  # Tuning is validated on top of model identity: permission alone never proves a control exists.
  _model_tuning_validate "model-check $prov:$model" "$prov" "$model" "$variant" "$reasoning" "$effort"
  if [ "$json" = 1 ]; then
    local cv cr ce
    cv="$(_model_capability "$prov" variant)"; cr="$(_model_capability "$prov" reasoning)"; ce="$(_model_capability "$prov" effort)"
    printf '{"provider":"%s","model":"%s","permission":"allowed","allowlist":"%s","requested":{"variant":"%s","reasoning":"%s","effort":"%s"},"capabilities":{"variant":"%s","reasoning":"%s","effort":"%s"},"evidence":"local documented adapter constraints"}\n' \
      "$prov" "$model" "$allow" "$variant" "$reasoning" "$effort" "$cv" "$cr" "$ce"
    return 0
  fi
  echo "model-check: $prov:$model — $permission"
  _model_tuning_summary "$prov" "$model"
  [ -z "$variant$reasoning$effort" ] || printf '  %-10s: %s\n' "requested" "variant=${variant:-—} reasoning=${reasoning:-—} effort=${effort:-—} (validated)"
  return 0
}


# Availability sibling of cmd_model_check (permission vs. availability — model-check NEVER
# proves a model exists, it only tests the allowlist). Resolves a task/PLAN row's model part
# against the provider's LIVE catalog and the PW_<PROVIDER>_API_PROVIDERS prefix scope
# (pw-common.sh §API-provider scope helpers), printing the canonical catalog id to bind with
# (`-m`/`--model` must receive that line, never the raw row text). The agent-provider prefix is
# SEMANTIC, not cosmetic: a BYOK wired up *directly* in the provider CLI is its own catalog line
# (`alibaba-token-plan/<m>`) and the same BYOK registered *under* the gateway is a different one
# (`kilo/alibaba-token-plan/<m>`) — different connections, auth, and billing — so matching is
# EXACT-FIRST: the row binds the line it literally names, and the prefix-less form falls back to
# the gateway line only when no direct line exists, announcing the substitution on stderr.
# Fail-open on "can't check" (claude has no catalog; a CLI off
# PATH, an empty catalog, or an unknown provider = unverified, exit 0) — a non-zero here is a
# POSITIVE determination, which is what makes it safe as a pre-spawn hard stop.
# Cursor has THREE sources (verified 2026-10-22): `agent models`, then cli-config.json
# modelParameters (desktop-only ids — `pw_api_catalog` merges both, so a config-only id
# resolves in the normal path and is announced on stderr), then an opt-in live probe
# (`--probe` / PW_CURSOR_PROBE=1) for an id neither source lists.
#   model-resolve --provider <p> --model <m> [--probe]
cmd_model_resolve() {
  local prov="" model="" a v probe=0
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --provider=*) v="${a#*=}"; a="--provider" ;;
      --model=*)    v="${a#*=}"; a="--model" ;;
    esac
    case "$a" in
      --provider|--model)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --provider) prov="$v" ;; --model) model="$v" ;; esac ;;
      --probe)    probe=1 ;;
      --no-probe) probe=0 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "model-resolve --provider <p> --model <m> [--probe]" ;;
      *) _pw_positional "$a" "model-resolve --provider <p> --model <m> [--probe]" ;;
    esac
  done
  [ -n "$prov" ] || die "model-resolve: --provider is required → fix: model-resolve --provider <p> --model <m> [--probe]   (prints the canonical catalog id on exit 0)"
  [ -n "$model" ] || die "model-resolve: --model is required → fix: model-resolve --provider <p> --model <m> [--probe]   (prints the canonical catalog id on exit 0)"
  local catalog cli_catalog="" line cands upper via=0 base="" model_suffix="" pids params _p _k _v
  case "$prov" in
    claude)
      echo "model-resolve: $prov:$model — unverified (Claude Code has a fixed alias set, no queryable catalog; model-check governs)"
      return 0 ;;
    kilo|opencode|cursor|codex) ;;
    *)
      echo "model-resolve: $prov:$model — unverified (no catalog surface for provider '$prov')"
      return 0 ;;
  esac
  catalog="$(pw_api_catalog "$prov")"
  if [ -z "$catalog" ]; then
    echo "model-resolve: $prov:$model — unverified ('$prov' catalog empty or CLI not on PATH)" >&2
    return 0
  fi
  # Cursor parameter overrides: `glm-5p3-flash[reasoning=low]` (the `agent --model` bracket
  # syntax) is a base model plus per-run tuning, not a catalog id. Validate the suffix shape,
  # resolve the BASE against the catalogs, and print the canonical base WITH the suffix intact
  # (the headless `--model` needs the whole string).
  base="$model"
  if [ "$prov" = cursor ]; then
    case "$model" in
      *'['*']')
        base="${model%%\[*}"
        model_suffix="${model#"$base"}"
        params="${model_suffix#\[}"; params="${params%\]}"
        if [ -z "$base" ]; then
          echo "model-resolve: $prov:$model — malformed parameter override (empty base id) (exit 1)" >&2
          return 1
        fi
        case "$params" in
          ''|*[!A-Za-z0-9_,.=:-]*)
            echo "model-resolve: $prov:$model — malformed parameter override; expected '<id>[<param>=<value>,…]' (exit 1)" >&2
            return 1 ;;
        esac
        IFS=',' read -ra pids <<< "$params"
        for _p in "${pids[@]}"; do
          case "$_p" in *=*) _k="${_p%%=*}"; _v="${_p#*=}" ;; *)
            echo "model-resolve: $prov:$model — malformed parameter '$_p'; expected <param>=<value> (exit 1)" >&2
            return 1 ;;
          esac
          case "$_k" in ''|*[!A-Za-z0-9_]*)
            echo "model-resolve: $prov:$model — malformed parameter name '$_k' (exit 1)" >&2
            return 1 ;;
          esac
          case "$_v" in ''|*[!A-Za-z0-9._:-]*)
            echo "model-resolve: $prov:$model — malformed value for '$_k' (exit 1)" >&2
            return 1 ;;
          esac
        done ;;
      *'['*|*']'*)
        echo "model-resolve: $prov:$model — malformed parameter override; expected '<id>[<param>=<value>,…]' (exit 1)" >&2
        return 1 ;;
    esac
  fi
  # Cursor's merged catalog hides which source matched; keep the CLI-only list so a
  # desktop-config hit is announced rather than silently treated as a CLI catalog line.
  if [ "$prov" = cursor ]; then cli_catalog="$(pw_cursor_cli_models)"; fi
  # EXACT catalog line first — the prefix distinguishes connections (see header), so a bare
  # row must never silently bind the gateway line when a direct provider line exists.
  line="$(printf '%s\n' "$catalog" | grep -F -x "$base" | head -1 || true)"
  if [ -z "$line" ]; then
    line="$(printf '%s\n' "$catalog" | grep -F -x "$prov/$base" | head -1 || true)"
    via=1
  fi
  if [ -z "$line" ] && [ "$prov" = cursor ] && { [ "$probe" = 1 ] || [ "${PW_CURSOR_PROBE:-0}" = 1 ]; }; then
    # Last source: one live ask. Reached only when BOTH catalogs miss, so a normal pin never
    # pays for a probe; a success proves the gateway accepts the id even though nothing lists it.
    if pw_cursor_probe_model "$model"; then
      echo "model-resolve: $prov:$model — absent from 'agent models' and cli-config modelParameters; verified by live probe" >&2
      printf '%s\n' "$model"
      return 0
    fi
    echo "model-resolve: $prov:$model — live probe failed (model refused, gated, or unreachable) (exit 1)" >&2
  fi
  if [ -z "$line" ]; then
    echo "model-resolve: $prov:$model — not in the live catalog (exit 1)" >&2
    if [ "$prov" = cursor ]; then
      echo "  → sources checked: \`agent models\` and ${PW_CURSOR_CLI_CONFIG:-~/.cursor/cli-config.json} modelParameters. Add PW_CURSOR_PROBE=1 (or --probe) to try one live call for a desktop-only id." >&2
    fi
    echo "  → fix: re-pin the row to a real id — candidates from the '$prov' catalog (\`pw-help\` lists each provider's catalog command):" >&2
    cands="$(printf '%s\n' "$catalog" | grep -F "${base##*/}" | head -5 || true)"
    [ -n "$cands" ] && printf '%s\n' "$cands" | sed 's/^/      /' >&2 || echo "      (none matching '${base##*/}' — check the provider scope too)" >&2
    return 1
  fi
  if [ "$via" = 1 ]; then
    echo "model-resolve: $prov:$model — no exact catalog line; bound the gateway-nested '$line'. A direct provider '$base' is a different connection; pin the full id if you meant the other." >&2
  fi
  if [ "$prov" = cursor ] && [ -n "$cli_catalog" ]; then
    # grep -F -x without -q: a -q early exit SIGPIPEs printf under pipefail (bundle lesson).
    if ! printf '%s\n' "$cli_catalog" | grep -F -x -- "$line" >/dev/null; then
      echo "model-resolve: $prov:$line — resolved from cli-config modelParameters (absent from 'agent models'; desktop-only id)" >&2
    fi
  fi
  if ! pw_api_in_scope "$prov" "$line"; then
    upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
    echo "model-resolve: $prov:$model — matched '$line' but it is OUTSIDE the PW_${upper}_API_PROVIDERS scope (exit 2)" >&2
    echo "  → fix: restore the matching entry in pw.config.sh, or re-pin the row to an in-scope id. Current scope:" >&2
    pw_api_entries "$prov" | sed 's/^/      /' >&2
    return 2
  fi
  printf '%s\n' "$line$model_suffix"
}

# --- per-project config (top-level show/get/set/ensure) + global floors ------------------------
# Storage stays markdown (dashboard/PLAN/META — the single source of truth; no parallel .pwrc).
# kind split (owner decision): config = a get/set knob; state/data = derived facts the owning flow
# writes — show lists them, get/set refuses them.
CONFIG_KEYS="routing execution-limit max-parallel produced-by ai-review ai-model pin rfc-target review-trigger review-repair review-rounds"
STATE_KEYS="status adopted base-branches landing-units"

_dep_note() {
  printf 'pw-config: bare "%s" is deprecated — use "%s" (one per-project config surface; /pw-config wraps it)\n' "$1" "$2" >&2
}

_plan_value() {  # <file> <bold-label> -> trimmed value, empty when the bullet/placeholder absent
  local v; v="$(pw_field "$1" "$2")"
  case "$v" in "<"*">"*) printf '%s' "" ;; *) printf '%s' "$v" ;; esac
}

_plan_set_bullet() {  # <file> <bold-label> <value> <insert-anchor-ERE>
  local f="$1" label="$2" value="$3" anchor="$4"
  if grep -qE "^- \*\*${label}:\*\*" "$f"; then
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;     awk -v label="$label" -v value="$value" '
      !done && index($0, "- **" label ":**") == 1 { print "- **" label ":** " value; done=1; next }
      { print } END { if (!done) exit 3 }' "$f" > "$_pwstage" && mv "$_pwstage" "$f" && return 0
    rm -f "$_pwstage"; return 3
  fi
  if [ -n "$anchor" ] && grep -qE "$anchor" "$f"; then
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;     awk -v label="$label" -v value="$value" -v anchor="$anchor" '
      { print }
      !done && $0 ~ anchor { print "- **" label ":** " value; done=1 }
      END { if (!done) exit 3 }' "$f" > "$_pwstage" && mv "$_pwstage" "$f" && return 0
    rm -f "$_pwstage"; return 3
  fi
  return 3
}

_plan_get_maxparallel() {  # <plan> -> digits, empty when unset/placeholder
  local v; v="$(grep -m1 '^- Max parallelism:' "$1" | sed -n 's/^- Max parallelism:[[:space:]]*\([0-9][0-9]*\).*/\1/p' || true)"
  printf '%s' "$v"
}

_plan_set_maxparallel() {
  local f="$1" value="$2"
  grep -qE '^- Max parallelism:' "$f" || return 3
_pwstage="$(pw_tmpfile "$(dirname "$f")")" || return 1;   awk -v value="$value" '
    !done && /^- Max parallelism:/ { print "- Max parallelism: " value " concurrent executors."; done=1; next }
    { print } END { if (!done) exit 3 }' "$f" > "$_pwstage" && mv "$_pwstage" "$f" && return 0
  rm -f "$_pwstage"; return 3
}

_require_int() { # <key> <value> <min> <max>
  case "$2" in ''|*[!0-9]*) die "$1: expected an integer ($3..$4), got '$2'" ;; esac
  [ "$2" -ge "$3" ] && [ "$2" -le "$4" ] || die "$1: expected $3..$4, got $2"
}

cmd_show() {
  local slug="" json=0 a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "show --project <slug> [--json]" ;;
      *) _pw_positional "$a" "show --project <slug> [--json]" ;;
    esac
  done
  [ -n "$slug" ] || die "show: --project is required → fix: show --project <slug> [--json]"
  local d; d="$(proj_dir "$slug")"
  local readme="$d/README.md" plan="$d/task/PLAN.md" meta="$d/rfc/META.md"
  [ -f "$readme" ] || die "no README.md in project $slug"
  local rows=""
  _row() { # key kind stored source effective
    rows="$rows$1	$2	$3	$4	$5
"
  }
  local line v kv k p r f t legacy_off=0 src
  line="$(grep -m1 '^- \*\*Status:\*\*' "$readme" | sed 's/^- \*\*Status:\*\*[[:space:]]*//' || true)"
  _row status state "${line:-—}" "README.md:Status" "—"
  line="$(grep -m1 '^- \*\*AI Models:\*\*' "$readme" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//' || true)"
  local tune; tune="$(grep -m1 '^- \*\*AI Model Tuning:\*\*' "$readme" | sed 's/^- \*\*AI Model Tuning:\*\*[[:space:]]*//' || true)"
  for r in $AI_MODEL_ROLES; do
    v="—"
    for kv in $line; do k="${kv%%=*}"; [ "$k" = "$r" ] && v="${kv#*=}"; done
    if [ "$v" != "—" ]; then
      for kv in $tune; do [ "${kv%%=*}" = "$r" ] && v="$v ($(printf '%s' "${kv#*=}" | tr ',' ' '))"; done
    fi
    _row "ai-model.$r" config "$v" "README.md:AI Models" "provider/session default"
  done
  line="$(grep -m1 '^- \*\*AI Review:\*\*' "$readme" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//' || true)"
  for p in $AI_REVIEW_PHASES; do
    v="—"
    for kv in $line; do k="${kv%%=*}"; [ "$k" = "$p" ] && v="${kv#*=}"; done
    case "$v" in off) legacy_off=1 ;; esac
    _row "ai-review.$p" config "$v" "README.md:AI Review" "$(_review_mode_effective "$v")"
  done
  line="$(grep -m1 '^- \*\*Review Trigger:\*\*' "$readme" | sed 's/^- \*\*Review Trigger:\*\*[[:space:]]*//' || true)"
  for p in $AI_REVIEW_PHASES; do
    v="—"
    for kv in $line; do k="${kv%%=*}"; [ "$k" = "$p" ] && v="${kv#*=}"; done
    _row "review-trigger.$p" config "$v" "README.md:Review Trigger" "manual"
  done
  line="$(grep -m1 '^- \*\*Review Repair:\*\*' "$readme" | sed 's/^- \*\*Review Repair:\*\*[[:space:]]*//' || true)"
  for p in $AI_REVIEW_PHASES; do
    v="—"
    for kv in $line; do k="${kv%%=*}"; [ "$k" = "$p" ] && v="${kv#*=}"; done
    _row "review-repair.$p" config "$v" "README.md:Review Repair" "manual"
  done
  v="$(grep -m1 '^- \*\*Review Budget:\*\*' "$readme" | sed -n 's/.*rounds=\([0-9][0-9]*\).*/\1/p' || true)"
  _row review-rounds config "${v:-—}" "README.md:Review Budget" "3"
  v="—"
  if [ -f "$plan" ]; then v="$(_plan_value "$plan" Routing)"; src="task/PLAN.md:Routing"
  elif _project_defaults_has_line "$readme"; then v="$(_project_defaults_member "$readme" routing)"; src="README.md:Project Defaults (pending PLAN)"
  else v=""; src="built-in default"; fi
  [ -n "$v" ] || v="—"; _row routing config "$v" "$src" "$PW_ROUTE_DEFAULT"
  v="—"
  if [ -f "$plan" ]; then v="$(_plan_value "$plan" "AI execution limit")"; src="task/PLAN.md:AI execution limit"
  elif _project_defaults_has_line "$readme"; then v="$(_project_defaults_member "$readme" execution-limit)"; src="README.md:Project Defaults (pending PLAN)"
  else v=""; src="built-in default"; fi
  [ -n "$v" ] || v="—"; _row execution-limit config "$v" "$src" "$PW_MAX_SELF_REPAIR"
  v="—"
  if [ -f "$plan" ]; then v="$(_plan_get_maxparallel "$plan")"; src="task/PLAN.md:Max parallelism"
  elif _project_defaults_has_line "$readme"; then v="$(_project_defaults_member "$readme" max-parallel)"; src="README.md:Project Defaults (pending PLAN)"
  else v=""; src="built-in default"; fi
  [ -n "$v" ] || v="—"; _row max-parallel config "$v" "$src" "—"
  v="—"; [ -f "$plan" ] && v="$(_plan_value "$plan" "Produced by")"; [ -n "$v" ] || v="—"
  _row produced-by config "$v" "task/PLAN.md:Produced by" "${PW_PROVIDERS[*]}"
  v="—"; [ -f "$meta" ] && v="$(pw_field "$meta" Target)"; [ -n "$v" ] || v="—"
  _row rfc-target config "$v" "rfc/META.md:Target" "${PW_RFC_BACKEND:-markdown}"
  if [ -d "$d/task" ]; then
    for f in "$d"/task/T*.md; do
      [ -e "$f" ] || continue
      t="$(basename "$f" .md)"
      v="$(pw_field "$f" "Execute with")"; [ -n "$v" ] || v="—"
      _row "pin.$t" config "$v" "task/$t.md:Execute with" "—"
      v="$(pw_field "$f" Effort)"; [ -n "$v" ] && _row "effort.$t" config "$v" "task/$t.md:Effort" "provider/session default"
      v="$(pw_field "$f" Thinking)"; [ -n "$v" ] && _row "thinking.$t" config "$v" "task/$t.md:Thinking" "provider/session default"
      v="$(pw_field "$f" Route)"; [ -n "$v" ] && _row "route.$t" config "$v" "task/$t.md:Route" "PLAN/env"
      v="$(pw_field "$f" "Landing unit")"; [ -n "$v" ] && _row "landing-unit.$t" data "$v" "task/$t.md:Landing unit" "—"
      v="$(pw_field "$f" "Base branch")"; [ -n "$v" ] && _row "base-branch.$t" data "$v" "task/$t.md:Base branch" "—"
    done
  fi
  line="$(grep -m1 '^- \*\*Adopted:\*\*' "$readme" | sed 's/^- \*\*Adopted:\*\*[[:space:]]*//' || true)"
  [ -n "$line" ] && _row adopted state "$line" "README.md:Adopted" "—"
  if [ "$json" = 1 ]; then
    printf '{"slug":"%s","rows":[' "$slug"
    local first=1
    while IFS='	' read -r k p v s e; do
      [ -n "$k" ] || continue
      v="$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      e="$(printf '%s' "$e" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"key":"%s","kind":"%s","stored":"%s","source":"%s","effective":"%s"}' "$k" "$p" "$v" "$s" "$e"
    done <<< "$rows"
    printf '],"ai_model":%s}\n' "$(_ai_model_json "$readme" | tr -d '\n')"
    return 0
  fi
  printf 'pw-config show — %s   (config = get/set knob · state/data = derived fact, show-only)\n' "$slug"
  printf '  %-24s %-6s %-28s %-26s %s\n' KEY KIND STORED SOURCE EFFECTIVE
  while IFS='	' read -r k p v s e; do
    [ -n "$k" ] || continue
    printf '  %-24s %-6s %-28s %-26s %s\n' "$k" "$p" "$v" "$s" "$e"
  done <<< "$rows"
  printf '  settable keys: routing[auto|subagent|headless] execution-limit[int 0..99] max-parallel[int 1..99] produced-by[from PW_PROVIDERS] ai-review[surface=advisory|auto|all=…] ai-model[role=provider:model|—] pin[T0n=provider:model|—] rfc-target[ref] review-trigger[surface=manual|completion|all=…] review-repair[surface=manual|bounded|all=…] review-rounds[int 1..3]\n'
  printf '  show-only (flows derive them; set refuses): status · adopted · base-branches · landing-units\n'
  if [ "$legacy_off" = 1 ]; then
    printf '  note: legacy AI Review off row(s) read as effective advisory — persist with: /pw-config ensure --project %s\n' "$slug"
  fi
  return 0
}

cmd_get() {
  local slug="" key="" a v json=0
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --key=*)     v="${a#*=}"; a="--key" ;;
    esac
    case "$a" in
      --project|--key)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --key) key="$v" ;; esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "get --project <slug> --key <key> [--json]   (keys: $CONFIG_KEYS; show-only: $STATE_KEYS)" ;;
      *) _pw_positional "$a" "get --project <slug> --key <key> [--json]   (keys: $CONFIG_KEYS; show-only: $STATE_KEYS)" ;;
    esac
  done
  [ -n "$slug" ] || die "get: --project is required → fix: get --project <slug> --key <key>   (keys: $CONFIG_KEYS; show-only: $STATE_KEYS)"
  [ -n "$key" ] || die "get: --key is required → fix: get --project <slug> --key <key>   (keys: $CONFIG_KEYS; show-only: $STATE_KEYS)"
  local d; d="$(proj_dir "$slug")"
  case "$key" in
    ai-review)   cmd_ai_review --project "$slug" ;;
    ai-model)    if [ "$json" = 1 ]; then cmd_ai_model --project "$slug" --json; else cmd_ai_model --project "$slug"; fi ;;
    review-trigger) cmd_review_trigger --project "$slug" ;;
    review-repair)  cmd_review_repair --project "$slug" ;;
    review-rounds)  cmd_review_rounds --project "$slug" ;;
    pin)         local _t _v _f _any=0
                 for _f in "$d"/task/T*.md; do
                   [ -e "$_f" ] || continue
                   _t="$(basename "$_f" .md)"; _v="$(pw_field "$_f" "Execute with")"
                   printf '%s=%s\n' "$_t" "${_v:-—}"; _any=1
                 done
                 [ "$_any" = 1 ] || die "get: pin — no task files in $slug — nothing pinned yet (/pw-breakdown --project $slug creates tasks)" ;;
    pin.T*)      local _t="${key#pin.}"
                 local _f="$d/task/$_t.md"
                 [ -f "$_f" ] || die "get: no task file task/$_t.md"
                 v="$(pw_field "$_f" "Execute with")"; printf '%s\n' "${v:-(unset — spawn uses the route ladder)}" ;;
    routing)
      [ "$json" = 0 ] || die "get: --json is supported for ai-model only"
      if [ -f "$d/task/PLAN.md" ]; then
        v="$(_plan_value "$d/task/PLAN.md" Routing)"; printf '%s\n' "${v:-(unset — effective: $PW_ROUTE_DEFAULT)}"
      else
        v="$(_project_defaults_member "$d/README.md" routing)"
        if _project_defaults_has_line "$d/README.md"; then printf '%s\n' "${v:-(unset — effective: $PW_ROUTE_DEFAULT)} (pending PLAN seed)"
        else printf '%s\n' "${v:-(unset — effective: $PW_ROUTE_DEFAULT)}"; fi
      fi ;;
    execution-limit)
      [ "$json" = 0 ] || die "get: --json is supported for ai-model only"
      if [ -f "$d/task/PLAN.md" ]; then
        v="$(_plan_value "$d/task/PLAN.md" "AI execution limit")"; printf '%s\n' "${v:-(unset — effective: $PW_MAX_SELF_REPAIR)}"
      else
        v="$(_project_defaults_member "$d/README.md" execution-limit)"
        if _project_defaults_has_line "$d/README.md"; then printf '%s\n' "${v:-(unset — effective: $PW_MAX_SELF_REPAIR)} (pending PLAN seed)"
        else printf '%s\n' "${v:-(unset — effective: $PW_MAX_SELF_REPAIR)}"; fi
      fi ;;
    max-parallel)
      [ "$json" = 0 ] || die "get: --json is supported for ai-model only"
      if [ -f "$d/task/PLAN.md" ]; then
        v="$(_plan_get_maxparallel "$d/task/PLAN.md")"; printf '%s\n' "${v:-(unset)}"
      else
        v="$(_project_defaults_member "$d/README.md" max-parallel)"
        if _project_defaults_has_line "$d/README.md"; then printf '%s\n' "${v:-(unset)} (pending PLAN seed)"
        else printf '%s\n' "${v:-(unset)}"; fi
      fi ;;
    produced-by) v="$(_plan_value "$d/task/PLAN.md" "Produced by")"; printf '%s\n' "${v:-(unset — providers: ${PW_PROVIDERS[*]})}" ;;
    rfc-target)  v="$(pw_field "$d/rfc/META.md" Target 2>/dev/null || true)"; printf '%s\n' "${v:-(unset — backend: ${PW_RFC_BACKEND:-markdown})}" ;;
    status|adopted|base-branches|landing-units)
      die "get: '$key' is project state/data, not configuration — written by its owning flow (/pw-status phase moves, /pw-adopt, /pw-breakdown; read it in 'show')" ;;
    *) die "get: unknown key '$key' (config keys: $CONFIG_KEYS; show-only state/data: $STATE_KEYS — see --help)" ;;
  esac
}

# The single propagator for the executor pin's TWO holders (plan 23 / KI-1 doctrine — one writer,
# never two): the task file's `- **Execute with:**` field (what the spawn binds) and the PLAN
# task-table `Execute with` cell (what the gate/audit/resume-guard reads). Writing one without
# the other is exactly the drift class provider-audit's `mismatch` verdict exists to catch.
#   _pin_propagate <proj-dir> <plan-file> <task-id> <provider:model|—>
_pin_propagate() {
  local d="$1" plan="$2" tid="$3" val="$4"
  local tf="$d/task/$tid.md"
  grep -q '^- \*\*Execute with:\*\*' "$tf" \
    || die "pin: task/$tid.md has no '- **Execute with:**' field — fix the task doc first (template line missing; pw-doctor --project C11 flags it)"
_pwstage="$(pw_tmpfile "$(dirname "$tf")")" || return 1;   awk -v v="$val" '!w && /^- \*\*Execute with:\*\*/ { print "- **Execute with:** " v; w=1; next } { print }' \
    "$tf" > "$_pwstage" && mv "$_pwstage" "$tf"
  _plan_cell_update "$plan" "$tid" executewith "$val" \
    || die "pin: PLAN 'Execute with' cell write failed for $tid (see above) — the PLAN task-table row must exist; repair the PLAN doc, then re-run"
}

cmd_set() {
  local slug="" key="" val="" hasval=0 a v s
  local variant="" reasoning="" effort="" tuning_given=0
  local -a sets; sets=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --key=*)     v="${a#*=}"; a="--key" ;;
      --value=*)   v="${a#*=}"; a="--value" ;;
      --set=*)     v="${a#*=}"; a="--set" ;;
      --variant=*) v="${a#*=}"; a="--variant" ;;
      --reasoning=*) v="${a#*=}"; a="--reasoning" ;;
      --effort=*)  v="${a#*=}"; a="--effort" ;;
    esac
    case "$a" in
      --project|--key|--value)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --project) slug="$v" ;;
          --key)     key="$v" ;;
          --value)   val="$v"; hasval=1 ;;
        esac ;;
      --variant|--reasoning|--effort)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --variant) variant="$v" ;;
          --reasoning) reasoning="$v" ;;
          --effort) effort="$v" ;;
        esac
        tuning_given=1 ;;
      --set) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --set; v="$1"; shift; }; sets+=("$v") ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "set --project <slug> --key <key> [--value <v> | --set <member=value>]… [--variant <v> --reasoning <v> --effort <v>]   (keys: $CONFIG_KEYS)" ;;
      *) _pw_positional "$a" "set --project <slug> --key <key> [--value <v> | --set <member=value>]…   (keys: $CONFIG_KEYS)" ;;
    esac
  done
  [ -n "$slug" ] || die "set: --project is required → fix: set --project <slug> --key <key> [--value <v> | --set <member=value>]…   (keys: $CONFIG_KEYS)"
  [ -n "$key" ] || die "set: --key is required → fix: set --project <slug> --key <key> [--value <v> | --set <member=value>]…   (keys: $CONFIG_KEYS)"
  local d; d="$(proj_dir "$slug")"
  local plan="$d/task/PLAN.md"
  case "$key" in
    ai-review|ai-model|pin|review-trigger|review-repair)
      [ ${#sets[@]} -ge 1 ] || die "set: '$key' needs --set <member=value> pairs → fix: set --project <slug> --key $key --set <member=value> […]"
      [ "$hasval" = 0 ] || die "set: '$key' takes --set <member=value> pairs, not --value → fix: set --project <slug> --key $key --set <member=value> […]" ;;
    routing|execution-limit|max-parallel|produced-by|rfc-target|review-rounds)
      [ "$hasval" = 1 ] || die "set: '$key' needs --value <v> → fix: set --project <slug> --key $key --value <v>"
      [ ${#sets[@]} -eq 0 ] || die "set: '$key' takes --value <v>, not --set → fix: set --project <slug> --key $key --value <v>" ;;
    status|adopted|base-branches|landing-units)
      die "set: '$key' is project state/data, not configuration — the owning flow writes it (/pw-status, /pw-adopt, /pw-breakdown)" ;;
    *) die "set: unknown key '$key' (config keys: $CONFIG_KEYS — see --help)" ;;
  esac
  local -a setflags; setflags=()
  for s in ${sets[@]+"${sets[@]}"}; do setflags+=("--set" "$s"); done
  if [ "$tuning_given" = 1 ]; then
    [ "$key" = ai-model ] \
      || die "set: --variant/--reasoning/--effort apply to --key ai-model only (got '$key') → fix: drop the tuning flags or set ai-model"
    [ ${#sets[@]} -eq 1 ] \
      || die "set: tuning flags apply to exactly ONE ai-model role per invocation → fix: give one --set <role>=<provider:model> (set roles separately, each with its own tuning)"
  fi
  local -a tuneflags; tuneflags=()
  [ -n "$variant" ] && tuneflags+=(--variant "$variant")
  [ -n "$reasoning" ] && tuneflags+=(--reasoning "$reasoning")
  [ -n "$effort" ] && tuneflags+=(--effort "$effort")
  case "$key" in
    ai-review)      cmd_ai_review    --project "$slug" ${setflags[@]+"${setflags[@]}"} ;;
    ai-model)       cmd_ai_model     --project "$slug" ${setflags[@]+"${setflags[@]}"} ${tuneflags[@]+"${tuneflags[@]}"} ;;
    review-trigger) cmd_review_trigger --project "$slug" ${setflags[@]+"${setflags[@]}"} ;;
    review-repair)  cmd_review_repair  --project "$slug" ${setflags[@]+"${setflags[@]}"} ;;
    review-rounds)  cmd_review_rounds  --project "$slug" --value "$val" ;;
    pin)       [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown --project $slug first"
               local _pair _tid _val
               # validate-all-first (plan 04 batch discipline): nothing is written unless EVERY pair binds
               for _pair in "${sets[@]}"; do
                 case "$_pair" in *=*) ;; *) die "pin: --set expects <T0n>=<provider:model|—>, got '$_pair'" ;; esac
                 _tid="${_pair%%=*}"; _val="${_pair#*=}"
                 pw_task_id_ok "$_tid" || die "pin: '$_tid' is not a task id (expected T01, T02, …)"
                 [ -f "$d/task/$_tid.md" ] || die "pin: no task file task/$_tid.md — /pw-breakdown owns task creation"
                 grep -q '^- \*\*Execute with:\*\*' "$d/task/$_tid.md" \
                   || die "pin: task/$_tid.md has no '- **Execute with:**' field — fix the task doc first (template line missing; pw-doctor --project C11 flags it)"
                 pw_plan_pairs "$plan" | awk -F'|' -v t="$_tid" '$1 == t { f=1 } END { exit !f }' \
                   || die "pin: no PLAN task-table row for $_tid — repair the PLAN doc first (rows are /pw-breakdown's)"
                 _model_pin_validate "pin '$_tid=$_val'" "$_val"
               done
               for _pair in "${sets[@]}"; do
                 _pin_propagate "$d" "$plan" "${_pair%%=*}" "${_pair#*=}"
               done
               if [ ${#sets[@]} -eq 1 ]; then
                 "$ST" log --project "$slug" --actor "config" --message "pin ${sets[0]%%=*} -> ${sets[0]#*=} (task file + PLAN cell)"
                 echo "$slug: pin ${sets[0]%%=*} -> ${sets[0]#*=}"
               else
                 "$ST" log --project "$slug" --actor "config" --message "pin set: ${sets[*]} (task files + PLAN cells)"
                 echo "$slug: pins set: ${sets[*]}"
               fi ;;
    rfc-target) "$HERE/pw-rfc.sh" target --project "$slug" --ref "$val" ;;
    routing)   case "$val" in auto|subagent|headless) ;; *) die "routing: expected auto|subagent|headless, got '$val' (headless = strict binding; see --help)" ;; esac
                if [ -f "$plan" ]; then
                  _plan_set_bullet "$plan" "Routing" "$val" '^## Breakdown rules' \
                    || die "set routing: no '- **Routing:**' bullet and no '## Breakdown rules' section to insert one into — fix the PLAN structure (pw-doc.sh lint --kind plan --project $slug)"
                else
                  _project_defaults_line_ensure "$d/README.md"
                  _line_pairs_set "$d/README.md" "Project Defaults" "routing=$val"
                fi ;;
    execution-limit) _require_int execution-limit "$val" 0 99
                if [ -f "$plan" ]; then
                  _plan_set_bullet "$plan" "AI execution limit" "$val" '^## Execution strategy' \
                    || die "set execution-limit: no anchor bullet/section in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint --kind plan --project $slug)"
                else
                  _project_defaults_line_ensure "$d/README.md"
                  _line_pairs_set "$d/README.md" "Project Defaults" "execution-limit=$val"
                fi ;;
    max-parallel) _require_int max-parallel "$val" 1 99
                if [ -f "$plan" ]; then
                  _plan_set_maxparallel "$plan" "$val" \
                    || die "set max-parallel: no '- Max parallelism:' line in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint --kind plan --project $slug)"
                else
                  _project_defaults_line_ensure "$d/README.md"
                  _line_pairs_set "$d/README.md" "Project Defaults" "max-parallel=$val"
                fi ;;
    produced-by) local _p found=0
               for _p in "${PW_PROVIDERS[@]}"; do [ "$_p" = "$val" ] && found=1; done
               [ "$found" = 1 ] || die "produced-by: '$val' is not an enabled Agent Provider (pw.config.sh PW_PROVIDERS: ${PW_PROVIDERS[*]})"
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown --project $slug first"
               _plan_set_bullet "$plan" "Produced by" "$val" '^- \*\*Status:\*\*' \
                 || die "set produced-by: no '- **Produced by:**' bullet and no 'Status:' anchor in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint --kind plan --project $slug)" ;;
  esac
  # dual-holder propagation (e.g. an executor pin's PLAN cell) is the half-sync fix's job —
  # the writer logs exactly what it changed, never claims more.
  case "$key" in
    ai-review|ai-model|pin|rfc-target|review-trigger|review-repair|review-rounds) : ;;   # those writers log their own change line
    *) "$ST" log --project "$slug" --actor "config" --message "$key -> $val" ;;
  esac
}

# Copy the creation seed into a newly created PLAN. Idempotent: an explicit PLAN value always
# wins, and the seed is never re-read after PLAN exists. Called by /pw-breakdown before its review
# initialization so an alternate entry path cannot skip it.
cmd_materialize() { # --project <slug>
  local slug="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "materialize --project <slug>" ;;
      *) _pw_positional "$a" "materialize --project <slug>" ;;
    esac
  done
  [ -n "$slug" ] || die "materialize: --project is required → fix: materialize --project <slug>"
  local d; d="$(proj_dir "$slug")"
  local plan="$d/task/PLAN.md" readme="$d/README.md"
  [ -f "$plan" ] || die "materialize: no task/PLAN.md in $slug → fix: run /pw-breakdown --project $slug (this operator runs inside breakdown)"
  local changed="" m val cur
  for m in routing execution-limit max-parallel; do
    val="$(_project_defaults_member "$readme" "$m" 2>/dev/null || true)"
    [ -n "$val" ] || continue
    case "$m" in
      routing) cur="$(_plan_value "$plan" Routing)" ;;
      execution-limit) cur="$(_plan_value "$plan" "AI execution limit")" ;;
      max-parallel) cur="$(_plan_get_maxparallel "$plan")" ;;
    esac
    case "$cur" in ""|"<"*">"*|"<"*) cur="" ;; esac
    [ -n "$cur" ] && continue
    case "$m" in
      routing)
        case "$val" in auto|subagent|headless) ;; *) die "materialize: malformed routing seed '$val' in README — nothing written" ;; esac
        _plan_set_bullet "$plan" "Routing" "$val" '^## Breakdown rules' || die "materialize: cannot place PLAN Routing (repair PLAN structure)" ;;
      execution-limit)
        _require_int execution-limit "$val" 0 99
        _plan_set_bullet "$plan" "AI execution limit" "$val" '^## Execution strategy' || die "materialize: cannot place PLAN AI execution limit (repair PLAN structure)" ;;
      max-parallel)
        _require_int max-parallel "$val" 1 99
        _plan_set_maxparallel "$plan" "$val" || die "materialize: cannot place PLAN Max parallelism (repair PLAN structure)" ;;
    esac
    changed="$changed $m=$val"
  done
  if [ -n "$changed" ]; then
    "$ST" log --project "$slug" --actor config --message "materialized project defaults into PLAN:$changed"
    echo "$slug: PLAN seeded from project defaults:${changed}"
  else
    echo "$slug: PLAN already carries its own routing/execution-limit/max-parallel (nothing changed)"
  fi
}

cmd_ensure() {
  local slug="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "ensure --project <slug>" ;;
      *) _pw_positional "$a" "ensure --project <slug>" ;;
    esac
  done
  [ -n "$slug" ] || die "ensure: --project is required → fix: ensure --project <slug>"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_models_line_ensure "$f"; _ai_review_line_ensure "$f"
  local migrated=0
  _ai_review_line_migrate "$f" && migrated=1
  _review_trigger_line_ensure "$f"; _review_repair_line_ensure "$f"; _review_budget_line_ensure "$f"
  _axis_line_fill "$f" "AI Review" "$(_review_default_mode)" || true
  _axis_line_fill "$f" "Review Trigger" "manual" || true
  _axis_line_fill "$f" "Review Repair" "manual" || true
  if [ "$migrated" = 1 ]; then
    echo "$slug: dashboard config lines ensured (missing lines inserted with explicit defaults); legacy 'off' migrated to advisory"
  else
    echo "$slug: dashboard config lines ensured (missing lines inserted with explicit defaults)"
  fi
}

# --- global project-setting defaults ---------------------------------------------------------
# One `global` operator family. Machine floors stay read-only here beyond the reusable project
# defaults below; the latter live in one bounded, managed assignment block at the end of the same
# pw.config.sh, so there is no second config file and no live inheritance for existing projects.
GLOBAL_PROJECT_KEYS="ai-model ai-review review-trigger review-repair review-rounds routing execution-limit max-parallel"
_GLOBAL_BEGIN='# >>> pw global project defaults (managed by /pw-config global; do not hand-edit) >>>'
_GLOBAL_END='# <<< pw global project defaults <<<'

_global_cfg_file() { printf '%s' "${PW_CONFIG_FILE:-$PW_HOME/pw.config.sh}"; }

_global_key_var() { # <key> -> scalar var (axes store their whole k=v string)
  case "$1" in
    routing)         printf 'PW_PROJECT_DEFAULT_ROUTING' ;;
    execution-limit) printf 'PW_PROJECT_DEFAULT_EXECUTION_LIMIT' ;;
    max-parallel)    printf 'PW_PROJECT_DEFAULT_MAX_PARALLEL' ;;
    review-rounds)   printf 'PW_PROJECT_DEFAULT_REVIEW_ROUNDS' ;;
    review-trigger)  printf 'PW_PROJECT_DEFAULT_REVIEW_TRIGGER' ;;
    review-repair)   printf 'PW_PROJECT_DEFAULT_REVIEW_REPAIR' ;;
    ai-review)       printf 'PW_PROJECT_DEFAULT_AI_REVIEW' ;;
    *) return 1 ;;
  esac
}

_global_role_var() { # <role> <MODEL|VARIANT|REASONING|EFFORT>
  local u; u="$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
  printf 'PW_PROJECT_DEFAULT_AI_MODEL_%s_%s' "$u" "$2"
}

_global_safe_value() { # <text> — managed block accepts literal single-token values only
  case "$1" in
    "" ) return 1 ;;
    *$'\n'*|*'"'*|*"'"*|*'`'*|*'\'*|*'$'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'{'*|*'}'*|*'*'*|*'?'*|*'['*|*']'*|*'~'*|*'#'*) return 1 ;;
  esac
  return 0
}

# Worker specs legitimately carry bracket parameters and `=`/`,` inside them. Accept only the
# parsed model-spec alphabet; the caller has already validated the grammar (prefix, params,
# capability). Quotes, expansion, redirection, command separators, globs, and whitespace stay
# refused, so a spec can never become shell program text.
_global_worker_value_ok() { # <spec>
  case "$1" in
    "" ) return 1 ;;
    *$'\n'*|*' '*|*$'\t'*|*'"'*|*"'"*|*'`'*|*'\'*|*'$'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'{'*|*'}'*|*'*'*|*'?'*|*'~'*|*'#'*) return 1 ;;
  esac
  return 0
}

_global_block_vars() { # -> one VAR=value per managed assignment (empty when no block)
  local f; f="$(_global_cfg_file)"
  [ -f "$f" ] || return 0
  awk -v b="$_GLOBAL_BEGIN" -v e="$_GLOBAL_END" '
    $0 == b { inb = 1; next }
    $0 == e { inb = 0; next }
    inb && /^(PW_PROJECT_DEFAULT_[A-Z0-9_]+|PW_[A-Z0-9_]+_AGENT_MODELS_[A-Z0-9_]+)=/ { print }' "$f"
}

# --- write transaction: lock, stale-read detection, symlink refusal, portable mode ----------
_GLOBAL_LOCK_DIR=""
_GLOBAL_TXN_DIGEST=""

_global_digest() { shasum -a 256 "$1" | awk '{print $1}'; }

_global_stat_mode() { # <file> -> octal mode (explicit platform branch, no GNU/BSD guessing)
  case "$(uname -s)" in
    Darwin) stat -f '%Lp' "$1" ;;
    *)      stat -c '%a' "$1" ;;
  esac
}

_global_lock_end() {
  [ -n "${_GLOBAL_LOCK_DIR:-}" ] && rm -rf "$_GLOBAL_LOCK_DIR" 2>/dev/null || true
  _GLOBAL_LOCK_DIR=""
}

_global_lock_begin() {
  local f; f="$(_global_cfg_file)"
  local lock="${f}.pwlock" i=0 tries="${PW_GLOBAL_LOCK_TRIES:-100}"
  case "$tries" in ''|*[!0-9]*|0) tries=100 ;; esac
  while ! mkdir "$lock" 2>/dev/null; do
    i=$((i+1))
    [ "$i" -le "$tries" ] \
      || die "global: configuration is locked by another writer ($lock) → fix: retry after it finishes; if no writer is running, remove the stale lock directory $lock"
    sleep 0.05 2>/dev/null || sleep 1
  done
  _GLOBAL_LOCK_DIR="$lock"
  trap '_global_lock_end' EXIT HUP INT TERM
  if [ -f "$f" ]; then
    _GLOBAL_TXN_DIGEST="$(_global_digest "$f")"
  else
    _GLOBAL_TXN_DIGEST=""
  fi
}

# Last literal assignment for <VAR> outside the managed block. A computed assignment cannot be
# evaluated again safely, so only a plain literal is reported (rc 1 otherwise).
_global_fallback_assignment() { # <VAR>
  local f line; f="$(_global_cfg_file)"
  [ -f "$f" ] || return 1
  line="$(awk -v b="$_GLOBAL_BEGIN" -v e="$_GLOBAL_END" -v v="$1" '
    $0 == b { inb = 1; next }
    $0 == e { inb = 0; next }
    inb { next }
    $0 ~ "^[[:space:]]*(export[[:space:]]+)?" v "=" { last = $0 }
    END { if (last != "") print last }' "$f")"
  [ -n "$line" ] || return 1
  line="${line#*=}"; line="${line#"${line%%[![:space:]]*}"}"
  case "$line" in
    \"*\") line="${line#\"}"; line="${line%\"}" ;;
    \'*\') line="${line#\'}"; line="${line%\'}" ;;
  esac
  case "$line" in *'$'*|*'`'*|*'('*) return 1 ;; esac
  printf '%s' "$line"
}

# Recompute one variable after its managed assignment was removed: restore the earlier literal
# assignment when one exists, otherwise fall back to the process/built-in default.
_global_reapply_fallback() { # <VAR>
  local var="$1" fb
  if fb="$(_global_fallback_assignment "$var")"; then
    printf -v "$var" '%s' "$fb"
    return 0
  fi
  unset "$var" 2>/dev/null || true
  return 1
}

_global_write_block() { # <VAR=value>… — rewrite the managed block, preserving every other byte
  local f; f="$(_global_cfg_file)"
  local own_lock=0
  if [ -z "$_GLOBAL_LOCK_DIR" ]; then _global_lock_begin; own_lock=1; fi
  if [ ! -f "$f" ]; then
    local example="$PW_HOME/pw.config.example.sh"
    if [ -f "$example" ]; then cp -p "$example" "$f" || die "global: cannot create $f from pw.config.example.sh"
    else : > "$f" || die "global: cannot create $f"; fi
    _GLOBAL_TXN_DIGEST="$(_global_digest "$f")"
  fi
  [ "$(_global_digest "$f")" = "$_GLOBAL_TXN_DIGEST" ] \
    || die "global: $f changed after this transaction read it — refusing to overwrite the external edit → fix: re-run the command on the current file"
  local mode; mode="$(_global_stat_mode "$f")"
  local tmp; tmp="$(pw_tmpfile "$(dirname "$f")")" || die "global: cannot stage $f"
  local line
  {
    awk -v b="$_GLOBAL_BEGIN" -v e="$_GLOBAL_END" '
      $0 == b { inb = 1; next }
      $0 == e { inb = 0; next }
      !inb { print }' "$f"
    printf '%s\n' "$_GLOBAL_BEGIN"
    # Deterministic order: the registry order for scalars, roles in their declared order.
    local k v r axis var
    for k in routing execution-limit max-parallel review-trigger review-repair review-rounds ai-review; do
      var="$(_global_key_var "$k" 2>/dev/null || true)"
      [ -n "$var" ] || continue
      for line in "$@"; do
        [ "${line%%=*}" = "$var" ] || continue
        v="${line#*=}"; v="${v#\"}"; v="${v%\"}"
        printf '%s="%s"\n' "$var" "$v"
      done
    done
    for r in $AI_MODEL_ROLES; do
      for axis in MODEL VARIANT REASONING EFFORT; do
        var="$(_global_role_var "$r" "$axis")"
        for line in "$@"; do
          [ "${line%%=*}" = "$var" ] || continue
          v="${line#*=}"; v="${v#\"}"; v="${v%\"}"
          printf '%s="%s"\n' "$var" "$v"
        done
      done
    done
    # Provider-by-worker model defaults: one managed assignment per provider/agent cell.
    # Print in managed-block order (not shell-expanded), so unrelated future assignments survive.
    for line in "$@"; do
      var="${line%%=*}"
      case "$var" in PW_[A-Z0-9_]*_AGENT_MODELS_[A-Z0-9_]*) ;; *) continue ;; esac
      v="${line#*=}"; v="${v#\"}"; v="${v%\"}"
      printf '%s="%s"\n' "$var" "$v"
    done
    printf '%s\n' "$_GLOBAL_END"
  } > "$tmp" || { rm -f "$tmp"; die "global: failed to compose $f"; }
  bash -n "$tmp" || { rm -f "$tmp"; die "global: staged configuration failed 'bash -n'; nothing written"; }
  # Test-only fault injection (opt-in path): runs between staging and the pre-publication
  # recheck so the suite can prove stale-read refusal and writer serialization without a race.
  [ "${PW_TESTING:-0}" = 1 ] && [ -n "${PW_GLOBAL_TEST_AFTER_STAGE:-}" ] \
    && "$PW_GLOBAL_TEST_AFTER_STAGE" "$f"
  [ ! -L "$f" ] || { rm -f "$tmp"; die "global: refusing a symlinked configuration target ($f) → fix: point PW_CONFIG_FILE at the real file"; }
  [ "$(_global_digest "$f")" = "$_GLOBAL_TXN_DIGEST" ] \
    || { rm -f "$tmp"; die "global: $f changed during this transaction — refusing to overwrite the external edit → fix: re-run the command on the current file"; }
  [ -n "$mode" ] && chmod "$mode" "$tmp" 2>/dev/null || true
  mv "$tmp" "$f" || { rm -f "$tmp"; die "global: atomic replacement failed for $f"; }
  _GLOBAL_TXN_DIGEST="$(_global_digest "$f")"
  [ "$own_lock" = 1 ] && _global_lock_end
  return 0
}

_global_set_var() { # <VAR> <value> [worker] — update/append one managed assignment
  local var="$1" val="$2" kind="${3:-}" line found=0
  local -a lines; lines=()
  if [ "$kind" = worker ]; then
    _global_worker_value_ok "$val" \
      || die "global: value for $var is not a supported model spec → fix: use <model-id>[key=value,…] (no quotes, spaces, or shell syntax)"
  else
    _global_safe_value "$val" \
      || die "global: value for $var contains unsupported characters → fix: use letters, digits, and _ , . = : + / @ -"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "${line%%=*}" = "$var" ]; then
      lines+=("${var}=${val}"); found=1
    else
      lines+=("$line")
    fi
  done < <(_global_block_vars)
  [ "$found" = 1 ] || lines+=("${var}=${val}")
  _global_write_block "${lines[@]+"${lines[@]}"}"
  printf -v "$var" '%s' "$val"
}

_global_unset_var() { # <VAR>
  local var="$1" line removed=0
  local -a lines; lines=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "${line%%=*}" = "$var" ]; then removed=1; continue; fi
    lines+=("$line")
  done < <(_global_block_vars)
  [ "$removed" = 1 ] || return 0
  _global_write_block "${lines[@]+"${lines[@]}"}"
}

# --- provider-by-worker model defaults -------------------------------------------------------
# A worker default is machine-scoped provider configuration for one canonical subagent
# definition, not a copied project default and not a task pin. The cell key is derived from the
# provider and the full canonical filename (see pw_common's pw_agent_key_var).
_worker_provider_enabled() { # <provider>
  local p
  for p in "${PW_PROVIDERS[@]}"; do [ "$p" = "$1" ] && return 0; done
  return 1
}

_worker_agent_known() { # <canonical-agent>
  local a
  for a in $(pw_canonical_agent_names); do [ "$a" = "$1" ] && return 0; done
  return 1
}

# Parse one worker model specification into W_MODEL/W_PARAMS/W_VARIANT/W_REASONING/W_EFFORT.
# Dies on anything the provider cannot express. The optional `<provider>:` prefix must match.
_worker_spec_parse() { # <context> <provider> <spec>
  local ctx="$1" prov="$2" spec="$3" prefix base params item k v seen=" "
  local -a items; items=()
  W_MODEL=""; W_PARAMS=""; W_VARIANT=""; W_REASONING=""; W_EFFORT=""
  [ -n "$spec" ] || die "$ctx: empty model specification → fix: set a model id or — to clear"
  prefix="$(pw_worker_spec_provider "$spec")"
  if [ -n "$prefix" ]; then
    [ "$prefix" = "$prov" ] \
      || die "$ctx: provider prefix '$prefix' does not match selected provider '$prov' → fix: use '$prov:<model>' or omit the prefix"
    spec="${spec#*:}"
  fi
  case "$spec" in
    *'['*']') base="${spec%%\[*}"; params="${spec#*\[}"; params="${params%\]}" ;;
    *'['*|*']'*) die "$ctx: malformed bracket parameters in '$spec' → fix: use <model>[key=value,…]" ;;
    *) base="$spec" ;;
  esac
  [ -n "$base" ] || die "$ctx: empty model id → fix: name a model"
  case "$base" in *[!A-Za-z0-9._/@+-]*) die "$ctx: invalid model id '$base' → fix: letters, digits, and . _ / @ + - only" ;; esac
  W_MODEL="$base"
  if [ -n "$params" ]; then
    IFS=',' read -ra items <<< "$params"
    for item in "${items[@]}"; do
      case "$item" in *=*) k="${item%%=*}"; v="${item#*=}" ;; *) die "$ctx: malformed parameter '$item' → fix: key=value pairs separated by commas" ;; esac
      case "$k" in ''|*[!A-Za-z0-9_]*) die "$ctx: invalid parameter name '$k'" ;; esac
      case " $seen " in *" $k "*) die "$ctx: duplicate parameter '$k'" ;; esac
      seen="$seen$k "
      case "$v" in ''|*[!A-Za-z0-9._:-]*) die "$ctx: invalid value for '$k' → fix: letters, digits, and . _ : - only" ;; esac
      case "$prov:$k" in
        cursor:reasoning|cursor:effort|cursor:context|cursor:fast) ;;
        cursor:*) die "$ctx: Cursor worker parameters are reasoning|effort|context|fast (got '$k')" ;;
        *:variant|*:reasoning|*:effort) ;;
        *) die "$ctx: provider '$prov' has no verified worker parameter '$k' → fix: use variant|reasoning|effort where supported" ;;
      esac
      case "$k" in
        variant) W_VARIANT="$v" ;;
        reasoning) W_REASONING="$v" ;;
        effort) W_EFFORT="$v" ;;
      esac
    done
    W_PARAMS="$params"
  fi
}

# Validate a parsed worker spec against permission, availability, and tuning capability, then
# print the normalized stored form (canonical model id plus any bracket parameters).
_worker_spec_normalize() { # <context> <provider> <spec>
  local ctx="$1" prov="$2" spec="$3" resolved rrc=0 effective upper
  _worker_provider_enabled "$prov" \
    || die "$ctx: provider '$prov' is not an enabled Agent Provider (PW_PROVIDERS: ${PW_PROVIDERS[*]})"
  _worker_spec_parse "$ctx" "$prov" "$spec"
  _model_permission_check "$prov" "$W_MODEL" >/dev/null
  resolved="$(cmd_model_resolve --provider "$prov" --model "$W_MODEL" 2>/dev/null)" || rrc=$?
  upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
  [ "$rrc" = 0 ] \
    || die "$ctx: $prov:$W_MODEL is not available on this machine (model-resolve exit $rrc) → fix: choose a catalog-listed model or adjust PW_${upper}_API_PROVIDERS"
  case "$resolved" in ''|*' '*) ;; *) W_MODEL="$resolved" ;; esac
  _model_tuning_validate "$ctx" "$prov" "$W_MODEL" "$W_VARIANT" "$W_REASONING" "$W_EFFORT"
  if [ -n "$W_PARAMS" ]; then printf '%s[%s]' "$W_MODEL" "$W_PARAMS"; else printf '%s' "$W_MODEL"; fi
}

_worker_source() { # <provider> <agent>
  local var val
  var="$(pw_agent_key_var "$1" "$2")" || { printf 'default'; return 0; }
  declare -p "$var" >/dev/null 2>&1 && [ -n "${!var:-}" ] && { printf 'managed'; return 0; }
  _global_fallback_assignment "$var" >/dev/null 2>&1 && { printf 'literal'; return 0; }
  printf 'default'
}

_worker_desc() { # <provider> <agent> -> "<model>|<params>|<source>" (model empty when default)
  local prov="$1" agent="$2" spec model params
  spec="$(pw_agent_default_spec "$prov" "$agent")"
  if [ -z "$spec" ]; then
    printf '||%s' "$(_worker_source "$prov" "$agent")"
    return 0
  fi
  model="$(pw_worker_spec_model "$spec")"
  params="$(pw_worker_spec_params "$spec")"
  printf '%s|%s|%s' "$model" "$params" "$(_worker_source "$prov" "$agent")"
}

cmd_agent_model() { # --provider <p> --agent <name> [--json]
  local prov="" agent="" json=0 a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --provider=*) v="${a#*=}"; a="--provider" ;; --agent=*) v="${a#*=}"; a="--agent" ;; esac
    case "$a" in
      --provider|--agent)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --provider) prov="$v" ;; --agent) agent="$v" ;; esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "agent-model --provider <p> --agent <name> [--json]" ;;
      *) _pw_positional "$a" "agent-model --provider <p> --agent <name> [--json]" ;;
    esac
  done
  [ -n "$prov" ] || die "agent-model: --provider is required → fix: agent-model --provider <p> --agent <name>"
  [ -n "$agent" ] || die "agent-model: --agent is required → fix: agent-model --provider <p> --agent <name>"
  _worker_provider_enabled "$prov" || die "agent-model: provider '$prov' is not enabled (${PW_PROVIDERS[*]})"
  _worker_agent_known "$agent" || die "agent-model: unknown canonical worker '$agent' → fix: use one of: $(pw_canonical_agent_names | tr '\n' ' ')"
  local spec model params source
  spec="$(pw_agent_default_spec "$prov" "$agent")"
  model="$(pw_worker_spec_model "$spec")"
  params="$(pw_worker_spec_params "$spec")"
  source="$(_worker_source "$prov" "$agent")"
  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"provider":"%s","agent":"%s","model":"%s","params":"%s","source":"%s","supported":"%s"}\n' \
      "$(_json_escape "$prov")" "$(_json_escape "$agent")" "$(_json_escape "$model")" "$(_json_escape "$params")" "$source" \
      "$([ "$source" = default ] && echo false || echo true)"
    return 0
  fi
  if [ -z "$model" ]; then
    printf '(unset — provider/canonical default)\n'
  else
    [ -n "$params" ] && printf '%s[%s]\n' "$model" "$params" || printf '%s\n' "$model"
  fi
  printf 'source: %s\n' "$source" >&2
}

cmd_agent_model_set() { # --provider <p> --agent <name> --value <spec|—>
  local prov="" agent="" val="" hasval=0 a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --provider=*) v="${a#*=}"; a="--provider" ;; --agent=*) v="${a#*=}"; a="--agent" ;; --value=*) v="${a#*=}"; a="--value" ;; esac
    case "$a" in
      --provider|--agent|--value)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --provider) prov="$v" ;; --agent) agent="$v" ;; --value) val="$v"; hasval=1 ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "agent-model-set --provider <p> --agent <name> --value <spec|—>" ;;
      *) _pw_positional "$a" "agent-model-set --provider <p> --agent <name> --value <spec|—>" ;;
    esac
  done
  [ -n "$prov" ] || die "agent-model-set: --provider is required → fix: agent-model-set --provider <p> --agent <name> --value <spec|—>"
  [ -n "$agent" ] || die "agent-model-set: --agent is required → fix: agent-model-set --provider <p> --agent <name> --value <spec|—>"
  [ "$hasval" = 1 ] || die "agent-model-set: --value is required → fix: agent-model-set --provider <p> --agent <name> --value <spec|—>"
  _worker_provider_enabled "$prov" || die "agent-model-set: provider '$prov' is not enabled (${PW_PROVIDERS[*]})"
  _worker_agent_known "$agent" || die "agent-model-set: unknown canonical worker '$agent' → fix: use one of: $(pw_canonical_agent_names | tr '\n' ' ')"
  local var; var="$(pw_agent_key_var "$prov" "$agent")" || die "agent-model-set: provider/agent token rejected (letters, digits, hyphen only)"
  _global_lock_begin
  if [ "$val" = "—" ] || [ "$val" = "-" ]; then
    _global_unset_var "$var"
    _global_reapply_fallback "$var" || true
  else
    val="$(_worker_spec_normalize "agent-model '$prov/$agent'" "$prov" "$val")"
    _global_set_var "$var" "$val" worker
  fi
  _global_lock_end
  printf 'agent-model: %s/%s -> %s\n' "$prov" "$agent" "$( [ -n "$(pw_agent_default_spec "$prov" "$agent")" ] && pw_agent_default_spec "$prov" "$agent" || printf '—')"
  printf '  source: %s\n' "$(_worker_source "$prov" "$agent")"
}

cmd_agent_model_unset() { # --provider <p> --agent <name>
  local prov="" agent="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --provider=*) v="${a#*=}"; a="--provider" ;; --agent=*) v="${a#*=}"; a="--agent" ;; esac
    case "$a" in
      --provider|--agent)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --provider) prov="$v" ;; --agent) agent="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "agent-model-unset --provider <p> --agent <name>" ;;
      *) _pw_positional "$a" "agent-model-unset --provider <p> --agent <name>" ;;
    esac
  done
  [ -n "$prov" ] || die "agent-model-unset: --provider is required"
  [ -n "$agent" ] || die "agent-model-unset: --agent is required"
  _worker_provider_enabled "$prov" || die "agent-model-unset: provider '$prov' is not enabled (${PW_PROVIDERS[*]})"
  _worker_agent_known "$agent" || die "agent-model-unset: unknown canonical worker '$agent'"
  local var; var="$(pw_agent_key_var "$prov" "$agent")" || die "agent-model-unset: provider/agent token rejected"
  _global_lock_begin
  _global_unset_var "$var"
  _global_reapply_fallback "$var" || true
  _global_lock_end
  printf 'agent-model: %s/%s unset -> %s\n' "$prov" "$agent" "$(_worker_source "$prov" "$agent")"
}

cmd_agent_models() { # [--provider <p>]… [--json]
  local json=0 a v
  local -a provs; provs=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --provider=*) v="${a#*=}"; a="--provider" ;; esac
    case "$a" in
      --provider) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --provider; v="$1"; shift; }; provs+=("$v") ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "agent-models [--provider <p>]… [--json]" ;;
      *) _pw_positional "$a" "agent-models [--provider <p>]… [--json]" ;;
    esac
  done
  [ ${#provs[@]} -gt 0 ] || provs=("${PW_PROVIDERS[@]}")
  local p agents a2 desc model params source first=1
  agents="$(pw_canonical_agent_names)"
  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"worker_defaults":['
    for p in "${provs[@]}"; do
      _worker_provider_enabled "$p" || die "agent-models: provider '$p' is not enabled (${PW_PROVIDERS[*]})"
      for a2 in $agents; do
        desc="$(_worker_desc "$p" "$a2")"
        model="${desc%%|*}"; desc="${desc#*|}"; params="${desc%%|*}"; source="${desc#*|}"
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"provider":"%s","agent":"%s","model":"%s","params":"%s","source":"%s"}' \
          "$(_json_escape "$p")" "$(_json_escape "$a2")" "$(_json_escape "$model")" "$(_json_escape "$params")" "$source"
      done
    done
    printf ']}\n'
    return 0
  fi
  printf '  %-10s %-24s %-40s %s\n' PROVIDER AGENT MODEL SOURCE
  for p in "${provs[@]}"; do
    _worker_provider_enabled "$p" || die "agent-models: provider '$p' is not enabled (${PW_PROVIDERS[*]})"
    for a2 in $agents; do
      desc="$(_worker_desc "$p" "$a2")"
      model="${desc%%|*}"; desc="${desc#*|}"; params="${desc%%|*}"; source="${desc#*|}"
      [ -n "$model" ] || model="—"
      [ -n "$params" ] && model="$model[$params]"
      printf '  %-10s %-24s %-40s %s\n' "$p" "$a2" "$model" "$source"
    done
  done
}

# Bounded model discovery. Sources are reported honestly: live CLI catalogs, Claude's fixed
# alias set, an unavailable CLI, a reachable-but-empty catalog, or no catalog surface.
cmd_models() {
  local a v json=0 details=0 all=0 limit=20 format=table search="" explicit=0
  local -a provs; provs=()
  local -a apis; apis=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --provider=*) v="${a#*=}"; a="--provider" ;;
      --api-provider=*) v="${a#*=}"; a="--api-provider" ;;
      --search=*) v="${a#*=}"; a="--search" ;;
      --limit=*) v="${a#*=}"; a="--limit" ;;
      --format=*) v="${a#*=}"; a="--format" ;;
    esac
    case "$a" in
      --provider|--api-provider|--search|--limit|--format)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --provider) provs+=("$v"); explicit=1 ;; --api-provider) apis+=("$v") ;;
          --search) search="$v" ;; --limit) limit="$v" ;; --format) format="$v" ;;
        esac ;;
      --all) all=1 ;;
      --details) details=1 ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "models [--provider <p>]… [--api-provider <prefix>]… [--search <term>] [--limit <n>] [--all] [--details] [--format table|tsv] [--json]" ;;
      *) _pw_positional "$a" "models [--provider <p>]… [--api-provider <prefix>]… [--search <term>] [--limit <n>] [--all] [--details] [--format table|tsv] [--json]" ;;
    esac
  done
  case "$format" in table|tsv) ;; *) die "models: --format expects table|tsv, got '$format'" ;; esac
  _require_int models "$limit" 1 1000
  [ ${#provs[@]} -gt 0 ] || provs=("${PW_PROVIDERS[@]}")
  if [ ${#apis[@]} -gt 0 ]; then
    local -a axis_provs; axis_provs=()
    for p in "${provs[@]}"; do
      case "$p" in kilo|opencode) axis_provs+=("$p") ;; esac
    done
    [ ${#axis_provs[@]} -gt 0 ] \
      || die "models: --api-provider applies only to kilo/opencode, and no selected provider has that axis"
    provs=("${axis_provs[@]}")
  fi
  local p kind catalog ids n truncated fail=0 partial=0
  local -a rows; rows=()
  for p in "${provs[@]}"; do
    _worker_provider_enabled "$p" || die "models: provider '$p' is not enabled (${PW_PROVIDERS[*]})"
    kind="$(pw_catalog_kind "$p")"
    case "$kind" in
      fixed) ids="$(pw_claude_models)" ;;
      live|empty)
        catalog="$(pw_api_catalog "$p")"
        if [ ${#apis[@]} -gt 0 ]; then
          ids=""
          local prefix line
          for prefix in "${apis[@]}"; do
            while IFS= read -r line; do
              case "$line" in "$prefix"*) ids="$ids$line
" ;; esac
            done <<EOF
$catalog
EOF
          done
          ids="${ids%$'\n'}"
        else
          ids="$(printf '%s\n' "$catalog" | pw_api_filter "$p")"
        fi ;;
      unavailable|unsupported|*) ids="" ;;
    esac
    if [ -n "$search" ]; then
      ids="$(printf '%s\n' "$ids" | grep -F -i -- "$search" || true)"
    fi
    n=0; truncated=0
    local line shown=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n=$((n+1))
      if [ "$all" = 0 ] && [ "$shown" -ge "$limit" ]; then truncated=1; continue; fi
      shown=$((shown+1))
      rows+=("$p"$'\t'"$kind"$'\t'"$line")
    done <<EOF
$ids
EOF
    case "$kind" in
      unavailable|empty|unsupported)
        fail=1; partial=1
        printf 'pw-config: %s: catalog %s → %s\n' "$p" "$kind" \
          "$([ "$kind" = unavailable ] && echo 'CLI not on PATH' || echo 'no models returned (auth, network, or unsupported surface)')" >&2 ;;
    esac
    [ "$truncated" = 1 ] && printf 'pw-config: %s: showing %s of %s matching models (use --all or a higher --limit)\n' "$p" "$shown" "$n" >&2
  done
  if [ "$json" = 1 ]; then
    printf '{"schema_version":1,"partial":%s,"models":[' "$([ "$partial" = 1 ] && echo true || echo false)"
    local first=1 k m s
    for k in "${rows[@]+"${rows[@]}"}"; do
      IFS=$'\t' read -r p s m _ <<EOF
$k
EOF
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"provider":"%s","source":"%s","model":"%s"}' "$(_json_escape "$p")" "$s" "$(_json_escape "$m")"
    done
    printf ']}\n'
  elif [ "$format" = tsv ]; then
    printf 'provider\tsource\tmodel\n'
    local k p2 s2 m2 st2
    for k in "${rows[@]+"${rows[@]}"}"; do
      IFS=$'\t' read -r p2 s2 m2 st2 <<EOF
$k
EOF
      printf '%s\t%s\t%s\n' "$p2" "$s2" "$m2"
    done
  else
    printf '  %-10s %-12s %s\n' PROVIDER SOURCE MODEL
    local k p2 s2 m2 st2
    for k in "${rows[@]+"${rows[@]}"}"; do
      IFS=$'\t' read -r p2 s2 m2 st2 <<EOF
$k
EOF
      printf '  %-10s %-12s %s\n' "$p2" "$s2" "$m2"
    done
    [ "$details" = 1 ] && printf '  (source: live CLI catalog | fixed = provider alias set; availability checked by model-resolve)\n'
  fi
  if [ "$fail" = 1 ] && [ "$explicit" = 1 ]; then
    die "models: one or more selected provider catalogs are unavailable (see diagnostics above)"
  fi
  return 0
}

_global_effective() { # <key> -> effective configured/fallback string
  local key="$1" var val line r axis out
  case "$key" in
    routing|execution-limit|max-parallel|review-rounds)
      case "$key" in
        routing) var="$(_global_key_var routing)" ;;
        execution-limit) var="$(_global_key_var execution-limit)" ;;
        max-parallel) var="$(_global_key_var max-parallel)" ;;
        review-rounds) var="$(_global_key_var review-rounds)" ;;
      esac
      val="${!var:-}"
      [ -n "$val" ] || val="$(pw_project_default_value "$key")"
      printf '%s' "$val" ;;
    ai-review)
      var="$(_global_key_var ai-review)"; val="${!var:-}"
      if [ -n "$val" ]; then printf '%s' "$val"; else _axis_default_kvs ai-review; fi ;;
    review-trigger|review-repair)
      var="$(_global_key_var "$key")"; val="${!var:-}"
      if [ -n "$val" ]; then printf '%s' "$val"; else _axis_default_kvs "$key"; fi ;;
    ai-model)
      out=""
      for r in $AI_MODEL_ROLES; do
        val="$(pw_project_default_role "$r")"
        out="$out${out:+ }$r=$val"
        axis="$(pw_project_default_tuning "$r")"
        [ -n "$axis" ] && out="$out ($axis)"
      done
      printf '%s' "$out" ;;
    *) return 1 ;;
  esac
}

_global_source() { # <key>
  local var; var="$(_global_key_var "$1" 2>/dev/null || true)"
  if [ -n "$var" ] && [ -n "${!var:-}" ]; then printf 'pw.config.sh managed global'; else printf 'built-in / legacy fallback'; fi
}

# Merge a new batch over the value currently persisted in the managed block, so unmentioned
# surfaces keep their configured value (or the compatibility default).
_global_axis_merge() { # <var> <new-pairs> <default-pairs>
  local var="$1" newp="$2" dflt="$3" p v kv cur out=""
  cur="$(_global_block_vars | awk -F= -v v="$var" '$1 == v { sub(/^[^=]*=/, ""); print }')"
  cur="${cur#\"}"; cur="${cur%\"}"
  for p in $AI_REVIEW_PHASES; do
    v=""
    for kv in $newp; do [ "${kv%%=*}" = "$p" ] && v="${kv#*=}"; done
    if [ -z "$v" ]; then
      for kv in $cur; do [ "${kv%%=*}" = "$p" ] && v="${kv#*=}"; done
    fi
    if [ -z "$v" ]; then
      for kv in $dflt; do [ "${kv%%=*}" = "$p" ] && v="${kv#*=}"; done
    fi
    [ -n "$v" ] && out="$out $p=$v"
  done
  printf '%s' "${out# }"
}

_global_validate_axis() { # <axis> <pairs…> — validates then prints expanded pairs
  local axis="$1"; shift
  local expanded pair
  expanded="$(_expand_axis_pairs "$axis" "$@")" || exit 2
  for pair in $expanded; do
    local s="${pair%%=*}" v="${pair#*=}"
    case "$axis" in
      ai-review) _ai_review_validate "$s" "$v" ;;
      review-trigger) _review_trigger_validate "$s" "$v" ;;
      review-repair) _review_repair_validate "$s" "$v" ;;
    esac
  done
  printf '%s' "$expanded"
}

cmd_global_show() { # [--json]
  local json=0 a
  for a in "$@"; do case "$a" in --json) json=1 ;; *) die "usage: global show [--json]" ;; esac; done
  if [ "$json" = 1 ]; then
    local first=1 k eff src inh p agent desc model params wsrc
    printf '{"schema_version":1,"project_defaults":['
    for k in $GLOBAL_PROJECT_KEYS; do
      eff="$(_global_effective "$k")"; src="$(_global_source "$k")"
      case "$k" in max-parallel) inh=yes ;; *) inh=yes ;; esac
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"key":"%s","inherited":"%s","effective":"%s","source":"%s"}' "$k" "$inh" "$eff" "$src"
    done
    printf '],"worker_defaults":['
    first=1
    for p in "${PW_PROVIDERS[@]}"; do
      case "$p" in *[!A-Za-z0-9_-]*) continue ;; esac
      for agent in $(pw_canonical_agent_names); do
        desc="$(_worker_desc "$p" "$agent")"
        model="${desc%%|*}"; desc="${desc#*|}"; params="${desc%%|*}"; wsrc="${desc#*|}"
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"provider":"%s","agent":"%s","model":"%s","params":"%s","source":"%s"}' \
          "$(_json_escape "$p")" "$(_json_escape "$agent")" "$(_json_escape "$model")" "$(_json_escape "$params")" "$wsrc"
      done
    done
    printf ']}\n'
    return 0
  fi
  local p upper av al es
  echo "pw-config global show — effective machine floors (source: pw.config.sh via pw-common.sh)"
  echo "  providers        : ${PW_PROVIDERS[*]}"
  for p in "${PW_PROVIDERS[@]}"; do
    case "$p" in *[!A-Za-z0-9_-]*) continue ;; esac   # same sink rule as model-check: no variable names from unchecked tokens
    upper="$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]')"
    es="$(pw_api_entries "$p" | tr '\n' ' ')"
    [ -n "${es// /}" ] || es="(unset = full catalog)"
    av="PW_MODEL_ALLOWLIST_${upper}"
    al="${!av:-}"
    [ -n "$al" ] || al="(unset = all models allowed)"
    printf '  %-18s: %s\n' "api-scope($p)" "$es"
    printf '  %-18s: %s\n' "allowlist($p)" "$al"
  done
  echo "  route-default    : $PW_ROUTE_DEFAULT   (task Route: > PLAN Routing: > this > auto)"
  echo "  headless budgets : stall ${PW_HEADLESS_STALL}m / timeout ${PW_HEADLESS_TIMEOUT}m"
  echo "  cursor probe     : ${PW_CURSOR_PROBE} (live model probe, timeout ${PW_CURSOR_PROBE_TIMEOUT}s; --probe overrides per call)"
  echo "  max-self-repair  : $PW_MAX_SELF_REPAIR"
  echo "  rfc-backend      : ${PW_RFC_BACKEND:-markdown}"
  echo "  review-frame     : $(pw_review_template_path) ($(pw_review_template_source); placeholders validated on use)"
  echo "  review-summary-prompt: $(pw_review_prompt_path summary) ($(pw_review_prompt_source summary); read when --summary/--mr-summary is enabled)"
  echo "  review-note-prompt   : $(pw_review_prompt_path note) ($(pw_review_prompt_source note); read when --note is enabled)"
  echo "  forge-hosts      : ${#PW_FORGE_HOSTS[@]} override(s) (else auto-detect)"
  echo "  memory           : ${PW_MEMORY:-none}"
  echo "  projects-dir     : $PW_PROJECTS"
  echo ""
  echo "Inherited project defaults (NEW projects only; existing projects keep their captured values)"
  printf '  %-18s %-10s %-42s %s\n' KEY INHERITED EFFECTIVE SOURCE
  local k eff src
  for k in $GLOBAL_PROJECT_KEYS; do
    eff="$(_global_effective "$k")"; src="$(_global_source "$k")"
    printf '  %-18s %-10s %-42s %s\n' "$k" "yes" "$eff" "$src"
  done
  echo "  destination      : dashboard config lines; routing/execution-limit/max-parallel seed the dashboard until PLAN owns them"
  echo ""
  echo "Worker defaults (provider-specific agent definitions; empty = provider/canonical default)"
  printf '  %-10s %-24s %-40s %s\n' PROVIDER AGENT MODEL SOURCE
  local wp wa wdesc wmodel wparams wsource
  for wp in "${PW_PROVIDERS[@]}"; do
    case "$wp" in *[!A-Za-z0-9_-]*) continue ;; esac
    for wa in $(pw_canonical_agent_names); do
      wdesc="$(_worker_desc "$wp" "$wa")"
      wmodel="${wdesc%%|*}"; wdesc="${wdesc#*|}"; wparams="${wdesc%%|*}"; wsource="${wdesc#*|}"
      [ -n "$wmodel" ] || wmodel="—"
      [ -n "$wparams" ] && wmodel="$wmodel[$wparams]"
      printf '  %-10s %-24s %-40s %s\n' "$wp" "$wa" "$wmodel" "$wsource"
    done
  done
}

cmd_global_get() { # --key <k> [--provider <p> --agent <name>] [--json]
  local key="" json=0 a v prov="" agent=""
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --key=*) v="${a#*=}"; a="--key" ;; --provider=*) v="${a#*=}"; a="--provider" ;; --agent=*) v="${a#*=}"; a="--agent" ;; esac
    case "$a" in
      --key|--provider|--agent)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --key) key="$v" ;; --provider) prov="$v" ;; --agent) agent="$v" ;; esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "global get --key <key> [--provider <p> --agent <name>] [--json]   (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;;
      *) _pw_positional "$a" "global get --key <key> [--provider <p> --agent <name>] [--json]   (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;;
    esac
  done
  [ -n "$key" ] || die "global get: --key is required → fix: global get --key <key>   (keys: $GLOBAL_PROJECT_KEYS or agent-model)"
  if [ "$key" = agent-model ]; then
    [ -n "$prov" ] && [ -n "$agent" ] \
      || die "global get agent-model: --provider and --agent are required → fix: global get --key agent-model --provider <p> --agent <pw-name>"
    if [ "$json" = 1 ]; then cmd_agent_model --provider "$prov" --agent "$agent" --json
    else cmd_agent_model --provider "$prov" --agent "$agent"; fi
    return 0
  fi
  case " $GLOBAL_PROJECT_KEYS " in *" $key "*) ;; *) die "global get: unknown key '$key' (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;; esac
  local eff src
  eff="$(_global_effective "$key")"; src="$(_global_source "$key")"
  if [ "$json" = 1 ]; then
    printf '{"key":"%s","inherited":"yes","effective":"%s","source":"%s"}\n' "$key" "$eff" "$src"
  else
    printf '%s\n' "$eff"
    printf 'source: %s\n' "$src" >&2
  fi
}

cmd_global_set() { # --key <k> [--value <v> | --set <member=value>]… [--variant/--reasoning/--effort]
  local key="" val="" hasval=0 a v variant="" reasoning="" effort="" tuning_given=0 prov="" agent=""
  local -a sets; sets=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --key=*) v="${a#*=}"; a="--key" ;;
      --value=*) v="${a#*=}"; a="--value" ;;
      --set=*) v="${a#*=}"; a="--set" ;;
      --provider=*) v="${a#*=}"; a="--provider" ;;
      --agent=*) v="${a#*=}"; a="--agent" ;;
      --variant=*) v="${a#*=}"; a="--variant" ;;
      --reasoning=*) v="${a#*=}"; a="--reasoning" ;;
      --effort=*) v="${a#*=}"; a="--effort" ;;
    esac
    case "$a" in
      --key|--value|--set|--provider|--agent|--variant|--reasoning|--effort)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --key) key="$v" ;; --value) val="$v"; hasval=1 ;; --set) sets+=("$v") ;;
          --provider) prov="$v" ;; --agent) agent="$v" ;;
          --variant) variant="$v"; tuning_given=1 ;;
          --reasoning) reasoning="$v"; tuning_given=1 ;;
          --effort) effort="$v"; tuning_given=1 ;;
        esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "global set --key <key> [--value <v> | --set <member=value>]…   (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;;
      *) _pw_positional "$a" "global set --key <key> [--value <v> | --set <member=value>]…" ;;
    esac
  done
  [ -n "$key" ] || die "global set: --key is required → fix: global set --key <key> [--value <v> | --set <member=value>]…   (keys: $GLOBAL_PROJECT_KEYS or agent-model)"
  if [ "$key" = agent-model ]; then
    [ -n "$prov" ] && [ -n "$agent" ] \
      || die "global set agent-model: --provider and --agent are required → fix: global set --key agent-model --provider <p> --agent <pw-name> --value <spec|—>"
    [ "$hasval" = 1 ] || die "global set agent-model: --value is required → fix: global set --key agent-model --provider <p> --agent <pw-name> --value <spec|—>"
    [ ${#sets[@]} -eq 0 ] || die "global set agent-model: takes --value <spec>, not --set pairs"
    [ "$tuning_given" = 0 ] || die "global set agent-model: tuning rides inside the bracket spec (e.g. model[effort=high]), not --variant/--reasoning/--effort"
    cmd_agent_model_set --provider "$prov" --agent "$agent" --value "$val"
    return 0
  fi
  case " $GLOBAL_PROJECT_KEYS " in *" $key "*) ;; *) die "global set: unknown key '$key' (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;; esac
  local var
  case "$key" in
    ai-model|ai-review|review-trigger|review-repair)
      [ ${#sets[@]} -ge 1 ] || die "global set: '$key' needs --set <member=value> → fix: global set --key $key --set <member=value> […]"
      [ "$hasval" = 0 ] || die "global set: '$key' takes --set pairs, not --value"
      ;;
    routing|execution-limit|max-parallel|review-rounds)
      [ "$hasval" = 1 ] || die "global set: '$key' needs --value <v> → fix: global set --key $key --value <v>"
      [ ${#sets[@]} -eq 0 ] || die "global set: '$key' takes --value <v>, not --set"
      [ "$tuning_given" = 0 ] || die "global set: tuning flags apply to ai-model only"
      ;;
  esac
  _global_lock_begin
  case "$key" in
    routing)
      case "$val" in auto|subagent|headless) ;; *) die "global set: routing expects auto|subagent|headless, got '$val'" ;; esac
      _global_set_var "$(_global_key_var routing)" "$val" ;;
    execution-limit) _require_int execution-limit "$val" 0 99; _global_set_var "$(_global_key_var execution-limit)" "$val" ;;
    max-parallel)    _require_int max-parallel "$val" 1 99; _global_set_var "$(_global_key_var max-parallel)" "$val" ;;
    review-rounds)   _require_int review-rounds "$val" 1 3; _global_set_var "$(_global_key_var review-rounds)" "$val" ;;
    ai-review|review-trigger|review-repair)
      local expanded merged dflt
      expanded="$(_global_validate_axis "$key" "${sets[@]}")"
      dflt="$(_axis_default_kvs "$key")"
      merged="$(_global_axis_merge "$(_global_key_var "$key")" "$expanded" "$dflt")"
      _global_set_var "$(_global_key_var "$key")" "$merged" ;;
    ai-model)
      [ "$tuning_given" = 1 ] && [ ${#sets[@]} -ne 1 ] \
        && die "global set: tuning flags apply to exactly ONE role assignment per invocation"
      local s role value pv
      for s in "${sets[@]}"; do
        case "$s" in *=*) ;; *) die "global set: ai-model --set expects <role>=<provider:model|—>, got '$s'" ;; esac
        role="${s%%=*}"; value="${s#*=}"
        case " $AI_MODEL_ROLES " in *" $role "*) ;; *) die "invalid role '$role' (allowed: $AI_MODEL_ROLES)" ;; esac
        case "$value" in
          —|-) ;;
          *:*) local _p="${value%%:*}"; local _m="${value#*:}"
               local _ok=0 _pp
               for _pp in "${PW_PROVIDERS[@]}"; do [ "$_pp" = "$_p" ] && _ok=1; done
               [ "$_ok" = 1 ] || die "global ai-model '$role': '$_p' is not an enabled Agent Provider (${PW_PROVIDERS[*]})"
               _model_permission_check "$_p" "$_m" >/dev/null
               ;;
          *) die "global ai-model '$role': expected <provider:model>, got '$value'" ;;
        esac
        if [ "$tuning_given" = 1 ]; then
          case "$value" in —|-|"") die "global set: tuning needs a real provider:model binding" ;; *:*) ;; *) die "global set: tuning needs provider:model, got '$value'" ;; esac
          _model_tuning_validate "global ai-model '$role'" "${value%%:*}" "${value#*:}" "$variant" "$reasoning" "$effort"
        fi
      done
      for s in "${sets[@]}"; do
        role="${s%%=*}"; value="${s#*=}"
        pv="$(_global_role_var "$role" MODEL)"
        _global_set_var "$pv" "$value"
        if [ "$tuning_given" = 1 ]; then
          local _axis_var _axis_val
          for _axis in VARIANT REASONING EFFORT; do
            case "$_axis" in VARIANT) _axis_val="$variant" ;; REASONING) _axis_val="$reasoning" ;; EFFORT) _axis_val="$effort" ;; esac
            _axis_var="$(_global_role_var "$role" "$_axis")"
            if [ -n "$_axis_val" ]; then _global_set_var "$_axis_var" "$_axis_val"; else _global_unset_var "$_axis_var"; unset "$_axis_var" 2>/dev/null || true; fi
          done
        else
          # Whole-binding replacement: omitted tuning resets instead of carrying stale controls.
          local _axis_var
          for _axis in VARIANT REASONING EFFORT; do
            _axis_var="$(_global_role_var "$role" "$_axis")"
            _global_unset_var "$_axis_var"
            unset "$_axis_var" 2>/dev/null || true
          done
        fi
      done ;;
  esac
  _global_lock_end
  echo "global: $key -> $(_global_effective "$key")"
  echo "  applies to NEW projects only; existing projects keep captured values (/pw-config set --project <slug> changes one project)."
}

cmd_global_unset() { # --key <k> [--provider <p> --agent <name>]
  local key="" prov="" agent="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --key=*) v="${a#*=}"; a="--key" ;; --provider=*) v="${a#*=}"; a="--provider" ;; --agent=*) v="${a#*=}"; a="--agent" ;; esac
    case "$a" in
      --key|--provider|--agent)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --key) key="$v" ;; --provider) prov="$v" ;; --agent) agent="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "global unset --key <key> [--provider <p> --agent <name>]   (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;;
      *) _pw_positional "$a" "global unset --key <key> [--provider <p> --agent <name>]   (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;;
    esac
  done
  [ -n "$key" ] || die "global unset: --key is required → fix: global unset --key <key> [--provider <p> --agent <name>]"
  if [ "$key" = agent-model ]; then
    [ -n "$prov" ] && [ -n "$agent" ] \
      || die "global unset agent-model: --provider and --agent are required → fix: global unset --key agent-model --provider <p> --agent <pw-name>"
    cmd_agent_model_unset --provider "$prov" --agent "$agent"
    return 0
  fi
  case " $GLOBAL_PROJECT_KEYS " in *" $key "*) ;; *) die "global unset: unknown key '$key' (keys: $GLOBAL_PROJECT_KEYS or agent-model)" ;; esac
  local r var restored=0
  _global_lock_begin
  if [ "$key" = ai-model ]; then
    for r in $AI_MODEL_ROLES; do
      for var in MODEL VARIANT REASONING EFFORT; do
        var="$(_global_role_var "$r" "$var")"
        _global_unset_var "$var"
        _global_reapply_fallback "$var" && restored=1
      done
    done
  else
    var="$(_global_key_var "$key")"
    _global_unset_var "$var"
    _global_reapply_fallback "$var" && restored=1
  fi
  _global_lock_end
  echo "global: $key unset -> $(_global_effective "$key")"
  if [ "$restored" = 1 ]; then
    echo "  source: earlier pw.config.sh assignment"
  else
    echo "  source: built-in / legacy fallback"
  fi
}

# --- creation-time snapshot validation -------------------------------------------------------
# Validate the resolved global project-default snapshot (scalars + every non-empty role binding)
# before scaffold publishes a destination. Positive determinations refuse; unverified metadata
# stays explicit, never a silent substitution.
cmd_validate_defaults() {
  local r v tun axis val bad=0
  case "$(pw_project_default_value routing)" in auto|subagent|headless) ;; *) echo "pw-config: global default routing is not auto|subagent|headless — fix: /pw-config global set --key routing --value auto" >&2; bad=1 ;; esac
  case "$(pw_project_default_value execution-limit)" in ''|*[!0-9]*) echo "pw-config: global default execution-limit is not an integer — fix: /pw-config global set --key execution-limit --value <0..99>" >&2; bad=1 ;; *) ;; esac
  v="$(pw_project_default_value max-parallel)"
  case "$v" in ''|—) ;; *[!0-9]*) echo "pw-config: global default max-parallel is not an integer — fix: /pw-config global set --key max-parallel --value <1..99>" >&2; bad=1 ;; esac
  case "$(pw_project_default_value review-rounds)" in 1|2|3) ;; *) echo "pw-config: global default review-rounds is not 1..3 — fix: /pw-config global set --key review-rounds --value <1..3>" >&2; bad=1 ;; esac
  local pair phase value
  for pair in $(_global_effective ai-review); do
    phase="${pair%%=*}"; value="${pair#*=}"
    case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) echo "pw-config: global default ai-review has unknown surface '$phase' — fix: /pw-config global set --key ai-review --set <surface>=advisory|auto" >&2; bad=1 ;; esac
    case "$value" in advisory|auto|off) ;; *) echo "pw-config: global default ai-review '$phase' is '$value' (allowed: advisory|auto; legacy off reads advisory) — fix: /pw-config global set --key ai-review --set $phase=advisory" >&2; bad=1 ;; esac
  done
  for pair in $(_global_effective review-trigger); do
    phase="${pair%%=*}"; value="${pair#*=}"
    case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) echo "pw-config: global default review-trigger has unknown surface '$phase' — fix: /pw-config global set --key review-trigger --set <surface>=manual|completion" >&2; bad=1 ;; esac
    case "$value" in manual|completion) ;; *) echo "pw-config: global default review-trigger '$phase' is '$value' (allowed: manual|completion) — fix: /pw-config global set --key review-trigger --set $phase=manual" >&2; bad=1 ;; esac
  done
  for pair in $(_global_effective review-repair); do
    phase="${pair%%=*}"; value="${pair#*=}"
    case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) echo "pw-config: global default review-repair has unknown surface '$phase' — fix: /pw-config global set --key review-repair --set <surface>=manual|bounded" >&2; bad=1 ;; esac
    case "$value" in manual|bounded) ;; *) echo "pw-config: global default review-repair '$phase' is '$value' (allowed: manual|bounded) — fix: /pw-config global set --key review-repair --set $phase=manual" >&2; bad=1 ;; esac
  done
  for r in $AI_MODEL_ROLES; do
    v="$(pw_project_default_role "$r")"
    case "$v" in ""|—) continue ;; esac
    _model_pin_validate "global default ai-model '$r'" "$v" || bad=1
    tun="$(pw_project_default_tuning "$r")"
    [ -n "$tun" ] || continue
    _model_tuning_validate "global default ai-model '$r'" "${v%%:*}" "${v#*:}" \
      "$(_tuning_field "$tun" variant)" "$(_tuning_field "$tun" reasoning)" "$(_tuning_field "$tun" effort)" || bad=1
  done
  [ "$bad" = 0 ] || return 1
  return 0
}

# --- provider binding -> spawn arguments -----------------------------------------------------
# One adapter contract for role dispatch. The caller never re-derives provider flags from a
# display string: this returns the validated binding plus its exact native/headless arguments.
# Unsupported tuning refuses (exit 2); it is never silently dropped.
_json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
_json_array() { # <arg>…
  local out="" a
  for a in "$@"; do out="$out${out:+,}\"$(_json_escape "$a")\""; done
  printf '[%s]' "$out"
}

cmd_spawn_args() { # [--project <slug>] (--role <role> | --agent <pw-name>) [--provider <p>] [--json]
  local slug="" role="" agent="" prov_hint="" a v json=0
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --role=*)    v="${a#*=}"; a="--role" ;;
      --agent=*)   v="${a#*=}"; a="--agent" ;;
      --provider=*) v="${a#*=}"; a="--provider" ;;
    esac
    case "$a" in
      --project|--role|--agent|--provider)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in
          --project) slug="$v" ;; --role) role="$v" ;;
          --agent) agent="$v" ;; --provider) prov_hint="$v" ;;
        esac ;;
      --json) json=1 ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "spawn-args [--project <slug>] (--role <role> | --agent <name>) [--provider <p>] [--json]   (roles: $AI_MODEL_ROLES)" ;;
      *) _pw_positional "$a" "spawn-args [--project <slug>] (--role <role> | --agent <name>) [--provider <p>] [--json]" ;;
    esac
  done
  [ -n "$role" ] || [ -n "$agent" ] || die "spawn-args: --role or --agent is required → fix: spawn-args --project <slug> --role <role> | spawn-args --provider <p> --agent <pw-name>   (roles: $AI_MODEL_ROLES)"
  if [ -n "$role" ] && [ -n "$agent" ]; then die "spawn-args: --role and --agent are mutually exclusive"; fi
  local f="" line="" tune="" binding="—" tuning="" prov="" model="" variant="" reasoning="" effort="" kv source="default"
  if [ -n "$agent" ]; then
    _worker_agent_known "$agent" || die "spawn-args: unknown canonical worker '$agent' → fix: use one of: $(pw_canonical_agent_names | tr '\n' ' ')"
    [ -n "$prov_hint" ] || die "spawn-args: --provider is required with --agent (worker defaults are provider-specific)"
    _worker_provider_enabled "$prov_hint" || die "spawn-args: provider '$prov_hint' is not enabled (${PW_PROVIDERS[*]})"
    binding="$(pw_agent_default_spec "$prov_hint" "$agent")"
    if [ -n "$binding" ]; then
      source="worker"
      _worker_spec_parse "spawn-args '$prov_hint/$agent'" "$prov_hint" "$binding"
      prov="$prov_hint"; model="$W_MODEL"; variant="$W_VARIANT"; reasoning="$W_REASONING"; effort="$W_EFFORT"
      if [ -n "$W_PARAMS" ] && [ "$prov_hint" = cursor ]; then model="$W_MODEL[$W_PARAMS]"; preset_cursor=1; fi
    else
      binding="—"; prov="$prov_hint"
    fi
  else
    case " $AI_MODEL_ROLES " in *" $role "*) ;; *) die "spawn-args: invalid role '$role' (allowed: $AI_MODEL_ROLES)" ;; esac
    [ -n "$slug" ] || die "spawn-args: --project is required with --role → fix: spawn-args --project <slug> --role <role>"
    f="$(proj_dir "$slug")/README.md"
    [ -f "$f" ] || die "spawn-args: no README.md in project $slug"
    line="$(grep -m1 '^- \*\*AI Models:\*\*' "$f" 2>/dev/null | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//' || true)"
    tune="$(grep -m1 '^- \*\*AI Model Tuning:\*\*' "$f" 2>/dev/null | sed 's/^- \*\*AI Model Tuning:\*\*[[:space:]]*//' || true)"
    binding="—"
    for kv in $line; do [ "${kv%%=*}" = "$role" ] && binding="${kv#*=}"; done
    tuning=""
    for kv in $tune; do [ "${kv%%=*}" = "$role" ] && tuning="${kv#*=}"; done
    if [ "$binding" != "—" ] && [ "$binding" != "-" ]; then
      case "$binding" in *:*) prov="${binding%%:*}"; model="${binding#*:}" ;; *) die "spawn-args: malformed stored binding '$binding' → fix: /pw-config set --project $slug --key ai-model --set $role=<provider:model>" ;; esac
      source="project"
      variant="$(_tuning_field "$tuning" variant)"
      reasoning="$(_tuning_field "$tuning" reasoning)"
      effort="$(_tuning_field "$tuning" effort)"
    else
      # No project pin: an authorized provider hint may select the worker default for this role.
      prov="$prov_hint"
      local _worker=""
      _worker="$(pw_role_worker "$role")" || _worker=""
      if [ -n "$prov_hint" ] && [ -n "$_worker" ]; then
        _worker_provider_enabled "$prov_hint" || die "spawn-args: provider '$prov_hint' is not enabled (${PW_PROVIDERS[*]})"
        binding="$(pw_agent_default_spec "$prov_hint" "$_worker")"
        if [ -n "$binding" ]; then
          source="worker"
          _worker_spec_parse "spawn-args '$prov_hint/$_worker'" "$prov_hint" "$binding"
          model="$W_MODEL"; variant="$W_VARIANT"; reasoning="$W_REASONING"; effort="$W_EFFORT"
          if [ -n "$W_PARAMS" ] && [ "$prov_hint" = cursor ]; then model="$W_MODEL[$W_PARAMS]"; preset_cursor=1; fi
        fi
      fi
      [ -n "$model" ] || binding="—"
    fi
  fi
  # Canonicalize the exact id the provider CLI must receive (the same availability gate the driver
  # runs before spawning). "unverified" prose is not a canonical id, so the stored value stays.
  if [ -n "$prov" ] && [ -n "$model" ]; then
    local _enabled=0 _p
    for _p in "${PW_PROVIDERS[@]}"; do [ "$_p" = "$prov" ] && _enabled=1; done
    [ "$_enabled" = 1 ] \
      || die "spawn-args: provider '$prov' is not an enabled Agent Provider (PW_PROVIDERS: ${PW_PROVIDERS[*]}) → fix: enable it in pw.config.sh or re-pin role '$role'"
    local _resolved _rrc=0 _base
    case "$prov" in cursor) _base="${model%%\[*}" ;; *) _base="$model" ;; esac
    _resolved="$(cmd_model_resolve --provider "$prov" --model "$_base" 2>/dev/null)" || _rrc=$?
    [ "$_rrc" = 0 ] || die "spawn-args: $prov:$model is not available on this route (model-resolve exit $_rrc) → fix: re-pin the role with /pw-config set --project $slug --key ai-model --set $role=<provider:model>"
    case "$_resolved" in ''|*' '*) ;; *)
      case "$prov" in
        cursor) model="$_resolved${model#"$_base"}" ;;
        *) model="$_resolved" ;;
      esac ;;
    esac
  fi
  local -a args; args=()
  local supported=1 reason="" route="native" effective_prov="$prov" effective_model="$model" preset_cursor=0
  if [ -z "$prov" ]; then
    supported=1; reason="unbound: provider/session default"
  else
    case "$prov" in
      kilo)
        args=(-m "$model")
        if [ -n "$variant" ]; then args+=(--variant "$variant"); fi
        if [ -n "$reasoning" ] || [ -n "$effort" ]; then supported=0; reason="kilo has no verified reasoning/effort control in the role route (supported: variant)"; fi ;;
      claude)
        args=(--model "$model")
        if [ -n "$effort" ]; then args+=(--effort "$effort"); fi
        if [ -n "$variant" ] || [ -n "$reasoning" ]; then supported=0; reason="claude role route supports effort only (unsupported: variant/reasoning)"; fi ;;
      cursor)
        if [ "$preset_cursor" = 1 ]; then
          effective_model="$model"
        else
          effective_model="$model"
          [ -n "$variant" ] && effective_model="${model}-${variant}"
          local bracket=""
          [ -n "$reasoning" ] && bracket="reasoning=$reasoning"
          [ -n "$effort" ] && bracket="${bracket:+$bracket,}effort=$effort"
          [ -n "$bracket" ] && effective_model="${effective_model}[${bracket}]"
        fi
        args=(--model "$effective_model") ;;
      codex)
        args=(-m "$model")
        if [ -n "$reasoning" ] && [ -n "$effort" ] && [ "$reasoning" != "$effort" ]; then
          supported=0; reason="codex has one reasoning-effort control; conflicting reasoning/effort refused"
        elif [ -n "$reasoning" ] || [ -n "$effort" ]; then
          args+=(-c "model_reasoning_effort=${reasoning:-$effort}")
        fi ;;
      *)
        args=(-m "$model")
        if [ -n "$variant$reasoning$effort" ]; then supported=0; reason="provider '$prov' has no verified role tuning mapping"; fi ;;
    esac
  fi
  if [ "$json" = 1 ]; then
    printf '{"role":"%s","agent":"%s","provider":"%s","model":"%s","variant":"%s","reasoning":"%s","effort":"%s","route":"%s","source":"%s","supported":%s,"reason":"%s","args":%s}\n' \
      "$(_json_escape "$role")" "$(_json_escape "$agent")" "$(_json_escape "$effective_prov")" "$(_json_escape "$effective_model")" \
      "$(_json_escape "$variant")" "$(_json_escape "$reasoning")" "$(_json_escape "$effort")" "$route" "$source" \
      "$([ "$supported" = 1 ] && echo true || echo false)" "$(_json_escape "$reason")" "$(_json_array ${args[@]+"${args[@]}"})"
  else
    printf 'role: %s\nagent: %s\nprovider: %s\nmodel: %s\nvariant: %s\nreasoning: %s\neffort: %s\nsource: %s\nsupported: %s\nreason: %s\n' \
      "$role" "$agent" "$effective_prov" "$effective_model" "$variant" "$reasoning" "$effort" "$source" "$([ "$supported" = 1 ] && echo yes || echo no)" "${reason:-exact binding}"
    local arg
    for arg in ${args[@]+"${args[@]}"}; do printf 'arg: %s\n' "$arg"; done
  fi
  [ "$supported" = 1 ] || exit 2
}

cmd_global() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    show)  cmd_global_show "$@" ;;
    get)   cmd_global_get "$@" ;;
    set)   cmd_global_set "$@" ;;
    unset) cmd_global_unset "$@" ;;
    "")    die "usage: global <show|get|set|unset> …   (show is read-only except the guarded project-default writes; see --help)" ;;
    *)     die "usage: global <show|get|set|unset> … (got '$sub')" ;;
  esac
}

case "${1:-}" in
  show)          shift; cmd_show "$@" ;;
  get)           shift; cmd_get "$@" ;;
  set)           shift; cmd_set "$@" ;;
  ensure)        shift; cmd_ensure "$@" ;;
  materialize)   shift; cmd_materialize "$@" ;;
  global)        shift; cmd_global "$@" ;;
  validate-defaults) shift; cmd_validate_defaults "$@" ;;
  spawn-args)    shift; cmd_spawn_args "$@" ;;
  model-check)   shift; cmd_model_check "$@" ;;
  model-resolve) shift; cmd_model_resolve "$@" ;;
  models)        shift; cmd_models "$@" ;;
  agent-model)   shift; cmd_agent_model "$@" ;;
  agent-model-set) shift; cmd_agent_model_set "$@" ;;
  agent-model-unset) shift; cmd_agent_model_unset "$@" ;;
  agent-models)  shift; cmd_agent_models "$@" ;;
  ai-model)      shift; _dep_note ai-model "set --project <slug> --key ai-model --set <role=value>…"; cmd_ai_model "$@" ;;
  ai-review)     shift; _dep_note ai-review "set --project <slug> --key ai-review --set <surface>=<mode>…"; cmd_ai_review "$@" ;;
  review-trigger) shift; _dep_note review-trigger "set --project <slug> --key review-trigger --set <surface>=<value>…"; cmd_review_trigger "$@" ;;
  review-repair)  shift; _dep_note review-repair "set --project <slug> --key review-repair --set <surface>=<value>…"; cmd_review_repair "$@" ;;
  review-rounds)  shift; _dep_note review-rounds "set --project <slug> --key review-rounds --value <n>"; cmd_review_rounds "$@" ;;
  project) die "the 'project' operator was flattened → fix: use show|get|set|ensure --project <slug> (see --help)" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-config.sh <show|get|set|ensure|materialize|global|validate-defaults|spawn-args|model-check|model-resolve|models|agent-model|agent-model-set|agent-model-unset|agent-models|ai-model|ai-review|review-trigger|review-repair|review-rounds> … (see --help)" ;;
esac
