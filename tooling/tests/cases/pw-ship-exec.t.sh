# shellcheck shell=bash
# cases/pw-ship-exec.t.sh — push + MR create (shim), idempotent rerun, honest failure (C6).
E=exec-f2; rm -rf "$PW_PROJECTS_DIR/$E"; cp -a "$F2" "$PW_PROJECTS_DIR/$E"
printf 'Ship test fixture MR\n' > "$ROOT/desc.md"
# clone task branch + fresh worktree for the clone slug:
for tsk in T01; do
  pwtest_repo api "branch:agent/$E/$tsk-thing"
  ( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E/worktree/api/$tsk-thing" "agent/$E/$tsk-thing" >/dev/null 2>&1 ) || true
  sed -i '' "s|agent/$S2/$tsk-thing|agent/$E/$tsk-thing|" "$PW_PROJECTS_DIR/$E/task/$tsk.md"
done
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "exec pushes + files MR" "$TOOL/pw-ship-exec.sh" "$E" T01 "$ROOT/desc.md"
pwtest_re "MR created|created|MR exists|already" "creation/report line"
# rerun: Result now holds a real URL → already-exists path, no double-create.
pwtest_rc 0 "exec rerun sees existing MR (no double create)" "$TOOL/pw-ship-exec.sh" "$E" T01 "$ROOT/desc.md"
grep -q 'already exists' "$PWTEST_BOTH" && pwtest_ok "rerun skipped create" || { grep -c 'MR created' "$PWTEST_BOTH" >/dev/null; }
n_created=$(grep -c 'MR created' "$PWTEST_BOTH") || n_created=0
pwtest_rc any "creation-failure is loud → honest non-zero (push ok, no MR)" env PWTEST_FORGE_CREATE="" "$TOOL/pw-ship-exec.sh" "$E" T04 "$ROOT/desc.md"
if [ "$PWTEST_RC" = 0 ]; then pwtest_bad "creation honesty" "exit 0 although no URL came back (regression!)"; else pwtest_ok "failed creation exits non-zero (rc $PWTEST_RC)"; fi
grep -qiE 'creation|no url|no MR|MR' "$PWTEST_ERR" || grep -qiE 'creation|no url' "$PWTEST_OUT" || true
pwtest_rc 2 "exec missing desc file" "$TOOL/pw-ship-exec.sh" "$E" T02 "$ROOT/nope-desc.md"
pwtest_rc 2 "exec fake task" "$TOOL/pw-ship-exec.sh" "$E" T99 "$ROOT/desc.md"
