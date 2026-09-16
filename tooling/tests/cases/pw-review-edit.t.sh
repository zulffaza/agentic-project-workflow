# shellcheck shell=bash
# cases/pw-review-edit.t.sh — review-doc entity operators (plan 17): init-all, signoff,
# add-item, answer, add-question, resolve. Works on a private clone of F2 (never the shared
# fixture — C22-style pollution is a known trap) plus a fresh-template review file.
E="$TOOL/pw-review-edit.sh"
L="$TOOL/pw-lib.sh"
RE=reviewedit; rm -rf "$PW_PROJECTS_DIR/$RE"; cp -a "$F2" "$PW_PROJECTS_DIR/$RE"
P="$PW_PROJECTS_DIR/$RE"
RV="task/review/T04.review.md"   # fresh template shape (stubs unfilled, placeholder sign-off row)

# 1) init-all: creates exactly the missing task review files, idempotent rerun
pwtest_rc 0 "init-all creates missing review files" "$E" init-all "$RE"
for t in T01 T02 T03; do
  [ -f "$P/task/review/$t.review.md" ] && pwtest_ok "init-all created $t.review.md" \
    || pwtest_bad "init-all $t.review.md" "missing"
done
[ -f "$P/task/review/T04.review.md" ] && pwtest_ok "init-all left existing T04.review.md" \
  || pwtest_bad "init-all clobber" "T04.review.md gone"
pwtest_rc 0 "init-all rerun (idempotent)" "$E" init-all "$RE"
pwtest_re "0 created, .* already present" "init-all rerun reports nothing created"

# 2) add-item fills the template stub in place → R1 (not R2 — stubs don't consume ids)
pwtest_rc 0 "add-item R1" "$E" add-item "$RE" "$RV" --section '§3 Repos' --text the toggle also lives in common-config, add a row
pwtest_grep_file '^### R1 · §3 Repos — \[OPEN\] \(you, [0-9-]* [0-9:]*\) <!-- pw-item-status: open -->' \
  "add-item wrote a real R1 heading with marker" "$P/$RV"
pwtest_grep_file 'the toggle also lives in common-config' "add-item body verbatim (spaces preserved)" "$P/$RV"
if grep -q '<YYYY-MM-DD' "$P/$RV" && ! awk '/^## Items/,/^## Open questions/' "$P/$RV" | grep -q '^### R1 · <§section'; then
  pwtest_ok "R-stub was filled, not duplicated"
else pwtest_bad "R-stub handling" "stub still live under ## Items or lost"; fi
pwtest_grep_file '\| R1 \| §3 Repos \| \[OPEN\] \|' "reindex picked R1 into ## Contents" "$P/$RV"

# second item appends → R2, multi-line via stdin with quotes/pipes
printf 'line one\nline two with "quotes" and | pipes\n' | pwtest_rc 0 "add-item R2 via stdin" "$E" add-item "$RE" "$RV" --section '§4' --stdin
pwtest_grep_file '^### R2 · §4 — \[OPEN\]' "second item is R2" "$P/$RV"
pwtest_grep_file 'line two with "quotes" and \| pipes' "stdin text verbatim" "$P/$RV"

# refusals: empty text, heading-collision text, missing section
pwtest_rc 2 "add-item refuses empty text" "$E" add-item "$RE" "$RV" --section '§4' --text ''
pwtest_fix "add-item empty-text refusal actionable"
pwtest_rc 2 "add-item refuses ## in text" "$E" add-item "$RE" "$RV" --section '§4' --text '### sneaky heading'
pwtest_rc 2 "add-item requires --section" "$E" add-item "$RE" "$RV" --text 'no anchor'

# 3) add-question fills the Q stub → Q1; answer appends ↳ you lines
pwtest_rc 0 "add-question Q1" "$E" add-question "$RE" "$RV" --section '§4' --text 'ship the flag off or on?'
pwtest_grep_file '^### Q1 · §4 — \[PENDING\] \(agent, [0-9-]* [0-9:]*\) <!-- pw-item-status: open -->' \
  "add-question wrote a real Q1 heading with marker" "$P/$RV"
pwtest_rc 0 "answer Q1" "$E" answer "$RE" "$RV" Q1 --text ship it OFF by default
pwtest_grep_file '^> ↳ \*\*you\*\* \([0-9-]* [0-9:]*\): ship it OFF by default' "answer wrote the ↳ you line" "$P/$RV"
pwtest_rc 0 "answer Q1 again" "$E" answer "$RE" "$RV" Q1 --text correction, staging first
# second answer joins the same quote block via a blank quoted '>' separator
if awk '/^### Q1 ·/{f=1} f && /^---$/{exit} f' "$P/$RV" | grep -q '^>$'; then
  pwtest_ok "second answer separated by blank quoted line"
