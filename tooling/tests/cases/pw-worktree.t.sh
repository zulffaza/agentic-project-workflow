# shellcheck shell=bash
# cases/pw-worktree.t.sh — the worktree entity (merged plan 20 Phase 4: create + remove).
pwtest_rc 0 "create T02 worktree (fresh branch from master)" "$(pwtest_script pw-worktree.sh)" create --project "$S2" --task T95 --repo api --base master
pwtest_re "worktree" "prints worktree path"
wt2="$PW_PROJECTS_DIR/$S2/worktree/api/$S2-T95-$(true)"
ls "$PW_PROJECTS_DIR/$S2/worktree/api/" >/dev/null 2>&1 && pwtest_ok "worktree dir created under project" || pwtest_bad "worktree dir" "ls failed"
pwtest_rc 2 "fake repo → 2" "$(pwtest_script pw-worktree.sh)" create --project "$S2" --task T01 --repo nope-repo --base master
pwtest_fix "missing repo names the remedy"

# 5) worktree-remove guards (P8): operate on F2's mounted worktrees; restore at end
WTBASE="$PW_PROJECTS_DIR/$S2/worktree/api"
ls "$WTBASE" >/dev/null 2>&1 || { pwtest_skip "worktree guards" "no mounted worktree in fixture"; }
if [ -d "$WTBASE/T02-thing" ]; then
  ( cd "$WTBASE/T02-thing" && "$(pwtest_script pw-worktree.sh)" remove --project "$S2" --task T02 >"$PWTEST_ROOT/wr.out" 2>&1; echo $? >"$PWTEST_ROOT/wr.rc" ) || true
  wrc=$(cat "$PWTEST_ROOT/wr.rc")
  [ "$wrc" != 0 ] && pwtest_ok "worktree-remove refuses when it is CWD (rc=$wrc)" \
    || { pwtest_bad "worktree-remove CWD guard" "removal succeeded while inside!"; git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$(basename "$S2")/T02-thing" >/dev/null 2>&1 || true; }
  ( git -C "$WTBASE/T02-thing" status >/dev/null 2>&1 || true )
  printf 'dirty\n' > "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt"
  ( cd / && "$(pwtest_script pw-worktree.sh)" remove --project "$S2" --task T02 >"$PWTEST_ROOT/wr2.out" 2>&1; echo $? >"$PWTEST_ROOT/wr2.rc" ) || true
  w2=$(cat "$PWTEST_ROOT/wr2.rc")
  [ "$w2" != 0 ] && pwtest_ok "worktree-remove refuses dirty tree" || pwtest_bad "worktree-remove dirty guard" "removed dirty worktree!"
fi
# ALWAYS leave the fixture as found (cases run in alphabetical order):
mkdir -p "$WTBASE" 2>/dev/null || true
git -C "$PW_REPOS/api" worktree list | grep -q "T02-thing" \
  || git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$S2/T02-thing" >/dev/null 2>&1 || true
rm -f "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt" 2>/dev/null || true

# --- plan 47 F04: reuse requires a real registered checkout on the expected branch -------------
W47="wt47"; rm -rf "$PW_PROJECTS_DIR/$W47"; cp -a "$F2" "$PW_PROJECTS_DIR/$W47"
wp47="$PW_PROJECTS_DIR/$W47/worktree/api/T01-$W47"
mkdir -p "$wp47"; printf 'stray\n' > "$wp47/STRAY.txt"
pwtest_rc 2 "worktree create refuses a plain directory (not a registered checkout)" \
  "$(pwtest_script pw-worktree.sh)" create --project "$W47" --task T01 --repo api --base master
pwtest_fix "plain-directory refusal names the remedy"
rm -rf "$wp47"
pwtest_rc 0 "worktree create succeeds on a clean path" \
  "$(pwtest_script pw-worktree.sh)" create --project "$W47" --task T01 --repo api --base master
pwtest_rc 0 "worktree create REUSES a valid checkout (idempotent)" \
  "$(pwtest_script pw-worktree.sh)" create --project "$W47" --task T01 --repo api --base master
# a registered checkout on the WRONG branch must still be refused (not silently reused)
git -C "$PW_REPOS/api" worktree remove --force "$wp47" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" worktree add "$wp47" -b "agent/$W47/other-branch" origin/master >/dev/null 2>&1 || true
pwtest_rc 2 "worktree create refuses a checkout on the wrong branch" \
  "$(pwtest_script pw-worktree.sh)" create --project "$W47" --task T01 --repo api --base master
git -C "$PW_REPOS/api" worktree remove --force "$wp47" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$W47/other-branch" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$W47/T01-$W47" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$W47"
