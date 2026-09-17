# shellcheck shell=bash
# cases/pw-doc.t.sh — the docs entity (merged plan 20 Phase 4: lint/summary/sync).
pwtest_rc 0 "lint all F2 baseline passes" "$(pwtest_script pw-doc.sh)" lint all "$S2"
pwtest_rc 1 "lint all F3 flags hostile file" "$(pwtest_script pw-doc.sh)" lint all "$S3"
pwtest_err 'missing|Story|Repo' "names the broken fields"
pwtest_fix "lint failure carries what-to-do"
pwtest_rc 1 "task T06 (missing fields, CRLF)" "$(pwtest_script pw-doc.sh)" lint task "$S3" T06
cp "$F2/task/T01.md" "$F2/task/T99.md"
sed -i '' -e '/\*\*Repo:\*\*/d' "$F2/task/T99.md"
pwtest_rc 1 "task with no Repo errors on that field" "$(pwtest_script pw-doc.sh)" lint task "$S2" T99
pwtest_fix "missing-field actionable"
rm -f "$F2/task/T99.md"
pwtest_rc 0 "task T03 prose-polluted values tolerated (C17)" "$(pwtest_script pw-doc.sh)" lint task "$S3" T03
pwtest_rc 2 "unknown project" "$(pwtest_script pw-doc.sh)" lint all nope-xyz
pwtest_fix "unknown project actionable"
pwtest_rc 2 "bogus mode" "$(pwtest_script pw-doc.sh)" lint bogus "$S2"

# C22 (2026-09-16): review marker lint reads pw-lib's detector — unfilled stubs must not false-fail,
# a filled real item with no status marker must.
RVF="$PWTEST_F2/task/review/T04.review.md"
pwtest_rc 0 "lint review on template-shape file (stubs exempt)" "$(pwtest_script pw-doc.sh)" lint review "$S2" "task/review/T04.review.md"
# The C22 mutation below writes into the SHARED F2 fixture — back it up and restore after,
# or T2's `lint-all pwt-f2-mid` later sees the leftover marker-less item and (correctly) fails.
cp "$RVF" "$RVF.c22bak"
awk '/^## Open questions/{print "### R9 · §1 real ask — (you, 2026-09-16 12:00)"; print "no marker here"; print "---"; print ""} {print}' "$RVF" > "$RVF.a" && mv "$RVF.a" "$RVF"
pwtest_rc 1 "lint review flags marker-less real item (C22)" "$(pwtest_script pw-doc.sh)" lint review "$S2" "task/review/T04.review.md"
if grep -q '1 item headings but only 0' "$PWTEST_BOTH"; then pwtest_ok "count in the error text (C22d)"; else pwtest_bad "count in the error text (C22d)" "$(head -c 160 "$PWTEST_BOTH" | tr '\n' ' ')"; fi
mv "$RVF.c22bak" "$RVF"

pwtest_rc 0 "summary plan F2" "$(pwtest_script pw-doc.sh)" summary plan "$S2"
pwtest_re '^Tasks: 4' "plan mode counts 4 tasks (linked IDs, C4)"
pwtest_re 'SP=7|SP: 7' "SP summed (1+3+2+1)"
pwtest_re 'Repos:' "repos listed (Repo manifest)"
pwtest_re '^Produced by: [a-z-]*$' "Produced by = bare provider token, no template prose ('$' anchor)"
pwtest_rc 0 "summary plan F3 hostile" "$(pwtest_script pw-doc.sh)" summary plan "$S3"
pwtest_re '^Tasks: 6' "hostile rows (plain+linked ids, quotes) parsed"
pwtest_rc 0 "summary project F2" "$(pwtest_script pw-doc.sh)" summary project "$S2"
pwtest_re '^Phase: executing' "phase token extracted (not prose)"
pwtest_rc 0 "summary project F3" "$(pwtest_script pw-doc.sh)" summary project "$S3"
pwtest_rc 0 "summary task F2 T01" "$(pwtest_script pw-doc.sh)" summary task "$S2" T01
pwtest_re 'Repo: api' "task keys parsed"
pwtest_rc 2 "unknown project" "$(pwtest_script pw-doc.sh)" summary project nope
pwtest_fix "summary unknown carries fix"

S=sync-f2; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"
D="$PW_PROJECTS_DIR/$S/README.md"
python3 - "$D" <<'PY'
import sys
f=sys.argv[1]; out=[]
for L in open(f):
    s=L.rstrip("\n")
    if s.startswith("| T01 |") and "| T01 |" in s:
        s=s.replace("| T01 |","| TXX |",1)       # renamed row → rebuild must drop it & re-add T01
    if s.startswith("| T02 |") and s.count("|")>=5:
        # hand-edit the Notes cell (last field) — the table rebuild must NEVER erase it (C7)
        parts=s.split("|"); parts[-2]=" handnote "
        s="|".join(parts)
    out.append(s+"\n")
open(f,"w").write("".join(out))
PY
pwtest_rc 1 "drifted dashboard lints red" "$(pwtest_script pw-doc.sh)" lint dashboard "$S"
pwtest_fix "drift points at pw-doc.sh sync"
pwtest_rc 0 "sync --dashboard-only repairs" "$(pwtest_script pw-doc.sh)" sync "$S" --dashboard-only
pwtest_rc 0 "post-repair lint green" "$(pwtest_script pw-doc.sh)" lint dashboard "$S"
grep -q 'handnote' "$D" && pwtest_ok "C7 hand-written Notes preserved through rebuild" || pwtest_bad "C7 Notes preservation" "Notes wiped by rebuild (must never happen)"
grep -q '^| T02 | api' "$D" && pwtest_bad "C7 TXX stale row dropped" "renamed row survived rebuild" || pwtest_ok "C7 stale row dropped by rebuild"
cp "$D" "$ROOT/sync.pass1"
pwtest_rc 0 "sync second run" "$(pwtest_script pw-doc.sh)" sync "$S" --dashboard-only
cmp -s "$ROOT/sync.pass1" "$D" && pwtest_ok "sync idempotent (second run no-op)" || pwtest_bad "sync idempotent" "README changed on a no-op run"
pwtest_rc 2 "sync unknown project rc2+fix" "$(pwtest_script pw-doc.sh)" sync nope; pwtest_fix "sync unknown fix"
rm -rf "$PW_PROJECTS_DIR/$S"
