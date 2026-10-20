# shellcheck shell=bash
# cases/pw-ship.t.sh — the ship/MR entity (plan 20 Phase 2): merged from the
# pw-ship-resolve / pw-ship-exec / pw-mr-state-batch / pw-pipeline-monitor cases
# plus pw-lib's ship comment-seen + dashboard-mr-state selftests.
SH=pw-ship.sh

# --- resolve (READ facet) ------------------------------------------------------
pwtest_rc 0 "resolve F2 rows" "$(pwtest_script $SH)" resolve --project "$S2"
pwtest_re '^T01\|api\|' "pipe-row contract stable"
grep -q "Fix api" "$PWTEST_BOTH" && pwtest_ok "apostrophe title intact across pipes (C14)" || pwtest_bad "apostrophe title" "see row: $(grep ^T01 "$PWTEST_BOTH"|head -1)"
pwtest_rc 0 "resolve F3 hostile (plain id + linked id + quotes)" "$(pwtest_script $SH)" resolve --project "$S3"
pwtest_re '^T01\|' "plain id row parsed (C4)"
pwtest_rc 2 "resolve no PLAN → 2" "$(pwtest_script $SH)" resolve --project "$S1"
pwtest_fix "no-PLAN actionable (/pw-breakdown)"

# --- monitor (READ facet) ------------------------------------------------------
pwtest_rc 0 "monitor SUCCESS exits 0" env PWTEST_PIPELINE='[{"status":"success"}]' "$(pwtest_script $SH)" monitor --project "$S2" --task T02 --interval 1 --timeout 1
pwtest_re 'SUCCESS|green|passed|no failing' "success vocab"
pwtest_rc any "monitor reports FAILED state → non-zero" env PWTEST_PIPELINE='[{"status":"failed"}]' "$(pwtest_script $SH)" monitor --project "$S2" --task T03 --interval 1 --timeout 1
[ "$PWTEST_RC" != 0 ] && pwtest_ok "failed pipeline non-zero (rc $PWTEST_RC)" || pwtest_bad "failed pipeline" "exit 0 — would pass a red CI (defect)"
pwtest_rc any "unknown pipeline fast-fails" env PWTEST_PIPELINE='' "$(pwtest_script $SH)" monitor --project "$S2" --task T02 --interval 0 --timeout 1
[ "$PWTEST_RC" -ge 2 ] && pwtest_ok "unknown → fast-fail rc=$PWTEST_RC" || pwtest_bad "fast-fail" "rc=$PWTEST_RC still 'running'?"
pwtest_fix "fast-fail says why"
pwtest_rc 2 "monitor unknown project" "$(pwtest_script $SH)" monitor --project nope-xyz --task T01

# --- monitor races (head-sha selection + skipped semantics; live incident 2026-09-23) ---
# shim reports MR head sha = dead000f (tests/bin/glab _state_json)
pwtest_rc 0 "branch-skipped before MR-success same sha → SUCCESS" env PWTEST_PIPELINE='[{"sha":"dead000f","status":"skipped"},{"sha":"dead000f","status":"success"}]' "$(pwtest_script $SH)" monitor --project "$S2" --task T02 --interval 1 --timeout 1
pwtest_rc 0 "all-skipped after grace → neutral SKIPPED, exit 0" env PWTEST_PIPELINE='[{"sha":"dead000f","status":"skipped"}]' "$(pwtest_script $SH)" monitor --project "$S2" --task T02 --interval 1 --timeout 2
pwtest_re 'SKIPPED' "skipped vocab (not FAILED)"
pwtest_rc 2 "stale pipeline on old sha not claimed while head has none" env PWTEST_PIPELINE='[{"sha":"aaaa1111","status":"success"}]' "$(pwtest_script $SH)" monitor --project "$S2" --task T02 --interval 1 --timeout 1

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
pwtest_rc 0 "exec pushes + files MR" "$(pwtest_script $SH)" exec --project "$E" --task T01 --file "$ROOT/desc.md"
pwtest_re "MR created|created|MR exists|already" "creation/report line"
# rerun: Result now holds a real URL → already-exists path, no double-create.
pwtest_rc 0 "exec rerun sees existing MR (no double create)" "$(pwtest_script $SH)" exec --project "$E" --task T01 --file "$ROOT/desc.md"
grep -q 'already exists' "$PWTEST_BOTH" && pwtest_ok "rerun skipped create" || { grep -c 'MR created' "$PWTEST_BOTH" >/dev/null; }
n_created=$(grep -c 'MR created' "$PWTEST_BOTH") || n_created=0
pwtest_rc any "creation-failure is loud → honest non-zero (push ok, no MR)" env PWTEST_FORGE_CREATE="" "$(pwtest_script $SH)" exec --project "$E" --task T04 --file "$ROOT/desc.md"
if [ "$PWTEST_RC" = 0 ]; then pwtest_bad "creation honesty" "exit 0 although no URL came back (regression!)"; else pwtest_ok "failed creation exits non-zero (rc $PWTEST_RC)"; fi
grep -qiE 'creation|no url|no MR|MR' "$PWTEST_ERR" || grep -qiE 'creation|no url' "$PWTEST_OUT" || true
pwtest_rc 2 "exec missing desc file" "$(pwtest_script $SH)" exec --project "$E" --task T02 --file "$ROOT/nope-desc.md"
pwtest_rc 2 "exec fake task" "$(pwtest_script $SH)" exec --project "$E" --task T99 --file "$ROOT/desc.md"

