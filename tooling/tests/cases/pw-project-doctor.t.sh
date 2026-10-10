# shellcheck shell=bash
# cases/pw-project-doctor.t.sh — the PROJECT side of the doctor: the C1–C12 walk, its
# read-only contract (the "doctor never mutates without --fix" canary), and --fix limited to
# the deterministic writer. Runs against clones of F2 (happy) / F3 (hostile). All variables are
# pd_-prefixed (T1 cases share one sourced shell — short names have bitten the harness before).
#
# Forge-state isolation: earlier sourced T1 cases (pw-preflight) can leave `42 merged` in the
# shared fake-forge ledger — which is EXACTLY the merged-but-unaccepted condition C7 must flag,
# so the happy-walk sections reset it; the planted-C7 section writes it back deliberately.
PDF="$ROOT/pd-dir"; mkdir -p "$PDF"
PDOCTOR="$(pwtest_script pw-project-doctor.sh)"
PDF2CFG="$PWTEST_TESTSDIR/pw.config.test.f2.sh"
: > "$PWTEST_FORGE_STATE_FILE"

pd_sha() { ( cd "$1" && find . -type f ! -name '*.tmp' ! -name '.*-err' -exec shasum {} + | sort | shasum ); }

# --- contract: unknown project → exit 2 with a fix -------------------------------------------
pwtest_rc 2 "doctor unknown project" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" nope-not-here
pwtest_fix "unknown project carries the fix"

# --- F2 happy walk: 0 ✗, exit 0, and NOTHING MUTATED (read-only contract canary) ------------
cp -a "$F2" "$PW_PROJECTS_DIR/pd-ok"
PWOK="$PW_PROJECTS_DIR/pd-ok"
PDPRE="$(pd_sha "$PW_PROJECTS_DIR/pd-ok")"
pwtest_rc 0 "doctor F2 walk exits 0" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-ok
pwtest_re 'project-doctor pd-ok: 0 ✗' "F2 summary line: zero ✗"
PDPOST="$(pd_sha "$PW_PROJECTS_DIR/pd-ok")"
[ "$PDPRE" = "$PDPOST" ] && pwtest_ok "doctor mutates nothing without --fix" || pwtest_bad "read-only contract" "project tree hash changed"

# --- C7 planted state: dashboard MR says merged, task says done → flagged, fix named. The
# agreement read is the dashboard MR table itself (owner ruling 09-28 — no live forge call). ---
awk -F'|' '/^## Merge requests/{sec=1} sec && /^\|[ -|]+$/ && !done {print; print "| T02 | api | [MR 42](https://gitlab.example.com/pwtest/api/-/merge_requests/42) | master | merged | — |"; done=1; next} {print}' "$PWOK/README.md" > "$PWOK/README.md.a" && mv "$PWOK/README.md.a" "$PWOK/README.md"
pwtest_rc 1 "doctor flags merged-but-unaccepted MR" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-ok
grep -qE "✗ .*T02.*dashboard MR says merged but task Status is 'done'" "$PWTEST_BOTH" \
  && pwtest_ok "C7 names the offender + acceptance fix" || pwtest_bad "C7 planted" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"
grep -qE '→ fix:.*accept pd-ok T02' "$PWTEST_BOTH" \
  && pwtest_ok "C7 fix line names the acceptance flow in user words" || pwtest_bad "C7 fix line" "$(grep '→' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
grep -qE '→ fix:.*pw-[a-z-]*\.sh' "$PWTEST_BOTH" \
  && pwtest_bad "fix hint names a raw script" "$(grep '→ fix:' "$PWTEST_BOTH" | head -1)" \
  || pwtest_ok "fix hints are script-free (plan 27 F1)"

# --- F3 hostile walk: exits 1 and NAMES the prose pin + the failing gate ----------------------
cp -a "$F3" "$PW_PROJECTS_DIR/pd-hostile"
pwtest_rc 1 "doctor F3 walk exits 1" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-hostile
grep -qE '✗ .*prose, not a single pin' "$PWTEST_BOTH" \
  && pwtest_ok "F3 prose 'Execute with:' named as ✗" || pwtest_bad "prose pin" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"
