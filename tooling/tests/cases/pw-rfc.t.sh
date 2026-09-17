# shellcheck shell=bash
# cases/pw-rfc.t.sh — the rfc-doc entity (merged plan 20 Phase 4: comments + meta upserts).
R=rfc-f2; rm -rf "$PW_PROJECTS_DIR/$R"; cp -a "$F2" "$PW_PROJECTS_DIR/$R"
pwtest_rc 2 "no rfc dir → missing-setup error" "$(pwtest_script pw-rfc.sh)" comments "$R"
pwtest_fix "names a next command"
rm -rf "$PW_PROJECTS_DIR/$R"
mkdir -p "$PW_PROJECTS_DIR/${S2}rfc-copy" 2>/dev/null; true
pwtest_rc any "unknown backend rejected" env PW_RFC_BACKEND=nosuchbackend "$(pwtest_script pw-rfc.sh)" comments "$S2"
[ "$PWTEST_RC" != 0 ] ; pwtest_fix "backend refusal actionable"

# 4) rfc meta upserts + comment-seen
"$(pwtest_script pw-rfc.sh)" init "$RI" markdown >/dev/null 2>&1 || true
pwtest_rc 0 "rfc target" "$(pwtest_script pw-rfc.sh)" target "$RI" none-md-test
grep -q 'none-md-test' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc target persists" || pwtest_bad "rfc target" "$(cat "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null | head -3 | tr '\n' ';')"
pwtest_rc 0 "rfc state wave1" "$(pwtest_script pw-rfc.sh)" state "$RI" Wave1Published yes
grep -qi 'wave 1 published' "$PW_PROJECTS_DIR/$RI/rfc/META.md" && pwtest_ok "rfc state persists (Wave 1 published)" || pwtest_bad "rfc state" "META unchanged: $(head -4 "$PW_PROJECTS_DIR/$RI/rfc/META.md")"
pwtest_rc 0 "rfc comment-seen (thread t99 solved=yes)" "$(pwtest_script pw-rfc.sh)" comment-seen "$RI" t99 2 yes
grep -qiE 't99' "$PW_PROJECTS_DIR/$RI/rfc/META.md" \
  && pwtest_ok "thread persisted in META" || pwtest_bad "rfc comment-seen" "$(tail -3 "$PW_PROJECTS_DIR/$RI/rfc/META.md" 2>/dev/null)"; 
