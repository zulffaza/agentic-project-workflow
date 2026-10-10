#!/usr/bin/env bash
# ============================================================================
# pw-config.sh — the per-project config entity: which models and which review
# modes a project runs with (dashboard config lines, get-or-set semantics).
#
#   pw-config.sh project      <op> <slug> …  — ALL per-project configuration, under ONE operation:
#       project show   <slug> [--json]   every axis: kind | stored | source | effective floor
#                                        (read-only — includes state/data rows, which have no set)
#       project get    <slug> <key>      one config key's stored value (or "(unset — effective: …)")
#       project set    <slug> <key> <value…>   validated write through the single owner location
#                                        (keys: routing | execution-limit | max-parallel |
#                                               produced-by | ai-review | ai-model | pin | rfc-target |
#                                               review-trigger | review-repair | review-rounds)
#                                        ai-review/ai-model/review-trigger/review-repair accept BATCH
#                                        pairs (`plan=auto ship=advisory`) and an `all=<value>`
#                                        baseline that expands over every supported surface, with
#                                        explicitly named surfaces overriding it (in either
#                                        argument order): every pair validated first
#                                        (all-or-nothing), then ONE write + ONE LOG line.
#                                        review-rounds takes one integer 1..3 (the bounded
#                                        review→repair cycle's total reviewer passes).
#                                        pin accepts BATCH task pins (`pin T01=kilo:prov/model
#                                        T02=claude:sonnet`, `—` clears): same all-or-nothing
#                                        validation (membership + model-check + model-resolve),
#                                        written to BOTH holders — task file `Execute with:` +
#                                        PLAN cell — by one propagator, ONE LOG line.
#       project ensure <slug>            insert any missing explicit dashboard config lines
#                                        (AI Models: / AI Review: / Review Trigger: /
#                                        Review Repair: / Review Budget: — `—`/`manual`/`3` are
#                                        legal explicit values; an absent line is a defect,
#                                        never a style choice). Also the one migration door for
#                                        legacy `off` outcome rows: they become effective
#                                        `advisory` on every read WITHOUT a write; ensure
#                                        persists that normalization.
#   pw-config.sh global     show
#       The effective machine floors view: providers, API-provider scopes, model allowlists,
#       route/ladder defaults, repair budgets, RFC backend. Read-only on purpose — pw.config.sh
#       is the human-owned floor file; there is deliberately no `global set`.
#   get/set on state/data keys (status, adopted, base-branches, landing-units) is REFUSED with the
#   owning flow's command — those are derived facts, not configuration.
#   Bare `ai-model` / `ai-review` are DEPRECATED shims onto `project ai-model` / `project
#   ai-review` — same behavior plus a pointer; use the project form in new invocations.
#   pw-config.sh ai-model     <slug> [<role> <provider:model|—> | <role>=<value>…]
#       Get or set spawn-lane model rows (roles: researcher analyst
#       writer-task reviewer verifier). — clears to provider/session default. Several
#       role=<value> pairs in one call = batch (validated all-or-nothing, one write/log).
#   pw-config.sh ai-review    <slug> [<surface> <mode> | <surface>=<mode>…]
#       Get or set AI-review OUTCOME modes. Two values only: advisory|auto (auto is
#       what lets pw-review.sh auto-signoff ever succeed). The removed `off` value
#       reads as effective `advisory` (missing rows too), so an explicit AI pass is
#       always callable; SCHEDULING lives on review-trigger, never here. `all=<mode>`
#       sets every surface, named surfaces override it. Surfaces:
#       context analysis plan task-plan task-exec ship rfc close.
#   pw-config.sh review-trigger <slug> [<surface> <value> | <surface>=<value>…]
#       Get or set WHEN an AI pass starts: manual (only an explicit /pw-review … ai
#       request) | completion (after a successful producing command's verification).
#       completion never disables explicit requests; missing rows mean manual.
#   pw-config.sh review-repair <slug> [<surface> <value> | <surface>=<value>…]
#       Get or set whether a completion review may run the BOUNDED repair cycle:
#       manual (findings stop for the owner) | bounded (review→repair→verify→fresh
#       review within the budget). Missing rows mean manual.
#   pw-config.sh review-rounds <slug> [<n>]
#       Get or set the bounded cycle's total reviewer passes (1..3; default 3 —
#       three passes allow at most two intervening verified repairs).
#   pw-config.sh model-check  <provider> <model-id>
#       Pass/refuse a model against PW_MODEL_ALLOWLIST_<PROVIDER> from
#       pw.config.sh (empty/unset = all allowed — the default rule).
#   pw-config.sh model-resolve <provider> <model-id>
#       AVAILABILITY check (the sibling of model-check's PERMISSION check): match the model
#       against the provider's live catalog, verify it sits inside the
#       PW_<PROVIDER>_API_PROVIDERS prefix scope, and print the CANONICAL catalog id that a
#       headless `-m`/`--model` must receive. exit 0 resolved / 1 not in catalog /
#       2 matched but out of configured scope. Providers with no queryable catalog (claude)
#       or no catalog reachable (CLI off PATH) exit 0 "unverified" — never a false dead.
#
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
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: /pw-new $1)"; printf '%s' "$d"; }