# --- mr-state-batch (READ facet) — inferred + explicit rows (C6/C8). ----------
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 closed\n43 closed\n" >> "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "batch F2 every task" "$(pwtest_script $SH)" mr-state-batch --project "$S2"
pwtest_re 'T02\|closed' "closed state mapped (glab vocab)"
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 merged\n43 opened\n" >> "$PWTEST_FORGE_STATE_FILE"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 T02+T04 (linked cell + decoy)" "$(pwtest_script $SH)" mr-state-batch --project "$S3" --task T02 --task T04
if grep -q '000-stencil' "$PWTEST_FORGE_LOG"; then pwtest_bad "decoy never queried" "$(cat "$PWTEST_FORGE_LOG")"; else pwtest_ok "decoy never queried (C6/C21)"; fi
pwtest_re 'T02\|merged' "merged via shim"
# auto-list (no explicit IDs) must normalize markdown-linked ID cells in the PLAN (C4):
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 auto-list over linked cells" "$(pwtest_script $SH)" mr-state-batch --project "$S3"
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
"$(pwtest_script pw-review.sh)" init --project "$RI" --file task/review/T99.review.md --doc task/T99.md >/dev/null
TREV="$PW_PROJECTS_DIR/$RI/task/review/T99.review.md"
pwtest_rc 0 "comment-seen new" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread aaaaaaaa1111 --kind resolvable --replied yes
grep -q '^## MR comment tracking' "$TREV" && pwtest_ok "tracking section created" || pwtest_bad "tracking section" "not created"
# placement: the section must land BEFORE ## Sign-off, never after (a blind end-of-file append
# was the actual bug — orphaned rows below the human-owned gate).
sec_line="$(grep -n '^## MR comment tracking' "$TREV" | head -1 | cut -d: -f1)"
sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
[ "$sec_line" -lt "$sign_line" ] && pwtest_ok "tracking section before ## Sign-off" || pwtest_bad "section placement" "line $sec_line vs $sign_line"
grep -qF '<!-- pw-mr-comment:aaaaaaaa1111 -->' "$TREV" && pwtest_ok "aaaaaaaa1111 row created" || pwtest_bad "row create" "marker missing"
grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | yes ' && pwtest_ok "row kind/replied correct" || pwtest_bad "row shape" "$(grep aaaaaaaa1111 "$TREV")"
pwtest_rc 0 "comment-seen second thread + note" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread bbbbbbbb2222 --kind unresolvable --replied yes --note "reviewer asked for X"
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "2 tracked threads" || pwtest_bad "thread count" "$(grep -c 'pw-mr-comment:' "$TREV")"
grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' && pwtest_ok "optional note recorded" || pwtest_bad "note text" "$(grep bbbbbbbb2222 "$TREV")"
last_marker_line="$(grep -n 'pw-mr-comment:' "$TREV" | tail -1 | cut -d: -f1)"
sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
[ "$last_marker_line" -lt "$sign_line" ] && pwtest_ok "both rows inside the table (before Sign-off)" || pwtest_bad "row placement" "a tracked row landed at/after ## Sign-off"
pwtest_rc 0 "comment-seen rerun updates in place" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread aaaaaaaa1111 --kind resolvable --replied no
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "rerun did not duplicate" || pwtest_bad "idempotent rerun" "rows: $(grep -c 'pw-mr-comment:' "$TREV")"
grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | no ' && pwtest_ok "replied flag updated" || pwtest_bad "in-place update" "$(grep aaaaaaaa1111 "$TREV")"
grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' && pwtest_ok "other row untouched by update" || pwtest_bad "update leaked" "$(grep bbbbbbbb2222 "$TREV")"
pwtest_rc any "invalid kind refused" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread cccccccc3333 --kind bogus-kind --replied yes
[ "$PWTEST_RC" != 0 ] && pwtest_ok "bad kind non-zero" || pwtest_bad "kind guard" "accepted bogus-kind"
pwtest_rc any "invalid replied refused" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread cccccccc3333 --kind unresolvable --replied maybe
[ "$PWTEST_RC" != 0 ] && pwtest_ok "bad replied non-zero" || pwtest_bad "replied guard" "accepted maybe"
[ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] && pwtest_ok "refused calls did not mutate" || pwtest_bad "refusal purity" "table mutated by rejected calls"
grep -q 'aaaaaaaa1111' "$PW_PROJECTS_DIR/$RI/LOG.md" && pwtest_ok "comment-seen logged" || pwtest_bad "comment-seen LOG" "nothing recorded"

# --- comment-seen evidence marker (opt-in resolution support) — optional --feedback/--reply/--head
# record the handled revision + reply id + verified head so a rerun can skip an unchanged handled
# thread and a later `--resolve` can close it without re-fixing.
pwtest_rc 0 "comment-seen evidence flags" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread dddddddd4444 --kind resolvable --replied yes --feedback note-778 --reply 991 --head abc1234
grep 'pw-mr-comment:dddddddd4444' "$TREV" | grep -q 'pw-mr-ev:dddddddd4444;f=note-778;r=991;h=abc1234' \
  && pwtest_ok "evidence marker recorded" || pwtest_bad "evidence marker" "$(grep dddddddd4444 "$TREV")"
