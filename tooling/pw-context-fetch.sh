#!/usr/bin/env bash
# ============================================================================
# pw-context-fetch.sh — fetch URLs in context/INDEX.md
#
#   pw-context-fetch.sh <slug> [--ignore-errors]
#
# Fetches all URLs in context/INDEX.md, dispatching to the right CLI based
# on URL pattern. Outputs fetched content or errors.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-context-fetch: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

IGNORE_ERRORS=0
SLUG=""

for arg in "$@"; do
  case "$arg" in
    --ignore-errors) IGNORE_ERRORS=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) die "unknown option: $arg" ;;
    *) SLUG="$arg" ;;
  esac
done

[ -n "$SLUG" ] || die "usage: pw-context-fetch.sh <slug> [--ignore-errors]"

D="$(proj_dir "$SLUG")"
INDEX="$D/context/INDEX.md"

[ -f "$INDEX" ] || die "context/INDEX.md not found"

ERRORS=()

# Extract URLs from INDEX.md
while IFS='|' read -r file link desc provenance; do
  file="$(echo "$file" | xargs)"
  link="$(echo "$link" | xargs)"
  
  # Skip header/separator rows
  [[ "$file" =~ ^File ]] && continue
  [[ "$file" =~ ^[-: ] ]] && continue
  [ -z "$link" ] && continue
  
  # Extract URL from link field
  URL=""
  if echo "$link" | grep -q 'http'; then
    URL="$(echo "$link" | grep -o 'https\?://[^ )]*' || echo "")"
  elif echo "$link" | grep -qE '^[A-Z]+-[0-9]+$'; then
    # Bare Jira ticket
    URL="$link"
  fi
  
  [ -n "$URL" ] || continue
  
  echo "Fetching: $file ($URL)"
  
  # Dispatch to right CLI based on URL pattern
  FETCHED=0
  
  # Jira URL or bare ticket
  if echo "$URL" | grep -qE '(atlassian\.net/browse|[A-Z]+-[0-9]+)'; then
    if command -v jira >/dev/null 2>&1; then
      TICKET="$(echo "$URL" | grep -oE '[A-Z]+-[0-9]+' | head -1)"
      if jira issue view "$TICKET" 2>/dev/null; then
        FETCHED=1
      fi
    fi
  fi
  
  # GitHub issue/PR URL
  if [ "$FETCHED" -eq 0 ] && echo "$URL" | grep -q 'github.com'; then
    if command -v gh >/dev/null 2>&1; then
      if echo "$URL" | grep -q '/issues/'; then
        if gh issue view "$URL" 2>/dev/null; then
          FETCHED=1
        fi
      elif echo "$URL" | grep -q '/pull/'; then
        if gh pr view "$URL" 2>/dev/null; then
          FETCHED=1
        fi
      fi
    fi
  fi
  
  # GitLab issue/MR URL
  if [ "$FETCHED" -eq 0 ] && echo "$URL" | grep -q 'gitlab.com'; then
    if command -v glab >/dev/null 2>&1; then
      if echo "$URL" | grep -q '/-/issues/'; then
        if glab issue view "$URL" 2>/dev/null; then
          FETCHED=1
        fi
      elif echo "$URL" | grep -q '/-/merge_requests/'; then
        if glab mr view "$URL" 2>/dev/null; then
          FETCHED=1
        fi
      fi
    fi
  fi
  
  # Lark URL (not scriptable — skip)
  if echo "$URL" | grep -qE '(lark|feishu|doubao)\.com'; then
    echo "  (Lark URL — agent handles via platform skill)"
    continue
  fi
  
  # Fallback: WebFetch (not available in shell — skip)
  if [ "$FETCHED" -eq 0 ]; then
    if [ "$IGNORE_ERRORS" -eq 1 ]; then
      echo "  $file — NOT fetched (--ignore-errors); treat with reduced confidence"
    else
      ERRORS+=("$file: cannot fetch $URL (no suitable CLI)")
    fi
  fi
  
  echo
  
done < <(awk '/^\|/{print}' "$INDEX" | grep -v '^|[-: ]' || true)

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "pw-context-fetch: ${#ERRORS[@]} error(s):" >&2
  for err in "${ERRORS[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

echo "Context fetch complete"