# --- AI Models (per-lane model row for the spawned sub-agent lanes — plan 01 §5.1) -----------
# The model sibling of the AI Review config block below: which model a *lane* should run on when a
# phase spawns it, per project. Roles = spawn lanes (researcher / analyst / writer-task / reviewer /
# verifier). The **executor is never a row** — a task's `Execute with:` already pins its per-unit
# model (a dashboard copy would only drift from it) — and clean-execution choices (`Results
# acceptance`, `- AI execution limit`) live in PLAN's Execution strategy, not the dashboard.
# `—` = no row = provider/session default (the kilo `small_model`/`subagent_model` floor, or
# claude's session/def model). Values are `<provider>:<model>`-shaped — the same syntax as
# `Execute with:` (tooling/docs/providers.md). Where a provider can't bind the row at spawn time
# (kilo's Task-tool spawn has no model arg), the driver runs the row as a **headless session** of
# that model over the same work order, and records what actually ran — a pin that can't fire says
# so in the result, instead of silently running the floor model while the row claims a pin.
AI_MODEL_ROLES="researcher analyst writer-task reviewer verifier"

# Idempotent: insert the dashboard line, all-—, if it doesn't exist yet (covers projects scaffolded
# before this feature existed — same ensure-if-missing idiom as _ai_review_line_ensure).
_ai_models_line_ensure() {
  local f="$1"
  grep -q '^- \*\*AI Models:\*\*' "$f" && return 0
  local default="" r
  for r in $AI_MODEL_ROLES; do default="$default $r=—"; done
  default="${default# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor AI Models: after in $f"
  awk -v t="$default" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **AI Models:** " t; d=1}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Get (no extra args) or set (role + value; — clears to no-row).
#   ai-model <slug>                                -> "researcher=— analyst=— writer-task=— reviewer=— verifier=—"
#   ai-model <slug> <role> <provider:model|—>      -> sets just that lane, leaves the other four untouched
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
  awk -v pre="- **${label}:** " -v t="$cur" '
    !d && index($0, pre) == 1 { print pre t; d=1; next }
    { print } END { if (!d) exit 3 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
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
      cmd_model_check "$_prov" "$_mdl" >/dev/null
      _mres="$(cmd_model_resolve "$_prov" "$_mdl" 2>&1)" || _mrc=$?
      if [ "$_mrc" = 1 ] || [ "$_mrc" = 2 ]; then
        die "$context refused at write time — $_mres"
      fi ;;
    *) die "invalid value '$value' ($context) — write <provider>:<model> (e.g. kilo:command_code/<m>, claude:sonnet) or — to clear" ;;
  esac
}

