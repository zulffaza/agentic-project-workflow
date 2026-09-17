# shellcheck shell=bash
# cases/pw-doc-lint.t.sh — lint verdicts on real shapes (both directions!).
pwtest_rc 0 "lint all F2 baseline passes" "$(pwtest_script pw-doc-lint.sh)" all "$S2"
pwtest_rc 1 "lint all F3 flags hostile file" "$(pwtest_script pw-doc-lint.sh)" all "$S3"
pwtest_err 'missing|Story|Repo' "names the broken fields"
pwtest_fix "lint failure carries what-to-do"
pwtest_rc 1 "task T06 (missing fields, CRLF)" "$(pwtest_script pw-doc-lint.sh)" task "$S3" T06
cp "$F2/task/T01.md" "$F2/task/T99.md"
sed -i '' -e '/\*\*Repo:\*\*/d' "$F2/task/T99.md"
pwtest_rc 1 "task with no Repo errors on that field" "$(pwtest_script pw-doc-lint.sh)" task "$S2" T99
pwtest_fix "missing-field actionable"
rm -f "$F2/task/T99.md"
pwtest_rc 0 "task T03 prose-polluted values tolerated (C17)" "$(pwtest_script pw-doc-lint.sh)" task "$S3" T03
pwtest_rc 2 "unknown project" "$(pwtest_script pw-doc-lint.sh)" all nope-xyz
pwtest_fix "unknown project actionable"
pwtest_rc 2 "bogus mode" "$(pwtest_script pw-doc-lint.sh)" bogus "$S2"

# C22 (2026-09-16): review marker lint reads pw-lib's detector — unfilled stubs must not false-fail,
# a filled real item with no status marker must.
RVF="$PWTEST_F2/task/review/T04.review.md"
pwtest_rc 0 "lint review on template-shape file (stubs exempt)" "$(pwtest_script pw-doc-lint.sh)" review "$S2" "task/review/T04.review.md"
# The C22 mutation below writes into the SHARED F2 fixture — back it up and restore after,
# or T2's `lint-all pwt-f2-mid` later sees the leftover marker-less item and (correctly) fails.
cp "$RVF" "$RVF.c22bak"
awk '/^## Open questions/{print "### R9 · §1 real ask — (you, 2026-09-16 12:00)"; print "no marker here"; print "---"; print ""} {print}' "$RVF" > "$RVF.a" && mv "$RVF.a" "$RVF"
pwtest_rc 1 "lint review flags marker-less real item (C22)" "$(pwtest_script pw-doc-lint.sh)" review "$S2" "task/review/T04.review.md"
if grep -q '1 item headings but only 0' "$PWTEST_BOTH"; then pwtest_ok "count in the error text (C22d)"; else pwtest_bad "count in the error text (C22d)" "$(head -c 160 "$PWTEST_BOTH" | tr '\n' ' ')"; fi
mv "$RVF.c22bak" "$RVF"
