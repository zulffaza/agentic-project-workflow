# shellcheck shell=bash
# cases/pw-review-hardening.t.sh — independent-audit hardening contracts for the review
# entity and its libraries: fail-closed heading gate (3+ hash open markers), archive
# sibling and slug containment, reserved-syntax injection guards, machine-role sign-off
# spoofing, archive no-op purity + retry idempotence, splice-failure propagation,
# Contents marker pairing, sign-off row placement order, lock ownership (no age-based
# takeover), init title escaping, and fail-closed pass entry on an invalid latest
# decision. Every project mutation happens on PRIVATE clones — shared F1/F2/F3 untouched.
. "$TOOL/scripts/lib/pw-mdlib.sh"
. "$TOOL/scripts/lib/pw-reviewlib.sh"
E="$(pwtest_script pw-review.sh)"
CFG="$(pwtest_script pw-config.sh)"
md5f() { cksum < "$1"; }
rowcount() { local n; n="$(_comment_blanked "$2" | grep -cF -- "$1" || true)"; echo "${n:-0}"; }
set_phase() {
  local file="$PW_PROJECTS_DIR/$1/README.md"
  sed "s|^- \*\*Status:\*\*.*|- **Status:** $2|" "$file" > "$file.phase.tmp" && mv "$file.phase.tmp" "$file"
}
# insert-before <label> <anchor-regex> <file> <lines-file>
insert_before() {
  local ln; ln="$(grep -n "$2" "$3" | head -1 | cut -d: -f1)"
  [ -n "$ln" ] || { pwtest_bad "$1" "anchor $2 not found in $3"; return 1; }
  { head -n "$((ln-1))" "$3"; cat "$4"; tail -n "+${ln}" "$3"; } > "$3.hard.tmp" && mv "$3.hard.tmp" "$3"
}

# ============================================================ H1) heading gate fail-closed
HG=hard-gate; rm -rf "$PW_PROJECTS_DIR/$HG"; cp -a "$F2" "$PW_PROJECTS_DIR/$HG"
G="$PW_PROJECTS_DIR/$HG"; set_phase "$HG" analysis
GRV=analysis/review/fixture.review.md   # F2: latest row approved, zero real open
GRF="$G/$GRV"
pwtest_rc 0 "baseline approved clean gate still passes" "$E" gate "$HG" "$GRV"
# a commented open-item heading (multi-line block) must stay invisible
CBK="$(mktemp)"; printf '<!--\n### R99 · §2 — [OPEN] (you, 2026-10-10 10:10) marker-note\n-->\n' > "$CBK"
insert_before "commented-item setup" '^## Sign-off' "$GRF" "$CBK"; rm -f "$CBK"
pwtest_rc 0 "commented open item never parses (gate still clean)" "$E" gate "$HG" "$GRV"
# stubs stay invisible too: an approved stub-only file must gate clean
SBK="$ROOT/hard-stubonly.review.md"
printf '# Review\nGate: see Sign-off\n## Items\n### R1 · <§section or anchor> — [OPEN] (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->\n<what needs to change>\n\n---\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-15 00:00 | pwtest | approved |\n' > "$SBK"
cp "$SBK" "$G/analysis/review/stubonly.review.md"
pwtest_rc 0 "approved + stub-only stays consumable (no marker parsing through stubs)" "$E" gate "$HG" analysis/review/stubonly.review.md
# inject the audit's exact shape: a 4-hash real OPEN heading above ## Sign-off
DK="$(mktemp)"; printf '#### R9 · §2 — [OPEN] (you, 2026-10-05 12:00) <!-- pw-item-status: open -->\ninjected deep blocker\n\n---\n\n' > "$DK"
insert_before "deep-heading setup" '^## Sign-off' "$GRF" "$DK"; rm -f "$DK"
pwtest_rc 1 "gate fails closed on injected 4-hash open marker" "$E" gate "$HG" "$GRV"
pwtest_err 'STALE' "stale-approval note explains the deep block"
if "$E" has-open "$HG" "$GRV" | grep -qx yes; then pwtest_ok "has-open sees the deep marker"
else pwtest_bad "has-open deep" "missed 4-hash open"; fi
pwtest_rc 0 "count sees the deep marker open" "$E" count "$HG" "$GRV"
pwtest_re 'open=1' "count agrees with the gate (no false approval)"
pwtest_rc 1 "deep malformed heading grants no eligible work" "$E" eligible "$HG" "$GRV"
pwtest_re 'eligible=0' "repair authority stays with canonical ### items"
HB_ROWS="$(rowcount ' changes-requested |' "$GRF")"
pwtest_rc 0 "start reports clean with only a deep blocker" "$E" start "$HG" "$GRV"
pwtest_re '__clean__' "start verdict is clean (no repair authority)"
[ "$(rowcount ' changes-requested |' "$GRF")" = "$HB_ROWS" ] \
  && pwtest_ok "start added no row behind a malformed blocker" || pwtest_bad "deep start" "row appeared"
