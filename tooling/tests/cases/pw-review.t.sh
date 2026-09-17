# shellcheck shell=bash
. "$TOOL/scripts/lib/pw-mdlib.sh"
# cases/pw-review.t.sh — review-doc entity operators (plan 17, consolidated plan 20): init-all, signoff,
# add-item, answer, add-question, resolve. Works on a private clone of F2 (never the shared
# fixture — C22-style pollution is a known trap) plus a fresh-template review file.
E="$(pwtest_script pw-review.sh)"
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
pwtest_rc 0 "gate reads approved" "$(pwtest_script pw-review.sh)" gate "$RE" "$RV"
pwtest_rc 0 "signoff changes-requested (--by)" "$E" signoff "$RE" "$RV" changes-requested --by faza
pwtest_rc 1 "gate now reads changes-requested (latest row wins)" "$(pwtest_script pw-review.sh)" gate "$RE" "$RV"
n1="$(grep -c '^| [0-9-]* [0-9:]* | you | approved |$' "$P/$RV")"
n2="$(grep -c '^| [0-9-]* [0-9:]* | faza | changes-requested |$' "$P/$RV")"
if [ "$n1" = 1 ] && [ "$n2" = 1 ]; then
  pwtest_ok "both sign-off rows preserved (append-only history)"
else pwtest_bad "signoff history" "approved-rows=$n1 changes-requested-rows=$n2 (want 1/1; template comment rows must not match)"; fi
grep -q 'signed off' "$P/LOG.md" && pwtest_ok "signoff logged" || pwtest_bad "signoff LOG" "nothing recorded"

# 6) ids stay monotonic across an archive run (archived markers counted)
pwtest_rc 0 "archive resolved items" "$(pwtest_script pw-review.sh)" archive "$RE" "$RV"
pwtest_rc 0 "add-item after archive" "$E" add-item "$RE" "$RV" --section '§6' --text post-archive item
pwtest_grep_file '^### R3 · §6 — \[OPEN\]' "next id skipped archived R1 (got R3, not R1)" "$P/$RV"

# 7) lint + count agree with the edited file (post-archive live state: R2 open, Q2 pending,
#    R3 open; R1/Q1 moved to the archive sibling)
pwtest_rc 0 "lint passes on the edited review file" "$(pwtest_script pw-doc.sh)" lint review "$RE" "$RV"
pwtest_rc 0 "count on edited file" "$(pwtest_script pw-review.sh)" count "$RE" "$RV"
pwtest_re 'open=3 resolved=0 items=2' "count sees the live post-archive state (open=3 resolved=0 items=2)"

rm -rf "$PW_PROJECTS_DIR/$RE"


# --- scan (merged from pw-review-scan.t.sh, plan 20 Phase 3) ---
pwtest_rc 0 "scan F1 empty report rc" "$(pwtest_script pw-review.sh)" scan "$S1"
pwtest_rc 0 "scan F2 reports rows" "$(pwtest_script pw-review.sh)" scan "$S2"
pwtest_re 'fixture.review.md' "analysis-lane row emitted"
pwtest_re 'in-review|open|approved' "shows decision state (col-3 read, C5)"
grep -qi template "$PWTEST_OUT" \
  && pwtest_bad "templates never surface as reviews" "$(head -c 160 "$PWTEST_OUT"|tr '\n' ' ')" \
  || pwtest_ok "no template file listed as a review (status/scan round)"
pwtest_rc 0 "scan F3 ignores commented example rows (C5)" "$(pwtest_script pw-review.sh)" scan "$S3"

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
pwtest_rc 0 "scan F2 with one real open heading" "$(pwtest_script pw-review.sh)" scan "$S2"
pwtest_re '1 open' "real open heading counted (C22b)"
printf '### R9b · §3 — [RESOLVED] (you, 2026-09-16 00:00) <!-- pw-item-status: resolved -->\n---\n' >> "$PW_PROJECTS_DIR/$S2/task/review/PLAN.review.md"
pwtest_rc 0 "scan F2 real resolved heading" "$(pwtest_script pw-review.sh)" scan "$S2"
pwtest_re 'PLAN.review.md: 1 resolved' "resolved heading counted under its file (C22c)"

