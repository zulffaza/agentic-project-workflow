#!/usr/bin/env bash
# ============================================================================
# pw-adopt-snapshot.sh — snapshot git state for adoption
#
#   pw-adopt-snapshot.sh <slug> <repo> <branch> [mr-url]
#
# Snapshots git state, resolves base branch from MR target, outputs
# structured data.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-adopt-snapshot: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -ge 3 ] || die "usage: pw-adopt-snapshot.sh <slug> <repo> <branch> [mr-url]"

SLUG="$1"
REPO="$2"
BRANCH="$3"
MR_URL="${4:-}"

D="$(proj_dir "$SLUG")"
REPO_DIR="$REPOS_DIR/$REPO"

[ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR"

# Validate branch exists
if ! git -C "$REPO_DIR" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  die "branch not found: $BRANCH"
fi

# Resolve base branch
BASE=""
BASE_SOURCE=""

if [ -n "$MR_URL" ]; then
  # Extract base from MR target
  if echo "$MR_URL" | grep -q 'gitlab'; then
    if command -v glab >/dev/null 2>&1; then
      MR_IID="$(echo "$MR_URL" | grep -o 'merge_requests/[0-9]*' | sed 's/merge_requests\///')"
      if [ -n "$MR_IID" ]; then
        BASE="$(glab api "projects/:id/merge_requests/$MR_IID" 2>/dev/null | grep -o '"target_branch":"[^"]*"' | sed 's/"target_branch":"//;s/"//' || echo "")"
        [ -n "$BASE" ] && BASE_SOURCE="from MR target"
      fi
    fi
  elif echo "$MR_URL" | grep -q 'github'; then
    if command -v gh >/dev/null 2>&1; then
      MR_NUM="$(echo "$MR_URL" | grep -o 'pull/[0-9]*' | sed 's/pull\///')"
      if [ -n "$MR_NUM" ]; then
        BASE="$(gh pr view "$MR_NUM" --json baseRefName 2>/dev/null | grep -o '"baseRefName":"[^"]*"' | sed 's/"baseRefName":"//;s/"//' || echo "")"
        [ -n "$BASE" ] && BASE_SOURCE="from MR target"
      fi
    fi
  fi
fi

# Fallback: infer base via merge-base
if [ -z "$BASE" ]; then
  # Try common default branches
  for default_branch in master main develop; do
    if git -C "$REPO_DIR" rev-parse --verify "origin/$default_branch" >/dev/null 2>&1; then
      BASE="$default_branch"
      BASE_SOURCE="inferred, unconfirmed — no MR target"
      break
    fi
  done
fi

[ -n "$BASE" ] || die "cannot determine base branch (no MR and no default branch found)"

# Snapshot git state
COMMIT_COUNT=0
FILES_CHANGED=0

if git -C "$REPO_DIR" rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
  COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..$BRANCH" 2>/dev/null | wc -l | xargs || echo "0")"
  FILES_CHANGED="$(git -C "$REPO_DIR" diff --stat "origin/$BASE...$BRANCH" 2>/dev/null | tail -1 | grep -o '[0-9]* file' | sed 's/ file//' || echo "0")"
fi

# Output structured data
echo "repo: $REPO"
echo "branch: $BRANCH"
echo "base: $BASE ($BASE_SOURCE)"
echo "mr-url: ${MR_URL:-none}"
echo "commits: $COMMIT_COUNT"
echo "files-changed: $FILES_CHANGED"