pwtest_rc 0 "configure auto for deep-block refusal" "$CFG" ai-review "$HG" analysis auto
pwtest_rc 2 "auto-signoff refuses past a deep open marker" "$E" auto-signoff "$HG" "$GRV" analysis
grep -q '| pw-reviewer (auto; provider=unknown; model=unknown) | approved |' "$GRF" \
  && pwtest_bad "deep blocker approved anyway" "auto row landed" || pwtest_ok "no auto approval row behind the blocker"
# the tool must never be the injector: heading-syntax text is refused, bytes untouched
BEF="$(md5f "$GRF")"
printf '#### R98 · §2 — [OPEN] (you, 2026-10-05 12:00) <!-- pw-item-status: open -->\n' \
  | pwtest_rc 2 "add-item refuses 4-hash injected heading text" "$E" add-item "$HG" "$GRV" --section '§2' --stdin
printf '## section header attempt\n' \
  | pwtest_rc 2 "add-item refuses 2-hash injected heading text" "$E" add-item "$HG" "$GRV" --section '§2' --stdin
[ "$BEF" = "$(md5f "$GRF")" ] && pwtest_ok "refused injections changed no bytes" || pwtest_bad "injection guard" "file changed"
# raw ask text with reserved-looking tokens in the BODY stays verbatim (only structure is refused)
printf 'check the [OPEN] tag convention in §2 docs (the literal word is fine in a body line)\n' \
  | pwtest_rc 0 "legit ask with tag words in body accepted" "$E" add-item "$HG" "$GRV" --section '§2' --stdin
grep -qF 'check the [OPEN] tag convention' "$GRF" \
  && pwtest_ok "raw ask text preserved verbatim" || pwtest_bad "ask text mangled" "body not verbatim"
rm -rf "$PW_PROJECTS_DIR/$HG" "$SBK"

# ============================================================ H2) archive sibling + slug guard
HS=hard-slug; rm -rf "$PW_PROJECTS_DIR/$HS"; cp -a "$F2" "$PW_PROJECTS_DIR/$HS"
S="$PW_PROJECTS_DIR/$HS"; set_phase "$HS" analysis
SRV=analysis/review/fixture.review.md
pwtest_rc 2 "dotdot slug refused" "$E" archive ".." "$SRV"
pwtest_fix "traversal slug refusal actionable"
pwtest_rc 2 "path slug with traversal component refused" "$E" add-item "a/../$HS" "$SRV" --section '§1' --text nope
pwtest_rc 2 "nested-path slug refused" "$E" archive "sub/$HS" "$SRV"
ln -s "$ROOT" "$PW_PROJECTS_DIR/evil-clone" 2>/dev/null || true
pwtest_rc 2 "slug resolving outside the projects dir refused" "$E" archive evil-clone "$SRV"
pwtest_fix "escape refusal actionable"
rm -f "$PW_PROJECTS_DIR/evil-clone"
# planted symlink at the derived .archive.md sibling → refused before any write
printf 'KEEP\n' > "$ROOT/outside-archive-payload.txt"
ln -s "$ROOT/outside-archive-payload.txt" "$S/analysis/review/fixture.archive.md"
pwtest_rc 0 "seed an archivable resolved item" "$E" add-item "$HS" "$SRV" --section '§1' --text archive me after resolving
RID="$(grep -oE '^### R[0-9]+' "$S/$SRV" | tail -1 | sed 's/^### //')"
pwtest_rc 0 "resolve the item" "$E" resolve "$HS" "$SRV" "$RID" --reply 'done and dusted'
pwtest_rc 2 "archive refuses symlinked sibling" "$E" archive "$HS" "$SRV"
pwtest_err 'symlink' "sibling refusal names the symlink"
[ "$(cat "$ROOT/outside-archive-payload.txt")" = "KEEP" ] \
  && pwtest_ok "external symlink target untouched" || pwtest_bad "public path write" "wrote through sibling symlink"