grep -qE '✗ .*PLAN gate failing' "$PWTEST_BOTH" \
  && pwtest_ok "F3 gate failure surfaced via preflight reuse" || pwtest_bad "gate ✗" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"

# --- C6 negatives (one scratch clone per planted defect, isolated greps) ----------------------
PDC6="$PW_PROJECTS_DIR/pd-c6"; cp -a "$F2" "$PDC6"
pwtest_rc 1 "doctor flags an illegal review mode" env PW_CONFIG_FILE="$PDF2CFG" bash -c \
  "sed -i '' 's/analysis=advisory/analysis=maybe/' '$PDC6/README.md' && PW_CONFIG_FILE='$PDF2CFG' '$PDOCTOR' pd-c6"
grep -qE "✗ .*AI Review row 'analysis=maybe'.*outside advisory\|auto" "$PWTEST_BOTH" \
  && pwtest_ok "illegal mode named precisely" || pwtest_bad "illegal mode" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
# a legacy stored `off` is NOT an illegal value: it reads as effective advisory — the doctor
# reports one migration note (not a ✗), and ensure is the persistence door.
PDC6L="$PW_PROJECTS_DIR/pd-c6-legacy"; cp -a "$F2" "$PDC6L"
pwtest_rc 0 "doctor accepts a legacy off row (advisory migration)" env PW_CONFIG_FILE="$PDF2CFG" bash -c \
  "sed -i '' 's/analysis=advisory/analysis=off/' '$PDC6L/README.md' && PW_CONFIG_FILE='$PDF2CFG' '$PDOCTOR' pd-c6-legacy"
grep -qE "· .*legacy 'off' row.*effective ADVISORY" "$PWTEST_BOTH" \
  && pwtest_ok "legacy off reported as a migration note" || pwtest_bad "legacy off note" "$(grep '·' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"

PDC6B="$PW_PROJECTS_DIR/pd-c6b"; cp -a "$F2" "$PDC6B"
pwtest_rc 1 "doctor flags stale produced-by" env PW_CONFIG_FILE="$PDF2CFG" bash -c \
  "sed -i '' 's/^\- \*\*Produced by:\*\* .*/- **Produced by:** ghostprov/' '$PDC6B/task/PLAN.md' && PW_CONFIG_FILE='$PDF2CFG' '$PDOCTOR' pd-c6b"
grep -qE "✗ .*Produced by: ghostprov.*no longer enabled" "$PWTEST_BOTH" \
  && pwtest_ok "provider dropped from global config lights up" || pwtest_bad "stale produced-by" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"

# --- C11/C12 + --fix: the deterministic-writer path -------------------------------------------
# Missing AI Review line (pre-explicit-line project): ✗ without --fix; --fix ensures it back with
# explicit off values; the same run then reports green.
PDFIX="$PW_PROJECTS_DIR/pd-fix"; cp -a "$F2" "$PDFIX"
sed -i '' '/^- \*\*AI Review:\*\*/d' "$PDFIX/README.md"
pwtest_rc 1 "doctor flags a missing config line" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-fix
grep -qE "✗ .*missing explicit config line\(s\):.*AI-Review" "$PWTEST_BOTH" \
  && pwtest_ok "absence named once by C11 (explicit-line doctrine)" || pwtest_bad "missing line" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
[ "$(grep -cE '✗ .*AI[- ][Rr]eview' "$PWTEST_BOTH")" = 1 ] \
  && pwtest_ok "one defect = one ✗ (C6/C11 deduped)" || pwtest_bad "dedupe" "$(grep -cE '✗ .*AI[- ][Rr]eview' "$PWTEST_BOTH")"

