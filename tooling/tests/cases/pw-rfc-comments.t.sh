# shellcheck shell=bash
# cases/pw-rfc-comments.t.sh
R=rfc-f2; rm -rf "$PW_PROJECTS_DIR/$R"; cp -a "$F2" "$PW_PROJECTS_DIR/$R"
pwtest_rc 2 "no rfc dir → missing-setup error" "$TOOL/pw-rfc-comments.sh" "$R"
pwtest_fix "names a next command"
rm -rf "$PW_PROJECTS_DIR/$R"
mkdir -p "$PW_PROJECTS_DIR/${S2}rfc-copy" 2>/dev/null; true
pwtest_rc any "unknown backend rejected" env PW_RFC_BACKEND=nosuchbackend "$TOOL/pw-rfc-comments.sh" "$S2"
[ "$PWTEST_RC" != 0 ] ; pwtest_fix "backend refusal actionable"
