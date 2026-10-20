# shellcheck shell=bash
# cases/pw-sync.t.sh — opt-in sync attempt + guarded conflict merge (plan 48).
# Real Git only: pinned attempt inputs, stale detection, keep/abort conflict paths,
# deterministic finish guards, and evidence binding to the final HEAD.
SH=pw-ship.sh

sync_mkproj() {
  local s="$1"; rm -rf "$PW_PROJECTS_DIR/$s"
  mkdir -p "$PW_PROJECTS_DIR/$s/task"
  printf '# %s\n\n- **Status:** executing\n' "$s" > "$PW_PROJECTS_DIR/$s/README.md"
  : > "$PW_PROJECTS_DIR/$s/LOG.md"
  printf '%s' "$PW_PROJECTS_DIR/$s"
}
sync_task() {
  local p="$1" id="$2" repo="$3" base="$4" br="$5" st="$6"
  printf '%s\n' "# $id: sync fixture" \
    "- **Repo:** $repo" "- **Base branch:** $base" "- **Branch:** \`$br\`" \
    "- **Worktree:** \`worktree/$repo/$id-thing/\`" \
    "- **Status:** $st" "- **MR:** —" > "$p/task/$id.md"
}
sync_branch() {   # <repo> <newbranch> <from> <file> <content>
  local repo="$1" nb="$2" from="$3" f="$4" c="$5"
  git -C "$PW_REPOS/$repo" checkout -q "$from"
  git -C "$PW_REPOS/$repo" checkout -q -B "$nb"
  printf '%s\n' "$c" > "$PW_REPOS/$repo/$f"
  git -C "$PW_REPOS/$repo" add -A
  git -C "$PW_REPOS/$repo" -c user.email=t@t -c user.name=t commit -qm "sync $nb"
  git -C "$PW_REPOS/$repo" push -q -u origin "$nb" >/dev/null 2>&1
  git -C "$PW_REPOS/$repo" checkout -q master
}
sync_advance() {  # <repo> <branch> <file> <content>
  local repo="$1" br="$2" f="$3" c="$4"
  git -C "$PW_REPOS/$repo" checkout -q "$br"
  printf '%s\n' "$c" > "$PW_REPOS/$repo/$f"
  git -C "$PW_REPOS/$repo" add -A
  git -C "$PW_REPOS/$repo" -c user.email=t@t -c user.name=t commit -qm "advance $br"
  git -C "$PW_REPOS/$repo" push -q origin "$br" >/dev/null 2>&1
  git -C "$PW_REPOS/$repo" checkout -q master
}
sync_wt() {       # <projdir> <repo> <taskdir> <branch>
  local p="$1" repo="$2" dir="$3" br="$4"
  rm -rf "$p/worktree/$repo/$dir"
  mkdir -p "$p/worktree/$repo"
  git -C "$PW_REPOS/$repo" worktree add -q "$p/worktree/$repo/$dir" "$br" >/dev/null 2>&1
}
sht() { "$(pwtest_script $SH)" "$@"; }

pwtest_repo syncgit
SY=syncatt; SY_DIR="$(sync_mkproj "$SY")"
sync_task "$SY_DIR" T01 syncgit master "agent/$SY/T01-sync" accepted
sync_task "$SY_DIR" T02 syncgit master "agent/$SY/T02-sync" accepted
sync_branch syncgit "agent/$SY/T01-sync" master shared.txt task-one
sync_branch syncgit "agent/$SY/T02-sync" master shared.txt task-two
sync_wt "$SY_DIR" syncgit T01-thing "agent/$SY/T01-sync"
sync_wt "$SY_DIR" syncgit T02-thing "agent/$SY/T02-sync"
git -C "$SY_DIR/worktree/syncgit/T01-thing" fetch -q origin
git -C "$SY_DIR/worktree/syncgit/T02-thing" fetch -q origin