# Backticked pins and lead-value bullets are machine-shaped, not prose (corpus audit 09-28):
PDBACK="$PW_PROJECTS_DIR/pd-back"; cp -a "$F2" "$PDBACK"
sed -i '' 's/^- \*\*Execute with:\*\* kilotest\/test-model/- **Execute with:** `kilotest\/test-model`/' "$PDBACK/task/T01.md"
sed -i '' 's|^- \*\*AI execution limit:\*\* .*|- **AI execution limit:** 3 (default 3 — `PW_MAX_SELF_REPAIR`) self-repair rounds an executor may take|' "$PDBACK/task/PLAN.md"
pwtest_rc 0 "quoted pin + annotated limit bullet read cleanly" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-back
grep -qE "✗ .*(not a single pin|not an integer|is not in provider)" "$PWTEST_BOTH" \
  && pwtest_bad "tolerant reads regressed" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' '|')" \
  || pwtest_ok "no false ✗ from quoting/prose tails"
pwtest_rc 0 "doctor --fix repairs the deterministic case" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-fix --fix
grep -qE "fixed: dashboard config lines ensured" "$PWTEST_BOTH" \
  && pwtest_ok "--fix report names the ensure" || pwtest_bad "--fix report" "$(grep 'fixed' "$PWTEST_BOTH" | tr '\n' '|')"
grep -qE '^- \*\*AI Review:\*\* context=advisory analysis=advisory plan=advisory' "$PDFIX/README.md" \
  && grep -qE '^- \*\*Review Trigger:\*\* context=manual' "$PDFIX/README.md" \
  && pwtest_ok "review lines restored with explicit advisory/manual values" || pwtest_bad "restored line" "$(grep -c 'AI Review' "$PDFIX/README.md")"

# RFC backend drift (C12, rev d ruling): optional UNTIL engaged — a META with no target/revision/
# wave only WARNS (·, exit unaffected); once the project actually uses the RFC (Target set here),
# the same drift is a real ✗.
PDRFCU="$PW_PROJECTS_DIR/pd-rfc-unused"; cp -a "$F2" "$PDRFCU"; mkdir -p "$PDRFCU/rfc"
printf '# RFC metadata — pd-rfc-unused\n\n- **Backend:** lark\n- **Target:** \n- **Last revision pushed:** \n- **Wave 1 published:** no\n- **Wave 2 published:** no\n' > "$PDRFCU/rfc/META.md"
pwtest_rc 0 "unengaged RFC side-loop warns but never fails" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-rfc-unused
grep -qE "· .*RFC backend drift.*'lark'.*'markdown'.*warning only — RFC side-loop not engaged" "$PWTEST_BOTH" \
  && pwtest_ok "retired backend surfaces as · while side-loop is untouched" || pwtest_bad "rfc unengaged" "$(grep -E '·|✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"

PDRFC="$PW_PROJECTS_DIR/pd-rfc"; cp -a "$F2" "$PDRFC"; mkdir -p "$PDRFC/rfc"
printf '# RFC metadata — pd-rfc\n\n- **Backend:** lark\n- **Target:** https://example/lark/doc\n' > "$PDRFC/rfc/META.md"
pwtest_rc 1 "engaged RFC (target set) makes backend drift a real ✗" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-rfc
grep -qE "✗ .*RFC backend drift.*'lark'.*'markdown'" "$PWTEST_BOTH" \
  && pwtest_ok "used RFC flow is mandatory-checked" || pwtest_bad "rfc drift" "$(grep -E '·|✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"
sed -i '' 's/\*\*Backend:\*\* lark/**Backend:** markdown/' "$PDRFC/rfc/META.md"
pwtest_rc 0 "matching backend green" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-rfc