# --- init idempotency (ported from pw-lib.t.sh §2, plan 20) ---
# 2) review-init idempotent (P8):
RI=libtestri; rm -rf "$PW_PROJECTS_DIR/$RI"; cp -a "$F2" "$PW_PROJECTS_DIR/$RI"
pwtest_rc 0 "review-init new file ok" "$(pwtest_script pw-review.sh)" init "$RI" task/review/T99.review.md task/T99.md || true
printf '\nspecial content kept\n' >> "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md"
pwtest_rc 0 "review-init rerun" "$(pwtest_script pw-review.sh)" init "$RI" task/review/T99.review.md task/T99.md
grep -q 'special content kept' "$PW_PROJECTS_DIR/$RI/task/review/T99.review.md" \
  && pwtest_ok "review-init preserves existing" || pwtest_bad "review-init clobber" "existing content lost"

# --- gate-doctrine corpus ported from pw-lib's inline selftest (plan 20 Phase 3) ---
# These run against synthetic minimal projects (not the shared fixtures) exactly as the
# original selftest did; a local die() records failures instead of aborting the suite.
rv_selftest() {
  local tmp="$ROOT/rv" die="$ROOT/rv-die"
  rm -rf "$tmp"; mkdir -p "$tmp/demo/analysis/review" "$tmp/demo2/analysis/review"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  printf '# Analysis: demo\n' > "$tmp/demo/analysis/topic.md"
  printf '# Analysis: demo2\n' > "$tmp/demo2/analysis/topic2.md"
  die() { pwtest_bad "rv-selftest: $*" "ported gate-doctrine assert failed"; }
  SH="$(pwtest_script pw-review.sh)"
  LIBP="$(pwtest_script pw-config.sh)"
  # demo2 starts advisory for the auto-signoff refusal checks (the original relied on the
  # ai-review section that runs earlier in the selftest):
  PW_PROJECTS_DIR="$tmp" "$LIBP" ai-review demo2 analysis advisory >/dev/null 2>&1 || true
  # review-init: creates a review file verbatim from the template (header + Reviewing: link
  # stamped, format hints intact), and is idempotent — a 2nd call never clobbers your items.
  mkdir -p "$tmp/demo/analysis"
  printf '# Analysis: demo\n' > "$tmp/demo/analysis/topic.md"
  PW_PROJECTS_DIR="$tmp" "$SH" init demo analysis/review/topic.review.md analysis/topic.md >/dev/null
  local RV="$tmp/demo/analysis/review/topic.review.md"
  [ -f "$RV" ] || die "selftest FAIL: review-init did not create the file"
  grep -q '^# Review: topic.md$' "$RV" || die "selftest FAIL: review header not stamped"
  grep -qF 'Reviewing: [topic.md](../topic.md)' "$RV" || die "selftest FAIL: Reviewing link not stamped"
  grep -q '^> \*\*Add an item:\*\*' "$RV" || die "selftest FAIL: permanent Items format hint missing"
  grep -q '^> \*\*Answer a question:\*\*' "$RV" || die "selftest FAIL: permanent Open-questions format hint missing"
  printf '\n### R1 · your item\n' >> "$RV"                    # simulate the human adding an item
  PW_PROJECTS_DIR="$tmp" "$SH" init demo analysis/review/topic.review.md analysis/topic.md >/dev/null
  grep -q '^### R1 · your item$' "$RV" || die "selftest FAIL: review-init clobbered an existing review file"

  # review note-init: idempotent, same shape as review-init/rfc init.
  PW_PROJECTS_DIR="$tmp" "$SH" note-init demo2 >/dev/null
  local NOTES="$tmp/demo2/REVIEWER-NOTES.md"
  [ -f "$NOTES" ] || die "selftest FAIL: review note-init did not create REVIEWER-NOTES.md"
  printf '\n## manual entry\n' >> "$NOTES"
  PW_PROJECTS_DIR="$tmp" "$SH" note-init demo2 >/dev/null
  grep -q '^## manual entry$' "$NOTES" || die "selftest FAIL: review note-init clobbered an existing file"

  # review auto-signoff: refuses when mode isn't auto (demo2/analysis is "advisory" above), refuses
  # while a REAL filled item is open, but succeeds on a clean pass over a just-created file — the
  # template's unfilled R1/Q1 stubs (literal `<YYYY-MM-DD` placeholder text) are heads-up copies,
  # not items, and must never block (C22: the same phantoms made pw-status report approved gates
  # as unresolved). Success places a distinctly-tagged row INSIDE the Sign-off table.
  PW_PROJECTS_DIR="$tmp" "$SH" init demo2 analysis/review/topic2.review.md analysis/topic2.md >/dev/null
  local RV2="$tmp/demo2/analysis/review/topic2.review.md"
  grep -q '\[OPEN\]' "$RV2" || die "selftest FAIL: fresh review-init unexpectedly has no [OPEN] stub (test assumption invalid)"
  if PW_PROJECTS_DIR="$tmp" "$SH" auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null 2>&1; then
    die "selftest FAIL: auto-signoff succeeded although mode is 'advisory', not 'auto'"
  fi
  PW_PROJECTS_DIR="$tmp" "$LIBP" ai-review demo2 analysis auto >/dev/null
  # a genuinely filled open item must still refuse auto-signoff — realistic timestamp, real ask.
  printf '### R9 · §1 Goal wording — [OPEN] (you, 2026-09-16 11:00) <!-- pw-item-status: open -->\nPlease reword §1.\n---\n' >> "$RV2"
  if PW_PROJECTS_DIR="$tmp" "$SH" auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null 2>&1; then
    die "selftest FAIL: auto-signoff succeeded although a real filled item is open"
  fi
  sed -i '' -e '/^### R9 · §1 Goal wording/,+2d' "$RV2"
  # only the unfilled stubs remain → invisible to the detector; a clean pass proceeds (next block).
  _review_has_open_marker "$RV2" && die "selftest FAIL: unfilled R1/Q1 stubs still register as open (C22 — placeholders must be invisible to the detector)"

  # --- _review_has_open_marker: dedicated unit-level checks for the machine marker itself,
  # isolated from the full auto-signoff integration flow above ---
  local MKT="$tmp/marker-test.md"
  # 0a. template stubs are invisible — both placeholder tokens, individually.
  printf '### Q1 · <§section> — [PENDING] (agent, )\n<!-- pw-item-status: open -->\n' > "$MKT"
  _review_has_open_marker "$MKT" && die "selftest FAIL: unfilled <§section> stub counted as open"
  printf '### R1 · §x — [OPEN] (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->\n' > "$MKT"
  _review_has_open_marker "$MKT" && die "selftest FAIL: unfilled <YYYY-MM-DD> stub counted as open"
  # 0b. a half-stub that only mentions the placeholder in its ANCHOR is still a stub (pato T01
  #     case), while a real heading with any other angle content stays visible.
  printf '### R2 · <T01> repo wiring — [OPEN] (you, 2026-09-16 18:55) [marker: pw-item-status open]\n' > "$MKT"
  _review_has_open_marker "$MKT" || die "selftest FAIL: <T01>-style real heading filtered as a stub"
  # 1. A real heading whose ONLY open signal is the new marker (no legacy emoji at all) must
  #    still be detected — proves the marker path works independently of the emoji fallback.
  printf '### R1 · §1 something — status pending <!-- pw-item-status: open -->\nbody\n' > "$MKT"
  _review_has_open_marker "$MKT" || die "selftest FAIL: marker-only open heading (no emoji) not detected as open"
  # 2. A resolved marker must NOT be treated as open even when unrelated prose elsewhere on the
  #    SAME line mentions the legacy "open" words — proves the marker, not stray text, decides.
  printf '### R1 · §1 something resolved, previously open <!-- pw-item-status: resolved -->\nbody\n' > "$MKT"
  _review_has_open_marker "$MKT" && die "selftest FAIL: a resolved-marker heading was treated as open because of unrelated 'open' text on the same line"
  # 3. A same-line marker on a real heading must never be swallowed by, or itself swallow, a
  #    separate genuinely-multi-line comment elsewhere in the file (the sed-range gotcha this
  #    mechanism was rewritten to avoid) — content after the multi-line block must survive.
  printf '### R1 real — open <!-- pw-item-status: open -->\n<!-- multiline wrapper\nswallowed middle line\nend of wrapper -->\n### R2 real — resolved <!-- pw-item-status: resolved -->\n' > "$MKT"
  _review_has_open_marker "$MKT" || die "selftest FAIL: real open marker lost across an unrelated multi-line comment block"
  grep -q "swallowed middle line" <(awk '
    BEGIN { in_comment = 0 }
    { line = $0
      if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; next }
      if (line ~ /<!--/ && line ~ /-->/) { print line; next }
      if (line ~ /<!--/) { in_comment = 1; next }
      print line }
  ' "$MKT") && die "selftest FAIL: multi-line comment content was not actually stripped"

  PW_PROJECTS_DIR="$tmp" "$SH" auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null
  grep -q '| pw-reviewer (auto) | approved |$' "$RV2" || die "selftest FAIL: auto-signoff row not written/tagged correctly"
  grep -q '| pw-reviewer (auto) | approved ✅ |$' "$RV2" && die "selftest FAIL: auto-signoff wrote the legacy emoji form — new rows must be plain 'approved'"
  grep -q '^| | | in-review |$' "$RV2" && die "selftest FAIL: auto-signoff left the placeholder row instead of replacing it"
  # anchor to an actual table ROW (starts with "| ", not prose mentioning the tag elsewhere in the
  # file's explanatory text, e.g. the template's own HOW-THIS-WORKS comment).
  local as_line as_sign; as_line="$(grep -nE '^\|.*pw-reviewer \(auto\).*approved \|$' "$RV2" | head -1 | cut -d: -f1)"
  as_sign="$(grep -n '^## Sign-off' "$RV2" | head -1 | cut -d: -f1)"
  [ -n "$as_line" ] || die "selftest FAIL: no auto-signoff table row found"
  [ "$as_line" -gt "$as_sign" ] || die "selftest FAIL: auto-signoff row landed before ## Sign-off"

  # --- backward compat: a file with the LEGACY "approved ✅" string (an already-approved real
  # project written before this migration) must still gate correctly, read-only, forever. ---
  local LEGACY="$tmp/legacy.review.md"
  printf '## Sign-off\n| Date | Who | Decision |\n|---|---|---|\n| 2026-01-01 00:00 | you | approved ✅ |\n' > "$LEGACY"
  local lgd; lgd="$(_signoff_latest_decision "$LEGACY")"
  [ "$lgd" = "approved ✅" ] || die "selftest FAIL: legacy decision text mangled, got '$lgd'"
  _decision_is_approved "$lgd" || die "selftest FAIL: _decision_is_approved rejected the legacy 'approved ✅' form — backward compat broken"
  _decision_is_approved "approved" || die "selftest FAIL: _decision_is_approved rejected the current 'approved' form"
  _decision_is_approved "in-review" && die "selftest FAIL: _decision_is_approved accepted a non-approved decision"

  # --- review gate / review reopen: the analysis/RFC-parity mechanism (docs/RFC.md) ---
  # RV2 is currently approved (the auto-signoff row just above) — and, being a verbatim
  # review-init copy, STILL carries the template's own trailing Sign-off WORKED-EXAMPLE comment
  # block, containing two lines that look exactly like real approved-row table rows. This is
  # exactly the fixture that would trip the naive "last | line from ## Sign-off to EOF" bug.
  local gd
  gd="$(PW_PROJECTS_DIR="$tmp" "$SH" gate demo2 analysis/review/topic2.review.md)" \
    || die "selftest FAIL: review gate exited non-zero on a genuinely approved file"
  [ "$gd" = "approved" ] || die "selftest FAIL: review gate printed '$gd', expected 'approved'"

  # reopen: must succeed, append (never delete) an in-review row, and gate must now report open.
  PW_PROJECTS_DIR="$tmp" "$SH" reopen demo2 analysis/review/topic2.review.md >/dev/null
  grep -q '| pw-reviewer (auto) | approved |$' "$RV2" \
    || die "selftest FAIL: review reopen deleted the prior approval instead of appending after it"
  grep -q '| pw-review (auto-reopen) | in-review |$' "$RV2" \
    || die "selftest FAIL: review reopen did not append the expected in-review row"
  if gd="$(PW_PROJECTS_DIR="$tmp" "$SH" gate demo2 analysis/review/topic2.review.md)"; then
    die "selftest FAIL: review gate exited 0 right after reopen (should read in-review now)"
  fi
  [ "$gd" = "in-review" ] || die "selftest FAIL: review gate printed '$gd' after reopen, expected 'in-review'"

  # From here on, count/locate rows against a COMMENT-STRIPPED view of RV2 — the template's own
  # trailing WORKED-EXAMPLE block (still present, since review-init copies it verbatim and nothing
  # in this flow ever deletes it) contains a decorative "pw-reviewer (auto) | approved |" line
  # of its own, which would otherwise inflate a naive grep -c on the raw file. Blank (never delete)
  # commented lines so real line numbers still line up — same technique as
  # _signoff_last_real_row_line, duplicated here since it's a private helper.
  strip_rv2() { _comment_blanked "$RV2"; }

  # reopen again while already open: idempotent no-op, must NOT append a second in-review row.
  PW_PROJECTS_DIR="$tmp" "$SH" reopen demo2 analysis/review/topic2.review.md >/dev/null
  [ "$(strip_rv2 | grep -c '| pw-review (auto-reopen) | in-review |$')" -eq 1 ] \
    || die "selftest FAIL: review reopen was not idempotent — appended a second in-review row"

  # re-approve (a SECOND auto-signoff on this file) must land as the table's new LAST row, not
  # inside/after the template's trailing WORKED-EXAMPLE comment block — the exact regression this
  # round's _signoff_last_real_row_line fix targets (a raw scan previously picked the example's
  # own "approved" lines, since they're the last such lines in the whole file).
  PW_PROJECTS_DIR="$tmp" "$LIBP" ai-review demo2 analysis auto >/dev/null   # already auto from above; explicit for clarity
  PW_PROJECTS_DIR="$tmp" "$SH" auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null
  [ "$(strip_rv2 | grep -c '| pw-reviewer (auto) | approved |$')" -eq 2 ] \
    || die "selftest FAIL: second auto-signoff didn't produce a second distinct real approved row"
  gd="$(PW_PROJECTS_DIR="$tmp" "$SH" gate demo2 analysis/review/topic2.review.md)" \
    || die "selftest FAIL: review gate exited non-zero after the second (re-)approval"
  [ "$gd" = "approved" ] || die "selftest FAIL: review gate printed '$gd' after re-approval, expected 'approved'"
  # and the row order must still be [1st approved, in-review, 2nd approved] top-to-bottom in the
  # file — proof the second approval landed AFTER the reopen row, not before/inside the example
  # block (line numbers, not just gate's reported decision, so this doesn't just re-check the same
  # function under test — it checks the row actually got spliced into the right physical spot).
  local ln_row1 ln_reopen ln_row2
  ln_row1="$(strip_rv2 | grep -n '| pw-reviewer (auto) | approved |$' | sed -n '1p' | cut -d: -f1)"
  ln_reopen="$(strip_rv2 | grep -n '| pw-review (auto-reopen) | in-review |$' | cut -d: -f1)"
  ln_row2="$(strip_rv2 | grep -n '| pw-reviewer (auto) | approved |$' | sed -n '2p' | cut -d: -f1)"
  [ -n "$ln_row1" ] && [ -n "$ln_reopen" ] && [ -n "$ln_row2" ] \
    || die "selftest FAIL: couldn't locate all 3 expected real Sign-off rows in $RV2"
  [ "$ln_row1" -lt "$ln_reopen" ] && [ "$ln_reopen" -lt "$ln_row2" ] \
    || die "selftest FAIL: Sign-off rows out of order (1st-approved=$ln_row1 reopen=$ln_reopen 2nd-approved=$ln_row2) — the second approval didn't land after the reopen row"

  # reopen must refuse silently (no-op, exit 0) when the file is NOT currently approved.
  PW_PROJECTS_DIR="$tmp" "$SH" reopen demo2 analysis/review/topic2.review.md >/dev/null
  PW_PROJECTS_DIR="$tmp" "$SH" reopen demo2 analysis/review/topic2.review.md >/dev/null || \
    die "selftest FAIL: reopen on an already-open file exited non-zero (should be a harmless no-op)"

  # --- review has-open: the generic open-item check /pw-breakdown's RFC hard block relies on ---
  # a project with no RFC.review.md at all (never touched the side-loop) must report "no"/exit 1,
  # never an error.
  local RFCRV="$tmp/demo2/analysis/review/RFC.review.md" hn
  if hn="$(PW_PROJECTS_DIR="$tmp" "$SH" has-open demo2 analysis/review/RFC.review.md)"; then
    die "selftest FAIL: review has-open exited 0 for a nonexistent RFC.review.md (should be 'no'/exit 1)"
  fi
  [ "$hn" = "no" ] || die "selftest FAIL: review has-open printed '$hn' for a missing file, expected 'no'"

  # a real pulled-comment item, still open — must report "yes"/exit 0.
  mkdir -p "$(dirname "$RFCRV")"
  printf '# RFC comments\n\n### R1 — a pulled comment <!-- pw-item-status: open -->\n\n> quoted comment text\n' \
    > "$RFCRV"
  if ! PW_PROJECTS_DIR="$tmp" "$SH" has-open demo2 analysis/review/RFC.review.md >/dev/null; then
    die "selftest FAIL: review has-open exited non-zero on a file with a real open item"
  fi
  hn="$(PW_PROJECTS_DIR="$tmp" "$SH" has-open demo2 analysis/review/RFC.review.md)"
  [ "$hn" = "yes" ] || die "selftest FAIL: review has-open printed '$hn' with an open item present, expected 'yes'"

  # resolve it in place — has-open must now report clean ("no"/exit 1), same file, no other rows.
  # Capture the printed value INSIDE the if-guard (not a separate call) — the expected exit here is
  # 1, and an ungated `hn="$(...)"` on a nonzero-exit command would trip `set -e` and abort the
  # whole selftest silently, same reasoning as the existing `review gate` checks above.
  sed -i '' -e 's/<!-- pw-item-status: open -->/<!-- pw-item-status: resolved -->/' "$RFCRV"
  if hn="$(PW_PROJECTS_DIR="$tmp" "$SH" has-open demo2 analysis/review/RFC.review.md)"; then
    die "selftest FAIL: review has-open exited 0 after the only open item was resolved"
  fi
  [ "$hn" = "no" ] || die "selftest FAIL: review has-open printed '$hn' after resolving, expected 'no'"

  # review gate on a review file with no Sign-off rows fabricated at all → dies, doesn't crash.
  local NOSIGN="$tmp/demo2/no-signoff.review.md"
  printf '# not a real review file\nno Sign-off section here\n' > "$NOSIGN"
  if PW_PROJECTS_DIR="$tmp" "$SH" gate demo2 no-signoff.review.md >/dev/null 2>&1; then
    die "selftest FAIL: review gate succeeded on a file with no ## Sign-off section at all"
  fi

  unset -f die 2>/dev/null || true
}
rv_selftest
rm -rf "$ROOT/rv"

