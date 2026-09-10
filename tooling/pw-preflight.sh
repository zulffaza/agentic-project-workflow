#!/usr/bin/env bash
# ============================================================================
# pw-preflight.sh — gate validation before expensive agent invocations
#
#   pw-preflight.sh execute <slug>         check PLAN review gate, phase, scope
#   pw-preflight.sh breakdown <slug>       check analysis review gates, RFC
#   pw-preflight.sh ship <slug>            check shippable tasks, verify
#   pw-preflight.sh close <slug>           check all tasks accepted
#   pw-preflight.sh review <slug> [phase]  check review files exist
#
# Exit 0 + silent on success; exit 1 + human-readable error on failure.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-preflight: $*" >&2; exit 1; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -ge 2 ] || die "usage: pw-preflight.sh <command> <slug> [args...]"

COMMAND="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"
PHASE="$("$HERE/pw-lib.sh" phase "$SLUG")"

case "$COMMAND" in
  execute)
    # Check phase is valid for execute
    case "$PHASE" in
      breakdown|executing|review) ;;
      *) die "cannot execute in phase '$PHASE' (must be breakdown, executing, or review)" ;;
    esac
    
    # Check PLAN review gate
    if [ -f "$D/task/review/PLAN.review.md" ]; then
      if ! "$HERE/pw-lib.sh" review gate "$SLUG" task/review/PLAN.review.md >/dev/null 2>&1; then
        die "PLAN review gate not approved (run /pw-review to approve)"
      fi
    else
      die "PLAN review file missing (run /pw-breakdown first)"
    fi
    
    # Check PLAN exists
    if [ ! -f "$D/task/PLAN.md" ]; then
      die "PLAN.md missing (run /pw-breakdown first)"
    fi
    
    # Check provider awareness: validate Execute with: fields
    if [ -f "$D/task/PLAN.md" ]; then
      while IFS= read -r line; do
        if echo "$line" | grep -qE '^\|.*Execute with:.*\|'; then
          EXEC_WITH="$(echo "$line" | sed -n 's/.*Execute with: \([^|]*\).*/\1/p' | xargs)"
          if [ -n "$EXEC_WITH" ] && [ "$EXEC_WITH" != "—" ]; then
            PROVIDER="${EXEC_WITH%%:*}"
            MODEL="${EXEC_WITH#*:}"
            if ! "$HERE/pw-lib.sh" model-check "$PROVIDER" "$MODEL" >/dev/null 2>&1; then
              die "model check failed for '$EXEC_WITH' (not in allowlist)"
            fi
          fi
        fi
      done < <(grep -E '^\|.*T[0-9]+' "$D/task/PLAN.md" || true)
    fi
    ;;
    
  breakdown)
    # Check phase is valid for breakdown
    case "$PHASE" in
      analysis|breakdown) ;;
      *) die "cannot breakdown in phase '$PHASE' (must be analysis or breakdown)" ;;
    esac
    
    # Check analysis review gates
    if [ -d "$D/analysis/review" ]; then
      for review_file in "$D/analysis/review"/*.review.md; do
        [ -f "$review_file" ] || continue
        if ! "$HERE/pw-lib.sh" review gate "$SLUG" "analysis/review/$(basename "$review_file")" >/dev/null 2>&1; then
          die "analysis review gate not approved for $(basename "$review_file") (run /pw-review to approve)"
        fi
      done
    fi
    
    # Check RFC open items (if RFC exists)
    if [ -f "$D/rfc/META.md" ]; then
      if "$HERE/pw-lib.sh" review has-open "$SLUG" "analysis/review/RFC.review.md" 2>/dev/null; then
        die "RFC has open items (resolve via /pw-review before breakdown)"
      fi
    fi
    ;;
    
  ship)
    # Check phase is valid for ship
    case "$PHASE" in
      executing|review) ;;
      *) die "cannot ship in phase '$PHASE' (must be executing or review)" ;;
    esac
    
    # Check for shippable tasks (done but not accepted)
    if [ -f "$D/task/PLAN.md" ]; then
      SHIPPABLE="$(grep -E '\|.*done.*\|' "$D/task/PLAN.md" | grep -v 'accepted' || true)"
      if [ -z "$SHIPPABLE" ]; then
        die "no shippable tasks (all tasks must be 'done' before shipping)"
      fi
    else
      die "PLAN.md missing"
    fi
    
    # Check verify passed for done tasks
    if [ -f "$D/task/PLAN.md" ]; then
      while IFS= read -r line; do
        if echo "$line" | grep -qE '\|.*done.*\|'; then
          TASK_ID="$(echo "$line" | sed -n 's/.*| *\([^ ]*\) *|.*/\1/p')"
          TASK_FILE="$D/task/$TASK_ID.md"
          if [ -f "$TASK_FILE" ]; then
            if grep -q 'verify-failed' "$TASK_FILE"; then
              die "task $TASK_ID is verify-failed (fix before shipping)"
            fi
          fi
        fi
      done < <(grep -E '^\|.*T[0-9]+' "$D/task/PLAN.md" || true)
    fi
    ;;
    
  close)
    # Check phase is valid for close
    if [ "$PHASE" != "done" ] && [ "$PHASE" != "review" ]; then
      die "cannot close in phase '$PHASE' (must be done or review)"
    fi
    
    # Check all tasks are accepted
    if [ -f "$D/task/PLAN.md" ]; then
      UNACCEPTED="$(grep -E '^\|.*T[0-9]' "$D/task/PLAN.md" | grep -v 'accepted' || true)"
      if [ -n "$UNACCEPTED" ]; then
        die "not all tasks are accepted (run /pw-ship first)"
      fi
    fi
    ;;
    
  review)
    PHASE_FILTER="${1:-}"
    
    # Check review files exist
    if [ -n "$PHASE_FILTER" ]; then
      case "$PHASE_FILTER" in
        analysis)
          if [ ! -d "$D/analysis/review" ] || [ -z "$(ls -A "$D/analysis/review"/*.review.md 2>/dev/null)" ]; then
            die "no analysis review files found"
          fi
          ;;
        plan|task-plan)
          if [ ! -f "$D/task/review/PLAN.review.md" ]; then
            die "PLAN review file missing"
          fi
          ;;
        task-exec)
          if [ ! -d "$D/task/review" ] || [ -z "$(ls -A "$D/task/review"/T*.review.md 2>/dev/null)" ]; then
            die "no task review files found"
          fi
          ;;
      esac
    else
      # Check any review files exist
      if [ ! -d "$D/analysis/review" ] && [ ! -d "$D/task/review" ]; then
        die "no review directories found"
      fi
    fi
    ;;
    
  *)
    die "unknown command: $COMMAND (expected: execute|breakdown|ship|close|review)"
    ;;
esac

exit 0
