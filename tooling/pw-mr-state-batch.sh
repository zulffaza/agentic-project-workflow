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

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-mr-state-batch: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }

[ $# -ge 1 ] || die "usage: pw-mr-state-batch.sh <slug> [task-ids...]"

SLUG="$1"
shift
TASK_IDS=("$@")

D="$(proj_dir "$SLUG")"
PLAN="$D/task/PLAN.md"

[ -f "$PLAN" ] || die "PLAN.md not found ($PLAN) — run /pw-breakdown <slug> to produce it"

# If no task IDs specified, use all tasks from PLAN
if [ ${#TASK_IDS[@]} -eq 0 ]; then
  while IFS='|' read -r task_id _status; do
    [ -n "$task_id" ] && TASK_IDS+=("$task_id")
  done < <(pw_plan_pairs "$PLAN")
fi

# Check MR state for each task
for task_id in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
  # pw-lib mr-state may itself print "unknown" AND exit non-zero — capture once, default after.
  STATE="$("$HERE/pw-lib.sh" mr-state "$SLUG" "$task_id" 2>/dev/null || true)"
  [ -n "$STATE" ] || STATE="unknown"
  echo "$task_id|$STATE"
done