cmd_ai_model() {
  [ $# -ge 1 ] || die "usage: ai-model <slug> [<role> <provider:model|—> | <role>=<value>…]   (role: $AI_MODEL_ROLES)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_models_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -ge 2 ] || die "usage: ai-model <slug> <role> <provider:model|—>   (or batch: '<role>=<value>' pairs; roles: $AI_MODEL_ROLES)"
  if [ "${1#*=}" = "$1" ]; then
    # legacy positional <role> <value> → normalize to the one pair form
    [ $# -eq 2 ] || die "usage: ai-model <slug> <role> <provider:model|—>   (or batch role=<value> pairs)"
    set -- "$1=$2"
  fi
  local pair
  for pair in "$@"; do
    case "$pair" in *=*) ;; *) die "ai-model: expected <role>=<provider:model|—>, got '$pair' (legacy form: '<role> <value>')" ;; esac
    _ai_model_validate "${pair%%=*}" "${pair#*=}"
  done
  _line_pairs_set "$f" "AI Models" "$@"
  if [ $# -eq 1 ]; then
    "$ST" log "$slug" ai-model "${1%%=*} -> ${1#*=}"
    echo "$slug: AI Model ${1%%=*} -> ${1#*=}"
  else
    "$ST" log "$slug" ai-model "set: $*"
    echo "$slug: AI Models set: $*"
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
#                  silently dead; /pw-config … project ensure persists the normalization.
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
  if awk -v pre="- **${label}:** " -v t="$t" -v apre="- **${anchorlabel}:** " '
      {print}
      !d && index($0, apre) == 1 {print pre t; d=1}
      END { if (!d) exit 3 }' "$f" > "$f.tmp"; then
    mv "$f.tmp" "$f" || { rm -f "$f.tmp"; return 1; }
    return 0
  fi
  rm -f "$f.tmp"
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
    off)  die "'off' was removed from ai-review — outcome is advisory|auto; keep review manual with review-trigger=manual instead (explicit AI review stays available). → fix: /pw-config <slug> set ai-review all=advisory" ;;
    *)    die "invalid mode '$2' (allowed: advisory auto) → fix: use advisory (human still approves) or auto (guarded self-approval on a clean pass)" ;;
  esac
}
_review_trigger_validate() {
  case " $AI_REVIEW_PHASES " in *" $1 "*) ;; *) die "invalid surface '$1' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$2" in
    manual|completion) ;;
    both) die "'both' was removed — 'completion' already keeps explicit review available → fix: /pw-config <slug> set review-trigger all=completion (or manual)" ;;
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
    case "$pair" in *=*) ;; *) die "$axis: expected <surface>=<value> or all=<value>, got '$pair'" ;; esac
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
# review-repair): ensure line → get (normalized for ai-review) or expand+validate+write+log.
_review_axis_cmd() { # <axis> <line-label> <validator-fn> <values-help> <slug> [args…]
  local axis="$1" label="$2" vfn="$3" vhelp="$4" slug="$5"; shift 5
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  case "$axis" in
    ai-review)      _ai_review_line_ensure "$f" ;;
    review-trigger) _review_trigger_line_ensure "$f" ;;
    review-repair)  _review_repair_line_ensure "$f" ;;
  esac
  if [ $# -eq 0 ]; then
    local line out kv norm=0
    line="$(grep -m1 "^- \*\*${label}:\*\*" "$f" | sed "s|^- \*\*${label}:\*\*[[:space:]]*||" || true)"
    if [ "$axis" = "ai-review" ]; then
      out=""
      for kv in $line; do
        case "${kv#*=}" in
          off) out="$out ${kv%%=*}=advisory"; norm=1 ;;
          *)   out="$out $kv" ;;
        esac
      done
      [ "$norm" = 1 ] && printf 'pw-config: note: stored legacy off row(s) read as effective advisory — persist with: /pw-config %s project ensure\n' "$slug" >&2
      printf '%s\n' "${out# }"
      return 0
    fi
    printf '%s\n' "$line"
    return 0
  fi
  [ $# -ge 1 ] || die "usage: $axis <slug> <surface> <value>   (or batch: '<surface>=<value>' pairs / all=<value>; $vhelp)"
  if [ "${1#*=}" = "$1" ]; then
    [ $# -eq 2 ] || die "usage: $axis <slug> <surface> <value>   (or batch pairs; $vhelp)"
    set -- "$1=$2"
  fi
  local argc=$# expanded pair
  expanded="$(_expand_axis_pairs "$axis" "$@")" || exit 2
  for pair in $expanded; do "$vfn" "${pair%%=*}" "${pair#*=}"; done
  _line_pairs_set "$f" "$label" $expanded
  if [ "$argc" = 1 ] && [ "$(printf '%s' "$expanded" | wc -w | tr -d ' ')" = 1 ]; then
    "$ST" log "$slug" "$axis" "${expanded%%=*} -> ${expanded#*=}"
    echo "$slug: ${label} ${expanded%%=*} -> ${expanded#*=}"
  else
    "$ST" log "$slug" "$axis" "set: $expanded"
    echo "$slug: ${label} set: $expanded"
  fi
}

# Get (no extra args) or set (surface + mode) this project's per-surface AI-review OUTCOME mode.
#   ai-review <slug>                       -> effective rows, legacy off normalized to advisory
#   ai-review <slug> <surface> <mode>      -> sets just that surface
#   ai-review <slug> all=<mode> [s=<mode>] -> baseline + named overrides
cmd_ai_review() {
  [ $# -ge 1 ] || die "usage: ai-review <slug> [<surface> <mode> | <surface>=<mode>… | all=<mode>]   (surfaces: $AI_REVIEW_PHASES; modes: advisory|auto)"
  local slug="$1"; shift
  _review_axis_cmd ai-review "AI Review" _ai_review_validate "modes: advisory|auto" "$slug" "$@"
}
cmd_review_trigger() {
  [ $# -ge 1 ] || die "usage: review-trigger <slug> [<surface> <value> | <surface>=<value>… | all=<value>]   (surfaces: $AI_REVIEW_PHASES; values: manual|completion)"
  local slug="$1"; shift
  _review_axis_cmd review-trigger "Review Trigger" _review_trigger_validate "values: manual|completion" "$slug" "$@"
}
cmd_review_repair() {
  [ $# -ge 1 ] || die "usage: review-repair <slug> [<surface> <value> | <surface>=<value>… | all=<value>]   (surfaces: $AI_REVIEW_PHASES; values: manual|bounded)"
  local slug="$1"; shift
  _review_axis_cmd review-repair "Review Repair" _review_repair_validate "values: manual|bounded" "$slug" "$@"
}
# Get/set the bounded cycle's total reviewer passes (1..3, default 3).
#   review-rounds <slug>       -> "rounds=3"
#   review-rounds <slug> <n>   -> sets n
cmd_review_rounds() {
  [ $# -ge 1 ] || die "usage: review-rounds <slug> [<n>]   (n: 1..3 — total reviewer passes in a bounded review→repair cycle; default 3)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _review_budget_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep -m1 '^- \*\*Review Budget:\*\*' "$f" | sed 's/^- \*\*Review Budget:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -eq 1 ] || die "usage: review-rounds <slug> <1..3>"
  _require_int review-rounds "$1" 1 3
  _line_pairs_set "$f" "Review Budget" "rounds=$1"
  "$ST" log "$slug" review-rounds "rounds -> $1"
  echo "$slug: Review Budget rounds -> $1"
}



# Guard against an agent picking an unexpectedly expensive model. Reads PW_MODEL_ALLOWLIST_<PROVIDER>
# (uppercased) from pw.config.sh — a comma-separated list of glob patterns matched against the
# model id (the part after the provider prefix, e.g. "opus" or "command_code/deepseek/*").
# THE RULE: empty or unset = ALL models allowed for that provider — this is the default, and it's
# deliberate: nothing is restricted unless you explicitly configure a pattern. Never taken on the
# caller's word — this re-reads the config itself, same spirit as auto-signoff re-checking its own
# gate rather than trusting the reviewer. Called by /pw-breakdown (while filling a task's `Execute
# with:`) and /pw-execute (again, right before invoking — catches a hand-edited PLAN.md too); not
# meant to be run directly by a human — see docs/EXECUTION.md's "Model allowlist" section.
#   model-check <provider> <model-id>
cmd_model_check() {
  [ $# -eq 2 ] || die "usage: model-check <provider> <model-id>   (empty PW_MODEL_ALLOWLIST_<PROVIDER> = all models allowed)"
  local prov="$1" model="$2" upper var allow pats pat matched=0
  upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
  var="PW_MODEL_ALLOWLIST_${upper}"
  allow="${!var:-}"
  if [ -z "$allow" ]; then
    echo "model-check: $prov:$model — allowed (PW_MODEL_ALLOWLIST_${upper} is empty = all models allowed, the default)"
    return 0
  fi
  IFS=',' read -ra pats <<< "$allow"
  for pat in "${pats[@]}"; do
    pat="$(printf '%s' "$pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$model" in
      $pat) matched=1; break ;;
    esac
  done
  if [ "$matched" -eq 1 ]; then
    echo "model-check: $prov:$model — allowed (matched allowlist pattern \"$pat\")"
    return 0
  fi
  die "model-check: $prov:$model — refused. Not in PW_MODEL_ALLOWLIST_${upper} (\"$allow\"). Add a matching pattern to pw.config.sh, or choose an allowed model."
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
#   model-resolve <provider> <model-id>
cmd_model_resolve() {
  [ $# -eq 2 ] || die "usage: model-resolve <provider> <model-id>   (prints the canonical catalog id on exit 0)"
  local prov="$1" model="$2" catalog line cands upper via=0
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
  # EXACT catalog line first — the prefix distinguishes connections (see header), so a bare
  # row must never silently bind the gateway line when a direct provider line exists.
  line="$(printf '%s\n' "$catalog" | grep -F -x "$model" | head -1 || true)"
  if [ -z "$line" ]; then
    line="$(printf '%s\n' "$catalog" | grep -F -x "$prov/$model" | head -1 || true)"
    via=1
  fi
  if [ -z "$line" ]; then
    echo "model-resolve: $prov:$model — not in the live catalog (exit 1)" >&2
    echo "  → fix: re-pin the row to a real id — candidates from the '$prov' live catalog (\`pw-help\` lists each provider's catalog command):" >&2
    cands="$(printf '%s\n' "$catalog" | grep -F "${model##*/}" | head -5 || true)"
    [ -n "$cands" ] && printf '%s\n' "$cands" | sed 's/^/      /' >&2 || echo "      (none matching '${model##*/}' — check the provider scope too)" >&2
    return 1
  fi
  if [ "$via" = 1 ]; then
    echo "model-resolve: $prov:$model — no exact catalog line; bound the gateway-nested '$line'. A direct provider '$model' is a different connection; pin the full id if you meant the other." >&2
  fi
  if ! pw_api_in_scope "$prov" "$line"; then
    upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
    echo "model-resolve: $prov:$model — matched '$line' but it is OUTSIDE the PW_${upper}_API_PROVIDERS scope (exit 2)" >&2
    echo "  → fix: restore the matching entry in pw.config.sh, or re-pin the row to an in-scope id. Current scope:" >&2
    pw_api_entries "$prov" | sed 's/^/      /' >&2
    return 2
  fi
  printf '%s\n' "$line"
}

# --- project scope (per-project config, ONE operation) + global floors -------------------------
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
    awk -v label="$label" -v value="$value" '
      !done && index($0, "- **" label ":**") == 1 { print "- **" label ":** " value; done=1; next }
      { print } END { if (!done) exit 3 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" && return 0
    rm -f "$f.tmp"; return 3
  fi
  if [ -n "$anchor" ] && grep -qE "$anchor" "$f"; then
    awk -v label="$label" -v value="$value" -v anchor="$anchor" '
      { print }
      !done && $0 ~ anchor { print "- **" label ":** " value; done=1 }
      END { if (!done) exit 3 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" && return 0
    rm -f "$f.tmp"; return 3
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
  awk -v value="$value" '
    !done && /^- Max parallelism:/ { print "- Max parallelism: " value " concurrent executors."; done=1; next }
    { print } END { if (!done) exit 3 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" && return 0
  rm -f "$f.tmp"; return 3
}

_require_int() { # <key> <value> <min> <max>
  case "$2" in ''|*[!0-9]*) die "$1: expected an integer ($3..$4), got '$2'" ;; esac
  [ "$2" -ge "$3" ] && [ "$2" -le "$4" ] || die "$1: expected $3..$4, got $2"
}

cmd_project_show() {
  local slug="$1" json="${2:-}"
  local d; d="$(proj_dir "$slug")"
  local readme="$d/README.md" plan="$d/task/PLAN.md" meta="$d/rfc/META.md"
  [ -f "$readme" ] || die "no README.md in project $slug"
  local rows=""
  _row() { # key kind stored source effective
    rows="$rows$1	$2	$3	$4	$5
"
  }
  local line v kv k p r f t legacy_off=0
  line="$(grep -m1 '^- \*\*Status:\*\*' "$readme" | sed 's/^- \*\*Status:\*\*[[:space:]]*//' || true)"
  _row status state "${line:-—}" "README.md:Status" "—"
  line="$(grep -m1 '^- \*\*AI Models:\*\*' "$readme" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//' || true)"
  for r in $AI_MODEL_ROLES; do
    v="—"
    for kv in $line; do k="${kv%%=*}"; [ "$k" = "$r" ] && v="${kv#*=}"; done
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
  v="—"; [ -f "$plan" ] && v="$(_plan_value "$plan" Routing)"; [ -n "$v" ] || v="—"
  _row routing config "$v" "task/PLAN.md:Routing" "$PW_ROUTE_DEFAULT"
  v="—"; [ -f "$plan" ] && v="$(_plan_value "$plan" "AI execution limit")"; [ -n "$v" ] || v="—"
  _row execution-limit config "$v" "task/PLAN.md:AI execution limit" "$PW_MAX_SELF_REPAIR"
  v="—"; [ -f "$plan" ] && v="$(_plan_get_maxparallel "$plan")"; [ -n "$v" ] || v="—"
  _row max-parallel config "$v" "task/PLAN.md:Max parallelism" "—"
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
  if [ "$json" = "--json" ]; then
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
    printf ']}\n'
    return 0
  fi
  printf 'pw-config project show — %s   (config = get/set knob · state/data = derived fact, show-only)\n' "$slug"
  printf '  %-24s %-6s %-28s %-26s %s\n' KEY KIND STORED SOURCE EFFECTIVE
  while IFS='	' read -r k p v s e; do
    [ -n "$k" ] || continue
    printf '  %-24s %-6s %-28s %-26s %s\n' "$k" "$p" "$v" "$s" "$e"
  done <<< "$rows"
  printf '  settable keys: routing[auto|subagent|headless] execution-limit[int 0..99] max-parallel[int 1..99] produced-by[from PW_PROVIDERS] ai-review[surface=advisory|auto|all=…] ai-model[role=provider:model|—] pin[T0n=provider:model|—] rfc-target[ref] review-trigger[surface=manual|completion|all=…] review-repair[surface=manual|bounded|all=…] review-rounds[int 1..3]\n'
  printf '  show-only (flows derive them; set refuses): status · adopted · base-branches · landing-units\n'
  if [ "$legacy_off" = 1 ]; then
    printf '  note: legacy AI Review off row(s) read as effective advisory — persist with: /pw-config %s project ensure\n' "$slug"
  fi
  return 0
}

cmd_project_get() {
  local slug="$1" key="$2" d v
  d="$(proj_dir "$slug")"
  case "$key" in
    ai-review)   cmd_ai_review "$slug" ;;
    ai-model)    cmd_ai_model "$slug" ;;
    review-trigger) cmd_review_trigger "$slug" ;;
    review-repair)  cmd_review_repair "$slug" ;;
    review-rounds)  cmd_review_rounds "$slug" ;;
    pin)         local _t _v _f _any=0
                 for _f in "$d"/task/T*.md; do
                   [ -e "$_f" ] || continue
                   _t="$(basename "$_f" .md)"; _v="$(pw_field "$_f" "Execute with")"
                   printf '%s=%s\n' "$_t" "${_v:-—}"; _any=1
                 done
                 [ "$_any" = 1 ] || die "project get pin: no task files in $slug — nothing pinned yet (/pw-breakdown creates tasks)" ;;
    pin.T*)      local _t="${key#pin.}"
                 local _f="$d/task/$_t.md"
                 [ -f "$_f" ] || die "project get: no task file task/$_t.md"
                 v="$(pw_field "$_f" "Execute with")"; printf '%s\n' "${v:-(unset — spawn uses the route ladder)}" ;;
    routing)     v="$(_plan_value "$d/task/PLAN.md" Routing)";   printf '%s\n' "${v:-(unset — effective: $PW_ROUTE_DEFAULT)}" ;;
    execution-limit) v="$(_plan_value "$d/task/PLAN.md" "AI execution limit")"; printf '%s\n' "${v:-(unset — effective: $PW_MAX_SELF_REPAIR)}" ;;
    max-parallel) v="$(_plan_get_maxparallel "$d/task/PLAN.md")"; printf '%s\n' "${v:-(unset)}" ;;
    produced-by) v="$(_plan_value "$d/task/PLAN.md" "Produced by")"; printf '%s\n' "${v:-(unset — providers: ${PW_PROVIDERS[*]})}" ;;
    rfc-target)  v="$(pw_field "$d/rfc/META.md" Target 2>/dev/null || true)"; printf '%s\n' "${v:-(unset — backend: ${PW_RFC_BACKEND:-markdown})}" ;;
    status|adopted|base-branches|landing-units)
      die "project get: '$key' is project state/data, not configuration — written by its owning flow (/pw-status phase moves, /pw-adopt, /pw-breakdown; read it in 'project show')" ;;
    *) die "project get: unknown key '$key' (config keys: $CONFIG_KEYS; show-only state/data: $STATE_KEYS — see --help)" ;;
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
  awk -v v="$val" '!w && /^- \*\*Execute with:\*\*/ { print "- **Execute with:** " v; w=1; next } { print }' \
    "$tf" > "$tf.tmp" && mv "$tf.tmp" "$tf"
  _plan_cell_update "$plan" "$tid" executewith "$val" \
    || die "pin: PLAN 'Execute with' cell write failed for $tid (see above) — the PLAN task-table row must exist; repair the PLAN doc, then re-run"
}

