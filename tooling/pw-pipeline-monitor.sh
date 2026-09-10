#!/usr/bin/env bash
# ============================================================================
# pw-pipeline-monitor.sh — monitor MR pipeline/checks after push
#
#   pw-pipeline-monitor.sh <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]
#
# Polls MR pipeline until terminal state. Exit 0 on success, 1 on failure,
# 2 on timeout.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-pipeline-monitor: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

TIMEOUT_MIN="${PW_PIPELINE_TIMEOUT:-15}"
INTERVAL_SEC="${PW_PIPELINE_INTERVAL:-30}"
SLUG=""
TASK_ID=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) shift; TIMEOUT_MIN="${1:-$TIMEOUT_MIN}"; shift ;;
    --timeout=*) TIMEOUT_MIN="${1#--timeout=}" ;;
    --interval) shift; INTERVAL_SEC="${1:-$INTERVAL_SEC}"; shift ;;
    --interval=*) INTERVAL_SEC="${1#--interval=}" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)
      if [ -z "$SLUG" ]; then
        SLUG="$1"
      elif [ -z "$TASK_ID" ]; then
        TASK_ID="$1"
      fi
      shift
      ;;
  esac
done

[ -n "$SLUG" ] && [ -n "$TASK_ID" ] || die "usage: pw-pipeline-monitor.sh <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]"

D="$(proj_dir "$SLUG")"
TASK_FILE="$D/task/$TASK_ID.md"

[ -f "$TASK_FILE" ] || die "task file not found: $TASK_FILE"

# Extract MR URL
MR_URL=""
if grep -q '^## Result' "$TASK_FILE"; then
  MR_URL="$(awk '/^## Result/{p=1; next} /^## /{p=0} p && /MR:/{print; exit}' "$TASK_FILE" | sed 's/.*MR: *//' | xargs || echo "")"
fi

[ -n "$MR_URL" ] && [ "$MR_URL" != "(none)" ] || die "no MR URL found in task file"

# Determine forge CLI
FORGE_CLI=""
if echo "$MR_URL" | grep -q 'gitlab'; then
  FORGE_CLI="glab"
elif echo "$MR_URL" | grep -q 'github'; then
  FORGE_CLI="gh"
else
  die "cannot determine forge from MR URL: $MR_URL"
fi

# Extract MR IID/number
MR_IID=""
if [ "$FORGE_CLI" = "glab" ]; then
  MR_IID="$(echo "$MR_URL" | grep -o 'merge_requests/[0-9]*' | sed 's/merge_requests\///')"
elif [ "$FORGE_CLI" = "gh" ]; then
  MR_IID="$(echo "$MR_URL" | grep -o 'pull/[0-9]*' | sed 's/pull\///')"
fi

[ -n "$MR_IID" ] || die "cannot extract MR IID from URL: $MR_URL"

# Poll pipeline
TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
ELAPSED=0
START_TIME="$(date +%s)"

echo "Monitoring pipeline for $TASK_ID (MR !$MR_IID)..."
echo "  Timeout: ${TIMEOUT_MIN}m, Interval: ${INTERVAL_SEC}s"
echo

while true; do
  STATUS=""
  
  if [ "$FORGE_CLI" = "glab" ]; then
    # GitLab: check pipeline status
    STATUS="$(glab api "projects/:id/merge_requests/$MR_IID/pipelines" 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || echo "unknown")"
  elif [ "$FORGE_CLI" = "gh" ]; then
    # GitHub: check PR checks status
    STATUS="$(gh pr checks "$MR_IID" 2>/dev/null | awk 'NR>1{print $2}' | sort -u | head -1 || echo "unknown")"
  fi
  
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START_TIME))
  ELAPSED_MIN=$((ELAPSED / 60))
  ELAPSED_SEC=$((ELAPSED % 60))
  
  # Check terminal states
  case "$STATUS" in
    success|SUCCESS|passing|passed)
      echo "$TASK_ID: pipeline SUCCESS (${ELAPSED_MIN}m ${ELAPSED_SEC}s)"
      
      # Update task file
      if grep -q '^## Result' "$TASK_FILE"; then
        if ! grep -q 'Build check:' "$TASK_FILE"; then
          awk '/^## Result/{p=1; print; print "- Build check: SUCCESS"; next} p && /^## /{p=0} {print}' \
            "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
        fi
      fi
      
      # Update dashboard
      "$HERE/pw-lib.sh" dashboard-mr-state "$SLUG" "$TASK_ID" "merged" 2>/dev/null || true
      
      exit 0
      ;;
    failed|FAILURE|failed|canceled|skipped|CANCELLED|SKIPPED|failing)
      echo "$TASK_ID: pipeline FAILED (${ELAPSED_MIN}m ${ELAPSED_SEC}s) — status: $STATUS"
      
      # Update task file
      if grep -q '^## Result' "$TASK_FILE"; then
        if ! grep -q 'Build check:' "$TASK_FILE"; then
          awk -v status="$STATUS" '/^## Result/{p=1; print; print "- Build check: FAILED (" status ")"; next} p && /^## /{p=0} {print}' \
            "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
        fi
      fi
      
      exit 1
      ;;
  esac
  
  # Check timeout
  if [ "$ELAPSED" -ge "$TIMEOUT_SEC" ]; then
    echo "$TASK_ID: pipeline still running after ${TIMEOUT_MIN}m — not yet resolved"
    exit 2
  fi
  
  # Still running
  echo "$TASK_ID: pipeline running (${ELAPSED_MIN}m ${ELAPSED_SEC}s elapsed) — status: $STATUS"
  
  # Wait before next poll
  sleep "$INTERVAL_SEC"
done
