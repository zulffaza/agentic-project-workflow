# shellcheck shell=bash
# cases/pw-worktree.t.sh — the worktree entity (merged plan 20 Phase 4: create + remove).
pwtest_rc 0 "create T02 worktree (fresh branch from master)" "$(pwtest_script pw-worktree.sh)" create "$S2" T95 api master
pwtest_re "worktree" "prints worktree path"
wt2="$PW_PROJECTS_DIR/$S2/worktree/api/$S2-T95-$(true)"
ls "$PW_PROJECTS_DIR/$S2/worktree/api/" >/dev/null 2>&1 && pwtest_ok "worktree dir created under project" || pwtest_bad "worktree dir" "ls failed"
pwtest_rc 2 "fake repo → 2" "$(pwtest_script pw-worktree.sh)" create "$S2" T01 nope-repo master
pwtest_fix "missing repo names the remedy"

# 5) worktree-remove guards (P8): operate on F2's mounted worktrees; restore at end
WTBASE="$PW_PROJECTS_DIR/$S2/worktree/api"
ls "$WTBASE" >/dev/null 2>&1 || { pwtest_skip "worktree guards" "no mounted worktree in fixture"; }
if [ -d "$WTBASE/T02-thing" ]; then
  ( cd "$WTBASE/T02-thing" && "$(pwtest_script pw-worktree.sh)" remove "$S2" T02 >"$PWTEST_ROOT/wr.out" 2>&1; echo $? >"$PWTEST_ROOT/wr.rc" ) || true
  wrc=$(cat "$PWTEST_ROOT/wr.rc")
  [ "$wrc" != 0 ] && pwtest_ok "worktree-remove refuses when it is CWD (rc=$wrc)" \
    || { pwtest_bad "worktree-remove CWD guard" "removal succeeded while inside!"; git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$(basename "$S2")/T02-thing" >/dev/null 2>&1 || true; }
  ( git -C "$WTBASE/T02-thing" status >/dev/null 2>&1 || true )
  printf 'dirty\n' > "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt"
  ( cd / && "$(pwtest_script pw-worktree.sh)" remove "$S2" T02 >"$PWTEST_ROOT/wr2.out" 2>&1; echo $? >"$PWTEST_ROOT/wr2.rc" ) || true
  w2=$(cat "$PWTEST_ROOT/wr2.rc")
  [ "$w2" != 0 ] && pwtest_ok "worktree-remove refuses dirty tree" || pwtest_bad "worktree-remove dirty guard" "removed dirty worktree!"
fi
# ALWAYS leave the fixture as found (alphabetical order: pw-lib runs before pw-ship!):
mkdir -p "$WTBASE" 2>/dev/null || true
git -C "$PW_REPOS/api" worktree list | grep -q "T02-thing" \
  || git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$S2/T02-thing" >/dev/null 2>&1 || true
rm -f "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt" 2>/dev/null || true
