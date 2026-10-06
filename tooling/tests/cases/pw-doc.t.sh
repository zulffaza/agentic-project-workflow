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

# C22 (2026-09-16): review marker lint reads the shared detector — unfilled stubs must not false-fail,
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

# ---------- PLAN task-table reconciliation (sync --plan-only) ----------
# All cases below run against PRIVATE F2 copies (fixture etiquette: clone, never mutate $F2).

tsync_cell() { # <plan> <Tnn> <lower-col> — header-name cell reader mirroring _plan_cell_update's mapping
  awk -F'|' -v id="$2" -v col="$3" '
    function norm(s){ gsub(/[ \t`*]/, "", s); return tolower(s) }
    /^## Task/ { p = 1 }
    p && /^## / && !/^## Task/ { p = 0 }
    p && /^[ \t]*\|/ {
      n = split($0, c, "|")
      if (!hdr) { for (i = 2; i < n; i++) { v = norm(c[i]); if (v == "id" || v == "task") ic = i; if (v == col) tc = i }; hdr = 1; next }
      if ($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) next
      if (ic > 0 && tc > 0 && n > tc) {
        d = c[ic]; gsub(/[ \t]/, "", d)
        if (match(d, /T[0-9]+/) && substr(d, RSTART, RLENGTH) == id) {
          v = c[tc]; gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v); print v; exit
        }
      }
    }' "$1"
}
tsync_sub() { # <file> <old> <new> … — exact substring replaces (pairs); LOUD if an anchor is absent
  python3 -c 'import sys
f = sys.argv[1]; t = open(f, encoding = "utf-8").read()
for k, v in zip(sys.argv[2::2], sys.argv[3::2]):
    assert k in t, "anchor missing: " + k[:72]
    t = t.replace(k, v)
open(f, "w", encoding = "utf-8").write(t)' "$@"
}
tsync_setrow() { # <plan> <Tnn> <status> <time> <result> — set the three tracked cells of a current-shape row
  awk -F'|' -v id="$2" -v st="$3" -v tm="$4" -v res="$5" '
    /^## Task/ { p = 1 }
    p && /^## / && !/^## Task/ { p = 0 }
    p && /^[ \t]*\|/ {
      n = split($0, c, "|")
      if (!hdr) { hdr = 1 }
      else if (n >= 12 && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/)) {
        d = c[2]; gsub(/[ \t]/, "", d)
        if (match(d, /T[0-9]+/) && substr(d, RSTART, RLENGTH) == id) {
          c[9] = " " st " "; c[10] = " " tm " "; c[11] = " " res " "
          line = ""
          for (i = 1; i <= n; i++) line = line c[i] (i < n ? "|" : "")
          print line; next
        }
      }
    }
    { print }' "$1" > "$1.tsynctmp" && mv "$1.tsynctmp" "$1"
}
tsync_cksum() { shasum -a 256 "$1"; }

# Case A — current table, linked IDs: Status/Time/Result copy from the task files;
# links and all other cells survive; Result-scoped MR URL beats Commit(s); idempotent rerun.
S=sync-plan-a; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSCUR="$PW_PROJECTS_DIR/$S"; PF="$TSCUR/task/PLAN.md"
tsync_sub "$TSCUR/task/T01.md" '- **Time:** <wall-clock, e.g. 12m>' '- **Time:** 12m' '- **Commit(s):** —' '- **Commit(s):** a1b2c3'
tsync_sub "$TSCUR/task/T02.md" '- **Time:** <wall-clock, e.g. 12m>' '- **Time:** 5m' '- **Commit(s):** —' '- **Commit(s):** c0ffee1'
tsync_sub "$TSCUR/task/T04.md" '- **Time:** <wall-clock, e.g. 12m>' '- **Time:** 2m'
tsync_setrow "$PF" T01 stale-1 keep-time keep-result
tsync_setrow "$PF" T02 stale-2 keep-time keep-result
tsync_setrow "$PF" T03 stale-3 keep-time keep-result
tsync_setrow "$PF" T04 stale-4 keep-time keep-result
pwtest_rc 0 "table-sync A: sync --plan-only" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_eq "A: T01 status copied (never promoted)" "done" "$(tsync_cell "$PF" T01 status)"
pwtest_eq "A: T01 time from Result" "12m" "$(tsync_cell "$PF" T01 time)"
pwtest_eq "A: T01 commits kept, no MR" "a1b2c3" "$(tsync_cell "$PF" T01 result)"
pwtest_eq "A: MR URL wins over Commit(s)" "https://gitlab.example.com/pwtest/api/-/merge_requests/42" "$(tsync_cell "$PF" T02 result)"
pwtest_eq "A: T02 time" "5m" "$(tsync_cell "$PF" T02 time)"
pwtest_eq "A: T03 status in-progress" "in-progress" "$(tsync_cell "$PF" T03 status)"
pwtest_eq "A: T04 status verify-failed" "verify-failed" "$(tsync_cell "$PF" T04 status)"
grep -qF '[T01](./T01.md)' "$PF" && pwtest_ok "A: markdown-linked IDs preserved" || pwtest_bad "A: linked IDs" "link destroyed"
pwtest_eq "A: Title cell untouched" "Add rate limiter" "$(tsync_cell "$PF" T02 title)"
pwtest_eq "A: depends_on untouched" "T01" "$(tsync_cell "$PF" T02 depends_on)"
pwtest_eq "A: SP cell untouched" "3" "$(tsync_cell "$PF" T02 sp)"
before="$(tsync_cksum "$PF")"
pwtest_rc 0 "A: repeat sync" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
[ "$before" = "$(tsync_cksum "$PF")" ] && pwtest_ok "A: repeat sync byte-identical (idempotence)" || pwtest_bad "A: idempotence" "PLAN changed on a no-op sync"

# Case B — legacy table, reordered columns, no Time/Result columns: Status updates BY NAME,
# Notes/Title cells survive, absent columns must not fail the sync.
S=sync-plan-b; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSLEG="$PW_PROJECTS_DIR/$S"; PF="$TSLEG/task/PLAN.md"
python3 -c 'import re, sys
f = sys.argv[1]
t = open(f, encoding = "utf-8").read()
new = ("| Task | Notes | Status | Title |\n"
       "|------|-------|--------|-------|\n"
       "| T01 | keep-me | stale-1 | Fix api'"'"'s retry shim |\n"
       "| [T02](./T02.md) | plain-notes | stale-2 | Add rate limiter |\n"
       "| **T03** | bold-id-row | stale-3 | Harden the sentinel path |\n"
       "| [T04](./T04.md) | n4 | stale-4 | Audit legacy flags |\n")
t, k = re.subn(r"\| ID \| Title \| Repo \| depends_on \| Group \| Execute with \| SP \| Status \| Time \| Result \|\n\|[-| ]+\n(?:\|[^\n]*\n)+", new, t, count = 1)
assert k == 1, "legacy table replace did not fire"
open(f, "w", encoding = "utf-8").write(t)' "$PF"
pwtest_rc 0 "table-sync B: legacy reordered table syncs without Time/Result" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_eq "B: T01 status by column name" "done" "$(tsync_cell "$PF" T01 status)"
pwtest_eq "B: T02 status linked row" "done" "$(tsync_cell "$PF" T02 status)"
pwtest_eq "B: T03 status bold-id row" "in-progress" "$(tsync_cell "$PF" T03 status)"
pwtest_eq "B: T04 status verify-failed" "verify-failed" "$(tsync_cell "$PF" T04 status)"
pwtest_eq "B: Notes cell preserved" "keep-me" "$(tsync_cell "$PF" T01 notes)"
pwtest_eq "B: Title cell preserved" "Harden the sentinel path" "$(tsync_cell "$PF" T03 title)"

# Case C — partial/rejected execution + empty-source preservation: the five recorded statuses
# copy verbatim (todo, in-progress, verify-failed, done, accepted); fields absent from the
# task file leave the PLAN cell untouched.
S=sync-plan-c; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSSTS="$PW_PROJECTS_DIR/$S"; PF="$TSSTS/task/PLAN.md"
cp "$TSSTS/task/T01.md" "$TSSTS/task/T05.md"
tsync_sub "$TSSTS/task/T01.md" '- **Status:** done' '- **Status:** todo'
tsync_sub "$TSSTS/task/T01.md" '
- **Time:** <wall-clock, e.g. 12m>' '
' '
- **Commit(s):** —' '
'
tsync_sub "$TSSTS/task/T03.md" '- **Status:** in-progress' '- **Status:** verify-failed'
tsync_sub "$TSSTS/task/T04.md" '- **Status:** verify-failed' '- **Status:** accepted'
tsync_sub "$TSSTS/task/T05.md" '- **Status:** done' '- **Status:** in-progress'
python3 -c 'import sys
f = sys.argv[1]
L = open(f, encoding = "utf-8").read().splitlines(True)
for i, x in enumerate(L):
    if x.startswith("| [T04]("):
        L.insert(i + 1, "| T05 | extra task | api | T01 | G1 | kilotest/test-model | 1 | stale-5 | — | — |\n")
        break
open(f, "w", encoding = "utf-8").write("".join(L))' "$PF"
tsync_setrow "$PF" T01 stale-1 keep-time keep-result
tsync_setrow "$PF" T02 stale-2 keep-time keep-result
tsync_setrow "$PF" T03 stale-3 keep-time keep-result
tsync_setrow "$PF" T04 stale-4 keep-time keep-result
pwtest_rc 0 "table-sync C: sync copies the full status ladder" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_eq "C: todo copies" "todo" "$(tsync_cell "$PF" T01 status)"
pwtest_eq "C: done copies" "done" "$(tsync_cell "$PF" T02 status)"
pwtest_eq "C: verify-failed copies" "verify-failed" "$(tsync_cell "$PF" T03 status)"
pwtest_eq "C: accepted copies" "accepted" "$(tsync_cell "$PF" T04 status)"
pwtest_eq "C: in-progress copies" "in-progress" "$(tsync_cell "$PF" T05 status)"
pwtest_eq "C: empty source preserves Time cell" "keep-time" "$(tsync_cell "$PF" T01 time)"
pwtest_eq "C: empty source preserves Result cell" "keep-result" "$(tsync_cell "$PF" T01 result)"

# Case D — recorded Result variants: Verify-section examples ignored, MR precedence,
# sentinel keeps commits, literal pipes escaped (never add cells), CRLF tasks leak no CR.
S=sync-plan-d; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSVAR="$PW_PROJECTS_DIR/$S"; PF="$TSVAR/task/PLAN.md"
tsync_sub "$TSVAR/task/T01.md" '## Verify (Definition of Done)' '## Verify (Definition of Done)
- **Time:** 99h
- **Commit(s):** zzz999'
tsync_sub "$TSVAR/task/T01.md" '- **Time:** <wall-clock, e.g. 12m>' '- **Time:** 12m' '- **Commit(s):** —' '- **Commit(s):** a1b2c3'
tsync_sub "$TSVAR/task/T02.md" '- **Commit(s):** —' '- **Commit(s):** c0ffee1'
tsync_sub "$TSVAR/task/T03.md" '- **MR:** -' '- **MR:** (none)' '## Steps' '## Steps
- Decoy: https://gitlab.example.com/pwtest/decoy/-/merge_requests/999 for context' '- **Commit(s):** —' '- **Commit(s):** e5f6a7'
tsync_sub "$TSVAR/task/T04.md" '- **Commit(s):** —' '- **Commit(s):** aaa|bbb'
cp "$TSVAR/task/T02.md" "$TSVAR/task/T05.md"
tsync_sub "$TSVAR/task/T05.md" '- **Status:** done' '- **Status:** accepted'
awk '{ printf "%s\r\n", $0 }' "$TSVAR/task/T05.md" > "$TSVAR/task/T05.crlf" && mv "$TSVAR/task/T05.crlf" "$TSVAR/task/T05.md"
python3 -c 'import sys
f = sys.argv[1]
L = open(f, encoding = "utf-8").read().splitlines(True)
for i, x in enumerate(L):
    if x.startswith("| [T04]("):
        L.insert(i + 1, "| T05 | crlf task | api | T01 | G1 | kilotest/test-model | 1 | stale-5 | — | — |\n")
        break
open(f, "w", encoding = "utf-8").write("".join(L))' "$PF"
pwtest_rc 0 "table-sync D: result-variant sync" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_eq "D: Time read Result-scoped (Verify decoy ignored)" "12m" "$(tsync_cell "$PF" T01 time)"
pwtest_eq "D: Commit(s) read Result-scoped (Verify decoy ignored)" "a1b2c3" "$(tsync_cell "$PF" T01 result)"
pwtest_eq "D: MR URL beats Commit(s)" "https://gitlab.example.com/pwtest/api/-/merge_requests/42" "$(tsync_cell "$PF" T02 result)"
pwtest_eq "D: (none) sentinel keeps commits, Steps URL ignored" "e5f6a7" "$(tsync_cell "$PF" T03 result)"
pwtest_eq "D: literal pipe escaped in cell" "aaa&#124;bbb" "$(tsync_cell "$PF" T04 result)"
d4cells="$(awk -F'|' '/^\| \[T04\]/ { print NF; exit }' "$PF")"
pwtest_eq "D: escaped pipe adds no cells" "12" "$d4cells"
pwtest_eq "D: CRLF task copies status exact (no CR bleed)" "accepted" "$(tsync_cell "$PF" T05 status)"
if grep -q $'\r' "$PF"; then pwtest_bad "D: PLAN stays CR-free" "a CR leaked from the CRLF task file into PLAN.md"; else pwtest_ok "D: PLAN stays CR-free"; fi

# Case E — atomic failure + entry-path wiring.
S=sync-plan-e1; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSERR="$PW_PROJECTS_DIR/$S"; PF="$TSERR/task/PLAN.md"
tsync_sub "$PF" '| Execute with | SP | Status | Time | Result |' '| Execute with | SP | Time | Result |'
before="$(tsync_cksum "$PF")"
pwtest_rc 2 "E: missing Status column fails the sync" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_err 'no Status column' "E: failure names the missing column"
pwtest_fix "E: missing column carries a fix hint"
[ "$before" = "$(tsync_cksum "$PF")" ] && pwtest_ok "E: missing column leaves PLAN untouched" || pwtest_bad "E: atomic (missing column)" "PLAN was modified"
rm -rf "$PW_PROJECTS_DIR/$S"
S=sync-plan-e2; rm -rf "$PW_PROJECTS_DIR/$S"; cp -a "$F2" "$PW_PROJECTS_DIR/$S"; TSERR="$PW_PROJECTS_DIR/$S"; PF="$TSERR/task/PLAN.md"
tsync_setrow "$PF" T01 stale-1 keep-time keep-result
tsync_setrow "$PF" T02 stale-2 keep-time keep-result
python3 -c 'import sys
f = sys.argv[1]
L = open(f, encoding = "utf-8").read().splitlines(True)
open(f, "w", encoding = "utf-8").write("".join(x for x in L if not x.startswith("| [T03")))
' "$PF"
before="$(tsync_cksum "$PF")"
pwtest_rc 2 "E: missing task row fails the sync" "$(pwtest_script pw-doc.sh)" sync "$S" --plan-only
pwtest_err 'no row for T03' "E: failure names the missing row"
[ "$before" = "$(tsync_cksum "$PF")" ] && pwtest_ok "E: earlier staged rows rolled back too" || pwtest_bad "E: atomic (missing row)" "partial PLAN edits survived the failure"
rm -rf "$PW_PROJECTS_DIR/$S"
for f in "$TOOL/commands/pw-execute.md" "$TOOL/agents/pw-orchestrator.md" "$TOOL/skill/project-workflow/references/execution-and-routing.md"; do
  b="$(basename "$f")"
  if grep -qF 'sync <slug> --plan-only' "$f" && grep -qF 'sync <slug> --dashboard-only' "$f" \
     && grep -qiF 'resolving scope' "$f" && grep -qiF 'starts or returns' "$f" \
     && grep -qiF 'repair/re-verification' "$f" && grep -qiF 'scheduling dependents' "$f"; then
    pwtest_ok "E: entry path reconciles the PLAN at every checkpoint: $b"
  else pwtest_bad "E: entry path checkpoint wiring: $b" "a sync checkpoint clause is missing from $f"
  fi
done
grep -qF "copies each task file's Status" "$TOOL/docs/scripts/document-automation.md" \
  && pwtest_ok "E: sync contract documented (--plan-only)" || pwtest_bad "E: sync contract documented" "document-automation.md lost the PLAN-table clause"
rm -rf "$PW_PROJECTS_DIR/sync-plan-a" "$PW_PROJECTS_DIR/sync-plan-b" "$PW_PROJECTS_DIR/sync-plan-c" "$PW_PROJECTS_DIR/sync-plan-d"
