#!/usr/bin/env bash
# ============================================================================
# pw-worktree.sh — the worktree entity: create, remove, and teardown of the
# per-task worktrees under <project>/worktree/.
#
#   pw-worktree.sh create --project <slug> --task <task-id> --repo <repo> --base <base-branch>
#       Isolated worktree for one task; branch agent/<slug>/<T0n>-<slug>;
#       prints the worktree path. (was pw-worktree-create.sh)
#   pw-worktree.sh remove --project <slug> --task <task-id>
#       Safely remove one task's worktree (was pw-lib.sh worktree-remove).
#   pw-worktree.sh teardown --dir <project-dir> [--task <task-id> | --all] [--worktree <path>] [--yes]
#       /pw-close teardown with the safety guards: refuses the worktree you're
#       standing in and any dirty one; exit 1 = skipped with a printed reason.
#       (was pw-teardown.sh)
#
# Named-argument grammar: operation words first, every value named; --project
# selects the project. Scalar values are ONE token (quote spaces).
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
proj_dir() { local d; d="$(pw_proj_dir "$1")" || die "no such project: $1 ($PROJECTS_DIR/$1) → fix: check the slug under the projects dir (new project? create it with: /pw-new --project $1)"; printf '%s' "$d"; }

cmd_create() {
local a v
while [ $# -gt 0 ]; do
  a="$1"; shift; v=""
  case "$a" in
    --project=*) v="${a#*=}"; a="--project" ;;
    --task=*)    v="${a#*=}"; a="--task" ;;
    --repo=*)    v="${a#*=}"; a="--repo" ;;
    --base=*)    v="${a#*=}"; a="--base" ;;
  esac
  case "$a" in
    --project|--task|--repo|--base)
      [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
      case "$a" in --project) SLUG="$v" ;; --task) TASK_ID="$v" ;; --repo) REPO="$v" ;; --base) BASE_BRANCH="$v" ;; esac ;;
    -h|--help) pw_usage ;;
    -*) _pw_unknown "$a" "create --project <slug> --task <T0n> --repo <r> --base <base-branch>" ;;
    *) _pw_positional "$a" "create --project <slug> --task <T0n> --repo <r> --base <base-branch>" ;;
  esac