cmd_project_set() {
  local slug="$1" key="$2"; shift 2
  local d; d="$(proj_dir "$slug")"
  local plan="$d/task/PLAN.md"
  case "$key" in
    ai-review|ai-model|rfc-target|review-trigger|review-repair|review-rounds) ;;
    *) [ $# -ge 1 ] || die "project set: '$key' needs a value (keys: $CONFIG_KEYS — see --help)" ;;
  esac
  case "$key" in
    ai-review) [ $# -ge 1 ] || die "usage: project set <slug> ai-review <surface>=<mode> […] | all=<mode> | <surface> <mode>   (surfaces: $AI_REVIEW_PHASES; modes: advisory|auto)"
               cmd_ai_review "$slug" "$@" ;;
    ai-model)  [ $# -ge 1 ] || die "usage: project set <slug> ai-model <role>=<value> […] | <role> <value>   (roles: $AI_MODEL_ROLES)"
               cmd_ai_model "$slug" "$@" ;;
    review-trigger) [ $# -ge 1 ] || die "usage: project set <slug> review-trigger <surface>=<value> […] | all=<value> | <surface> <value>   (values: manual|completion)"
               cmd_review_trigger "$slug" "$@" ;;
    review-repair)  [ $# -ge 1 ] || die "usage: project set <slug> review-repair <surface>=<value> […] | all=<value> | <surface> <value>   (values: manual|bounded)"
               cmd_review_repair "$slug" "$@" ;;
    review-rounds)  [ $# -ge 1 ] || die "usage: project set <slug> review-rounds <1..3>"
               cmd_review_rounds "$slug" "$@" ;;
    pin)       [ $# -ge 1 ] || die "usage: project set <slug> pin <T0n>=<provider:model|—> […] | <T0n> <value>   (batch: several pairs, all-or-nothing; writes task file + PLAN cell)"
               if [ "${1#*=}" = "$1" ]; then
                 [ $# -eq 2 ] || die "usage: project set <slug> pin <T0n>=<provider:model|—> […]   (or single: pin <T0n> <value>)"
                 set -- "$1=$2"
               fi
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
               local _pair _tid _val
               # validate-all-first (plan 04 batch discipline): nothing is written unless EVERY pair binds
               for _pair in "$@"; do
                 case "$_pair" in *=*) ;; *) die "pin: expected <T0n>=<provider:model|—>, got '$_pair' (single form: pin <T0n> <value>)" ;; esac
                 _tid="${_pair%%=*}"; _val="${_pair#*=}"
                 case "$_tid" in T[0-9]*) ;; *) die "pin: '$_tid' is not a task id (expected T01, T02, …)" ;; esac
                 [ -f "$d/task/$_tid.md" ] || die "pin: no task file task/$_tid.md — /pw-breakdown owns task creation"
                 grep -q '^- \*\*Execute with:\*\*' "$d/task/$_tid.md" \
                   || die "pin: task/$_tid.md has no '- **Execute with:**' field — fix the task doc first (template line missing; pw-doctor --project C11 flags it)"
                 pw_plan_pairs "$plan" | awk -F'|' -v t="$_tid" '$1 == t { f=1 } END { exit !f }' \
                   || die "pin: no PLAN task-table row for $_tid — repair the PLAN doc first (rows are /pw-breakdown's)"
                 _model_pin_validate "pin '$_tid=$_val'" "$_val"
               done
               for _pair in "$@"; do
                 _pin_propagate "$d" "$plan" "${_pair%%=*}" "${_pair#*=}"
               done
               if [ $# -eq 1 ]; then
                 "$ST" log "$slug" config "pin ${1%%=*} -> ${1#*=} (task file + PLAN cell)"
                 echo "$slug: pin ${1%%=*} -> ${1#*=}"
               else
                 "$ST" log "$slug" config "pin set: $* (task files + PLAN cells)"
                 echo "$slug: pins set: $*"
               fi ;;
    rfc-target) [ $# -eq 1 ] || die "usage: project set <slug> rfc-target <ref>"
               "$HERE/pw-rfc.sh" target "$slug" "$1" ;;
    routing)   [ $# -eq 1 ] || die "usage: project set <slug> routing <auto|subagent|headless>   (headless = strict model binding)"
               case "$1" in auto|subagent|headless) ;; *) die "routing: expected auto|subagent|headless, got '$1' (headless = strict binding; see --help)" ;; esac
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
               _plan_set_bullet "$plan" "Routing" "$1" '^## Breakdown rules' \
                 || die "project set routing: no '- **Routing:**' bullet and no '## Breakdown rules' section to insert one into — fix the PLAN structure (pw-doc.sh lint plan $slug)" ;;
    execution-limit) [ $# -eq 1 ] || die "usage: project set <slug> execution-limit <n>   (self-repair rounds; floor $PW_MAX_SELF_REPAIR)"
               _require_int execution-limit "$1" 0 99
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
               _plan_set_bullet "$plan" "AI execution limit" "$1" '^## Execution strategy' \
                 || die "project set execution-limit: no anchor bullet/section in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint plan $slug)" ;;
    max-parallel) [ $# -eq 1 ] || die "usage: project set <slug> max-parallel <n>"
               _require_int max-parallel "$1" 1 99
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
               _plan_set_maxparallel "$plan" "$1" \
                 || die "project set max-parallel: no '- Max parallelism:' line in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint plan $slug)" ;;
    produced-by) [ $# -eq 1 ] || die "usage: project set <slug> produced-by <provider>   (enabled: ${PW_PROVIDERS[*]})"
               local _p found=0
               for _p in "${PW_PROVIDERS[@]}"; do [ "$_p" = "$1" ] && found=1; done
               [ "$found" = 1 ] || die "produced-by: '$1' is not an enabled Agent Provider (pw.config.sh PW_PROVIDERS: ${PW_PROVIDERS[*]})"
               [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
               _plan_set_bullet "$plan" "Produced by" "$1" '^- \*\*Status:\*\*' \
                 || die "project set produced-by: no '- **Produced by:**' bullet and no 'Status:' anchor in task/PLAN.md — fix the PLAN structure (pw-doc.sh lint plan $slug)" ;;
    status|adopted|base-branches|landing-units)
      die "project set: '$key' is project state/data, not configuration — the owning flow writes it (/pw-status, /pw-adopt, /pw-breakdown)" ;;
    *) die "project set: unknown key '$key' (config keys: $CONFIG_KEYS — see --help)" ;;
  esac
  # dual-holder propagation (e.g. an executor pin's PLAN cell) is the half-sync fix's job —
  # the writer logs exactly what it changed, never claims more.
  case "$key" in
    ai-review|ai-model|pin|rfc-target|review-trigger|review-repair|review-rounds) : ;;   # those writers log their own change line
    *) "$ST" log "$slug" config "$key -> $1" ;;
  esac
}