rm -f "$S/analysis/review/fixture.archive.md"
ln -s "$ROOT/nowhere-exists.txt" "$S/analysis/review/fixture.archive.md"
BEF2="$(md5f "$S/$SRV")"
pwtest_rc 2 "archive refuses dangling symlink sibling" "$E" archive "$HS" "$SRV"
[ ! -e "$ROOT/nowhere-exists.txt" ] && pwtest_ok "dangling redirect target never created" || pwtest_bad "dangling symlink write" "target materialized"
[ "$BEF2" = "$(md5f "$S/$SRV")" ] && pwtest_ok "refused archive changed no review bytes" || pwtest_bad "dangling refusal" "review changed"
rm -f "$S/analysis/review/fixture.archive.md" "$ROOT/outside-archive-payload.txt"
# archive on a non-.review.md target is refused (can't .review→.archive suffix-fold twice)
touch "$S/analysis/review/fixture.archive.md"
pwtest_rc 2 "archive refuses a non-.review.md target" "$E" archive "$HS" analysis/review/fixture.archive.md
rm -f "$S/analysis/review/fixture.archive.md"
# note-init symlink guard
ln -s "$ROOT/notes-outside.md" "$S/REVIEWER-NOTES.md"
pwtest_rc 2 "note-init refuses symlinked notes path" "$E" note-init "$HS"
[ ! -e "$ROOT/notes-outside.md" ] && pwtest_ok "notes redirect never followed" || pwtest_bad "note-init symlink write" "wrote through symlink"
rm -f "$S/REVIEWER-NOTES.md"
rm -rf "$PW_PROJECTS_DIR/$HS"

# ============================================================ H3) reserved syntax + archive can't strip OPEN
HI=hard-inject; rm -rf "$PW_PROJECTS_DIR/$HI"; cp -a "$F2" "$PW_PROJECTS_DIR/$HI"
N="$PW_PROJECTS_DIR/$HI"; set_phase "$HI" analysis
NRV=analysis/review/fixture.review.md
NRF="$N/$NRV"
BEF="$(md5f "$NRF")"
pwtest_rc 2 "actor carrying a status tag is refused" "$E" add-item "$HI" "$NRV" --section '§1' --actor 'x) — [RESOLVED] (you' --text nope
pwtest_rc 2 "actor carrying the machine marker is refused" "$E" add-item "$HI" "$NRV" --section '§1' --actor 'y <!-- pw-item-status: resolved -->' --text nope
pwtest_rc 2 "actor carrying stub tokens is refused" "$E" add-item "$HI" "$NRV" --section '§1' --actor 'z (<YYYY-MM-DD HH:MM>)' --text nope
pwtest_rc 2 "section carrying a status tag is refused" "$E" add-item "$HI" "$NRV" --section '§1 [OPEN] anchor' --text nope
pwtest_rc 2 "section carrying HTML comment syntax is refused" "$E" add-question "$HI" "$NRV" --section '§1 <!-- c -->' --text nope
pwtest_rc 2 "section carrying stub tokens is refused" "$E" add-question "$HI" "$NRV" --section '<§section>' --text nope
[ "$BEF" = "$(md5f "$NRF")" ] && pwtest_ok "every hostile-metadata refusal left no file changes" || pwtest_bad "metadata guard" "bytes moved"
# marker-vs-tag disagreement: gate blocks; archive cannot move it — archiving never removes OPEN
IK="$(mktemp)"; printf '### R4 · §1 — [OPEN] (you, 2026-10-05 12:00) <!-- pw-item-status: resolved -->\ncrafted disagreement\n\n---\n\n' > "$IK"
insert_before "conflict setup" '^## Sign-off' "$NRF" "$IK"; rm -f "$IK"
pwtest_rc 1 "conflicting heading blocks the gate" "$E" gate "$HI" "$NRV"
BEF="$(md5f "$NRF")"
pwtest_rc 0 "archive skips the conflicting heading (no-op)" "$E" archive "$HI" "$NRV"
grep -q '^### R4 · §1 — \[OPEN\]' "$NRF" && grep -q 'crafted disagreement' "$NRF" \
  && pwtest_ok "conflicting OPEN heading stayed live (not archived away)" || pwtest_bad "archive stripped OPEN" "crafted item moved"
[ ! -f "$N/analysis/review/fixture.archive.md" ] \
  && pwtest_ok "no sibling created for a non-archivable set" || pwtest_bad "conflict archive" "sibling written"