pwtest_rc 0 "comment-seen evidence rerun" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread dddddddd4444 --kind resolvable --replied yes --feedback note-779 --reply 992 --head def5678
[ "$(grep -c 'pw-mr-comment:dddddddd4444' "$TREV")" = "1" ] && pwtest_ok "evidence rerun no duplicate" || pwtest_bad "evidence rerun" "row duplicated"
grep 'pw-mr-comment:dddddddd4444' "$TREV" | grep -q 'pw-mr-ev:dddddddd4444;f=note-779;r=992;h=def5678' \
  && pwtest_ok "evidence marker updated in place" || pwtest_bad "evidence update" "$(grep dddddddd4444 "$TREV")"
grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q 'pw-mr-ev:' \
  && pwtest_bad "legacy row shape" "a plain call grew an evidence marker" || pwtest_ok "plain call keeps the legacy row shape"
pwtest_rc any "evidence token injection refused" "$(pwtest_script $SH)" comment-seen --project "$RI" --task T99 --thread eeeeeeee5555 --kind resolvable --replied yes --head 'abc|xyz'
[ "$PWTEST_RC" != 0 ] && pwtest_ok "hostile evidence non-zero" || pwtest_bad "evidence guard" "accepted a pipe in --head"
grep -q 'eeeeeeee5555' "$TREV" && pwtest_bad "refusal purity" "a refused evidence call wrote a row" || pwtest_ok "refused evidence call wrote nothing"

# --- dashboard-mr-state (WRITE facet) — column-NAME driven MR table edit.
DM=dashmr; rm -rf "$PW_PROJECTS_DIR/$DM"; mkdir -p "$PW_PROJECTS_DIR/$DM"
printf -- '- **Status:** executing\n- **One-liner:** dashmr\n\n## Task status\n\n| ID | Title | Repo | Status | Notes |\n|----|-------|------|--------|-------|\n| T01 | fix x | repo-a | done | |\n\n## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |\n' > "$PW_PROJECTS_DIR/$DM/README.md"
: > "$PW_PROJECTS_DIR/$DM/LOG.md"
pwtest_rc 0 "dashboard-mr-state updates State column" "$(pwtest_script $SH)" dashboard-mr-state --project "$DM" --task T01 --state merged
grep -q '^| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | merged | green |$' "$PW_PROJECTS_DIR/$DM/README.md" \
  && pwtest_ok "State cell written, MR URL intact" || pwtest_bad "dashboard-mr-state" "$(grep 'merge_requests/12' "$PW_PROJECTS_DIR/$DM/README.md")"
[ "$(grep -c 'merge_requests/12' "$PW_PROJECTS_DIR/$DM/README.md")" = "1" ] && pwtest_ok "row not duplicated" || pwtest_bad "row integrity" "MR URL row duplicated/lost"

# cleanup — leave shared fixtures as found (fixture-pollution etiquette)
rm -rf "$PW_PROJECTS_DIR/$E" "$PW_PROJECTS_DIR/$RI" "$PW_PROJECTS_DIR/$DM"

# --- resolve: own-work / inherited-only / missing base / accepted (plan 47 F01-F03,F11) --------
# Dedicated fixture with LOCAL-ONLY branches (never pushed) and an accepted-no-MR task: the shared
# F2 repo already pushes its branches, so it cannot tell a local-ref read from a remote-ref read.
R47="resolve47"; rm -rf "$PW_PROJECTS_DIR/$R47"; cp -a "$F2" "$PW_PROJECTS_DIR/$R47"
RP="$PW_PROJECTS_DIR/$R47"
pwtest_repo r47
( cd "$PW_REPOS/r47"
  git checkout -q -b "agent/$R47/T01-thing" master
  echo own1 > own1.txt; git add -A; git -c user.email=t@t -c user.name=t commit -qm "own work T01"
  git checkout -q -b "agent/$R47/T02-thing" "agent/$R47/T01-thing"   # identical to the parent head
  git checkout -q -b "agent/$R47/T05-thing" master
  echo own5 > own5.txt; git add -A; git -c user.email=t@t -c user.name=t commit -qm "own work T05"
  git checkout -q master ) >/dev/null 2>&1
rm -f "$RP/task/T01.md" "$RP/task/T02.md" "$RP/task/T05.md"
pwtest_fill_task "$RP" T01 done     "-" "Own work"             r47 master
pwtest_fill_task "$RP" T02 done     "-" "Inherited only"       r47 master
pwtest_fill_task "$RP" T05 accepted "-" "Accepted unpublished" r47 master
sed -i '' 's@^- \*\*Stacked on:\*\* .*@- **Stacked on:** T01@' "$RP/task/T02.md"
python3 - "$RP/task/PLAN.md" <<'PLANEOF'
import re,sys
f=sys.argv[1]
t=open(f).read()
rows=("| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |\n"
      "|----|-------|------|------------|-------|--------------|----|--------|------|--------|\n"
      "| [T01](./T01.md) | Own work | r47 | — | G1 | kilotest/test-model | 1 | done | — | — |\n"
      "| [T02](./T02.md) | Inherited only | r47 | T01 | G1 | kilotest/test-model | 1 | done | — | — |\n"
      "| [T05](./T05.md) | Accepted unpublished | r47 | — | G1 | kilotest/test-model | 1 | accepted | — | — |\n")
hdr=re.search(r'^\| ID \| Title \|.*\n\|[-| ]+\n', t, re.M)
if hdr:
    tail=re.match(r'(?:\|[^\n]*\n?)+', t[hdr.end():])
    t=t[:hdr.start()]+rows+t[(hdr.end()+tail.end()) if tail else hdr.end():]