# --- C1/C3 planted defects ---------------------------------------------------------------------
PDC13="$PW_PROJECTS_DIR/pd-c13"; cp -a "$F2" "$PDC13"
# plant the row INSIDE the task table (pw_plan_pairs scans to the next '## ' — a row appended at
# EOF would sit outside the table and silently not exist as far as the PLAN readers care):
awk '{print} /^\| \[?T04/ {print "| T99 | planted | api | — | G1 | kilotest/test-model | 1 | shipped | — | — |"}' "$PDC13/task/PLAN.md" > "$PDC13/task/PLAN.md.a" && mv "$PDC13/task/PLAN.md.a" "$PDC13/task/PLAN.md"
printf '# T77: cyc one\n- **Repo:** api\n- **depends_on:** T78\n- **Status:** todo\n- **Execute with:** kilotest/test-model\n' > "$PDC13/task/T77.md"
printf '# T78: cyc two\n- **Repo:** api\n- **depends_on:** T77\n- **Status:** todo\n- **Execute with:** kilotest/test-model\n' > "$PDC13/task/T78.md"
pwtest_rc 1 "doctor flags status-vocab + cycle" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-c13
grep -qE "✗ .*T99.*Status 'shipped'" "$PWTEST_BOTH" && pwtest_ok "bad PLAN status named" || pwtest_bad "status vocab" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"
grep -qE "✗ .*depends_on cycle" "$PWTEST_BOTH" && pwtest_ok "cycle detected" || pwtest_bad "cycle" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"

# --- plan 27 regressions ------------------------------------------------------------------------
# C3 universe (F2): an edge to a task WITHOUT a depends_on field is the normal shape, never
# "unknown"; non-id tokens in the field are annotations (·), never edges.
PDC3U="$PW_PROJECTS_DIR/pd-c3u"; cp -a "$F2" "$PDC3U"
sed -i '' 's/^- \*\*depends_on:\*\* none/- **depends_on:** T01 (after the shim lands)/' "$PDC3U/task/T02.md"
pwtest_rc 0 "depends_on to a no-depends_on task is green" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-c3u
grep -qE '· .*non-id tokens .*T02' "$PWTEST_BOTH" \
  && pwtest_ok "annotation tokens reported as ·" || pwtest_bad "C3 annot" "$(grep -E 'depends_on' "$PWTEST_BOTH" | tr '\n' '|')"

# Tokens (F3): an absolute {{PW_PROJECTS}} Worktree path is a document defect (C11 ✗) — but the
# existence checks expand it, so it must NEVER also read "not mounted"; --fix stamps it away.
PDTOK="$PW_PROJECTS_DIR/pd-tok"; cp -a "$F2" "$PDTOK"
sed -i '' 's|^- \*\*Worktree:\*\* .*|- **Worktree:** `{{PW_PROJECTS}}/pd-tok/worktree/api/T03-thing/`|' "$PDTOK/task/T03.md"
pwtest_rc 1 "doctor flags unexpanded scaffold tokens in task files" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-tok
grep -qE '✗ .*unexpanded scaffold token.*T03\.md' "$PWTEST_BOTH" \
  && pwtest_ok "C11 names the token-carrying file" || pwtest_bad "C11 token ✗" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' '|')"
grep -qE '✗ T03: declared worktree.*not mounted' "$PWTEST_BOTH" \
  && pwtest_bad "token path failed an existence check" "expanded reader did not run" \
  || pwtest_ok "token-expanded path tested, no false not-mounted"
pwtest_rc 0 "doctor --fix stamps the tokens" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-tok --fix
grep -qE 'fixed: scaffold tokens stamped' "$PWTEST_BOTH" \
  && pwtest_ok "--fix ran the scaffold render" || pwtest_bad "--fix stamp" "$(grep -E 'fixed|✗' "$PWTEST_BOTH" | tr '\n' '|')"
grep -c '{{PW_' "$PDTOK/task/T03.md" | grep -q '^0$' \
  && pwtest_ok "T03.md token-free after fix" || pwtest_bad "stamp left tokens" "$(grep -c '{{PW_' "$PDTOK/task/T03.md")"
pwtest_rc 0 "second --fix pass is a no-op (idempotence)" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-tok --fix
grep -qE 'fixed:' "$PWTEST_BOTH" \
  && pwtest_bad "--fix not idempotent" "$(grep 'fixed' "$PWTEST_BOTH")" \
  || pwtest_ok "second --fix reports zero repairs"

