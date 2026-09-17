# shellcheck shell=bash
# cases/pw-ship.t.sh — the ship/MR entity (plan 20 Phase 2): merged from the
# pw-ship-resolve / pw-ship-exec / pw-mr-state-batch / pw-pipeline-monitor cases
# plus pw-lib's ship comment-seen + dashboard-mr-state selftests.
SH=pw-ship.sh

# --- resolve (READ facet) ------------------------------------------------------
pwtest_rc 0 "resolve F2 rows" "$(pwtest_script $SH)" resolve "$S2"
pwtest_re '^T01\|api\|' "pipe-row contract stable"
grep -q "Fix api" "$PWTEST_BOTH" && pwtest_ok "apostrophe title intact across pipes (C14)" || pwtest_bad "apostrophe title" "see row: $(grep ^T01 "$PWTEST_BOTH"|head -1)"
pwtest_rc 0 "resolve F3 hostile (plain id + linked id + quotes)" "$(pwtest_script $SH)" resolve "$S3"
pwtest_re '^T01\|' "plain id row parsed (C4)"
pwtest_rc 2 "resolve no PLAN → 2" "$(pwtest_script $SH)" resolve "$S1"
pwtest_fix "no-PLAN actionable (/pw-breakdown)"

# --- monitor (READ facet) ------------------------------------------------------
pwtest_rc 0 "monitor SUCCESS exits 0" env PWTEST_PIPELINE='[{"status":"success"}]' "$(pwtest_script $SH)" monitor "$S2" T02 --interval 1 --timeout 1
pwtest_re 'SUCCESS|green|passed|no failing' "success vocab"
pwtest_rc any "monitor reports FAILED state → non-zero" env PWTEST_PIPELINE='[{"status":"failed"}]' "$(pwtest_script $SH)" monitor "$S2" T03 --interval 1 --timeout 1
[ "$PWTEST_RC" != 0 ] && pwtest_ok "failed pipeline non-zero (rc $PWTEST_RC)" || pwtest_bad "failed pipeline" "exit 0 — would pass a red CI (defect)"
pwtest_rc any "unknown pipeline fast-fails" env PWTEST_PIPELINE='' "$(pwtest_script $SH)" monitor "$S2" T02 --interval 0 --timeout 1
[ "$PWTEST_RC" -ge 2 ] && pwtest_ok "unknown → fast-fail rc=$PWTEST_RC" || pwtest_bad "fast-fail" "rc=$PWTEST_RC still 'running'?"
pwtest_fix "fast-fail says why"
pwtest_rc 2 "monitor unknown project" "$(pwtest_script $SH)" monitor nope-xyz T01