# --- attempt record + pinned inputs ------------------------------------------
pwtest_rc 0 "sync-attempt begin pins the tuple" sht sync-attempt --project "$SY" begin --task T01 --kind independent --mode auto --target-branch master
pwtest_re 'attempt prepared' "begin reports the prepared attempt"
pwtest_rc 0 "sync-attempt show prints the row" sht sync-attempt --project "$SY" show --task T01
pwtest_re '^T01\t' "row keyed by task"
pwtest_rc 0 "sync-attempt check fresh after begin" sht sync-attempt --project "$SY" check --task T01
pwtest_re '^fresh$' "fresh vocabulary"
pwtest_rc 2 "begin refuses a duplicate attempt" sht sync-attempt --project "$SY" begin --task T01 --kind independent --mode auto --target-branch master
pwtest_err 'already exists' "duplicate attempt names the existing stage"
pwtest_rc 2 "begin rejects an unknown kind" sht sync-attempt --project "$SY" begin --task T02 --kind merged --mode auto --target-branch master
pwtest_rc 2 "begin rejects an unsafe target branch" sht sync-attempt --project "$SY" begin --task T02 --kind independent --mode auto --target-branch '--bad'
pwtest_rc 2 "begin rejects an unsafe task id" sht sync-attempt --project "$SY" begin --task '../../x' --kind independent --mode auto --target-branch master
pwtest_rc 2 "check without an attempt fails closed" sht sync-attempt --project "$SY" check --task T99

# the pinned target moves: the old tuple no longer certifies a resolution
sync_advance syncgit master shared.txt target-two
git -C "$PW_REPOS/syncgit" fetch -q origin
pwtest_rc 1 "check detects a moved target" sht sync-attempt --project "$SY" check --task T01
pwtest_re '^stale: origin/master moved' "stale reason names the target"
pwtest_rc 2 "sync-merge refuses an unpinned target" sht sync-merge --project "$SY" --task T01 --target "$(git -C "$PW_REPOS/syncgit" rev-parse master)" --keep-conflict
pwtest_err 'pinned target' "unpinned target names the pinned tuple"

# re-capture, then move the task branch itself
pwtest_rc 0 "clear a stale attempt" sht sync-attempt --project "$SY" clear --task T01
pwtest_rc 0 "begin again after re-fetch" sht sync-attempt --project "$SY" begin --task T01 --kind independent --mode auto --target-branch master
pwtest_rc 0 "check fresh after re-capture" sht sync-attempt --project "$SY" check --task T01
printf 'task-one-b\n' > "$SY_DIR/worktree/syncgit/T01-thing/shared.txt"
git -C "$SY_DIR/worktree/syncgit/T01-thing" add -A
git -C "$SY_DIR/worktree/syncgit/T01-thing" -c user.email=t@t -c user.name=t commit -qm "advance task branch"
git -C "$SY_DIR/worktree/syncgit/T01-thing" push -q origin "agent/$SY/T01-sync"
git -C "$PW_REPOS/syncgit" fetch -q origin
pwtest_rc 1 "check detects a moved task branch" sht sync-attempt --project "$SY" check --task T01
pwtest_re '^stale: origin/agent/' "task-branch movement is named"

# final re-capture against both current refs
pwtest_rc 0 "clear the moved-branch attempt" sht sync-attempt --project "$SY" clear --task T01
pwtest_rc 0 "final attempt prepared" sht sync-attempt --project "$SY" begin --task T01 --kind independent --mode auto --target-branch master
pwtest_rc 0 "final attempt is fresh" sht sync-attempt --project "$SY" check --task T01
TARGET="$(git -C "$PW_REPOS/syncgit" rev-parse refs/remotes/origin/master)"

