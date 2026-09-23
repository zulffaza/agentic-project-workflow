# shellcheck shell=bash
# cases/pw-preflight.t.sh — gate semantics beyond the golden matrix (gates.tsv).
E=pre-f2; rm -rf "$PW_PROJECTS_DIR/$E"; cp -a "$F2" "$PW_PROJECTS_DIR/$E"
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 merged\n" >> "$PWTEST_FORGE_STATE_FILE"
# review gate lane: PLAN lane approved (fixture) → plan mode 0; task-exec lane reviews unsigned → non-0
pwtest_rc 0 "review gate plan lane F2 approved" "$(pwtest_script pw-preflight.sh)" review "$E" plan
pwtest_rc 1 "bogus mode rc1 + actionable usage" "$(pwtest_script pw-preflight.sh)" bogus "$E"
pwtest_fix "usage names allowed gates"
# analyze gate (C24): every preflight verb exists in the unknown-command listing…
grep -qF 'analyze|' "$PWTEST_BOTH" \
  && pwtest_ok "usage enumerates the analyze gate (C24)" || pwtest_bad "usage enumerates analyze (C24)" "die message lost the verb"
# …and the gate is gate-shaped in both directions:
pwtest_rc 1 "analyze F1 scaffold: example-only INDEX is NO input" "$(pwtest_script pw-preflight.sh)" analyze "$S1"
pwtest_err "no input rows" "names the missing-input condition"
pwtest_fix "analyze refusal actionable"
A=ana-f1; rm -rf "$PW_PROJECTS_DIR/$A"; cp -a "$F1" "$PW_PROJECTS_DIR/$A"
printf -- '| REQUIREMENTS.md | the brief | hand | 2026-01-01 | seed |\n' >> "$PW_PROJECTS_DIR/$A/context/INDEX.md"
pwtest_rc 0 "analyze passes with one REAL context row" "$(pwtest_script pw-preflight.sh)" analyze "$A"
rm -rf "$PW_PROJECTS_DIR/$A"
pwtest_rc 1 "analyze after phase moved on names --rewind" "$(pwtest_script pw-preflight.sh)" analyze "$S2"
pwtest_err "analysis --rewind|must be: context analysis" "phase refusal carries the rewind repair"
# ship gate: unshipped shippable exists (T01) → ready
pwtest_rc 0 "ship gate F2 finds shippable" "$(pwtest_script pw-preflight.sh)" ship "$E"
# close gate on F2 (nothing accepted): refuse, must name the offenders (close semantics):
"$(pwtest_script pw-status.sh)" status "$E" review >/dev/null 2>&1
pwtest_rc 1 "close gate refuses with offenders named" "$(pwtest_script pw-preflight.sh)" close "$E"
grep -qE "T01[ ,]|T02[ ,]|T03[ ,]|T04[ ,]|task" "$PWTEST_BOTH" && pwtest_ok "names offending task ids" || pwtest_bad "close offenders" "no task list in stderr: $(head -c 120 "$PWTEST_ERR"|tr '
' ' ')"
pwtest_fix "close refusal actionable"
rm -rf "$PW_PROJECTS_DIR/$E"

# --- execute gate: availability axis (plan-22) — a row pinning a gone model/provider is a
# hard stop BEFORE any spawn; a live in-scope row passes. Shim catalog + fixture config keep
# this machine-independent. (python3 edits — the PLAN rows are data, sed quoting isn't worth it.)
G=pre-gate; rm -rf "$PW_PROJECTS_DIR/$G"; cp -a "$F2" "$PW_PROJECTS_DIR/$G"
PLAN="$PW_PROJECTS_DIR/$G/task/PLAN.md"
python3 - "$PLAN" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("kilotest/test-model","kilo:alibaba-token-plan/test-model")
t=t.replace("| [T01](./T01.md) | Fix api's retry shim | api | — | G1 | kilo:alibaba-token-plan/test-model |",
            "| [T01](./T01.md) | Fix api's retry shim | api | — | G1 | kilo:alibaba-token-plan/gone-xyz |",1)
open(f,"w").write(t)
PYEOF
pwtest_rc 1 "execute gate refuses a row whose model is not in the catalog" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" "$(pwtest_script pw-preflight.sh)" execute "$G"
grep -qE "model-resolve refused.*gone-xyz|not in the live catalog" "$PWTEST_BOTH" \
  && pwtest_ok "refusal names the row + the availability reason" || pwtest_bad "gate refusal text" "$(head -c 160 "$PWTEST_BOTH" | tr '\n' ' ')"
# out-of-scope provider (the migration case) → refused too:
python3 - "$PLAN" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("kilo:alibaba-token-plan/gone-xyz","kilo:command_code/MiniMaxAI/MiniMax-M3",1)
open(f,"w").write(t)
PYEOF
pwtest_rc 1 "execute gate refuses a row whose provider left PW_KILO_API_PROVIDERS" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" "$(pwtest_script pw-preflight.sh)" execute "$G"
grep -qE "OUTSIDE the PW_KILO_API_PROVIDERS scope" "$PWTEST_BOTH" \
  && pwtest_ok "scope refusal relayed with its fix" || pwtest_bad "scope refusal text" "$(head -c 160 "$PWTEST_BOTH" | tr '\n' ' ')"
# all rows live + in scope → gate passes (positive direction):
python3 - "$PLAN" <<'PYEOF'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace("kilo:command_code/MiniMaxAI/MiniMax-M3","kilo:alibaba-token-plan/test-model")
open(f,"w").write(t)
PYEOF
pwtest_rc 0 "execute gate passes with every row resolvable" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" "$(pwtest_script pw-preflight.sh)" execute "$G"
rm -rf "$PW_PROJECTS_DIR/$G"