# --- ported from pw-lib's inline selftest (plan 20 Phase 5) ---
pl_review_selftest() {
  local tmp="$ROOT/pl-review"; rm -rf "$tmp"
  die() { pwtest_bad "pw-lib-port[review]: $*" "ported selftest assert failed"; }
  # --- review reindex / review archive -------------------------------------------------
  mkdir -p "$tmp/reviewtest/analysis"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/reviewtest/README.md"
  : > "$tmp/reviewtest/LOG.md"
  printf '# Analysis: rt\n' > "$tmp/reviewtest/analysis/rt.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" init reviewtest analysis/review/rt.review.md analysis/rt.md >/dev/null
  local RTV="$tmp/reviewtest/analysis/review/rt.review.md"
  # Add a 2nd OPEN item and a RESOLVED item into ## Items, BEFORE ## Open questions — realistic
  # placement (never a blind end-of-file append, which would land after ## Sign-off and prove
  # nothing). Written to a temp file with plain printf, then head/tail/cat-spliced in — NOT
  # `awk -v` with this multi-line block: macOS's stock awk rejects a `-v` value containing embedded
  # newlines ("awk: newline in string") — the exact portability trap _ship_comment_section_ensure's
  # own comment already documents; sidestep it here the same way that function does.
  local newitems; newitems="$(mktemp)"
  {
    printf '### R2 · §3 second item — [OPEN] (you, 2026-08-19 10:00) <!-- pw-item-status: open -->\n'
    printf 'Second ask, still open.\n\n---\n\n'
    printf '### R3 · §4 third item — [RESOLVED] (you, 2026-08-19 09:00) <!-- pw-item-status: resolved -->\n'
    printf 'Third ask, already fixed.\n\n'
    printf '> ↳ **agent** (2026-08-19 09:30): §4 — fixed as asked.\n\n---\n\n'
  } > "$newitems"
  local oqline; oqline="$(grep -n '^## Open questions' "$RTV" | head -1 | cut -d: -f1)"
  { head -n "$((oqline-1))" "$RTV"; cat "$newitems"; tail -n "+${oqline}" "$RTV"; } > "$RTV.tmp" && mv "$RTV.tmp" "$RTV"
  rm -f "$newitems"
  # Clear the template's own live R1/Q1 stubs (same convention as the auto-signoff test above —
  # never a real "fix", just clearing a never-filled-in placeholder) so this test is isolated to
  # R2/R3.
  sed -i '' -e '/^### R1 · <§section or anchor> — \[OPEN\]/,+1d' \
            -e '/^### Q1 · <§section> — \[PENDING\]/,+1d' "$RTV"

  # reindex: builds a Contents table with exactly R2 (open) and R3 (resolved) — ignoring the
  # template's own commented-out worked-example headings (R1/Q1, still present verbatim above the
  # live section) — and is idempotent (a 2nd run replaces the block in place, never duplicates it).
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" reindex reviewtest analysis/review/rt.review.md >/dev/null
  grep -q '<!-- pw-contents:begin -->' "$RTV" || die "selftest FAIL: review reindex did not insert a Contents block"
  local CT1; CT1="$(sed -n '/pw-contents:begin/,/pw-contents:end/p' "$RTV")"
  printf '%s\n' "$CT1" | grep -qF '| R2 | §3 second item | [OPEN] |' || die "selftest FAIL: reindex Contents missing/wrong R2 row"
  printf '%s\n' "$CT1" | grep -qF '| R3 | §4 third item | [RESOLVED] |' || die "selftest FAIL: reindex Contents missing/wrong R3 row"
  printf '%s\n' "$CT1" | grep -q '| R1 |' && die "selftest FAIL: reindex Contents picked up a commented-out worked-example heading"
  [ "$(grep -c '<!-- pw-contents:begin -->' "$RTV")" = "1" ] || die "selftest FAIL: reindex duplicated the Contents begin-marker"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" reindex reviewtest analysis/review/rt.review.md >/dev/null
  [ "$(grep -c '<!-- pw-contents:begin -->' "$RTV")" = "1" ] || die "selftest FAIL: re-running reindex duplicated the Contents block instead of replacing it in place"
  [ "$(grep -c '^## Contents' "$RTV")" = "1" ] || die "selftest FAIL: re-running reindex duplicated the Contents heading"

  # archive: gate-safety proof — capture the Sign-off section + has-open verdict BEFORE, run
  # archive, assert both are UNCHANGED after, R3's heading is gone from the live file, R2's is
  # untouched, the archive file has R3's text verbatim (including its reply), and a pointer row
  # with the right marker landed in a new "## Archived items" section.
  local before_signoff before_hasopen
  before_signoff="$(sed -n '/^## Sign-off/,$p' "$RTV")"
  before_hasopen="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" has-open reviewtest analysis/review/rt.review.md)"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" archive reviewtest analysis/review/rt.review.md >/dev/null
  local after_signoff after_hasopen
  after_signoff="$(sed -n '/^## Sign-off/,$p' "$RTV")"
  after_hasopen="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" has-open reviewtest analysis/review/rt.review.md)"
  [ "$before_signoff" = "$after_signoff" ] || die "selftest FAIL: review archive changed the Sign-off table/section — gate-safety broken"
  [ "$before_hasopen" = "$after_hasopen" ] || die "selftest FAIL: review archive changed has-open's verdict ($before_hasopen -> $after_hasopen)"
  [ "$after_hasopen" = "yes" ] || die "selftest FAIL: R2 should still be open after archiving R3 (test assumption invalid)"
  grep -q '^### R3 · §4 third item' "$RTV" && die "selftest FAIL: R3's heading is still in the live file after archiving"
  grep -q '^### R2 · §3 second item' "$RTV" || die "selftest FAIL: R2's heading was removed by archive (should be untouched — still [OPEN])"
  local RTA="$tmp/reviewtest/analysis/review/rt.archive.md"
  [ -f "$RTA" ] || die "selftest FAIL: review archive did not create rt.archive.md"
  grep -q '^### R3 · §4 third item — \[RESOLVED\]' "$RTA" || die "selftest FAIL: R3's heading not moved verbatim into the archive file"
  grep -qF '> ↳ **agent** (2026-08-19 09:30): §4 — fixed as asked.' "$RTA" || die "selftest FAIL: R3's reply text not preserved verbatim in the archive file"
  grep -q '^## Archived items' "$RTV" || die "selftest FAIL: review archive did not add an Archived items section"
  grep -qF '<!-- pw-archived:R3 -->' "$RTV" || die "selftest FAIL: no pointer row/marker for R3 in Archived items"

  # a 2nd archive run with nothing newly resolved must be a harmless no-op (no duplicate rows).
  local archived_rows_before; archived_rows_before="$(grep -c 'pw-archived:' "$RTV")"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-review.sh)" archive reviewtest analysis/review/rt.review.md >/dev/null
  [ "$(grep -c 'pw-archived:' "$RTV")" = "$archived_rows_before" ] \
    || die "selftest FAIL: re-running archive with nothing newly resolved was not a no-op"
  rm -rf "$tmp"
}
pl_review