rm -rf "$PW_PROJECTS_DIR/$HI"

# ============================================================ H4) machine-role spoof via --by
HB=hard-by; rm -rf "$PW_PROJECTS_DIR/$HB"; cp -a "$F2" "$PW_PROJECTS_DIR/$HB"
B="$PW_PROJECTS_DIR/$HB"; set_phase "$HB" analysis
HRV=task/review/T04.review.md   # fresh template shape, ZERO real items
HRF="$B/$HRV"
BEF="$(md5f "$HRF")"
for spoof in 'pw-reviewer (auto)' 'pw-reviewer (auto; provider=kilo; model=m)' 'pw-reviewer (advisory; provider=kilo; model=m)' 'pw-reviewer' 'pw-review (repair)' 'pw-review (feedback)' 'pw-review (auto-reopen)'; do
  pwtest_rc 2 "signoff --by [$spoof] denied even with zero items" "$E" signoff "$HB" "$HRV" approved --by "$spoof"
  pwtest_err 'reserved machine actor' "denial explains the reserved role"
done
[ "$BEF" = "$(md5f "$HRF")" ] && pwtest_ok "spoof denials wrote nothing" || pwtest_bad "spoof denial" "file changed"
# legacy machine rows stay READABLE (append-only history preserved)
printf '# Review\n## Items\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-01 08:00 | pw-reviewer (auto) | approved |\n' > "$B/analysis/review/legacy-auto.review.md"
pwtest_rc 0 "legacy pw-reviewer (auto) row still gates" "$E" gate "$HB" analysis/review/legacy-auto.review.md
pwtest_rc 0 "named human --by still signs off" "$E" signoff "$HB" "$HRV" approved --by faza
rm -rf "$PW_PROJECTS_DIR/$HB"

# ============================================================ H5) archive no-op purity
HN=hard-noop; rm -rf "$PW_PROJECTS_DIR/$HN"; cp -a "$F2" "$PW_PROJECTS_DIR/$HN"
NRV5="$PW_PROJECTS_DIR/$HN/task/review/T04.review.md"
BEF="$(md5f "$NRV5")"
pwtest_rc 0 "archive on an empty resolved set is a clean no-op" "$E" archive "$HN" task/review/T04.review.md
pwtest_re 'nothing to archive' "the no-op is reported"
[ ! -f "$PW_PROJECTS_DIR/$HN/task/review/T03.archive.md" ] \
  && pwtest_ok "empty archive created no sibling" || pwtest_bad "noop sibling" ".archive.md appeared"
if grep -q '^## Archived items' "$NRV5"; then pwtest_bad "noop header" "Archived items section created on an empty set"
else pwtest_ok "no header written for an empty set"; fi
[ "$BEF" = "$(md5f "$NRV5")" ] && pwtest_ok "no-op changed zero bytes" || pwtest_bad "noop bytes" "file moved"
rm -rf "$PW_PROJECTS_DIR/$HN"

# ============================================================ H6) sibling retry: failed publish must not duplicate
HT=hard-retry; rm -rf "$PW_PROJECTS_DIR/$HT"; cp -a "$F2" "$PW_PROJECTS_DIR/$HT"
T="$PW_PROJECTS_DIR/$HT"; set_phase "$HT" analysis
TRV=analysis/review/extra.review.md
cp "$T/analysis/fixture.md" "$T/analysis/extra.md"
pwtest_rc 0 "init retry target" "$E" init-docs "$HT" analysis/extra.md
pwtest_rc 0 "seed retry item" "$E" add-item "$HT" "$TRV" --section '§1' --text retry payload sentence
RID="$(grep -oE '^### R[0-9]+' "$T/$TRV" | tail -1 | sed 's/^### //')"
pwtest_rc 0 "resolve retry item" "$E" resolve "$HT" "$TRV" "$RID" --reply 'resolved for retry test'
# break the Contents pair so the LAST worker step (rebuild) fails AFTER the sibling append
sedi '/<!-- pw-contents:end -->/d' "$T/$TRV"
BEF="$(md5f "$T/$TRV")"
pwtest_rc 2 "archive aborts when its Contents rebuild fails" "$E" archive "$HT" "$TRV"
grep -qF "### $RID · §1" "$T/$TRV" && [ "$BEF" = "$(md5f "$T/$TRV")" ] \
  && pwtest_ok "failed publish left the review file byte-identical" || pwtest_bad "archive failure purity" "review changed"
