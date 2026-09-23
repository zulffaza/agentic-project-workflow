#!/usr/bin/env bash
# ============================================================================
# pw-config.sh — the per-project config entity: which models and which review
# modes a project runs with (dashboard config lines, get-or-set semantics).
#
#   pw-config.sh ai-model     <slug> [<role> <provider:model|—>]
#       Get or set one spawn-lane's model row (roles: researcher analyst
#       writer-task reviewer verifier). — clears to provider/session default.
#   pw-config.sh ai-review    <slug> [<phase> <mode>]
#       Get or set one phase's AI-review mode (off|advisory|auto; phases:
#       analysis plan task-plan task-exec ship). 'auto' is what lets
#       pw-review.sh auto-signoff ever succeed.
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

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
ST="$HERE/pw-status.sh"

die() { echo "pw-config: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

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
cmd_ai_model() {
  [ $# -ge 1 ] || die "usage: ai-model <slug> [<role> <provider:model|—>]   (role: $AI_MODEL_ROLES)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_models_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -eq 2 ] || die "usage: ai-model <slug> <role> <provider:model|—>   (role: $AI_MODEL_ROLES)"
  local role="$1" value="$2"
  case " $AI_MODEL_ROLES " in *" $role "*) ;; *) die "invalid role '$role' (allowed: $AI_MODEL_ROLES)" ;; esac
  case "$value" in
    —|-) ;;  # clearing to no-row is always valid
    *:*) ;;
    *) die "invalid value '$value' — write <provider>:<model> (e.g. kilo:command_code/<m>, claude:sonnet) or — for no row" ;;
  esac
  local cur; cur="$(grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//')"
  local new="" found=0 kv k
  for kv in $cur; do
    k="${kv%%=*}"
    if [ "$k" = "$role" ]; then new="$new $role=$value"; found=1
    else new="$new $kv"; fi
  done
  [ "$found" -eq 1 ] || new="$new $role=$value"
  new="${new# }"
  awk -v t="$new" '!d && /^- \*\*AI Models:\*\*/ {print "- **AI Models:** " t; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  "$ST" log "$slug" ai-model "$role -> $value"
  echo "$slug: AI Model $role -> $value"
}

# --- AI-assisted review (optional delegated review pass — see docs/REVIEW.md + the pw-review
# skill) -----------------------------------------------------------------------------------------
# One config axis per (project, phase): off (default, no change to today's behavior) | advisory
# (pw-reviewer files items, a human still signs off) | auto (pw-reviewer may ALSO sign off itself,
# but ONLY through cmd_review_auto_signoff below, and ONLY when this mode is genuinely "auto").
AI_REVIEW_PHASES="analysis plan task-plan task-exec ship"

# Idempotent: insert the dashboard line, all-off, if it doesn't exist yet (covers projects
# scaffolded before this feature existed — same "never assume, always ensure" idiom as
# _rfc_meta_ensure). Anchored after One-liner, same convention as cmd_adopted.
_ai_review_line_ensure() {
  local f="$1"
  grep -q '^- \*\*AI Review:\*\*' "$f" && return 0
  local default="" p
  for p in $AI_REVIEW_PHASES; do default="$default $p=off"; done
  default="${default# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor AI Review: after in $f"
  awk -v t="$default" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **AI Review:** " t; d=1}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Get (no extra args) or set (phase + mode) this project's per-phase AI-review mode.
#   ai-review <slug>                 -> prints "analysis=off plan=off task-plan=off task-exec=off ship=off"
#   ai-review <slug> <phase> <mode>  -> sets just that phase's mode, leaves the other four untouched
cmd_ai_review() {
  [ $# -ge 1 ] || die "usage: ai-review <slug> [<phase> <mode>]   (phase: $AI_REVIEW_PHASES; mode: off|advisory|auto)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_review_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep '^- \*\*AI Review:\*\*' "$f" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -eq 2 ] || die "usage: ai-review <slug> <phase> <mode>   (phase: $AI_REVIEW_PHASES; mode: off|advisory|auto)"
  local phase="$1" mode="$2"
  case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$mode" in off|advisory|auto) ;; *) die "invalid mode '$mode' (allowed: off advisory auto)" ;; esac
  local cur; cur="$(grep '^- \*\*AI Review:\*\*' "$f" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//')"
  local new="" found=0 kv k
  for kv in $cur; do
    k="${kv%%=*}"
    if [ "$k" = "$phase" ]; then new="$new $phase=$mode"; found=1
    else new="$new $kv"; fi
  done
  [ "$found" -eq 1 ] || new="$new $phase=$mode"
  new="${new# }"
  awk -v t="$new" '!d && /^- \*\*AI Review:\*\*/ {print "- **AI Review:** " t; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  "$ST" log "$slug" ai-review "$phase -> $mode"
  echo "$slug: AI Review $phase -> $mode"
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
    kilo|opencode|cursor) ;;
    *)
      echo "model-resolve: $prov:$model — unverified (no catalog surface for provider '$prov')"
      return 0 ;;
  esac
  catalog="$(pw_api_catalog "$prov")"
  if [ -z "$catalog" ]; then
    echo "model-resolve: $prov:$model — unverified ('$prov models' catalog empty or CLI not on PATH)" >&2
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
    echo "  → fix: re-pin the row to a real id — candidates from \`$(pw_api_bin "$prov") models\`:" >&2
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

case "${1:-}" in
  ai-model)      shift; cmd_ai_model "$@" ;;
  ai-review)     shift; cmd_ai_review "$@" ;;
  model-check)   shift; cmd_model_check "$@" ;;
  model-resolve) shift; cmd_model_resolve "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-config.sh <ai-model|ai-review|model-check|model-resolve> … (see --help)" ;;
esac
