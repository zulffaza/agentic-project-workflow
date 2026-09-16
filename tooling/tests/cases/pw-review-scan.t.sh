# shellcheck shell=bash
# cases/pw-review-scan.t.sh
pwtest_rc 0 "scan F1 empty report rc" "$TOOL/pw-review-scan.sh" "$S1"
pwtest_rc 0 "scan F2 reports rows" "$TOOL/pw-review-scan.sh" "$S2"
pwtest_re 'fixture.review.md' "analysis-lane row emitted"
pwtest_re 'in-review|open|approved' "shows decision state (col-3 read, C5)"
grep -qi template "$PWTEST_OUT" \
  && pwtest_bad "templates never surface as reviews" "$(head -c 160 "$PWTEST_OUT"|tr '\n' ' ')" \
  || pwtest_ok "no template file listed as a review (status/scan round)"
pwtest_rc 0 "scan F3 ignores commented example rows (C5)" "$TOOL/pw-review-scan.sh" "$S3"
