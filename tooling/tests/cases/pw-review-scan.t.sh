# shellcheck shell=bash
# cases/pw-review-scan.t.sh
pwtest_rc 0 "scan F1 empty report rc" "$(pwtest_script pw-review-scan.sh)" "$S1"
pwtest_rc 0 "scan F2 reports rows" "$(pwtest_script pw-review-scan.sh)" "$S2"
pwtest_re 'fixture.review.md' "analysis-lane row emitted"
pwtest_re 'in-review|open|approved' "shows decision state (col-3 read, C5)"
grep -qi template "$PWTEST_OUT" \
  && pwtest_bad "templates never surface as reviews" "$(head -c 160 "$PWTEST_OUT"|tr '\n' ' ')" \
  || pwtest_ok "no template file listed as a review (status/scan round)"
pwtest_rc 0 "scan F3 ignores commented example rows (C5)" "$(pwtest_script pw-review-scan.sh)" "$S3"

# C22 (2026-09-16): display counts must read the SAME heading-level detector the gates use —
# the template guidance line in every review file literally contains `pw-item-status: open`
# and a raw grep phantom-counted "+1 open" forever (user saw approved reviews as unresolved).
pwtest_re 'approved' "F2 approved rows still render"
if printf '%s' "$PWTEST_OUT" | grep -q '[0-9] open'; then
  pwtest_bad "guidance-only review files must report zero opens (C22)" "$(printf '%s' "$PWTEST_OUT" | tr '\n' '|')"
else
  pwtest_ok "no phantom opens from template guidance (C22)"
fi
printf '### R9 · §2 — [OPEN] (you, 2026-09-16 00:00) <!-- pw-item-status: open -->\n---\n' >> "$PW_PROJECTS_DIR/$S2/analysis/review/fixture.review.md"
pwtest_rc 0 "scan F2 with one real open heading" "$(pwtest_script pw-review-scan.sh)" "$S2"
pwtest_re '1 open' "real open heading counted (C22b)"
printf '### R9b · §3 — [RESOLVED] (you, 2026-09-16 00:00) <!-- pw-item-status: resolved -->\n---\n' >> "$PW_PROJECTS_DIR/$S2/task/review/PLAN.review.md"
pwtest_rc 0 "scan F2 real resolved heading" "$(pwtest_script pw-review-scan.sh)" "$S2"
pwtest_re 'PLAN.review.md: 1 resolved' "resolved heading counted under its file (C22c)"