cmd_project() {
  [ $# -ge 2 ] || die "usage: project <show|get|set|ensure> <slug> [<key> [<value>…]]   (keys: $CONFIG_KEYS — see --help)"
  local op="$1" slug="$2"; shift 2
  case "$op" in
    show) [ $# -le 1 ] || die "usage: project show <slug> [--json]"
          cmd_project_show "$slug" "${1:-}" ;;
    get)  [ $# -eq 1 ] || die "usage: project get <slug> <key>   (keys: $CONFIG_KEYS; show-only: $STATE_KEYS)"
          cmd_project_get "$slug" "$1" ;;
    set)  [ $# -ge 2 ] || die "usage: project set <slug> <key> <value…>   (keys: $CONFIG_KEYS)"
          cmd_project_set "$slug" "$@" ;;
    ensure) [ $# -eq 0 ] || die "usage: project ensure <slug>"
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
          fi ;;
    *) die "project: unknown op '$op' (expected: show|get|set|ensure)" ;;
  esac
}

cmd_global() {
  [ "${1:-}" = "show" ] || die "usage: global show   (read-only — pw.config.sh is the human-owned floor file; there is no 'global set')"
  local p upper av al es
  echo "pw-config global show — effective machine floors (source: pw.config.sh via pw-common.sh)"
  echo "  providers        : ${PW_PROVIDERS[*]}"
  for p in "${PW_PROVIDERS[@]}"; do
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
  echo "  max-self-repair  : $PW_MAX_SELF_REPAIR"
  echo "  rfc-backend      : ${PW_RFC_BACKEND:-markdown}"
  echo "  review-frame     : $(pw_review_template_path) ($(pw_review_template_source); placeholders validated on use)"
  echo "  review-summary-prompt: $(pw_review_prompt_path summary) ($(pw_review_prompt_source summary); read when --summary/--mr-summary is enabled)"
  echo "  review-note-prompt   : $(pw_review_prompt_path note) ($(pw_review_prompt_source note); read when --note is enabled)"
  echo "  forge-hosts      : ${#PW_FORGE_HOSTS[@]} override(s) (else auto-detect)"
  echo "  memory           : ${PW_MEMORY:-none}"
  echo "  projects-dir     : $PW_PROJECTS"
}

case "${1:-}" in
  ai-model)      shift; _dep_note ai-model "project ai-model"; cmd_ai_model "$@" ;;
  ai-review)     shift; _dep_note ai-review "project ai-review"; cmd_ai_review "$@" ;;
  project)       shift; cmd_project "$@" ;;
  global)        shift; cmd_global "$@" ;;
  model-check)   shift; cmd_model_check "$@" ;;
  model-resolve) shift; cmd_model_resolve "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-config.sh <project|global|model-check|model-resolve|ai-model*|ai-review*> … (see --help)" ;;
esac