AF="$T/analysis/review/extra.archive.md"
[ -f "$AF" ] && pwtest_ok "sibling kept the appended block across the failure" || pwtest_bad "sibling lost on failure" "no sibling"
[ "$(grep -cF "<!-- pw-archived-block:$RID -->" "$AF")" = 1 ] \
  && pwtest_ok "payload fenced exactly once after the failed attempt" || pwtest_bad "block fence" "count != 1"
grep -qF 'retry payload sentence' "$AF" && pwtest_ok "payload landed in the archive" || pwtest_bad "payload lost" "not archived"
# repair by removing the leftover begin marker (neither marker → rebuild recreates the block);
# the retry must complete WITHOUT duplicating the payload or the pointer row
grep -v '<!-- pw-contents:begin -->' "$T/$TRV" > "$T/$TRV.rp" && mv "$T/$TRV.rp" "$T/$TRV"
pwtest_rc 0 "repaired retry completes the archive" "$E" archive "$HT" "$TRV"
[ "$(grep -cF "<!-- pw-archived-block:$RID -->" "$AF")" = 1 ] \
  && pwtest_ok "retry did not duplicate the payload block" || pwtest_bad "retry duplication" "block twice in sibling"
[ "$(grep -cF 'retry payload sentence' "$AF")" = 1 ] \
  && pwtest_ok "payload text appears exactly once" || pwtest_bad "payload duplicated" "text repeated"
[ "$(grep -cF "pw-archived:$RID" "$T/$TRV")" = 1 ] \
  && pwtest_ok "exactly one pointer row after retry" || pwtest_bad "pointer duplication" "multiple pointer rows"
grep -qF "<!-- end pw-archived-block:$RID -->" "$AF" \
  && pwtest_ok "historical block preserved between its fences" || pwtest_bad "block fences" "end fence lost"
grep -qF "### $RID · §1" "$T/$TRV" && pwtest_bad "archive did not move the item" "still live" || pwtest_ok "item moved out of the live file"
rm -rf "$PW_PROJECTS_DIR/$HT"

# ============================================================ H7) splice-failure propagation (stubbed primitives)
UF="$ROOT/hard-unit.md"
mk_unit_file() {
  printf '# Review\nGate: in-review\n<!-- pw-contents:begin -->\n## Contents   [agent-owned; refreshed automatically; do not edit]\n\n| ID | Section / anchor | Status |\n|----|-------------------|--------|\n| _(none yet)_ | | |\n<!-- pw-contents:end -->\n## Items\n\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-01 08:00 | you | approved |\n' > "$UF"
}
mk_unit_file; UB="$(md5f "$UF")"
md_insert_lines_after() { return 1; }   # stub the shared splice primitive
if pw_signoff_row_put "$UF" "2026-10-05 12:00 WIB" "faza" "in-review" 2>/dev/null; then
  pwtest_bad "row_put propagates insert failure" "returned success with a dead splice"
else pwtest_ok "pw_signoff_row_put fails when md_insert_lines_after fails"; fi
[ "$UB" = "$(md5f "$UF")" ] && pwtest_ok "failed row_put left the unit file unchanged" || pwtest_bad "row_put failure" "file mutated"
unset -f md_insert_lines_after
md_replace_line() { return 1; }
if pw_review_gate_refresh "$UF" 2>/dev/null; then pwtest_bad "gate_refresh propagates splice failure" "success with dead splice"
else pwtest_ok "pw_review_gate_refresh fails when md_replace_line fails"; fi
unset -f md_replace_line
md_replace_range() { return 1; }
if pw_review_contents_rebuild "$UF" 2>/dev/null; then pwtest_bad "contents_rebuild propagates splice failure" "success with dead splice"
else pwtest_ok "pw_review_contents_rebuild fails when md_replace_range fails"; fi
if [ -e "$UF.tmp" ]; then rm -f "$UF.tmp"; pwtest_bad "rebuild tmp leak" ".tmp left behind"; else pwtest_ok "no leftover .tmp after a failed rebuild"; fi
unset -f md_replace_range
# placeholder-only table: publish goes through mv — a dead mv must fail the call, not fake success
printf '# Review\nGate: in-review\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| | | in-review |\n' > "$UF"
UB="$(md5f "$UF")"
mv() { return 1; }
if pw_signoff_row_put "$UF" "x" "faza" "approved" 2>/dev/null; then pwtest_bad "placeholder publish propagates mv failure" "success with dead mv"
else pwtest_ok "pw_signoff_row_put fails when the placeholder publish mv fails"; fi
if [ -e "$UF.tmp" ]; then rm -f "$UF.tmp"; pwtest_bad "row_put tmp leak" ".tmp left behind"; else pwtest_ok "row_put cleaned its .tmp on failure"; fi
unset -f mv
[ "$UB" = "$(md5f "$UF")" ] && pwtest_ok "dead-mv placeholder path changed no bytes" || pwtest_bad "dead mv" "file mutated"
rm -f "$UF"

