#!/usr/bin/env bash
# ============================================================================
# pw-doc-sync.sh — reconcile all documents from on-disk state
#
#   pw-doc-sync.sh <slug> [--dashboard-only | --plan-only | --tasks-only]
#
# Reconciles document relationships:
# - Dashboard sync (README.md): task status table, MR table
# - PLAN sync (task/PLAN.md): header metadata, task table
# - Task file sync: ## Result fields reflect actual git state
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-doc-sync: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

SYNC_MODE="all"
for arg in "$@"; do
  case "$arg" in
    --dashboard-only) SYNC_MODE="dashboard" ;;
    --plan-only) SYNC_MODE="plan" ;;
    --tasks-only) SYNC_MODE="tasks" ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $arg" ;;
  esac
done

# Extract slug (first non-flag argument)
SLUG=""
for arg in "$@"; do
  [[ "$arg" =~ ^-- ]] && continue
  SLUG="$arg"
  break
done

[ -n "$SLUG" ] || die "usage: pw-doc-sync.sh <slug> [--dashboard-only | --plan-only | --tasks-only]"

D="$(proj_dir "$SLUG")"
README="$D/README.md"
PLAN="$D/task/PLAN.md"

[ -f "$README" ] || die "README.md not found"

sync_dashboard() {
  echo "Syncing dashboard (README.md)..."
  
  # Sync task status table
  if [ -f "$PLAN" ]; then
    # Extract task statuses from task files
    while IFS='|' read -r _ task_id _ _ _ _ _ status _; do
      task_id="$(echo "$task_id" | xargs)"
      status="$(echo "$status" | xargs)"
      [[ "$task_id" =~ ^T[0-9]+ ]] || continue
      
      # Get actual status from task file
      TASK_FILE="$D/task/$task_id.md"
      if [ -f "$TASK_FILE" ]; then
        ACTUAL_STATUS="$(grep '^Status:' "$TASK_FILE" | sed 's/^Status: *//' | xargs || echo "$status")"
        
        # Update dashboard if different
        if [ "$ACTUAL_STATUS" != "$status" ]; then
          # Update README task table
          awk -v tid="$task_id" -v new_status="$ACTUAL_STATUS" '
            BEGIN { in_table=0 }
            /^## Task( |s)/ { in_table=1; print; next }
            /^## / { in_table=0 }
            in_table && $0 ~ "\\|" tid "\\|" {
              gsub(/\| *(todo|in-progress|done|accepted|verify-failed) *\|/, "| " new_status " |")
            }
            { print }
          ' "$README" > "$README.tmp" && mv "$README.tmp" "$README"
        fi
      fi
    done < <(awk '/^## Task( |s)/{p=1; next} p && /^\|/{print}' "$PLAN" | grep -vE '^\|[-: |(]*\|?$' || true)
  fi
  
  # Sync MR table
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    task_id="$(basename "$task_file" .md)"
    
    # Extract MR URL from task file
    MR_URL=""
    if grep -q '^## Result' "$task_file"; then
      MR_URL="$(awk '/^## Result/{p=1; next} /^## /{p=0} p && /MR:/{print; exit}' "$task_file" | sed 's/.*MR: *//' | xargs || echo "")"
    fi
    
    # Update dashboard MR table if needed
    if [ -n "$MR_URL" ] && [ "$MR_URL" != "(none)" ]; then
      if ! grep -q "$task_id" "$README" || ! grep -A5 "$task_id" "$README" | grep -q "$MR_URL"; then
        # Add or update MR table row
        if grep -q '^## Merge requests' "$README"; then
          if ! grep -q "$task_id" "$README"; then
            # Add new row
            awk -v tid="$task_id" -v mr="$MR_URL" '
              /^## Merge requests/ { print; print "| " tid " | " mr " | open |"; next }
              { print }
            ' "$README" > "$README.tmp" && mv "$README.tmp" "$README"
          fi
        fi
      fi
    fi
  done
  
  echo "Dashboard sync complete"
}

sync_plan() {
  echo "Syncing PLAN.md..."
  
  [ -f "$PLAN" ] || { echo "PLAN.md not found, skipping"; return 0; }
  
  # Sync task count and SP totals
  TASK_COUNT="$(ls -1 "$D/task"/T*.md 2>/dev/null | wc -l | xargs)"
  TOTAL_SP=0
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    SP="$(grep '^Story points:' "$task_file" | sed 's/^Story points: *//' | xargs || echo "0")"
    [[ "$SP" =~ ^[0-9]+$ ]] && TOTAL_SP=$((TOTAL_SP + SP))
  done
  
  # Update PLAN header if needed
  if grep -q '^\*\*Task count:\*\*' "$PLAN"; then
    awk -v count="$TASK_COUNT" -v sp="$TOTAL_SP" '
      /^\*\*Task count:\*\*/ { print "- **Task count:** " count " (ΣSP=" sp ")"; next }
      { print }
    ' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  fi
  
  echo "PLAN sync complete"
}

sync_tasks() {
  echo "Syncing task files..."
  
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    task_id="$(basename "$task_file" .md)"
    
    REPO="$(grep '^Repo:' "$task_file" | sed 's/^Repo: *//' | xargs || echo "")"
    BRANCH="$(grep '^Branch:' "$task_file" | sed 's/^Branch: *//' | xargs || echo "")"
    BASE="$(grep '^Base branch:' "$task_file" | sed 's/^Base branch: *//' | xargs || echo "master")"
    
    [ -n "$REPO" ] && [ -n "$BRANCH" ] || continue
    
    REPO_DIR="$REPOS_DIR/$REPO"
    [ -d "$REPO_DIR" ] || continue
    
    # Check for commits
    COMMIT_COUNT=0
    if git -C "$REPO_DIR" rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
      COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..origin/$BRANCH" 2>/dev/null | wc -l | xargs || echo "0")"
    fi
    
    # Update Result section if needed
    if [ "$COMMIT_COUNT" -gt 0 ]; then
      if ! grep -q 'commits' "$task_file" 2>/dev/null; then
        # Append commit count to Result section
        if grep -q '^## Result' "$task_file"; then
          awk -v count="$COMMIT_COUNT" '/^## Result/{p=1; print; print "- " count " commit(s)"; next} p && /^## /{p=0} {print}' \
            "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
        fi
      fi
    fi
  done
  
  echo "Task file sync complete"
}

case "$SYNC_MODE" in
  dashboard) sync_dashboard ;;
  plan) sync_plan ;;
  tasks) sync_tasks ;;
  all)
    sync_dashboard
    sync_plan
    sync_tasks
    ;;
esac

echo "Document sync complete"