else pwtest_bad "quote separator" "no '>' line between the two ↳ you lines"; fi
pwtest_rc 2 "answer refuses unknown Qid" "$E" answer "$RE" "$RV" Q9 --text nope
pwtest_rc 2 "answer refuses non-Q id" "$E" answer "$RE" "$RV" R1 --text nope

# 4) resolve: flips the SAME heading (tag+marker), appends ↳ agent, human text untouched
ASK_BEFORE="$(grep -F 'the toggle also lives in common-config' "$P/$RV")"
pwtest_rc 0 "resolve R1" "$E" resolve "$RE" "$RV" R1 --reply 'added a common-config row (config-only change)'
pwtest_grep_file '^### R1 · §3 Repos — \[RESOLVED\] .*<!-- pw-item-status: resolved -->' \
  "resolve flipped R1 tag+marker in the same heading" "$P/$RV"
[ "$(grep -c '^### R1 · §3 Repos' "$P/$RV")" = 1 ] && pwtest_ok "no second R1 heading" \
  || pwtest_bad "resolve duplicate heading" "R1 heading appears twice"
[ "$ASK_BEFORE" = "$(grep -F 'the toggle also lives in common-config' "$P/$RV")" ] \
  && pwtest_ok "human ask byte-identical after resolve" || pwtest_bad "resolve edited human text" "ask line changed"
pwtest_grep_file '^> ↳ \*\*agent\*\* \([0-9-]* [0-9:]*\): added a common-config row' "resolve appended the ↳ agent reply" "$P/$RV"
pwtest_rc 2 "resolve refuses already-resolved" "$E" resolve "$RE" "$RV" R1 --reply again
pwtest_rc 2 "resolve refuses empty reply" "$E" resolve "$RE" "$RV" R2 --reply '  '
# Q resolve requires the human's answer first
pwtest_rc 0 "add-question Q2" "$E" add-question "$RE" "$RV" --section '§5' --text 'a second question?'
pwtest_rc 2 "resolve Q2 refuses without a ↳ you line" "$E" resolve "$RE" "$RV" Q2 --reply folding nothing
pwtest_rc 0 "resolve Q1 (answered)" "$E" resolve "$RE" "$RV" Q1 --reply folded into §4 — default off
pwtest_grep_file '^### Q1 · §4 — \[ANSWERED\] .*<!-- pw-item-status: resolved -->' "Q1 flipped to ANSWERED" "$P/$RV"

# 5) signoff: placeholder replaced, history append-only, gate reads the latest row
pwtest_rc 2 "signoff refuses bad decision" "$E" signoff "$RE" "$RV" approve
pwtest_fix "bad-decision refusal actionable"
pwtest_rc 0 "signoff approved" "$E" signoff "$RE" "$RV" approved
pwtest_rc 0 "gate reads approved" "$L" review gate "$RE" "$RV"
pwtest_rc 0 "signoff changes-requested (--by)" "$E" signoff "$RE" "$RV" changes-requested --by faza
pwtest_rc 1 "gate now reads changes-requested (latest row wins)" "$L" review gate "$RE" "$RV"
n1="$(grep -c '^| [0-9-]* [0-9:]* | you | approved |$' "$P/$RV")"
n2="$(grep -c '^| [0-9-]* [0-9:]* | faza | changes-requested |$' "$P/$RV")"
if [ "$n1" = 1 ] && [ "$n2" = 1 ]; then
  pwtest_ok "both sign-off rows preserved (append-only history)"
else pwtest_bad "signoff history" "approved-rows=$n1 changes-requested-rows=$n2 (want 1/1; template comment rows must not match)"; fi
grep -q 'signed off' "$P/LOG.md" && pwtest_ok "signoff logged" || pwtest_bad "signoff LOG" "nothing recorded"

# 6) ids stay monotonic across an archive run (archived markers counted)
pwtest_rc 0 "archive resolved items" "$L" review archive "$RE" "$RV"
pwtest_rc 0 "add-item after archive" "$E" add-item "$RE" "$RV" --section '§6' --text post-archive item
pwtest_grep_file '^### R3 · §6 — \[OPEN\]' "next id skipped archived R1 (got R3, not R1)" "$P/$RV"

# 7) lint + count agree with the edited file (post-archive live state: R2 open, Q2 pending,
#    R3 open; R1/Q1 moved to the archive sibling)
pwtest_rc 0 "lint passes on the edited review file" "$TOOL/pw-doc-lint.sh" review "$RE" "$RV"
pwtest_rc 0 "count on edited file" "$L" review count "$RE" "$RV"
pwtest_re 'open=3 resolved=0 items=2' "count sees the live post-archive state (open=3 resolved=0 items=2)"

rm -rf "$PW_PROJECTS_DIR/$RE"
