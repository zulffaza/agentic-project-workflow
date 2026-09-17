#!/usr/bin/env bash
# ============================================================================
# pw-worktree.sh — the worktree entity: create, remove, and teardown of the
# per-task worktrees under <project>/worktree/.
#
#   pw-worktree.sh create   <slug> <task-id> <repo> <base-branch>
#       Isolated worktree for one task; branch agent/<slug>/<T0n>-<slug>;
#       prints the worktree path. (was pw-worktree-create.sh)
#   pw-worktree.sh remove   <slug> <task-id>
#       Safely remove one task's worktree (was pw-lib.sh worktree-remove).
#   pw-worktree.sh teardown <project-dir> [all|<task-id>] [worktree-path]
#       /pw-close teardown with the safety guards: refuses the worktree you're
#       standing in and any dirty one; exit 1 = skipped with a printed reason.
#       (was pw-teardown.sh)
#
# Merged plan 20 (one entity, three entry points -> one script; S1/S4).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"
ST="$HERE/pw-status.sh"

die() { echo "pw-worktree: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

cmd_create() {
[ $# -eq 4 ] || die "usage: pw-worktree.sh create <slug> <task-id> <repo> <base-branch>"

SLUG="$1"
TASK_ID="$2"
REPO="$3"
BASE_BRANCH="$4"

D="$(proj_dir "$SLUG")"
REPO_DIR="$REPOS_DIR/$REPO"

[ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR → fix: pass the repo dir name (repos live under $REPOS_DIR — clone it there first)"

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
}

cmd_teardown() {
projdir="${1:-}"
YES=0; [ "${2:-}" = "--yes" ] && YES=1
target="${3:-}"
[ -n "$projdir" ] && [ -d "$projdir" ] || { echo "usage: teardown <project-dir> [--yes] [worktree-path]" >&2; exit 2; }
projdir="$(cd "$projdir" && pwd)"
wtroot="$projdir/worktree"
here="$PWD"

[ -d "$wtroot" ] || { echo "no worktree/ dir under $projdir — nothing to tear down."; exit 0; }

removed=0 skipped_cwd=0 skipped_dirty=0

# A worktree is a leaf dir under worktree/ that git recognises (has a .git file/dir).
# Single-target mode: only the named worktree, which must be under wtroot; else every worktree.
if [ -n "$target" ]; then
  case "$target" in
    /*) ;;
    *) target="$projdir/$target" ;;
  esac
  [ -e "$target/.git" ] || { echo "not a worktree (no .git marker): $target" >&2; exit 2; }
  target="$(cd "$target" && pwd)"
  case "$target/" in
    "$wtroot/"*) ;;
    *) echo "target worktree not under $projdir/worktree: $target" >&2; exit 2 ;;
  esac
  marker_list="$target/.git"
else
  marker_list="$(find "$wtroot" -maxdepth 4 -name .git 2>/dev/null)"
fi

while IFS= read -r gitmarker; do
  [ -n "$gitmarker" ] || continue
  wt="$(cd "$(dirname "$gitmarker")" && pwd)"

  # Guard 1: never remove the worktree we're standing in (the #14 editor-close bug).
  case "$here/" in
    "$wt/"*) echo "  ⚠ SKIP (current dir is inside): $wt"
             echo "     cd out of it (and close it in your editor) before tearing down."
             skipped_cwd=$((skipped_cwd+1)); continue ;;
  esac

  # Guard 2: don't silently discard uncommitted work.
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && [ "$YES" -eq 0 ]; then
    echo "  ⚠ SKIP (uncommitted changes): $wt   — commit/stash, or re-run with --yes"
    skipped_dirty=$((skipped_dirty+1)); continue
  fi

  # --force only when the human opted in with --yes (needed for a dirty worktree we were told
  # to remove anyway); a clean worktree removes fine without it.
  force=""; [ "$YES" -eq 1 ] && force="--force"
  if git -C "$wt" worktree remove $force "$wt" 2>/dev/null; then
    echo "  ✓ removed worktree: $wt"
    removed=$((removed+1))
  else
    echo "  ✗ could not remove: $wt (remove manually: git -C <real-repo> worktree remove '$wt')"
  fi
done <<< "$marker_list"

echo
echo "Teardown: $removed removed, $skipped_cwd skipped (current dir), $skipped_dirty skipped (dirty)."
[ "$skipped_cwd" -gt 0 ] && echo "Re-run from the project/bundle root (not inside a worktree) to finish."

# Single-target mode: the caller needs to know whether the worktree actually went away.
if [ -n "$target" ] && [ "$removed" -eq 0 ]; then
  exit 1
fi
exit 0
}

# Safely remove a task's worktree (used when MR is already merged).
#   worktree-remove <slug> <task-id>
cmd_remove() {
  [ $# -eq 2 ] || die "usage: remove <slug> <task-id>"
  local slug="$1" task="$2"
  local d; d="$(proj_dir "$slug")"
  local wt="$d/worktree"

  # Find the worktree directory for this task
  local task_wt
  task_wt="$(find "$wt" -maxdepth 3 -type d -name "$task-*" 2>/dev/null | head -1)"
  [ -n "$task_wt" ] && [ -d "$task_wt" ] || { echo "no worktree found for $task"; return 1; }

  # Delegate to pw-teardown.sh — the single owner of the safety guards (refuses the worktree
  # you're standing in, refuses one with uncommitted changes). Never passes --yes: a dirty worktree
  # must be committed/stashed first, exactly as /pw-close requires. Exit 1 from teardown means it
  # skipped the worktree (reason already printed) — don't log "removed".
  cmd_teardown "$d" "" "$task_wt" || return 1
  ST log "$slug" sync "$task: worktree removed (MR already merged)"
  echo "$slug: $task worktree removed"
}


case "${1:-}" in
  create)   shift; cmd_create "$@" ;;
  remove)   shift; cmd_remove "$@" ;;
  teardown) shift; cmd_teardown "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-worktree.sh <create|remove|teardown> … (see --help)" ;;
esac