# --- guarded conflict: keep, validate, finish, bind ---------------------------
pwtest_rc 3 "sync-merge keeps the conflict for resolution" sht sync-merge --project "$SY" --task T01 --target "$TARGET" --keep-conflict
pwtest_re '^conflict: shared.txt' "conflict path reported"
[ -n "$(git -C "$SY_DIR/worktree/syncgit/T01-thing" rev-parse --verify --quiet MERGE_HEAD || true)" ] \
  && pwtest_ok "attempt-owned merge remains active (MERGE_HEAD)" || pwtest_bad "keep-conflict" "merge was aborted"
pwtest_rc 2 "sync-finish refuses unresolved paths" sht sync-finish --project "$SY" --task T01
pwtest_err 'unresolved paths remain' "unresolved refusal is explicit"
# an introduced marker is refused even with every path staged
printf 'both\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> target\n' > "$SY_DIR/worktree/syncgit/T01-thing/shared.txt"
git -C "$SY_DIR/worktree/syncgit/T01-thing" add shared.txt
pwtest_rc 2 "sync-finish refuses introduced conflict markers" sht sync-finish --project "$SY" --task T01
pwtest_err 'conflict markers' "marker refusal is explicit"
printf 'both\nresolved\n' > "$SY_DIR/worktree/syncgit/T01-thing/shared.txt"
git -C "$SY_DIR/worktree/syncgit/T01-thing" add shared.txt
pwtest_rc 0 "sync-finish completes the merge with both parents" sht sync-finish --project "$SY" --task T01
pwtest_re '^resolved ' "resolved result head reported"
PARENTS="$(git -C "$SY_DIR/worktree/syncgit/T01-thing" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"
[ "$PARENTS" = 3 ] && pwtest_ok "merge commit keeps two parents" || pwtest_bad "merge parents" "parent fields=$PARENTS"
pwtest_rc 2 "sync-bind refuses empty evidence" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/empty-ev"
: > "$ROOT/empty-ev"
pwtest_rc 2 "sync-bind refuses a whitespace-only evidence file" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/empty-ev"
printf 'verify: green\n' > "$ROOT/ev-sync"
printf 'untracked\n' > "$SY_DIR/worktree/syncgit/T01-thing/untracked.txt"
pwtest_rc 2 "sync-bind refuses a dirty worktree" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/ev-sync"
pwtest_err 'dirty after verification' "dirty bind refusal is explicit"
rm -f "$SY_DIR/worktree/syncgit/T01-thing/untracked.txt"
pwtest_rc 0 "sync-bind records evidence at the result HEAD" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/ev-sync"
pwtest_re 'verified at ' "bind reports the final head"
pwtest_rc 0 "sync-attempt show reaches verified" sht sync-attempt --project "$SY" show --task T01
pwtest_eq "verified stage recorded" "verified" "$(awk -F'\t' '$1=="T01"{print $10}' "$SY_DIR/task/sync-attempts.tsv")"
printf 'repair\n' >> "$SY_DIR/worktree/syncgit/T01-thing/shared.txt"
git -C "$SY_DIR/worktree/syncgit/T01-thing" add -A
git -C "$SY_DIR/worktree/syncgit/T01-thing" -c user.email=t@t -c user.name=t commit -qm "bounded repair"
printf 'verify: repaired green\n' > "$ROOT/ev-sync-repair"
pwtest_rc 0 "one bounded repair can rebind" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/ev-sync-repair"
pwtest_eq "repair count recorded" "1" "$(awk -F'\t' '$1=="T01"{print $11}' "$SY_DIR/task/sync-attempts.tsv")"
printf 'second-repair\n' >> "$SY_DIR/worktree/syncgit/T01-thing/shared.txt"
git -C "$SY_DIR/worktree/syncgit/T01-thing" add -A
git -C "$SY_DIR/worktree/syncgit/T01-thing" -c user.email=t@t -c user.name=t commit -qm "second repair"
pwtest_rc 2 "a second repair cannot bind" sht sync-bind --project "$SY" --task T01 --evidence "$ROOT/ev-sync-repair"
pwtest_err 'repair budget exhausted' "exhausted budget is explicit"
pwtest_rc 2 "sync-merge refuses to re-merge a verified attempt" sht sync-merge --project "$SY" --task T01 --target "$TARGET" --keep-conflict
pwtest_rc 0 "sync-attempt sets pushed only after verification" sht sync-attempt --project "$SY" set --task T01 --stage pushed
pwtest_re 'stage pushed' "published stage recorded"
pwtest_rc 2 "a published attempt cannot be marked failed" sht sync-attempt --project "$SY" set --task T01 --stage failed