open(f,"w").write(t)
PLANEOF
R47OUT="$("$(pwtest_script $SH)" resolve --project "$R47" 2>"$PWTEST_ROOT/r47.err")"; R47RC=$?
[ "$R47RC" = 0 ] && pwtest_ok "resolve rc 0 on the own-work fixture" \
  || pwtest_bad "resolve fixture rc" "rc=$R47RC: $(cat "$PWTEST_ROOT/r47.err")"
printf '%s\n' "$R47OUT" | grep -q "^T01|r47|agent/$R47/T01-thing|master|.*|yes|no$" \
  && pwtest_ok "F01 local-only work resolves has-commits=yes" \
  || pwtest_bad "F01 local-only" "rows: $(printf '%s' "$R47OUT" | tr '\n' ';')"
printf '%s\n' "$R47OUT" | grep -q "^T02|r47|.*|no|no$" \
  && pwtest_ok "F02 inherited-only child excluded (has-commits=no)" \
  || pwtest_bad "F02 inherited-only" "rows: $(printf '%s' "$R47OUT" | tr '\n' ';')"
printf '%s\n' "$R47OUT" | grep -q "^T05|r47|.*|yes|no$" \
  && pwtest_ok "F11 accepted-no-MR task is eligible" \
  || pwtest_bad "F11 accepted" "rows: $(printf '%s' "$R47OUT" | tr '\n' ';')"

# F03: a candidate whose comparison BASE cannot resolve must fail loudly with → fix and NO rows.
rm -f "$RP/task/T06.md"
pwtest_fill_task "$RP" T06 done "-" "Missing base" r47 "no-such-base-47"
( cd "$PW_REPOS/r47"; git checkout -q -b "agent/$R47/T06-thing" master; git checkout -q master ) >/dev/null 2>&1
python3 - "$RP/task/PLAN.md" <<'PLANEOF'
import re,sys
f=sys.argv[1]
t=open(f).read()
row="| [T06](./T06.md) | Missing base | r47 | — | G1 | kilotest/test-model | 1 | done | — | — |\n"
out=[]
for ln in t.splitlines(True):
    out.append(ln)
    if re.match(r'\| \[T05\]', ln):
        out.append(row)
open(f,"w").write("".join(out))
PLANEOF
R47B="$("$(pwtest_script $SH)" resolve --project "$R47" 2>"$PWTEST_ROOT/r47b.err")"; R47BRC=$?
[ "$R47BRC" = 2 ] && pwtest_ok "F03 unresolved base → exit 2" || pwtest_bad "F03 rc" "rc=$R47BRC"
[ -z "$R47B" ] && pwtest_ok "F03 emits no partial shipment list" \
  || pwtest_bad "F03 partial list" "$(printf '%s' "$R47B" | head -2)"
grep -q "fix:" "$PWTEST_ROOT/r47b.err" && pwtest_ok "F03 names a → fix remedy" \
  || pwtest_bad "F03 remedy" "$(cat "$PWTEST_ROOT/r47b.err")"
rm -rf "$PW_PROJECTS_DIR/$R47"

# --- forge routing + CI identity + current Result record (plan 47 F05,F07,F09,F10) --------------
# F05/F09: a PRETTY-PRINTED MR body must still yield the head sha, so an old-head green pipeline
# cannot certify a build whose head has no pipeline yet; the unresolved timeout must then REPLACE
# a previous SUCCESS in the current record.
M47=mon47; rm -rf "$PW_PROJECTS_DIR/$M47"; cp -a "$F2" "$PW_PROJECTS_DIR/$M47"
python3 - "$PW_PROJECTS_DIR/$M47/task/T02.md" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("- **Build check:** —","- **Build check:** SUCCESS",1)
open(f,"w").write(t)
PYEOF
pwtest_rc 2 "F05 pretty JSON head still selects by sha (stale green not claimed)" \
  env PWTEST_MR_PRETTY=1 PWTEST_PIPELINE='[
    { "sha": "aaaa1111", "status": "success" }
  ]' "$(pwtest_script $SH)" monitor --project "$M47" --task T02 --interval 1 --timeout 1
grep -qE 'Build check:.*UNRESOLVED' "$PW_PROJECTS_DIR/$M47/task/T02.md" \
  && pwtest_ok "F09 timeout records the unresolved observation" \
  || pwtest_bad "F09 timeout record" "$(grep -i 'build check' "$PW_PROJECTS_DIR/$M47/task/T02.md")"
grep -qiE 'build check:.*SUCCESS' "$PW_PROJECTS_DIR/$M47/task/T02.md" \
  && pwtest_bad "F09 stale SUCCESS must not stay current" "$(grep -i 'build check' "$PW_PROJECTS_DIR/$M47/task/T02.md")" \
  || pwtest_ok "F09 stale SUCCESS replaced by the latest observation"
rm -rf "$PW_PROJECTS_DIR/$M47"

