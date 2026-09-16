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

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-review-scan: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }

SLUG=""
PHASE_FILTER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --phase) [ $# -ge 2 ] || die "--phase requires an argument"; PHASE_FILTER="$2"; shift 2 ;;
    --phase=*) PHASE_FILTER="${1#--phase=}"; shift ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) SLUG="$1"; shift ;;
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
  
  # Counts come from pw-lib's "review count" — THE same heading-level detector the approval
  # gates use. A whole-file `grep -c "pw-item-status: open"` previously counted the template's
  # permanent "> Add an item: … <!-- pw-item-status: open -->" guidance line in EVERY review
  # file, so each one phantom-reported "(1 open)" forever, no matter what was approved.
  COUNTS="$("$HERE/pw-lib.sh" review count "$SLUG" "$REL" 2>/dev/null || true)"
  OPEN="$(printf '%s' "$COUNTS" | sed -n 's/open=\([0-9]*\).*/\1/p')"; OPEN="${OPEN:-0}"
  RESOLVED="$(printf '%s' "$COUNTS" | sed -n 's/.*resolved=\([0-9]*\).*/\1/p')"; RESOLVED="${RESOLVED:-0}"
  
  # Check sign-off status
  SIGNOFF=""
  if grep -q '## Sign-off' "$f"; then
    # Get the last sign-off row
    # last REAL table row only — the template's example rows live in an HTML comment after
    # the table; an unguarded `/^\|/` scan lands on them and inverts gate state.
    LAST_SIGNOFF="$(awk '
      /^## Sign-off/ {p=1; next}
      p && /^[[:space:]]*<!--/ {exit}
      p && /^\|/ {last=$0; next}
      p && last != "" && /^[^|[:space:]]/ {exit}
      END {print last}' "$f")"
    if echo "$LAST_SIGNOFF" | grep -q 'approved'; then
      SIGNOFF="approved"
    elif echo "$LAST_SIGNOFF" | grep -q 'in-review'; then
      SIGNOFF="in-review"
    elif echo "$LAST_SIGNOFF" | grep -q 'changes-requested'; then
      SIGNOFF="changes-requested"
    fi
  fi
  
  # Build summary line: "<rel>[: N open[, M resolved]] (<decision>)" — parts joined without a
  # leading comma when open is zero (an approved 0-open review reads clean, not ", 1 resolved").
  PARTS=""
  _p() { [ -n "$PARTS" ] && PARTS="$PARTS, "; PARTS="$PARTS$1"; }
  [ "$OPEN" -gt 0 ] && _p "$OPEN open"
  [ "$RESOLVED" -gt 0 ] && _p "$RESOLVED resolved"
  SUMMARY="$REL:"
  [ -n "$PARTS" ] && SUMMARY="$SUMMARY $PARTS"
  # (no separate "pending questions" counter: Q-items ride the same pw-item-status markers;
  #  the old grep looked for a vocabulary the templates never emit — always dead, always 0.)
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

# a filtered run must be a clean report, not the rc of the last test in the loop (docs:
# only 0/2 exit shapes — 0 report/nothing, 2 usage/missing project).
exit 0