# --- exec (WRITE facet) — push + MR create (shim), idempotent rerun, honest failure (C6).
E=exec-f2; rm -rf "$PW_PROJECTS_DIR/$E"; cp -a "$F2" "$PW_PROJECTS_DIR/$E"
printf 'Ship test fixture MR\n' > "$ROOT/desc.md"
# clone task branch + fresh worktree for the clone slug:
for tsk in T01; do
  pwtest_repo api "branch:agent/$E/$tsk-thing"
  ( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E/worktree/api/$tsk-thing" "agent/$E/$tsk-thing" >/dev/null 2>&1 ) || true
  sed -i '' "s|agent/$S2/$tsk-thing|agent/$E/$tsk-thing|" "$PW_PROJECTS_DIR/$E/task/$tsk.md"
done
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "exec pushes + files MR" "$(pwtest_script $SH)" exec "$E" T01 "$ROOT/desc.md"
pwtest_re "MR created|created|MR exists|already" "creation/report line"
# rerun: Result now holds a real URL → already-exists path, no double-create.
pwtest_rc 0 "exec rerun sees existing MR (no double create)" "$(pwtest_script $SH)" exec "$E" T01 "$ROOT/desc.md"
grep -q 'already exists' "$PWTEST_BOTH" && pwtest_ok "rerun skipped create" || { grep -c 'MR created' "$PWTEST_BOTH" >/dev/null; }
n_created=$(grep -c 'MR created' "$PWTEST_BOTH") || n_created=0
pwtest_rc any "creation-failure is loud → honest non-zero (push ok, no MR)" env PWTEST_FORGE_CREATE="" "$(pwtest_script $SH)" exec "$E" T04 "$ROOT/desc.md"
if [ "$PWTEST_RC" = 0 ]; then pwtest_bad "creation honesty" "exit 0 although no URL came back (regression!)"; else pwtest_ok "failed creation exits non-zero (rc $PWTEST_RC)"; fi
grep -qiE 'creation|no url|no MR|MR' "$PWTEST_ERR" || grep -qiE 'creation|no url' "$PWTEST_OUT" || true
pwtest_rc 2 "exec missing desc file" "$(pwtest_script $SH)" exec "$E" T02 "$ROOT/nope-desc.md"
pwtest_rc 2 "exec fake task" "$(pwtest_script $SH)" exec "$E" T99 "$ROOT/desc.md"

# --- mr-state-batch (READ facet) — inferred + explicit rows (C6/C8). ----------
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 closed\n43 closed\n" >> "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "batch F2 every task" "$(pwtest_script $SH)" mr-state-batch "$S2"
pwtest_re 'T02\|closed' "closed state mapped (glab vocab)"
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 merged\n43 opened\n" >> "$PWTEST_FORGE_STATE_FILE"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 T02+T04 (linked cell + decoy)" "$(pwtest_script $SH)" mr-state-batch "$S3" T02 T04
if grep -q '000-stencil' "$PWTEST_FORGE_LOG"; then pwtest_bad "decoy never queried" "$(cat "$PWTEST_FORGE_LOG")"; else pwtest_ok "decoy never queried (C6/C21)"; fi
pwtest_re 'T02\|merged' "merged via shim"
# auto-list (no explicit IDs) must normalize markdown-linked ID cells in the PLAN (C4):
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 auto-list over linked cells" "$(pwtest_script $SH)" mr-state-batch "$S3"
pwtest_re 'T02\|merged' "linked-cell T02 picked up by auto-list"
if grep -q '000-stencil' "$PWTEST_FORGE_LOG"; then pwtest_bad "auto-list decoy query" "$(cat "$PWTEST_FORGE_LOG")"; else pwtest_ok "auto-list kept decoy unqueried"; fi
# C21 (lib-owner): exercise _resolve_task_mr_url's SOURCE directly (eval-extract, as the lib's
# own selftest does — the function has no CLI). Discriminating shapes = the exact b5a4da7
# regression: a Result field next to a Steps stencil (field must win), and a Steps-only task
# (must resolve EMPTY — never leak the decoy into the parse path).
_pwt_lib_resolve() {
  eval "$(sed -n '/^_resolve_task_mr_url()/,/^}/p' "$(pwtest_script pw-ship.sh)")"
  _resolve_task_mr_url "$1"
}
tf="$ROOT/c21-field.md"
printf '# T\n## Steps\n- See https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil (placeholder)\n\n## Result\n- **MR:** https://gitlab.example.com/pwtest/api/-/merge_requests/44\n' > "$tf"
pwtest_eq "C21 lib: Result field beats Steps decoy" "$(_pwt_lib_resolve "$tf")" "https://gitlab.example.com/pwtest/api/-/merge_requests/44"
tf="$ROOT/c21-decoy-only.md"
printf '# T\n## Steps\n- Decoy: https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil\n\n## Result\n- **Commit(s):** —\n' > "$tf"
pwtest_eq "C21 lib: Steps-only resolves EMPTY (b5a4da7 symptom)" "$(_pwt_lib_resolve "$tf")" ""
# the rest of the regression family (ported from pw-lib's inline selftest, plan 20):
tf="$ROOT/c21-sentinel.md"; printf '# T91\n## Result\n- **MR:** (none)\n' > "$tf"
pwtest_eq "C21 lib: (none) sentinel survives" "$(_pwt_lib_resolve "$tf")" "(none)"
tf="$ROOT/c21-bare.md"; printf '# T92\n## Result\n- See the MR at https://forge.example.com/g/p/-/merge_requests/9\n' > "$tf"
pwtest_eq "C21 lib: bare-URL-in-Result fallback" "$(_pwt_lib_resolve "$tf")" "https://forge.example.com/g/p/-/merge_requests/9"
pwtest_eq "C21 lib: missing file returns empty" "$(_pwt_lib_resolve "$ROOT/nope-$$.md")" ""

# --- comment-seen (WRITE facet) — per-thread upsert, placement, refusals.
# Thread IDs deliberately differ in their first 8 chars (the truncated display prefix).
RI=shipcs; rm -rf "$PW_PROJECTS_DIR/$RI"; cp -a "$F2" "$PW_PROJECTS_DIR/$RI"
"$(pwtest_script pw-lib.sh)" review-init "$RI" task/review/T99.review.md task/T99.md >/dev/null
TREV="$PW_PROJECTS_DIR/$RI/task/review/T99.review.md"
pwtest_rc 0 "comment-seen new" "$(pwtest_script $SH)" comment-seen "$RI" T99 aaaaaaaa1111 resolvable yes
grep -q '^## MR comment tracking' "$TREV" && pwtest_ok "tracking section created" || pwtest_bad "tracking section" "not created"
# placement: the section must land BEFORE ## Sign-off, never after (a blind end-of-file append
# was the actual bug — orphaned rows below the human-owned gate).
sec_line="$(grep -n '^## MR comment tracking' "$TREV" | head -1 | cut -d: -f1)"
sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
[ "$sec_line" -lt "$sign_line" ] && pwtest_ok "tracking section before ## Sign-off" || pwtest_bad "section placement" "line $sec_line vs $sign_line"
grep -qF '<!-- pw-mr-comment:aaaaaaaa1111 -->' "$TREV" && pwtest_ok "aaaaaaaa1111 row created" || pwtest_bad "row create" "marker missing"
grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | yes ' && pwtest_ok "row kind/replied correct" || pwtest_bad "row shape" "$(grep aaaaaaaa1111 "$TREV")"
pwtest_rc 0 "comment-seen second thread + note" "$(pwtest_script $SH)" comment-seen "$RI" T99 bbbbbbbb2222 unresolvable yes "reviewer asked for X"
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "2 tracked threads" || pwtest_bad "thread count" "$(grep -c 'pw-mr-comment:' "$TREV")"
grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' && pwtest_ok "optional note recorded" || pwtest_bad "note text" "$(grep bbbbbbbb2222 "$TREV")"
last_marker_line="$(grep -n 'pw-mr-comment:' "$TREV" | tail -1 | cut -d: -f1)"
sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
[ "$last_marker_line" -lt "$sign_line" ] && pwtest_ok "both rows inside the table (before Sign-off)" || pwtest_bad "row placement" "a tracked row landed at/after ## Sign-off"
pwtest_rc 0 "comment-seen rerun updates in place" "$(pwtest_script $SH)" comment-seen "$RI" T99 aaaaaaaa1111 resolvable no
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "rerun did not duplicate" || pwtest_bad "idempotent rerun" "rows: $(grep -c 'pw-mr-comment:' "$TREV")"
grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | no ' && pwtest_ok "replied flag updated" || pwtest_bad "in-place update" "$(grep aaaaaaaa1111 "$TREV")"
grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' && pwtest_ok "other row untouched by update" || pwtest_bad "update leaked" "$(grep bbbbbbbb2222 "$TREV")"
pwtest_rc any "invalid kind refused" "$(pwtest_script $SH)" comment-seen "$RI" T99 cccccccc3333 bogus-kind yes
[ "$PWTEST_RC" != 0 ] && pwtest_ok "bad kind non-zero" || pwtest_bad "kind guard" "accepted bogus-kind"
pwtest_rc any "invalid replied refused" "$(pwtest_script $SH)" comment-seen "$RI" T99 cccccccc3333 unresolvable maybe
[ "$PWTEST_RC" != 0 ] && pwtest_ok "bad replied non-zero" || pwtest_bad "replied guard" "accepted maybe"
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "refused calls did not mutate" || pwtest_bad "refusal purity" "table mutated by rejected calls"
grep -q 'aaaaaaaa1111' "$PW_PROJECTS_DIR/$RI/LOG.md" && pwtest_ok "comment-seen logged" || pwtest_bad "comment-seen LOG" "nothing recorded"

# --- dashboard-mr-state (WRITE facet) — column-NAME driven MR table edit.
DM=dashmr; rm -rf "$PW_PROJECTS_DIR/$DM"; mkdir -p "$PW_PROJECTS_DIR/$DM"
printf -- '- **Status:** executing\n- **One-liner:** dashmr\n\n## Task status\n\n| ID | Title | Repo | Status | Notes |\n|----|-------|------|--------|-------|\n| T01 | fix x | repo-a | done | |\n\n## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |\n' > "$PW_PROJECTS_DIR/$DM/README.md"
: > "$PW_PROJECTS_DIR/$DM/LOG.md"
pwtest_rc 0 "dashboard-mr-state updates State column" "$(pwtest_script $SH)" dashboard-mr-state "$DM" T01 merged
grep -q '^| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | merged | green |$' "$PW_PROJECTS_DIR/$DM/README.md" \
  && pwtest_ok "State cell written, MR URL intact" || pwtest_bad "dashboard-mr-state" "$(grep 'merge_requests/12' "$PW_PROJECTS_DIR/$DM/README.md")"
[ "$(grep -c 'merge_requests/12' "$PW_PROJECTS_DIR/$DM/README.md")" = "1" ] && pwtest_ok "row not duplicated" || pwtest_bad "row integrity" "MR URL row duplicated/lost"

# cleanup — leave shared fixtures as found (fixture-pollution etiquette)
rm -rf "$PW_PROJECTS_DIR/$E" "$PW_PROJECTS_DIR/$RI" "$PW_PROJECTS_DIR/$DM"