# F10: a decoy `Build check:` line OUTSIDE ## Result must never be the one rewritten.
BC=bcdecoy; rm -rf "$PW_PROJECTS_DIR/$BC"; cp -a "$F2" "$PW_PROJECTS_DIR/$BC"
python3 - "$PW_PROJECTS_DIR/$BC/task/T02.md" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
# Insert before the REAL Result section heading (line-anchored: an earlier "## Result"
# mention lives inside prose, and inserting there would not create a parseable decoy line).
t=t.replace("\n## Result", "\n- Build check: DECOY-OUTSIDE\n\n## Result", 1)
open(f,"w").write(t)
PYEOF
pwtest_rc 0 "monitor success on the decoy project" \
  env PWTEST_PIPELINE='[{"sha":"dead000f","status":"success"}]' "$(pwtest_script $SH)" monitor --project "$BC" --task T02 --interval 1 --timeout 1
grep -q 'Build check: DECOY-OUTSIDE' "$PW_PROJECTS_DIR/$BC/task/T02.md" \
  && pwtest_ok "F10 decoy outside Result left untouched" \
  || pwtest_bad "F10 decoy rewritten" "$(grep -i 'build check' "$PW_PROJECTS_DIR/$BC/task/T02.md")"
grep -qE 'Build check:.*SUCCESS' "$PW_PROJECTS_DIR/$BC/task/T02.md" \
  && pwtest_ok "F10 current Result record updated" \
  || pwtest_bad "F10 Result record" "$(grep -i 'build check' "$PW_PROJECTS_DIR/$BC/task/T02.md")"
rm -rf "$PW_PROJECTS_DIR/$BC"

# F07: an exact PW_FORGE_HOSTS entry routes exec to the configured forge (not a substring guess).
E2=exec-f2gh; rm -rf "$PW_PROJECTS_DIR/$E2"; cp -a "$F2" "$PW_PROJECTS_DIR/$E2"
pwtest_repo api "branch:agent/$E2/T01-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E2/worktree/api/T01-thing" "agent/$E2/T01-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T01-thing|agent/$E2/T01-thing|" "$PW_PROJECTS_DIR/$E2/task/T01.md"
: > "$ROOT/forge47.log"
pwtest_rc 0 "F07 exec honors an exact PW_FORGE_HOSTS mapping" \
  env PWTEST_FORGE_LOG="$ROOT/forge47.log" PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.forge.sh" \
  "$(pwtest_script $SH)" exec --project "$E2" --task T01 --file "$ROOT/desc.md"
grep -q '^gh pr create' "$ROOT/forge47.log" \
  && pwtest_ok "F07 configured forge (github) drove MR creation" \
  || pwtest_bad "F07 forge choice" "$(tr '\n' ';' < "$ROOT/forge47.log" 2>/dev/null)"
grep -q '^glab ' "$ROOT/forge47.log" \
  && pwtest_bad "F07 must not fall back to glab" "$(cat "$ROOT/forge47.log")" \
  || pwtest_ok "F07 no glab fallback under the configured forge"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E2/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E2/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E2"

# --- creation capability + Result-scoped MR write (plan 47 F12,F14) ------------------------------
# F12: a glab release WITHOUT `mr create --output json` must still create — the capability probe
# runs before the push and selects the supported (plain) invocation.
E3=exec-f2cap; rm -rf "$PW_PROJECTS_DIR/$E3"; cp -a "$F2" "$PW_PROJECTS_DIR/$E3"
pwtest_repo api "branch:agent/$E3/T01-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E3/worktree/api/T01-thing" "agent/$E3/T01-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T01-thing|agent/$E3/T01-thing|" "$PW_PROJECTS_DIR/$E3/task/T01.md"
: > "$ROOT/forge47cap.log"
pwtest_rc 0 "F12 create succeeds on a CLI without --output json" \
  env PWTEST_GLAB_CREATE_NO_OUTPUT=1 PWTEST_FORGE_LOG="$ROOT/forge47cap.log" \
  "$(pwtest_script $SH)" exec --project "$E3" --task T01 --file "$ROOT/desc.md"
grep -q -- '--output' "$ROOT/forge47cap.log" \
  && pwtest_bad "F12 unsupported flag still sent" "$(cat "$ROOT/forge47cap.log")" \
  || pwtest_ok "F12 unsupported flag never sent to the installed CLI"
grep -q 'merge_requests/' "$PW_PROJECTS_DIR/$E3/task/T01.md" \
  && pwtest_ok "F12 created MR recorded from plain output" \
  || pwtest_bad "F12 result record" "$(grep -i 'MR:' "$PW_PROJECTS_DIR/$E3/task/T01.md")"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E3/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E3/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E3"

# F14: an MR-looking line OUTSIDE ## Result must not be the one rewritten.
E4=exec-f2decoy; rm -rf "$PW_PROJECTS_DIR/$E4"; cp -a "$F2" "$PW_PROJECTS_DIR/$E4"
pwtest_repo api "branch:agent/$E4/T01-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E4/worktree/api/T01-thing" "agent/$E4/T01-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T01-thing|agent/$E4/T01-thing|" "$PW_PROJECTS_DIR/$E4/task/T01.md"
python3 - "$PW_PROJECTS_DIR/$E4/task/T01.md" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("\n## Result", "\n- **MR:** https://decoy.example.com/g/p/-/merge_requests/999\n\n## Result", 1)
open(f,"w").write(t)
PYEOF
pwtest_rc 0 "F14 exec creates with an outside-Result MR decoy" \
  "$(pwtest_script $SH)" exec --project "$E4" --task T01 --file "$ROOT/desc.md"
