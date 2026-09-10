#!/usr/bin/env bash
# ============================================================================
# pw-review-scan.sh — scan and summarize review state (read-only)
#
#   pw-review-scan.sh <slug> [--phase <phase>]
#
# Scans all review files and produces a structured summary of open/resolved
# items and sign-off status. Used by pw-status.sh, /pw-review pre-flight,
# and /pw-close pre-flight.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-review-scan: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

SLUG=""
PHASE_FILTER=""

for arg in "$@"; do
  case "$arg" in
    --phase) shift; PHASE_FILTER="${1:-}"; shift || die "--phase requires an argument" ;;
    --phase=*) PHASE_FILTER="${arg#--phase=}" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) die "unknown option: $arg (try --help)" ;;
    *) SLUG="$arg" ;;
  esac
done

[ -n "$SLUG" ] || die "usage: pw-review-scan.sh <slug> [--phase <phase>]"

D="$(proj_dir "$SLUG")"

# Find all review files
REVIEW_FILES=()
if [ -d "$D/analysis/review" ]; then
  while IFS= read -r -d '' f; do
    REVIEW_FILES+=("$f")
  done < <(find "$D/analysis/review" -name '*.review.md' -print0 2>/dev/null)
fi
if [ -d "$D/task/review" ]; then
  while IFS= read -r -d '' f; do
    REVIEW_FILES+=("$f")
  done < <(find "$D/task/review" -name '*.review.md' -print0 2>/dev/null)
fi

if [ ${#REVIEW_FILES[@]} -eq 0 ]; then
  echo "No review files found"
  exit 0
fi

for f in "${REVIEW_FILES[@]}"; do
  REL="${f#$D/}"
  
  # Count open items
  OPEN="$(grep -c "pw-item-status: open" "$f" 2>/dev/null || echo 0)"
  
  # Count resolved items
  RESOLVED="$(grep -c "pw-item-status: resolved" "$f" 2>/dev/null || echo 0)"
  
  # Count pending questions
  PENDING="$(grep -c "pw-question-status: pending" "$f" 2>/dev/null || echo 0)"
  
  # Check sign-off status
  SIGNOFF=""
  if grep -q '## Sign-off' "$f"; then
    # Get the last sign-off row
    LAST_SIGNOFF="$(awk '/## Sign-off/{p=1; next} p && /^\|/{last=$0} END{print last}' "$f")"
    if echo "$LAST_SIGNOFF" | grep -q 'approved'; then
      SIGNOFF="approved"
    elif echo "$LAST_SIGNOFF" | grep -q 'in-review'; then
      SIGNOFF="in-review"
    elif echo "$LAST_SIGNOFF" | grep -q 'changes-requested'; then
      SIGNOFF="changes-requested"
    fi
  fi
  
  # Build summary line
  SUMMARY="$REL:"
  if [ "$OPEN" -gt 0 ]; then
    SUMMARY="$SUMMARY $OPEN open"
  fi
  if [ "$RESOLVED" -gt 0 ]; then
    SUMMARY="$SUMMARY, $RESOLVED resolved"
  fi
  if [ "$PENDING" -gt 0 ]; then
    SUMMARY="$SUMMARY, $PENDING pending question(s)"
  fi
  if [ -n "$SIGNOFF" ]; then
    SUMMARY="$SUMMARY ($SIGNOFF)"
  fi
  
  # Apply phase filter if specified
  if [ -n "$PHASE_FILTER" ]; then
    case "$REL" in
      analysis/review/*)
        [ "$PHASE_FILTER" = "analysis" ] && echo "$SUMMARY"
        ;;
      task/review/PLAN.review.md)
        [ "$PHASE_FILTER" = "plan" ] || [ "$PHASE_FILTER" = "task-plan" ] && echo "$SUMMARY"
        ;;
      task/review/T*.review.md)
        [ "$PHASE_FILTER" = "task-exec" ] && echo "$SUMMARY"
        ;;
    esac
  else
    echo "$SUMMARY"
  fi
done