# --- default path: conflict abort restores the worktree ----------------------
pwtest_rc 0 "T02 attempt prepared" sht sync-attempt --project "$SY" begin --task T02 --kind independent --mode clean --target-branch master
pwtest_rc 2 "sync-merge without keep aborts the conflict" sht sync-merge --project "$SY" --task T02 --target "$TARGET"
pwtest_err 'aborted' "abort path reported"
[ -z "$(git -C "$SY_DIR/worktree/syncgit/T02-thing" rev-parse --verify --quiet MERGE_HEAD || true)" ] \
  && pwtest_ok "aborted merge leaves no MERGE_HEAD" || pwtest_bad "abort cleanup" "MERGE_HEAD survived"
[ -z "$(git -C "$SY_DIR/worktree/syncgit/T02-thing" status --porcelain)" ] \
  && pwtest_ok "aborted merge restores a clean worktree" || pwtest_bad "abort cleanliness" "$(git -C "$SY_DIR/worktree/syncgit/T02-thing" status --porcelain | tr '\n' ' ')"
pwtest_rc 2 "sync-attempt set cannot jump to resolved" sht sync-attempt --project "$SY" set --task T02 --stage resolved

# --- abort path preserves untracked ownership reporting ----------------------
sht sync-attempt --project "$SY" clear --task T02 >/dev/null 2>&1
pwtest_rc 0 "T02 attempt prepared for abort" sht sync-attempt --project "$SY" begin --task T02 --kind independent --mode auto --target-branch master
pwtest_rc 3 "T02 conflict kept for abort" sht sync-merge --project "$SY" --task T02 --target "$TARGET" --keep-conflict
printf 'attempt scratch\n' > "$SY_DIR/worktree/syncgit/T02-thing/attempt-scratch.txt"
pwtest_rc 0 "sync-abort aborts only the attempt merge" sht sync-abort --project "$SY" --task T02
pwtest_err 'untracked files remain' "abort reports attempt-created files"
[ -z "$(git -C "$SY_DIR/worktree/syncgit/T02-thing" rev-parse --verify --quiet MERGE_HEAD || true)" ] \
  && pwtest_ok "abort removed the merge state" || pwtest_bad "abort" "MERGE_HEAD survived"
pwtest_rc 2 "sync-abort refuses to undo a published attempt" sht sync-abort --project "$SY" --task T01

# --- dirty worktree refuses before any merge --------------------------------
sync_advance syncgit master shared.txt target-three
git -C "$PW_REPOS/syncgit" fetch -q origin
sht sync-attempt --project "$SY" clear --task T02 >/dev/null 2>&1
pwtest_rc 0 "T02 attempt prepared for dirty guard" sht sync-attempt --project "$SY" begin --task T02 --kind independent --mode auto --target-branch master
printf 'dirty\n' >> "$SY_DIR/worktree/syncgit/T02-thing/shared.txt"
pwtest_rc 2 "sync-merge refuses a dirty worktree" sht sync-merge --project "$SY" --task T02 --target "$(git -C "$PW_REPOS/syncgit" rev-parse refs/remotes/origin/master)" --keep-conflict
pwtest_err 'uncommitted changes' "dirty refusal is explicit"
git -C "$SY_DIR/worktree/syncgit/T02-thing" checkout -- shared.txt
