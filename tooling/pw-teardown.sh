#!/usr/bin/env bash
# ============================================================================
# pw-teardown.sh — safely remove a project's git worktrees at close-out.
#
#   tooling/pw-teardown.sh <project-dir> [--yes] [worktree-path]
#
# With no [worktree-path], removes every worktree under <project-dir>/worktree.
# With a [worktree-path], removes ONLY that one worktree (it must live under the
# project's worktree/ dir) — this is the single-worktree mode `pw-lib.sh
# worktree-remove` delegates to, so the safety guards below have exactly one owner.
# It exits 1 when a single-target worktree could not be removed (so the caller
# knows to look at the printed reason), and 0 when it went away.
#
# Why this exists: `git worktree remove` deletes the worktree directory. If that
# directory is the one your editor (VS Code, JetBrains, …) currently has OPEN as
# its workspace folder — or is your shell's CWD — removing it can make the editor
# reload or close the window. This helper refuses to remove:
#   • the worktree that contains the current working directory ($PWD), and
#   • any worktree with uncommitted changes (unless --yes).
# It never deletes branches or the project dir. Run it from the bundle/project
# root, NOT from inside a worktree.
# ============================================================================
set -euo pipefail

projdir="${1:-}"
YES=0; [ "${2:-}" = "--yes" ] && YES=1
target="${3:-}"
[ -n "$projdir" ] && [ -d "$projdir" ] || { echo "usage: pw-teardown.sh <project-dir> [--yes] [worktree-path]" >&2; exit 2; }
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
