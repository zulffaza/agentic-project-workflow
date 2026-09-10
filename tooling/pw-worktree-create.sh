#!/usr/bin/env bash
# ============================================================================
# pw-worktree-create.sh — create worktree with proper branch naming
#
#   pw-worktree-create.sh <slug> <task-id> <repo> <base-branch>
#
# Creates worktree with proper branch naming (agent/<slug>/<T0n>-<slug>).
# Outputs worktree path.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-worktree-create: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -eq 4 ] || die "usage: pw-worktree-create.sh <slug> <task-id> <repo> <base-branch>"

SLUG="$1"
TASK_ID="$2"
REPO="$3"
BASE_BRANCH="$4"

D="$(proj_dir "$SLUG")"
REPO_DIR="$REPOS_DIR/$REPO"

[ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR"

# Construct branch name
BRANCH_NAME="agent/$SLUG/$TASK_ID-$SLUG"

# Construct worktree path
WORKTREE_PATH="$D/worktree/$REPO/$TASK_ID-$SLUG"

# Create worktree directory
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Check if worktree already exists
if [ -d "$WORKTREE_PATH" ]; then
  echo "Worktree already exists: $WORKTREE_PATH"
  echo "$WORKTREE_PATH"
  exit 0
fi

# Check if branch already exists
if git -C "$REPO_DIR" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  # Branch exists, attach to it
  echo "Branch $BRANCH_NAME already exists, attaching..."
  git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" "$BRANCH_NAME" || die "failed to attach worktree"
else
  # Create new branch from base
  echo "Creating worktree with new branch $BRANCH_NAME from origin/$BASE_BRANCH..."
  git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "origin/$BASE_BRANCH" || die "failed to create worktree"
fi

echo "Worktree created: $WORKTREE_PATH"
echo "$WORKTREE_PATH"
