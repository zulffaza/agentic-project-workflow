#!/usr/bin/env bash
# ============================================================================
# pw-mr-state-batch.sh — batch MR state resolution
#
#   pw-mr-state-batch.sh <slug> [task-ids...]
#
# Batches MR state checks for multiple tasks. For tasks with merged state,
# can also trigger cleanup sequence directly.
#
# Output: T01|open  T02|merged  T03|closed  T04|unknown
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-mr-state-batch: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -ge 1 ] || die "usage: pw-mr-state-batch.sh <slug> [task-ids...]"

SLUG="$1"
shift
TASK_IDS=("$@")

D="$(proj_dir "$SLUG")"
PLAN="$D/task/PLAN.md"

[ -f "$PLAN" ] || die "PLAN.md not found"

# If no task IDs specified, use all tasks from PLAN
if [ ${#TASK_IDS[@]} -eq 0 ]; then
  while IFS='|' read -r _ task_id _; do
    task_id="$(echo "$task_id" | xargs)"
    [[ "$task_id" =~ ^T[0-9]+ ]] && TASK_IDS+=("$task_id")
  done < <(awk '/^## Task( |s)/{p=1; next} p && /^\|/{print}' "$PLAN" | grep -vE '^\|[-: |(]*\|?$' || true)
fi

# Check MR state for each task
for task_id in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
  # pw-lib mr-state may itself print "unknown" AND exit non-zero — capture once, default after.
  STATE="$("$HERE/pw-lib.sh" mr-state "$SLUG" "$task_id" 2>/dev/null || true)"
  [ -n "$STATE" ] || STATE="unknown"
  echo "$task_id|$STATE"
done