# Status-awareness (F5): an ACCEPTED task with its worktree torn down is expected (·, not ✗).
PDACC="$PW_PROJECTS_DIR/pd-acc"; cp -a "$F2" "$PDACC"
sed -i '' 's/^- \*\*Status:\*\* done/- **Status:** accepted/' "$PDACC/task/T01.md"
rm -rf "$PDACC/worktree/api/T01-thing"
pwtest_rc 0 "accepted task with removed worktree is green" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-acc
grep -qE '· 1 accepted task.*torn down' "$PWTEST_BOTH" \
  && pwtest_ok "teardown reported as expected" || pwtest_bad "C2 accepted note" "$(grep -E '✗|·' "$PWTEST_BOTH" | tr '\n' '|')"

# Annotation prose after a backticked field value (F4): checks read the token, report hygiene as ·.
PDPROSE="$PW_PROJECTS_DIR/pd-prose"; cp -a "$F2" "$PDPROSE"
sed -i '' 's|^\- \*\*Branch:\*\* `\(agent[^`]*\)`$|- **Branch:** `\1` (standard global branch rule)|' "$PDPROSE/task/T01.md"
pwtest_rc 0 "annotated Branch field still resolves" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-prose
grep -qE '✗ T01: branch' "$PWTEST_BOTH" \
  && pwtest_bad "prose broke the branch reader" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' '|')" \
  || pwtest_ok "backtick-first reader survived the annotation"
grep -qE 'annotation prose' "$PWTEST_BOTH" \
  && pwtest_bad "hygiene note still emitted (owner ruling 09-28: drop it)" "$(grep '·' "$PWTEST_BOTH" | tr '\n' '|')" \
  || pwtest_ok "no prose-hygiene noise in the output"

# C6 rev f ruling (09-28): pin debt on ACCEPTED tasks is history too — · count, never ✗;
# the same problem on a LIVE task still fails with its hint.
PDHIST="$PW_PROJECTS_DIR/pd-pinhist"; cp -a "$F2" "$PDHIST"
sed -i '' 's/^- \*\*Status:\*\* done/- **Status:** accepted/' "$PDHIST/task/T01.md"
sed -i '' 's|^- \*\*Execute with:\*\* .*|- **Execute with:** ghostprov:ghost-model|' "$PDHIST/task/T01.md"
pwtest_rc 0 "accepted-task pin debt only counts as ·" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-pinhist
grep -qE "· 1 accepted task\(s\) carry pins outside" "$PWTEST_BOTH" \
  && pwtest_ok "pin history counted, not enforced" || pwtest_bad "C6 rev f note" "$(grep -E '✗|·' "$PWTEST_BOTH" | head -4 | tr '\n' '|')"
sed -i '' 's|^- \*\*Execute with:\*\* .*|- **Execute with:** ghostprov:ghost-model|' "$PDHIST/task/T03.md"
pwtest_rc 1 "same pin problem on a LIVE task still ✗" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-pinhist
grep -qE "✗ T03: pin 'ghostprov:ghost-model'.*not in current PW_PROVIDERS" "$PWTEST_BOTH" \
  && grep -qE '→ fix: /pw-config pd-pinhist project set pin T03=' "$PWTEST_BOTH" \
  && pwtest_ok "live pin ✗ carries its command hint" || pwtest_bad "live pin enforcement" "$(grep -E '✗|→' "$PWTEST_BOTH" | head -4 | tr '\n' '|')"

# C8 owner ruling (09-28): "ran a different model than the pin" is history, never a fail.
# The audit computes mismatch from the LOG spawn line (the ledger is the record) — plant one
# for the LIVE (in-progress) T03 with a different model than its pin:
PDDRIFT="$PW_PROJECTS_DIR/pd-drift"; cp -a "$F2" "$PDDRIFT"
printf -- '- **2026-09-25 00:00** · `orchestrator` — spawned T03 (kilotest/other-model) via=subagent route=in-process\n' >> "$PDDRIFT/LOG.md"
pwtest_rc 0 "pin-vs-used drift on a live task informs but never fails" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-drift
grep -qE '· [0-9]+ row\(s\) ran with a different model' "$PWTEST_BOTH" \
  && pwtest_ok "drift reported as ·" || pwtest_bad "C8 drift note" "$(grep -E '✗|·' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"

rm -rf "$PDF"