grep -q 'merge_requests/999' "$PW_PROJECTS_DIR/$E4/task/T01.md" \
  && pwtest_ok "F14 outside-Result decoy untouched" \
  || pwtest_bad "F14 decoy rewritten" "$(grep -i 'MR:' "$PW_PROJECTS_DIR/$E4/task/T01.md")"
awk '/^## Result/{p=1} /^## / && !/^## Result/{p=0} p && /merge_requests\/[0-9]+/ && !/999/{f=1} END{exit(f?0:1)}' "$PW_PROJECTS_DIR/$E4/task/T01.md" \
  && pwtest_ok "F14 created URL recorded inside Result" \
  || pwtest_bad "F14 Result record" "$(grep -i 'MR:' "$PW_PROJECTS_DIR/$E4/task/T01.md")"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E4/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E4/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E4"

# F23: a continuation write must not reopen a merged/closed MR.
E5=exec-f2closed; rm -rf "$PW_PROJECTS_DIR/$E5"; cp -a "$F2" "$PW_PROJECTS_DIR/$E5"
pwtest_repo api "branch:agent/$E5/T02-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E5/worktree/api/T02-thing" "agent/$E5/T02-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T02-thing|agent/$E5/T02-thing|" "$PW_PROJECTS_DIR/$E5/task/T02.md"
printf '42 closed\n' > "$ROOT/forge47closed.txt"
pwtest_rc 0 "F23 continuation on a closed MR succeeds" \
  env PWTEST_FORGE_STATE_FILE="$ROOT/forge47closed.txt" \
  "$(pwtest_script $SH)" exec --project "$E5" --task T02 --file "$ROOT/desc.md"
grep -qE '^\| T02 .*\| closed \|' "$PW_PROJECTS_DIR/$E5/README.md" \
  && pwtest_ok "F23 closed MR stays terminal in the dashboard" \
  || pwtest_bad "F23 dashboard state" "$(grep '^| T02 ' "$PW_PROJECTS_DIR/$E5/README.md")"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E5/worktree/api/T02-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E5/T02-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E5"

# F13: an MR already existing for the source branch is adopted, never duplicated.
E6=exec-f2found; rm -rf "$PW_PROJECTS_DIR/$E6"; cp -a "$F2" "$PW_PROJECTS_DIR/$E6"
pwtest_repo api "branch:agent/$E6/T01-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E6/worktree/api/T01-thing" "agent/$E6/T01-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T01-thing|agent/$E6/T01-thing|" "$PW_PROJECTS_DIR/$E6/task/T01.md"
printf '%s %s\n' "agent/$E6/T01-thing" "https://gitlab.example.com/pwtest/api/-/merge_requests/77" > "$ROOT/mrlist47.txt"
: > "$ROOT/forge47found.log"
pwtest_rc 0 "F13 existing MR reconciled without a duplicate create" \
  env PWTEST_MR_LIST_FILE="$ROOT/mrlist47.txt" PWTEST_FORGE_LOG="$ROOT/forge47found.log" \
  "$(pwtest_script $SH)" exec --project "$E6" --task T01 --file "$ROOT/desc.md"
grep -q '^glab mr create --source-branch' "$ROOT/forge47found.log" \
  && pwtest_bad "F13 duplicate create issued" "$(cat "$ROOT/forge47found.log")" \
  || pwtest_ok "F13 no duplicate creation request"
grep -q 'merge_requests/77' "$PW_PROJECTS_DIR/$E6/task/T01.md" \
  && pwtest_ok "F13 adopted URL recorded in Result" \
  || pwtest_bad "F13 adopted record" "$(grep -i 'MR:' "$PW_PROJECTS_DIR/$E6/task/T01.md")"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E6/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E6/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E6"

# --- description marker boundary (plan 47 D01) -------------------------------------------------
# The managed-marker parser requires the end marker to end a real line. Workflow-owned creation
# must run that SAME parser over the whole body before anything is published.
python3 - "$ROOT/desc-valid.md" "$ROOT/desc-bad.md" <<'PYEOF'
import sys
valid = """<!-- pw-mr-summary:start -->
## What & why
Fixture body.
## High-level changes
One thing.
## Low-level changes
One detail.
## Verification
Ran the check.
## Notes for the reviewer
Nothing special.
<!-- pw-mr-summary:end -->
"""
open(sys.argv[1], "w").write(valid)
# The live incident shape: literal backslash-n separators appended on the SAME line as the end
# marker (a literal on the next line would be legal trailing text and prove nothing).
bs = chr(92)
bad = valid.replace("<!-- pw-mr-summary:end -->",
                    "<!-- pw-mr-summary:end -->" + bs + "n" + bs + "n", 1)
open(sys.argv[2], "w").write(bad)
PYEOF
pwtest_rc 0 "D01 valid managed description passes the parser" \
  "$(pwtest_script $SH)" history --project "$S2" --operation validate --options --file "$ROOT/desc-valid.md"
pwtest_rc 2 "D01 malformed marker suffix is rejected" \
  "$(pwtest_script $SH)" history --project "$S2" --operation validate --options --file "$ROOT/desc-bad.md"
pwtest_fix "marker rejection names the remedy"