# ============================================================ H8) Contents marker pairing
HC=hard-contents; rm -rf "$PW_PROJECTS_DIR/$HC"; cp -a "$F2" "$PW_PROJECTS_DIR/$HC"
C="$PW_PROJECTS_DIR/$HC"; set_phase "$HC" analysis
CRV=task/review/T04.review.md    # fresh template copy (paired healthy block)
CRF="$C/$CRV"
sedi '/<!-- pw-contents:end -->/d' "$CRF"
BEF="$(md5f "$CRF")"
pwtest_rc 2 "reindex refuses begin-without-end markers" "$E" reindex "$HC" "$CRV"
pwtest_err 'malformed' "pairing refusal names the malformed block"
[ "$BEF" = "$(md5f "$CRF")" ] && pwtest_ok "byte-unchanged on malformed-block reindex" || pwtest_bad "pairing guard" "file rewritten"
BEF="$(md5f "$CRF")"
pwtest_rc 2 "add-item refuses a malformed Contents block" "$E" add-item "$HC" "$CRV" --section '§1' --text should not land
[ "$BEF" = "$(md5f "$CRF")" ] && pwtest_ok "byte-unchanged on malformed-block add-item" || pwtest_bad "add-item pairing" "wrote into malformed file"
printf '<!-- pw-contents:begin -->\n' >> "$CRF"
pwtest_rc 2 "reindex refuses a doubled begin marker" "$E" reindex "$HC" "$CRV"
# orphan end (remove every begin, keep one end) is equally refused — never a blind rewrite
grep -v '<!-- pw-contents:begin -->' "$CRF" > "$CRF.o" && mv "$CRF.o" "$CRF"
printf '<!-- pw-contents:end -->\n' >> "$CRF"
BEF="$(md5f "$CRF")"
pwtest_rc 2 "reindex refuses an orphan end marker" "$E" reindex "$HC" "$CRV"
[ "$BEF" = "$(md5f "$CRF")" ] && pwtest_ok "orphan-end refusal changed no bytes" || pwtest_bad "orphan end" "file rewritten"
# an ordered pair whose window swallows live sections (stray end far below begin) is
# refused: the replacement region must be the Contents block itself
pwtest_rc 0 "init span probe" "$E" init-docs "$HC" task/T02.md
XRF="$C/task/review/T02.review.md"
sedi '/<!-- pw-contents:end -->/d' "$XRF"
printf '<!-- pw-contents:end -->\n' >> "$XRF"
BEF="$(md5f "$XRF")"
pwtest_rc 2 "reindex refuses a pair spanning live sections" "$E" reindex "$HC" task/review/T02.review.md
[ "$BEF" = "$(md5f "$XRF")" ] && pwtest_ok "spanning-pair refusal changed no bytes" || pwtest_bad "spanning pair" "file rewritten"
# and a file with NO markers at all rebuilds cleanly (insertion path) — no over-refusal
grep -vE '<!-- pw-contents:(begin|end) -->' "$CRF" > "$CRF.o" && mv "$CRF.o" "$CRF"
pwtest_rc 0 "marker-free file rebuilds via the insertion path" "$E" reindex "$HC" "$CRV"
pwtest_grep_file '<!-- pw-contents:begin -->' "fresh block inserted" "$CRF"
[ "$(grep -c '<!-- pw-contents:begin -->' "$CRF")" = 1 ] && [ "$(grep -c '<!-- pw-contents:end -->' "$CRF")" = 1 ] \
  && pwtest_ok "inserted block is a single healthy pair" || pwtest_bad "insertion pair" "duplicate markers"
rm -rf "$PW_PROJECTS_DIR/$HC"

