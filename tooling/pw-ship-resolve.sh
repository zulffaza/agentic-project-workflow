#!/usr/bin/env bash
# ============================================================================
# pw-ship-resolve.sh — pre-compute shippable task set
#
#   pw-ship-resolve.sh <slug>
#
# Before /pw-ship invokes an agent, this script resolves the exact set of
# shippable tasks. Reads task statuses, checks for real commits, checks for
# existing MRs, resolves ticket numbers from context/INDEX.md.
#
# Output format (one line per shippable task):
#   T01|repo|branch|base|ticket|title|has-commit|has-mr
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-ship-resolve: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -eq 1 ] || die "usage: pw-ship-resolve.sh <slug>"

SLUG="$1"
D="$(proj_dir "$SLUG")"
PLAN="$D/task/PLAN.md"
INDEX="$D/context/INDEX.md"

[ -f "$PLAN" ] || die "PLAN.md not found"

# Build ticket map from context/INDEX.md
declare -A TICKET_MAP
if [ -f "$INDEX" ]; then
  while IFS='|' read -r _ file _ _; do
    file="$(echo "$file" | xargs)"
    if [[ "$file" =~ ^\`?([A-Z]+-[0-9]+)\`?$ ]]; then
      ticket="${BASH_REMATCH[1]}"
      TICKET_MAP["$ticket"]="$ticket"
    fi
  done < <(awk '/^\|/{print}' "$INDEX" | grep -v '^|[-: ]' || true)
fi

# Process each task in PLAN
while IFS='|' read -r _ task_id repo branch _ _ depends status _; do
  task_id="$(echo "$task_id" | xargs)"
  repo="$(echo "$repo" | xargs)"
  branch="$(echo "$branch" | xargs)"
  status="$(echo "$status" | xargs)"
  
  # Skip non-shippable tasks
  [[ "$task_id" =~ ^T[0-9]+ ]] || continue
  [ "$status" = "done" ] || continue
  
  # Check for real commits
  HAS_COMMIT="no"
  REPO_DIR="$REPOS_DIR/$repo"
  if [ -d "$REPO_DIR" ]; then
    # Get base branch from task file
    TASK_FILE="$D/task/$task_id.md"
    BASE=""
    if [ -f "$TASK_FILE" ]; then
      BASE="$(grep '^Base branch:' "$TASK_FILE" | sed 's/^Base branch: *//' | xargs)"
    fi
    [ -n "$BASE" ] || BASE="master"
    
    # Check for commits
    if git -C "$REPO_DIR" rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..origin/$branch" 2>/dev/null | wc -l | xargs)"
      if [ "$COMMIT_COUNT" -gt 0 ]; then
        HAS_COMMIT="yes"
      fi
    fi
  fi
  
  # Check for existing MR
  HAS_MR="no"
  TASK_FILE="$D/task/$task_id.md"
  if [ -f "$TASK_FILE" ]; then
    if grep -q '^## Result' "$TASK_FILE"; then
      MR_URL="$(awk '/^## Result/{p=1; next} /^## /{p=0} p && /MR:/{print; exit}' "$TASK_FILE" | sed 's/.*MR: *//' | xargs)"
      if [ -n "$MR_URL" ] && [ "$MR_URL" != "(none)" ]; then
        HAS_MR="yes"
      fi
    fi
  fi
  
  # Resolve ticket
  TICKET=""
  if [ -f "$TASK_FILE" ]; then
    TICKET="$(grep '^Ticket:' "$TASK_FILE" | sed 's/^Ticket: *//' | xargs || echo "")"
  fi
  
  # Extract title from task file
  TITLE=""
  if [ -f "$TASK_FILE" ]; then
    TITLE="$(grep '^# ' "$TASK_FILE" | head -1 | sed 's/^# //' | xargs)"
  fi
  [ -n "$TITLE" ] || TITLE="$task_id"
  
  # Output line
  echo "$task_id|$repo|$branch|$BASE|$TICKET|$TITLE|$HAS_COMMIT|$HAS_MR"
  
done < <(awk '/^## Tasks/{p=1; next} p && /^\|/{print}' "$PLAN" | grep -v '^|[-: ]' || true)