done
[ -n "${SLUG:-}" ] || die "create: --project is required → fix: create --project <slug> --task <T0n> --repo <r> --base <base-branch>"
[ -n "${TASK_ID:-}" ] || die "create: --task is required → fix: pass the task id (T0n)"
[ -n "${REPO:-}" ] || die "create: --repo is required → fix: pass the repo dir name"
[ -n "${BASE_BRANCH:-}" ] || die "create: --base is required → fix: pass the base branch"
# Content gates BEFORE any path/git use: the task id, repo name, and base branch all come
# from the orchestrator (task-file fields) and feed path builds and git commands below.
pw_task_id_ok "$TASK_ID" || die "create: --task must be a task id (T0n) → fix: pass the task id, e.g. --task T01"
case "$REPO" in ''|.|..|*/*) die "create: --repo must be a repository directory name (got '$REPO') → fix: pass the repo dir name" ;; esac
pw_branch_ok "$BASE_BRANCH" || die "create: refusing unsafe base branch '$BASE_BRANCH' → fix: pass a plain branch name"

D="$(proj_dir "$SLUG")"
REPO_DIR="$REPOS_DIR/$REPO"

[ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR → fix: pass the repo dir name (repos live under $REPOS_DIR — clone it there first)"
pw_dir_within "$REPOS_DIR" "$REPO_DIR" || die "create: repo path resolves outside $REPOS_DIR: $REPO_DIR → fix: check the --repo name"

# Construct branch name
BRANCH_NAME="agent/$SLUG/$TASK_ID-$SLUG"
WORKTREE_PATH="$D/worktree/$REPO/$TASK_ID-$SLUG"
mkdir -p "$(dirname "$WORKTREE_PATH")"

# --- branch-inheritance parent (plan 35) ------------------------------------------------
# A `Stacked on:` field means this branch forks the parent's EXACT locally verified commit — no
# execution-time push of the parent, no reliance on a stale origin/<parent> ref. The parent must
# be verified (its recorded verified_head must equal its current local branch head) and in the
# same repository.
TASK_FILE="$D/task/$TASK_ID.md"
STACK_PARENT=""
[ -f "$TASK_FILE" ] && STACK_PARENT="$(pw_stack_parent "$TASK_FILE")"
PARENT_SHA=""
CONSUMED_PARENT_BRANCH=""

if [ -n "$STACK_PARENT" ]; then
  PARENT_FILE="$D/task/$STACK_PARENT.md"
  [ -f "$PARENT_FILE" ] || die "stack parent $STACK_PARENT has no task file → fix: correct the 'Stacked on:' field in task/$TASK_ID.md"
  PARENT_REPO="$(pw_field "$PARENT_FILE" Repo 2>/dev/null || true)"
  [ "$PARENT_REPO" = "$REPO" ] || die "stack parent $STACK_PARENT is in repo '${PARENT_REPO:-?}', not '$REPO' → fix: a stack inherits branches only within one repository; use depends_on for cross-repo prerequisites"
  CONSUMED_PARENT_BRANCH="$(pw_field "$PARENT_FILE" Branch 2>/dev/null || true)"; CONSUMED_PARENT_BRANCH="${CONSUMED_PARENT_BRANCH//\`/}"; CONSUMED_PARENT_BRANCH="${CONSUMED_PARENT_BRANCH%%[[:space:]]*}"
  [ -n "$CONSUMED_PARENT_BRANCH" ] || die "stack parent $STACK_PARENT has no Branch field → fix: complete the parent task file first"
  [ "$CONSUMED_PARENT_BRANCH" != "$BRANCH_NAME" ] || die "task $TASK_ID cannot stack on itself (same branch) → fix: correct the 'Stacked on:' field"
  git -C "$REPO_DIR" rev-parse --verify "$CONSUMED_PARENT_BRANCH" >/dev/null 2>&1 \
    || die "parent branch '$CONSUMED_PARENT_BRANCH' ($STACK_PARENT) not found locally in $REPO → fix: execute the parent first (/pw-execute --project $SLUG --task $STACK_PARENT)"
  PARENT_HEAD="$(git -C "$REPO_DIR" rev-parse "$CONSUMED_PARENT_BRANCH" 2>/dev/null || true)"
  VPARENT="$(pw_stack_state_get "$D" "$STACK_PARENT" verified_head 2>/dev/null || true)"
  [ -n "$VPARENT" ] || die "parent $STACK_PARENT has no verified commit binding → fix: execute + verify the parent first (/pw-execute --project $SLUG --task $STACK_PARENT)"
  [ "$VPARENT" = "$PARENT_HEAD" ] \
    || die "parent $STACK_PARENT head changed after verification (verified ${VPARENT:0:8}, now ${PARENT_HEAD:0:8}) → fix: re-verify the parent (/pw-execute --project $SLUG --task $STACK_PARENT)"
  PARENT_SHA="$VPARENT"
fi

# Reuse an existing path ONLY when it is a real registered checkout of THIS repository already on
# the expected task branch. An arbitrary directory here was once accepted as ready (exit 0 with a
# misleading path). A stacked branch must additionally carry its recorded parent binding, exactly
# like the attach path below. Nothing is removed, reset, or switched here.
if [ -e "$WORKTREE_PATH" ]; then
  [ -d "$WORKTREE_PATH" ] \
    || die "existing path is not a directory: $WORKTREE_PATH → fix: move it aside (mv \"$WORKTREE_PATH\" \"$WORKTREE_PATH.bak\"), then re-run"
  [ -f "$WORKTREE_PATH/.git" ] \
    || die "existing path is not a linked worktree of '$REPO' (no .git marker): $WORKTREE_PATH → fix: move it aside (mv ...); a plain directory is never a reusable checkout"
  _wt_gitdir="$(sed -n 's/^gitdir: //p' "$WORKTREE_PATH/.git" 2>/dev/null | head -1)"
  case "$_wt_gitdir" in
    /*) ;;
    "") die "existing worktree has an empty gitdir marker: $WORKTREE_PATH → fix: move it aside (mv ...), then re-run" ;;
    *) _wt_gitdir="$WORKTREE_PATH/$_wt_gitdir" ;;
  esac
  # Physical forms: macOS /var resolves to /private/var, so a raw prefix match against the
  # logical $REPO_DIR would wrongly reject a genuine worktree.
  _wt_gitdir="$(cd "$(dirname "$_wt_gitdir")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "$_wt_gitdir")")"
  _rd_phys="$(cd "$REPO_DIR" 2>/dev/null && pwd -P)"
  case "$_wt_gitdir" in
    "$_rd_phys"/.git/*) ;;
    *) die "existing checkout $WORKTREE_PATH is not registered to $REPO_DIR → fix: move it aside (mv ...), then re-run" ;;
  esac
  _wt_branch="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$_wt_branch" = "$BRANCH_NAME" ] \
    || die "existing worktree is on branch '${_wt_branch:-?}', expected '$BRANCH_NAME' → fix: move it aside (mv ...), or select the task that owns that checkout"
  if [ -n "$STACK_PARENT" ]; then
    RECORDED="$(pw_stack_state_get "$D" "$TASK_ID" consumed_parent_sha 2>/dev/null || true)"
    [ -n "$RECORDED" ] || RECORDED="$(pw_stack_state_get "$D" "$TASK_ID" fork_sha 2>/dev/null || true)"
    [ -n "$RECORDED" ] \
      || die "stacked worktree $WORKTREE_PATH has no recorded parent binding → fix: re-create it (/pw-execute --project $SLUG --task $TASK_ID after verifying $STACK_PARENT)"
    git -C "$REPO_DIR" merge-base --is-ancestor "$RECORDED" "$BRANCH_NAME" 2>/dev/null \
      || die "stacked worktree $WORKTREE_PATH is stale — it does not contain its recorded parent commit ${RECORDED:0:8} → fix: /pw-sync --project $SLUG --task $TASK_ID (merge the updated parent, re-verify, push)"
    git -C "$REPO_DIR" merge-base --is-ancestor "$VPARENT" "$BRANCH_NAME" 2>/dev/null \
      || die "stacked worktree $WORKTREE_PATH predates $STACK_PARENT's current verified head ${VPARENT:0:8} → fix: /pw-sync --project $SLUG --task $TASK_ID (merge the updated parent, re-verify, push)"
  fi
  if [ -n "$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null || true)" ]; then
    echo "Worktree exists with uncommitted changes (left intact): $WORKTREE_PATH" >&2
  fi
  echo "Worktree already exists: $WORKTREE_PATH"
  echo "$WORKTREE_PATH"
  exit 0
fi

if git -C "$REPO_DIR" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  # Branch exists, attach to it. Attachment alone is not readiness: a stacked branch must carry a
  # recorded consumption/verification identity AND contain the parent's CURRENT verified head. An
  # empty binding fails closed (a stacked branch is never attached unbound), and a parent advanced
  # past the child's fork must go through the descendant update procedure (/pw-sync).
  echo "Branch $BRANCH_NAME already exists, attaching..."
  if [ -n "$STACK_PARENT" ]; then
    RECORDED="$(pw_stack_state_get "$D" "$TASK_ID" consumed_parent_sha 2>/dev/null || true)"
    [ -n "$RECORDED" ] || RECORDED="$(pw_stack_state_get "$D" "$TASK_ID" fork_sha 2>/dev/null || true)"
    [ -n "$RECORDED" ] \
      || die "stacked branch $BRANCH_NAME has no recorded parent binding → fix: re-create it (/pw-execute --project $SLUG --task $TASK_ID after verifying $STACK_PARENT); a stacked branch is never attached without its verification identity"
    git -C "$REPO_DIR" merge-base --is-ancestor "$RECORDED" "$BRANCH_NAME" 2>/dev/null \
      || die "stacked branch $BRANCH_NAME is stale — it does not contain its recorded parent commit ${RECORDED:0:8} → fix: /pw-sync --project $SLUG --task $TASK_ID (merge the updated parent, re-verify, push)"
    git -C "$REPO_DIR" merge-base --is-ancestor "$VPARENT" "$BRANCH_NAME" 2>/dev/null \
      || die "stacked branch $BRANCH_NAME predates $STACK_PARENT's current verified head ${VPARENT:0:8} → fix: /pw-sync --project $SLUG --task $TASK_ID (merge the updated parent, re-verify, push)"
  fi
  git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" "$BRANCH_NAME" || die "failed to attach worktree"
elif [ -n "$STACK_PARENT" ]; then
  echo "Creating worktree with new branch $BRANCH_NAME from $STACK_PARENT's verified commit ${PARENT_SHA:0:8}..."
  git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "$PARENT_SHA" || die "failed to create worktree"
  pw_stack_state_upsert "$D" "$TASK_ID" \
    parent="$STACK_PARENT" branch="$BRANCH_NAME" base="$BASE_BRANCH" \
    fork_sha="$PARENT_SHA" consumed_parent_sha="$PARENT_SHA" \
    consumed_parent_branch="$CONSUMED_PARENT_BRANCH" target="$CONSUMED_PARENT_BRANCH" \
    freshness=fresh || die "failed to record the stack fork binding"
  "$ST" log --project "$SLUG" --actor execute --message "$TASK_ID: forked from $STACK_PARENT @ ${PARENT_SHA:0:8} (stacked on $CONSUMED_PARENT_BRANCH)" >/dev/null 2>&1 || true
else
  # Create new branch from base (legacy independent behavior)
  echo "Creating worktree with new branch $BRANCH_NAME from origin/$BASE_BRANCH..."
  git -C "$REPO_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" "origin/$BASE_BRANCH" || die "failed to create worktree"
fi

echo "Worktree created: $WORKTREE_PATH"
echo "$WORKTREE_PATH"
}

cmd_teardown() {
local dir="" YES=0 ALL=0 TASK="" WPATH="" a v
while [ $# -gt 0 ]; do
  a="$1"; shift; v=""
  case "$a" in
    --dir=*)      v="${a#*=}"; a="--dir" ;;
    --task=*)     v="${a#*=}"; a="--task" ;;
    --worktree=*) v="${a#*=}"; a="--worktree" ;;
  esac
  case "$a" in
    --dir|--task|--worktree)
      [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
      case "$a" in --dir) dir="$v" ;; --task) TASK="$v" ;; --worktree) WPATH="$v" ;; esac ;;
    --yes) YES=1 ;;
    --all) ALL=1 ;;
    -h|--help) pw_usage ;;
    -*) _pw_unknown "$a" "teardown --dir <project-dir> [--task <T0n> | --all] [--worktree <path>] [--yes]" ;;
    *) _pw_positional "$a" "teardown --dir <project-dir> [--task <T0n> | --all] [--worktree <path>] [--yes]" ;;
  esac
done
[ -n "$dir" ] || die "teardown: --dir is required → fix: teardown --dir <project-dir> [--task <T0n> | --all] [--worktree <path>] [--yes]"
[ -d "$dir" ] || die "teardown: no such project dir: $dir → fix: pass the project directory (teardown --dir <project-dir>)"
if [ -n "$TASK" ] && [ -n "$WPATH" ]; then
  die "teardown: --task and --worktree select the same single target → fix: pass one of them (--task <T0n> or --worktree <path>)"
fi
if [ "$ALL" -eq 1 ] && [ -n "$TASK$WPATH" ]; then
  die "teardown: --all conflicts with --task/--worktree → fix: pass --all alone, or one single target"
fi

projdir="$(cd "$dir" && pwd -P)"
wtroot="$projdir/worktree"
# Physical PWD: the guard compares against physically-resolved worktree paths (wtroot above),
# so a logical PWD under a symlinked root (/var → /private/var) would never match.
here="$(pwd -P)"

[ -d "$wtroot" ] || { echo "no worktree/ dir under $projdir — nothing to tear down."; exit 0; }

removed=0 skipped_cwd=0 skipped_dirty=0

# A worktree is a leaf dir under worktree/ that git recognises (has a .git file/dir).
# Single-target mode (--task resolves the task's worktree dir, --worktree takes a path):
# only that worktree, which must be under wtroot; else (--all / no target) every worktree.
target=""
if [ -n "$TASK" ]; then
  pw_task_id_ok "$TASK" || die "teardown: --task must be a task id (T0n) → fix: pass the task id, e.g. --task T01"
  target="$(find "$wtroot" -maxdepth 3 -type d -name "$TASK-*" 2>/dev/null | head -1)"
  [ -n "$target" ] || die "teardown: no worktree found for $TASK under $wtroot → fix: check the task id (worktree dirs are named <T0n>-<slug>)"
elif [ -n "$WPATH" ]; then
  target="$WPATH"
fi
if [ -n "$target" ]; then
  case "$target" in
    /*) ;;
    *) target="$projdir/$target" ;;
  esac
  [ -e "$target/.git" ] || { echo "not a worktree (no .git marker): $target" >&2; exit 2; }
  target="$(cd "$target" && pwd -P)"
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
#   remove --project <slug> --task <task-id>
cmd_remove() {
  local slug="" task="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; --task=*) v="${a#*=}"; a="--task" ;; esac
    case "$a" in
      --project|--task)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --task) task="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "remove --project <slug> --task <T0n>" ;;
      *) _pw_positional "$a" "remove --project <slug> --task <T0n>" ;;
    esac
  done
  [ -n "$slug" ] || die "remove: --project is required → fix: remove --project <slug> --task <T0n>"
  [ -n "$task" ] || die "remove: --task is required → fix: remove --project <slug> --task <T0n>"
  pw_task_id_ok "$task" || die "remove: --task must be a task id (T0n) → fix: pass the task id, e.g. --task T01"
  local d; d="$(proj_dir "$slug")"
  local wt="$d/worktree"

  # Find the worktree directory for this task
  local task_wt
  task_wt="$(find "$wt" -maxdepth 3 -type d -name "$task-*" 2>/dev/null | head -1)"
  [ -n "$task_wt" ] && [ -d "$task_wt" ] || { echo "no worktree found for $task"; return 1; }

  # Delegate to teardown — the single owner of the safety guards (refuses the worktree
  # you're standing in, refuses one with uncommitted changes). Never passes --yes: a dirty worktree
  # must be committed/stashed first, exactly as /pw-close requires. Exit 1 from teardown means it
  # skipped the worktree (reason already printed) — don't log "removed".
  cmd_teardown --dir "$d" --worktree "$task_wt" || return 1
  "$ST" log --project "$slug" --actor sync --message "$task: worktree removed (MR already merged)"
  echo "$slug: $task worktree removed"
}


case "${1:-}" in
  create)   shift; cmd_create "$@" ;;
  remove)   shift; cmd_remove "$@" ;;
  teardown) shift; cmd_teardown "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-worktree.sh <create|remove|teardown> … (see --help)" ;;
esac
