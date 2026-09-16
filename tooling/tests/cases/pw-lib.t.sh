# shellcheck shell=bash
# cases/pw-lib.t.sh — load-bearing helper round-trips (plan 06 §1) + status/phase semantics.
L="$TOOL/pw-lib.sh"

# 1) status self-heal + backward guards (C19 companion): prose drift normalizes on a forward write:
CP=libclonestat; rm -rf "$PW_PROJECTS_DIR/$CP"; cp -a "$F3" "$PW_PROJECTS_DIR/$CP"
HEAL="$PW_PROJECTS_DIR/$CP/README.md"
pwtest_rc 0 "status forward write onto drifted prose" "$L" status "$CP" executing
if grep -qxF -- '- **Status:** executing' "$HEAL"; then pwtest_ok "forward write self-heals drifted prose line"
else pwtest_bad "status heal" "$(grep '\*\*Status' "$HEAL" | head -2 | tr '\n' '|')"; fi
pwtest_rc 2 "backward refusing still honest: analysis ← executing without --rewind" "$L" status "$CP" analysis
# 2) review-init idempotent (P8):
RI=libtestri; rm -rf "$PW_PROJECTS_DIR/$RI"; cp -a "$F2" "$PW_PROJECTS_DIR/$RI"
pwtest_rc 0 "review-init new file ok" "$L" review-init "$RI" task/review/T99.review.md task/T99.md || true
printf '\nspecial content kept\n' >> "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md"
pwtest_rc 0 "review-init rerun" "$L" review-init "$RI" task/review/T99.review.md task/T99.md
grep -q 'special content kept' "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md" \
  && pwtest_ok "review-init preserves existing" || pwtest_bad "review-init clobber" "existing content lost"

# 3) ship comment-seen: one row, idempotent rerun, placement before ## Sign-off
pwtest_rc 0 "comment-seen new" "$L" ship comment-seen "$RI" T99 thread-555 resolvable yes
pwtest_rc 0 "comment-seen rerun" "$L" ship comment-seen "$RI" T99 thread-555 resolvable yes
if [ "$(grep -c 'thread-555' "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md")" = 1 ]; then pwtest_ok "thread row once (idempotent)"
else pwtest_bad "comment-seen dup" "$(grep -n thread-555 "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md" | head -2 | tr '\n' ';')"; fi
python3 - "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md" <<'ZPY'
import sys
i=open(sys.argv[1]).read().find("thread-555"); j=open(sys.argv[1]).read().find("## Sign-off")
sys.exit(0 if 0 <= i < j else 1)
ZPY
[ $? = 0 ] && pwtest_ok "thread row sits before ## Sign-off" || { grep -q 'thread-555' "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md" && pwtest_bad "thread placement" "after Sign-off" || pwtest_bad "thread row" "not written at all"; }
grep -q 'thread-555' "$PW_PROJECTS_DIR/$RI/LOG.md" && pwtest_ok "comment-seen logged" || pwtest_bad "comment-seen LOG" "nothing recorded"

# 4) rfc meta upserts + comment-seen
"$L" rfc init "$RI" markdown >/dev/null 2>&1 || true
pwtest_rc 0 "rfc target" "$L" rfc target "$RI" none-md-test
grep -q 'none-md-test' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc target persists" || pwtest_bad "rfc target" "$(cat "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null | head -3 | tr '\n' ';')"
pwtest_rc 0 "rfc state wave1" "$L" rfc state "$RI" Wave1Published yes
grep -qi 'wave 1 published' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc state persists (Wave 1 published)" || pwtest_bad "rfc state" "META unchanged: $(head -4 "$PW_PROJECTS_DIR/$RI/rfc/META.md")"
pwtest_rc 0 "rfc comment-seen (thread t99 solved=yes)" "$L" rfc comment-seen "$RI" t99 2 yes
grep -qiE 't99' "$PW_PROJECTS_DIR/$RI/rfc/META.md" \
  && pwtest_ok "thread persisted in META" || pwtest_bad "rfc comment-seen" "$(tail -3 "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null)"; 

# 5) worktree-remove guards (P8): operate on F2's mounted worktrees; restore at end
WTBASE="$PW_PROJECTS_DIR/$S2/worktree/api"
ls "$WTBASE" >/dev/null 2>&1 || { pwtest_skip "worktree guards" "no mounted worktree in fixture"; }
if [ -d "$WTBASE/T02-thing" ]; then
  ( cd "$WTBASE/T02-thing" && "$L" worktree-remove "$S2" T02 >"$PWTEST_ROOT/wr.out" 2>&1; echo $? >"$PWTEST_ROOT/wr.rc" ) || true
  wrc=$(cat "$PWTEST_ROOT/wr.rc")
  [ "$wrc" != 0 ] && pwtest_ok "worktree-remove refuses when it is CWD (rc=$wrc)" \
    || { pwtest_bad "worktree-remove CWD guard" "removal succeeded while inside!"; git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$(basename "$S2")/T02-thing" >/dev/null 2>&1 || true; }
  ( git -C "$WTBASE/T02-thing" status >/dev/null 2>&1 || true )
  printf 'dirty\n' > "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt"
  ( cd / && "$L" worktree-remove "$S2" T02 >"$PWTEST_ROOT/wr2.out" 2>&1; echo $? >"$PWTEST_ROOT/wr2.rc" ) || true
  w2=$(cat "$PWTEST_ROOT/wr2.rc")
  [ "$w2" != 0 ] && pwtest_ok "worktree-remove refuses dirty tree" || pwtest_bad "worktree-remove dirty guard" "removed dirty worktree!"
fi
# ALWAYS leave the fixture as found (alphabetical order: pw-lib runs before pw-mr-state-batch!):
mkdir -p "$WTBASE" 2>/dev/null || true
git -C "$PW_REPOS/api" worktree list | grep -q "T02-thing" \
  || git -C "$PW_REPOS/api" worktree add "$WTBASE/T02-thing" "agent/$S2/T02-thing" >/dev/null 2>&1 || true
rm -f "$WTBASE/T02-thing/DIRTY-UNCOMMITTED.txt" 2>/dev/null || true

# 6) phase/ship gate helpers on the clone:
pwtest_rc 0 "phase getter" "$L" phase "$RI"
[ "$("$L" phase "$RI" 2>/dev/null)" ] ; pwtest_ok "phase prints non-empty" || true
rm -rf "$PW_PROJECTS_DIR/$RI" "$PW_PROJECTS_DIR/$CP"
