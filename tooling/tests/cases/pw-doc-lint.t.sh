# shellcheck shell=bash
# cases/pw-doc-lint.t.sh — lint verdicts on real shapes (both directions!).
pwtest_rc 0 "lint all F2 baseline passes" "$TOOL/pw-doc-lint.sh" all "$S2"
pwtest_rc 1 "lint all F3 flags hostile file" "$TOOL/pw-doc-lint.sh" all "$S3"
pwtest_err 'missing|Story|Repo' "names the broken fields"
pwtest_fix "lint failure carries what-to-do"
pwtest_rc 1 "task T06 (missing fields, CRLF)" "$TOOL/pw-doc-lint.sh" task "$S3" T06
cp "$F2/task/T01.md" "$F2/task/T99.md"
sed -i '' -e '/\*\*Repo:\*\*/d' "$F2/task/T99.md"
pwtest_rc 1 "task with no Repo errors on that field" "$TOOL/pw-doc-lint.sh" task "$S2" T99
pwtest_fix "missing-field actionable"
rm -f "$F2/task/T99.md"
pwtest_rc 0 "task T03 prose-polluted values tolerated (C17)" "$TOOL/pw-doc-lint.sh" task "$S3" T03
pwtest_rc 2 "unknown project" "$TOOL/pw-doc-lint.sh" all nope-xyz
pwtest_fix "unknown project actionable"
pwtest_rc 2 "bogus mode" "$TOOL/pw-doc-lint.sh" bogus "$S2"
