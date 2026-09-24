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
PDPRE="$(pd_sha "$PW_PROJECTS_DIR/pd-ok")"
pwtest_rc 0 "doctor F2 walk exits 0" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-ok
pwtest_re 'project-doctor pd-ok: 0 ✗' "F2 summary line: zero ✗"
PDPOST="$(pd_sha "$PW_PROJECTS_DIR/pd-ok")"
[ "$PDPRE" = "$PDPOST" ] && pwtest_ok "doctor mutates nothing without --fix" || pwtest_bad "read-only contract" "project tree hash changed"

# --- C7 planted state: the merged-but-unaccepted case gets flagged, with the fix named --------
printf "42 merged\n" >> "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 1 "doctor flags merged-but-unaccepted MR" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-ok
grep -qE "✗ .*T02.*MR already merged but task Status is 'done'" "$PWTEST_BOTH" \
  && pwtest_ok "C7 names the offender + acceptance fix" || pwtest_bad "C7 planted" "$(grep '✗' "$PWTEST_BOTH" | head -3 | tr '\n' '|')"
grep -qE '→ fix: pw-status.sh task-accept pd-ok T02' "$PWTEST_BOTH" \
  && pwtest_ok "C7 fix line names the owning command" || pwtest_bad "C7 fix line" "$(grep '→' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
: > "$PWTEST_FORGE_STATE_FILE"

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
  "sed -i '' 's/analysis=off/analysis=maybe/' '$PDC6/README.md' && PW_CONFIG_FILE='$PDF2CFG' '$PDOCTOR' pd-c6"
grep -qE "✗ .*AI Review row 'analysis=maybe'.*outside off\|advisory\|auto" "$PWTEST_BOTH" \
  && pwtest_ok "illegal mode named precisely" || pwtest_bad "illegal mode" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"

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
grep -qE "✗ .*no '- \*\*AI Review:\*\*' line" "$PWTEST_BOTH" \
  && pwtest_ok "absence named (explicit-line doctrine)" || pwtest_bad "missing line" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
pwtest_rc 0 "doctor --fix repairs the deterministic case" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-fix --fix
grep -qE "fixed: dashboard config lines ensured" "$PWTEST_BOTH" \
  && pwtest_ok "--fix report names the ensure" || pwtest_bad "--fix report" "$(grep 'fixed' "$PWTEST_BOTH" | tr '\n' '|')"
grep -qE '^- \*\*AI Review:\*\* analysis=off plan=off' "$PDFIX/README.md" \
  && pwtest_ok "AI Review line restored with explicit off values" || pwtest_bad "restored line" "$(grep -c 'AI Review' "$PDFIX/README.md")"

# RFC backend drift (C12): META says lark while the config floor says markdown.
PDRFC="$PW_PROJECTS_DIR/pd-rfc"; cp -a "$F2" "$PDRFC"; mkdir -p "$PDRFC/rfc"
printf '# RFC metadata — pd-rfc\n\n- **Backend:** lark\n- **Target:** https://example/lark/doc\n' > "$PDRFC/rfc/META.md"
pwtest_rc 1 "doctor flags RFC backend drift" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-rfc
grep -qE "✗ .*RFC backend drift.*'lark'.*'markdown'" "$PWTEST_BOTH" \
  && pwtest_ok "retired backend lights up vs current global config" || pwtest_bad "rfc drift" "$(grep '✗' "$PWTEST_BOTH" | head -2 | tr '\n' '|')"
sed -i '' 's/\*\*Backend:\*\* lark/**Backend:** markdown/' "$PDRFC/rfc/META.md"
pwtest_rc 0 "matching backend passes" env PW_CONFIG_FILE="$PDF2CFG" "$PDOCTOR" pd-rfc

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

rm -rf "$PDF"