E7=exec-f2badmarker; rm -rf "$PW_PROJECTS_DIR/$E7"; cp -a "$F2" "$PW_PROJECTS_DIR/$E7"
pwtest_repo api "branch:agent/$E7/T01-thing"
( cd "$PW_REPOS/api" && git worktree add "$PW_PROJECTS_DIR/$E7/worktree/api/T01-thing" "agent/$E7/T01-thing" >/dev/null 2>&1 ) || true
sed -i '' "s|agent/$S2/T01-thing|agent/$E7/T01-thing|" "$PW_PROJECTS_DIR/$E7/task/T01.md"
: > "$ROOT/forge47marker.log"
pwtest_rc 2 "D01 exec refuses a malformed boundary before pushing" \
  env PWTEST_FORGE_LOG="$ROOT/forge47marker.log" \
  "$(pwtest_script $SH)" exec --project "$E7" --task T01 --file "$ROOT/desc-bad.md"
# The fixture branch is already pushed by pwtest_repo, so an origin ref proves nothing; the push
# line is the real signal that publication started before validation.
grep -q '^Pushing ' "$PWTEST_BOTH" \
  && pwtest_bad "D01 exec pushed despite a malformed boundary" "push line present: $(cat "$PWTEST_BOTH" | head -3)" \
  || pwtest_ok "D01 nothing was pushed"
grep -q 'nothing was pushed' "$PWTEST_BOTH" \
  && pwtest_ok "D01 refusal states that nothing was pushed" \
  || pwtest_bad "D01 refusal wording" "$(cat "$PWTEST_BOTH" | head -3)"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$E7/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$E7/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$E7"

# --- MR identity for state reads (plan 47 F24,F25) ----------------------------------------------
# Identity comes from the recorded MR URL, so a state read does not need the task's worktree; an
# enterprise GitHub host resolves to gh with explicit repository identity.
M47=mrstate47; rm -rf "$PW_PROJECTS_DIR/$M47"; cp -a "$F2" "$PW_PROJECTS_DIR/$M47"
pwtest_rc 0 "F24 mr-state reads with no worktree for the task" \
  "$(pwtest_script $SH)" mr-state --project "$M47" --task T02
# An observed state (whatever the fixture seeds) proves the read did not depend on the worktree.
pwtest_re '^(open|merged|closed)$' "F24 returns an observed state"
rm -rf "$PW_PROJECTS_DIR/$M47"

G47=ghstate47; rm -rf "$PW_PROJECTS_DIR/$G47"; cp -a "$F2" "$PW_PROJECTS_DIR/$G47"
python3 - "$PW_PROJECTS_DIR/$G47/task/T02.md" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("https://gitlab.example.com/pwtest/api/-/merge_requests/42",
            "https://github.example.com/owner/api/pull/42")
open(f,"w").write(t)
PYEOF
: > "$ROOT/ghstate47.log"
pwtest_rc 0 "F25 enterprise GitHub state read succeeds" \
  env PWTEST_FORGE_LOG="$ROOT/ghstate47.log" PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.forge.sh" \
  "$(pwtest_script $SH)" mr-state --project "$G47" --task T02
grep -q -- '-R owner/api' "$ROOT/ghstate47.log" \
  && pwtest_ok "F25 uses the URL's repository identity" \
  || pwtest_bad "F25 repo identity" "$(tr '\n' ';' < "$ROOT/ghstate47.log" 2>/dev/null)"
rm -rf "$PW_PROJECTS_DIR/$G47"

# F28: an unresolvable branch must fail, never be recorded as the verified head.
S47=sv47; rm -rf "$PW_PROJECTS_DIR/$S47"; cp -a "$F2" "$PW_PROJECTS_DIR/$S47"
sed -i '' "s|agent/$S2/T01-thing|agent/$S47/does-not-exist|" "$PW_PROJECTS_DIR/$S47/task/T01.md"
printf 'manual evidence\n' > "$ROOT/ev47.txt"
pwtest_rc 2 "F28 stack-verify refuses an unresolvable branch" \
  "$(pwtest_script $SH)" stack-verify --project "$S47" --task T01 --evidence "$ROOT/ev47.txt"
grep -q "cannot resolve branch" "$PWTEST_BOTH" \
  && pwtest_ok "F28 names the unresolvable branch" \
  || pwtest_bad "F28 message" "$(head -2 "$PWTEST_BOTH")"
grep -q "does-not-exist" "$PW_PROJECTS_DIR/$S47/task/stack.tsv" 2>/dev/null \
  && pwtest_bad "F28 recorded the branch token as a head" "$(grep 'does-not-exist' "$PW_PROJECTS_DIR/$S47/task/stack.tsv")" \
  || pwtest_ok "F28 no fabricated head recorded"
rm -rf "$PW_PROJECTS_DIR/$S47"

# --- GitHub check aggregation (plan 47 F06) -----------------------------------------------------
# EVERY selected check contributes: the old table read dropped the first row and reduced the rest
# to one sorted status, so a failing check could be reported green.
CI47=ci47; rm -rf "$PW_PROJECTS_DIR/$CI47"; cp -a "$F2" "$PW_PROJECTS_DIR/$CI47"
pwtest_repo ghrepo
git -C "$PW_REPOS/ghrepo" remote set-url origin https://github.example.com/owner/ghrepo.git >/dev/null 2>&1 || true
python3 - "$PW_PROJECTS_DIR/$CI47/task/T02.md" <<'PYEOF'
import sys, re
f=sys.argv[1]; t=open(f).read()
t=re.sub(r'^- \*\*Repo:\*\*.*$', '- **Repo:** ghrepo', t, count=1, flags=re.M)
t=t.replace("https://gitlab.example.com/pwtest/api/-/merge_requests/42",
            "https://github.example.com/owner/ghrepo/pull/42")
