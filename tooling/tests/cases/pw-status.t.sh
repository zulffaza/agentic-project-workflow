# shellcheck shell=bash
# cases/pw-status.t.sh
pwtest_rc 0 "status F1 sections" "$TOOL/pw-status.sh" "$S1" --skip-cli-check
pwtest_re '^## Phase' "phase header present"
pwtest_re '^## Next action' "next-action guidance (P5)"
pwtest_rc 0 "status F2 sections" "$TOOL/pw-status.sh" "$S2" --skip-cli-check
pwtest_re '^## Tasks' "task table header"
grep -q 'REVIEW.template\|_TEMPLATE' "$PWTEST_OUT" \
  && pwtest_bad "status ignores scaffold templates in counts" "template leaked into report" \
  || pwtest_ok "no scaffold template counted (status round)"
pwtest_rc 0 "status F3 hostile parses clean" "$TOOL/pw-status.sh" "$S3" --skip-cli-check
pwtest_re 'prose around the token|repair with' "prose phase surfaced as repair, not silent"
pwtest_rc 2 "no-such-project" "$TOOL/pw-status.sh" nope-not-here
pwtest_fix "unknown carries the fix"