# ============================================================ H9) sign-off placement order
HP=hard-place; rm -rf "$PW_PROJECTS_DIR/$HP"; cp -a "$F2" "$PW_PROJECTS_DIR/$HP"
P9="$PW_PROJECTS_DIR/$HP"; set_phase "$HP" analysis
PRV=analysis/review/legacy.review.md
# an OLD placeholder left ABOVE real rows: new transitions append after the LATEST data row
printf '# Review\n## Items\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| | | in-review |\n| 2026-09-01 08:00 | you | approved |\n| 2026-09-02 09:00 | faza | changes-requested |\n' > "$P9/$PRV"
pwtest_rc 0 "signoff on placeholder-above-rows file" "$E" signoff "$HP" "$PRV" in-review --by faza
L_PL="$(grep -nF '| | | in-review |' "$P9/$PRV" | head -1 | cut -d: -f1)"
L_HA="$(grep -nF '| you | approved |' "$P9/$PRV" | head -1 | cut -d: -f1)"
L_HB="$(grep -nF '| faza | changes-requested |' "$P9/$PRV" | head -1 | cut -d: -f1)"
L_NEW="$(grep -nF '| faza | in-review |' "$P9/$PRV" | tail -1 | cut -d: -f1)"
[ -n "$L_PL" ] && [ -n "$L_HA" ] && [ -n "$L_HB" ] && [ -n "$L_NEW" ] \
  && pwtest_ok "placeholder and history rows preserved" || pwtest_bad "placement" "a row vanished"
[ "$L_PL" -lt "$L_HA" ] && [ "$L_HA" -lt "$L_HB" ] && [ "$L_HB" -lt "$L_NEW" ] \
  && pwtest_ok "new row appended after the current latest (never above real rows)" \
  || pwtest_bad "placement order" "placeholder=$L_PL approved=$L_HA cr=$L_HB new=$L_NEW"
[ "$(_signoff_latest_decision "$P9/$PRV")" = "in-review" ] \
  && pwtest_ok "latest reader sees the new transition" || pwtest_bad "placement read" "latest still old"
# first-ever decision on a placeholder-only table still REPLACES the placeholder
PRV2=analysis/review/fresh2.review.md
printf '# Review\n## Items\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| | | in-review |\n' > "$P9/$PRV2"
pwtest_rc 0 "first signoff replaces untouched placeholder" "$E" signoff "$HP" "$PRV2" approved --by faza
[ "$(grep -cF '| | | in-review |' "$P9/$PRV2")" = 0 ] \
  && pwtest_ok "placeholder consumed on first decision" || pwtest_bad "placeholder path" "not replaced"
rm -rf "$PW_PROJECTS_DIR/$HP"

# ============================================================ H10) lock ownership (no age takeover)
HL=hard-lock; rm -rf "$PW_PROJECTS_DIR/$HL"; cp -a "$F2" "$PW_PROJECTS_DIR/$HL"
L10="$PW_PROJECTS_DIR/$HL"; set_phase "$HL" analysis
LRV=analysis/review/fixture.review.md
LRF="$L10/$LRV"
mkdir "$LRF.pwlock"
printf '99999\n' > "$LRF.pwlock/owner"
touch -t 202001010000 "$LRF.pwlock"       # older than any takeover window: must STILL block
BEF="$(md5f "$LRF")"
pwtest_rc 2 "old-stamped live lock is never stolen" "$E" add-item "$HL" "$LRV" --section '§1' --text nope
pwtest_err 'locked by another writer' "busy report names the condition"
pwtest_err 'remove the stale lock' "explicit stale-removal guidance offered"
[ -d "$LRF.pwlock" ] && [ "$(cat "$LRF.pwlock/owner")" = "99999" ] \
  && pwtest_ok "foreign lock survived a failed write (unlock is owned-only)" || pwtest_bad "lock steal" "took over another holder"
[ "$BEF" = "$(md5f "$LRF")" ] && pwtest_ok "locked refusal changed no bytes" || pwtest_bad "locked write" "file mutated"
rm -rf "$LRF.pwlock"
# failure cleanup removes OUR lock: force a worker failure with a malformed Contents block
sedi '/<!-- pw-contents:end -->/d' "$LRF"
pwtest_rc 2 "writer fails closed on malformed block" "$E" add-item "$HL" "$LRV" --section '§1' --text nope
[ ! -d "$LRF.pwlock" ] && pwtest_ok "owned lock released on failure" || pwtest_bad "lock leak" ".pwlock survived a failed op"
if ls "$L10/analysis/review" | grep -q 'pwrev\|\.tmp\|\.hdr'; then pwtest_bad "failure tmp leak" "temps left in the review dir"
else pwtest_ok "failed writer left no temps in the project"; fi
rm -rf "$PW_PROJECTS_DIR/$HL"

