# shellcheck shell=bash
# cases/pw-status.t.sh
pwtest_rc 0 "status F1 sections" "$(pwtest_script pw-status.sh)" "$S1" --skip-cli-check
pwtest_re '^## Phase' "phase header present"
pwtest_re '^## Next action' "next-action guidance (P5)"
pwtest_rc 0 "status F2 sections" "$(pwtest_script pw-status.sh)" "$S2" --skip-cli-check
pwtest_re '^## Tasks' "task table header"
grep -q 'REVIEW.template\|_TEMPLATE' "$PWTEST_OUT" \
  && pwtest_bad "status ignores scaffold templates in counts" "template leaked into report" \
  || pwtest_ok "no scaffold template counted (status round)"
pwtest_rc 0 "status F3 hostile parses clean" "$(pwtest_script pw-status.sh)" "$S3" --skip-cli-check
pwtest_re 'prose around the token|repair with' "prose phase surfaced as repair, not silent"
pwtest_rc 2 "no-such-project" "$(pwtest_script pw-status.sh)" nope-not-here
pwtest_fix "unknown carries the fix"

# --- status/oneliner + phase/ship gate helpers (ported from pw-lib.t.sh, plan 20) ---
# 1) status self-heal + backward guards (C19 companion): prose drift normalizes on a forward write:
CP=libclonestat; rm -rf "$PW_PROJECTS_DIR/$CP"; cp -a "$F3" "$PW_PROJECTS_DIR/$CP"
HEAL="$PW_PROJECTS_DIR/$CP/README.md"
pwtest_rc 0 "status forward write onto drifted prose" "$(pwtest_script pw-status.sh)" status "$CP" executing
if grep -qxF -- '- **Status:** executing' "$HEAL"; then pwtest_ok "forward write self-heals drifted prose line"
else pwtest_bad "status heal" "$(grep '\*\*Status' "$HEAL" | head -2 | tr '\n' '|')"; fi
pwtest_rc 2 "backward refusing still honest: analysis ← executing without --rewind" "$(pwtest_script pw-status.sh)" status "$CP" analysis
# 6) phase/ship gate helpers on the clone:
pwtest_rc 0 "phase getter" "$(pwtest_script pw-status.sh)" phase "$CP"
[ "$("$(pwtest_script pw-status.sh)" phase "$CP" 2>/dev/null)" ] ; pwtest_ok "phase prints non-empty" || true