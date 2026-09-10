#!/usr/bin/env bash
# ============================================================================
# pw-ship-exec.sh — script the mechanical parts of ship
#
#   pw-ship-exec.sh <slug> <task-id> <description-file>
#
# Handles the mechanical execution after the agent has confirmed the push
# list and generated MR descriptions:
# - git push origin <branch>
# - glab mr create / gh pr create with structured args
# - Dashboard updates
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-ship-exec: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -eq 3 ] || die "usage: pw-ship-exec.sh <slug> <task-id> <description-file>"

SLUG="$1"
TASK_ID="$2"
DESC_FILE="$3"

D="$(proj_dir "$SLUG")"
TASK_FILE="$D/task/$TASK_ID.md"
PLAN="$D/task/PLAN.md"

[ -f "$TASK_FILE" ] || die "task file not found: $TASK_FILE"
[ -f "$DESC_FILE" ] || die "description file not found: $DESC_FILE"
[ -f "$PLAN" ] || die "PLAN.md not found"

# Extract task info
REPO="$(grep '^Repo:' "$TASK_FILE" | sed 's/^Repo: *//' | xargs)"
BRANCH="$(grep '^Branch:' "$TASK_FILE" | sed 's/^Branch: *//' | xargs)"
BASE="$(grep '^Base branch:' "$TASK_FILE" | sed 's/^Base branch: *//' | xargs)"
TICKET="$(grep '^Ticket:' "$TASK_FILE" | sed 's/^Ticket: *//' | xargs || echo "")"
TITLE="$(grep '^# ' "$TASK_FILE" | head -1 | sed 's/^# //' | xargs)"

[ -n "$REPO" ] || die "Repo not set in task file"
[ -n "$BRANCH" ] || die "Branch not set in task file"
[ -n "$BASE" ] || BASE="master"

REPO_DIR="$REPOS_DIR/$REPO"
[ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR"

# Push branch
echo "Pushing $BRANCH to origin..."
git -C "$REPO_DIR" push origin "$BRANCH" || die "push failed"

# Check for existing MR
MR_URL=""
if grep -q '^## Result' "$TASK_FILE"; then
  MR_URL="$(awk '/^## Result/{p=1; next} /^## /{p=0} p && /MR:/{print; exit}' "$TASK_FILE" | sed 's/.*MR: *//' | xargs || echo "")"
fi

# Determine forge CLI
FORGE_CLI=""
if command -v glab >/dev/null 2>&1; then
  FORGE_CLI="glab"
elif command -v gh >/dev/null 2>&1; then
  FORGE_CLI="gh"
else
  die "no forge CLI found (need glab or gh)"
fi

# Create or update MR
if [ -n "$MR_URL" ] && [ "$MR_URL" != "(none)" ]; then
  echo "MR already exists: $MR_URL"
else
  echo "Creating MR..."
  
  # Build MR title with ticket prefix if available
  MR_TITLE="$TITLE"
  if [ -n "$TICKET" ]; then
    MR_TITLE="[$TICKET] $TITLE"
  fi
  
  # Read description
  DESCRIPTION="$(cat "$DESC_FILE")"
  
  # Create MR
  if [ "$FORGE_CLI" = "glab" ]; then
    MR_OUTPUT="$(glab mr create \
      --source-branch "$BRANCH" \
      --target-branch "$BASE" \
      --title "$MR_TITLE" \
      --description "$DESCRIPTION" \
      --no-editor \
      --output json 2>&1 || echo "")"
    MR_URL="$(echo "$MR_OUTPUT" | grep -o '"web_url":"[^"]*"' | sed 's/"web_url":"//;s/"//' || echo "")"
  elif [ "$FORGE_CLI" = "gh" ]; then
    MR_OUTPUT="$(gh pr create \
      --head "$BRANCH" \
      --base "$BASE" \
      --title "$MR_TITLE" \
      --body "$DESCRIPTION" 2>&1 || echo "")"
    MR_URL="$(echo "$MR_OUTPUT" | grep -o 'https://github.com/[^ ]*' || echo "")"
  fi
  
  if [ -n "$MR_URL" ]; then
    echo "MR created: $MR_URL"
    
    # Update task file with MR URL
    if grep -q '^## Result' "$TASK_FILE"; then
      # Append MR line to Result section
      awk -v mr="$MR_URL" '/^## Result/{p=1; print; print "- MR: " mr; next} p && /^## /{p=0} {print}' \
        "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
    else
      # Add Result section
      printf '\n## Result\n\n- MR: %s\n' "$MR_URL" >> "$TASK_FILE"
    fi
  else
    echo "Warning: MR creation output unclear, check manually"
  fi
fi

# Update dashboard
"$HERE/pw-lib.sh" dashboard-mr-state "$SLUG" "$TASK_ID" "open" 2>/dev/null || true

echo "Ship execution complete for $TASK_ID"