# ============================================================ H11) init title escaping + safe creation
HTI=hard-title; rm -rf "$PW_PROJECTS_DIR/$HTI"; cp -a "$F2" "$PW_PROJECTS_DIR/$HTI"
TI="$PW_PROJECTS_DIR/$HTI"; set_phase "$HTI" analysis
pwtest_rc 0 "init with sed-metacharacter doc name" "$E" init "$HTI" 'analysis/review/esc.review.md' 'analysis/we&ird\pi|pe.md'
TIH="$TI/analysis/review/esc.review.md"
grep -qxF '# Review: we&ird\pi|pe.md' "$TIH" \
  && pwtest_ok "title preserved (& backslash | escaped)" || pwtest_bad "title sed corruption" "got: $(head -1 "$TIH")"
grep -qF 'Reviewing: [we&ird\pi|pe.md](../we&ird\pi|pe.md)' "$TIH" \
  && pwtest_ok "Reviewing link escaped too" || pwtest_bad "link escape" "$(sed -n '3p' "$TIH")"
if grep -q '<doc.md>' "$TIH"; then pwtest_bad "token left" "unsubstituted <doc.md>"; else pwtest_ok "no unsubstituted placeholder token"; fi
# dangling symlink creation target is refused before writing
ln -s "$ROOT/never-created.md" "$TI/analysis/review/dang.review.md"
pwtest_rc 2 "init refuses dangling symlinked target" "$E" init "$HTI" analysis/review/dang.review.md analysis/fixture.md
[ ! -e "$ROOT/never-created.md" ] && pwtest_ok "dangling init target never created" || pwtest_bad "init symlink write" "wrote through link"
rm -f "$TI/analysis/review/dang.review.md"
# no .pwlock or temp litter after init
if ls "$TI/analysis/review" | grep -q 'pwlock\|\.init\.\|\.hard\.tmp'; then pwtest_bad "init temp leak" "lock/temp left behind"
else pwtest_ok "init left no lock or temp litter"; fi
rm -rf "$PW_PROJECTS_DIR/$HTI"

# ============================================================ H12) fail-closed pass entry ordering
HF=hard-startfail; rm -rf "$PW_PROJECTS_DIR/$HF"; cp -a "$F2" "$PW_PROJECTS_DIR/$HF"
F12="$PW_PROJECTS_DIR/$HF"; set_phase "$HF" analysis
FRV=analysis/review/badstate.review.md
# invalid latest decision + EMPTY work set: the old order short-circuited clean BEFORE the
# enum check, reporting an untrustworthy file as clean.
printf '# Review\nGate: see Sign-off\n## Items\n\n## Open questions\n\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-01 08:00 | you | rejected |\n' > "$F12/$FRV"
BEF="$(md5f "$F12/$FRV")"
pwtest_rc 2 "start fails closed on invalid decision with empty work" "$E" start "$HF" "$FRV"
pwtest_err 'unrecognized latest decision' "invalid decision named, not swallowed"
[ "$BEF" = "$(md5f "$F12/$FRV")" ] && pwtest_ok "fail-closed start changed no bytes" || pwtest_bad "start fail" "file mutated"
# RFC staging still keeps no approval role at all
printf '# RFC comment staging\n\n## Items\n' > "$F12/analysis/review/RFC.review.md"
pwtest_rc 2 "RFC staging gets no pass entry" "$E" start "$HF" analysis/review/RFC.review.md
pwtest_rc 2 "RFC staging gets no auto approval" "$E" auto-signoff "$HF" analysis/review/RFC.review.md analysis
rm -rf "$PW_PROJECTS_DIR/$HF"

# ============================================================ H13) formatter hygiene
if declare -F pw_now_wib_date >/dev/null 2>&1; then
  pwtest_bad "unused date-only formatter removed" "pw_now_wib_date still defined"
else pwtest_ok "unused date-only WIB formatter removed from reviewlib"; fi
if grep -q 'pw_now_wib_date' "$TOOL/scripts/lib/pw-reviewlib.sh" "$TOOL/scripts/entities/pw-review.sh" 2>/dev/null; then
  pwtest_bad "stale formatter references remain" "pw_now_wib_date still referenced in shipped sources"
else pwtest_ok "review writers keep the single full-WIB stamp (pw_now_wib)"; fi
unset -f set_phase md5f rowcount insert_before mk_unit_file 2>/dev/null || true
