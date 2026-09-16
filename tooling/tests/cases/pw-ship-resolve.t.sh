# shellcheck shell=bash
# cases/pw-ship-resolve.t.sh
pwtest_rc 0 "resolve F2 rows" "$TOOL/pw-ship-resolve.sh" "$S2"
pwtest_re '^T01\|api\|' "pipe-row contract stable"
grep -q "Fix api" "$PWTEST_BOTH" && pwtest_ok "apostrophe title intact across pipes (C14)" || pwtest_bad "apostrophe title" "see row: $(grep ^T01 "$PWTEST_BOTH"|head -1)"
pwtest_rc 0 "resolve F3 hostile (plain id + linked id + quotes)" "$TOOL/pw-ship-resolve.sh" "$S3"
pwtest_re '^T01\|' "plain id row parsed (C4)"
pwtest_rc 2 "resolve no PLAN → 2" "$TOOL/pw-ship-resolve.sh" "$S1"
pwtest_fix "no-PLAN actionable (/pw-breakdown)"