open(f,"w").write(t)
PYEOF
pwtest_rc 1 "F06 a failing selected check fails the run" \
  env PWTEST_CHECKS_JSON='[{"state":"SUCCESS"},{"state":"FAILURE"}]' PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.forge.sh" \
  "$(pwtest_script $SH)" monitor --project "$CI47" --task T02 --interval 1 --timeout 1
grep -qi 'Build check:.*FAILED' "$PW_PROJECTS_DIR/$CI47/task/T02.md" \
  && pwtest_ok "F06 failure is recorded" \
  || pwtest_bad "F06 failure record" "$(grep -i 'build check' "$PW_PROJECTS_DIR/$CI47/task/T02.md")"
pwtest_rc 2 "F06 a pending selected check blocks a green verdict" \
  env PWTEST_CHECKS_JSON='[{"state":"SUCCESS"},{"state":"PENDING"}]' PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.forge.sh" \
  "$(pwtest_script $SH)" monitor --project "$CI47" --task T02 --interval 1 --timeout 1
pwtest_rc 0 "F06 all selected checks passing is green" \
  env PWTEST_CHECKS_JSON='[{"state":"SUCCESS"},{"state":"SKIPPED"}]' PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.forge.sh" \
  "$(pwtest_script $SH)" monitor --project "$CI47" --task T02 --interval 1 --timeout 1
rm -rf "$PW_PROJECTS_DIR/$CI47"

# --- root freshness proof (plan 47 F17) ---------------------------------------------------------
# A ROOT task whose branch moved after verification must not publish stale evidence.
R47=stale47; rm -rf "$PW_PROJECTS_DIR/$R47"; cp -a "$F2" "$PW_PROJECTS_DIR/$R47"
pwtest_repo api "branch:agent/$R47/T01-thing"
sed -i '' "s|agent/$S2/T01-thing|agent/$R47/T01-thing|" "$PW_PROJECTS_DIR/$R47/task/T01.md"
printf 'verify ok\n' > "$ROOT/ev47f.txt"
pwtest_rc 0 "F17 records a verification tuple for the root" \
  "$(pwtest_script $SH)" stack-verify --project "$R47" --task T01 --evidence "$ROOT/ev47f.txt"
# Advance the branch in the shared repo (the fixture copy's worktree path already exists, so a
# `git worktree add` there fails; this test only needs the ref to move after verification).
( cd "$PW_REPOS/api" && git checkout -q "agent/$R47/T01-thing" \
  && echo post-verify >> stale47.txt && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm "post-verify change" \
  && git checkout -q master ) >/dev/null 2>&1
: > "$ROOT/forge47stale.log"
pwtest_rc 2 "F17 exec refuses stale root evidence before pushing" \
  env PWTEST_FORGE_LOG="$ROOT/forge47stale.log" \
  "$(pwtest_script $SH)" exec --project "$R47" --task T01 --file "$ROOT/desc-valid.md"
grep -q '^Pushing ' "$PWTEST_BOTH" \
  && pwtest_bad "F17 pushed stale work" "$(head -3 "$PWTEST_BOTH")" \
  || pwtest_ok "F17 nothing was pushed"
grep -q 'stale' "$PWTEST_BOTH" \
  && pwtest_ok "F17 names the stale tuple" \
  || pwtest_bad "F17 message" "$(head -3 "$PWTEST_BOTH")"
git -C "$PW_REPOS/api" worktree remove --force "$PW_PROJECTS_DIR/$R47/worktree/api/T01-thing" >/dev/null 2>&1 || true
git -C "$PW_REPOS/api" branch -D "agent/$R47/T01-thing" >/dev/null 2>&1 || true
rm -rf "$PW_PROJECTS_DIR/$R47"

# --- persistent repair budget (plan 47 cross-workflow policy) -----------------------------------
BR47=rb47; rm -rf "$PW_PROJECTS_DIR/$BR47"; cp -a "$F2" "$PW_PROJECTS_DIR/$BR47"
pwtest_rc 0 "repair-round reports the effective limit" \
  "$(pwtest_script $SH)" repair-round --project "$BR47" --task T01 --work "T01@branch" --limit 2
pwtest_re 'remaining=2' "repair-round starts unreserved"
pwtest_rc 0 "repair-round consumes a round" "$(pwtest_script $SH)" repair-round --project "$BR47" --task T01 --work "T01@branch" --limit 2 --consume
pwtest_re 'remaining=1' "repair-round counts the consumed round"
pwtest_rc 0 "repair-round consumes the last round" "$(pwtest_script $SH)" repair-round --project "$BR47" --task T01 --work "T01@branch" --limit 2 --consume
pwtest_rc 2 "repair-round refuses past the budget" "$(pwtest_script $SH)" repair-round --project "$BR47" --task T01 --work "T01@branch" --limit 2 --consume
pwtest_err 'repair budget exhausted' "exhaustion names the budget"
grep -q 'T01@branch' "$PW_PROJECTS_DIR/$BR47/task/repair-budget.tsv" \
  && pwtest_ok "repair budget persisted in the project" || pwtest_bad "repair budget file" "missing"
pwtest_rc 0 "a new work identity gets its own budget" \
  "$(pwtest_script $SH)" repair-round --project "$BR47" --task T01 --work "T01@new-run" --limit 2 --consume
rm -rf "$PW_PROJECTS_DIR/$BR47"
