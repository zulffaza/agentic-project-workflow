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

# --- plan-31 readers/gates: approval = latest row AND no real open items; RFC staging is
# excluded from approval discovery (its own open-item gate stays); review lanes fail closed.
# Clone etiquette (testing.md): only private clones are mutated, never $F2/$S2 themselves.
STS="$(pwtest_script pw-status.sh)"; PF3="$(pwtest_script pw-preflight.sh)"
_rv_add() { # <file> <anchor-substring> <line> — insert <line> right after the FIRST matching line
  awk -v a="$2" -v n="$3" 'BEGIN{done=0} {print; if(!done && index($0,a)>0){print n; done=1}}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
_open_item() { # <file> — one REAL filled open heading right after ## Items
  awk -v h='### R9 · §Scope — [OPEN] (pwtest, 2026-10-05 12:00) <!-- pw-item-status: open -->' 'BEGIN{done=0} {print; if(!done && index($0,"## Items")==1){print ""; print h; done=1}}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
P3=pre-plan31; rm -rf "$PW_PROJECTS_DIR/$P3"; cp -a "$F2" "$PW_PROJECTS_DIR/$P3"
"$STS" status "$P3" breakdown --rewind >/dev/null 2>&1
# 1) RFC staging has no Sign-off approval gate of its own — an unapproved RFC.review.md
# must never block the analysis approval loop:
cp "$PWTEST_TEMPLATE_DIR/_REVIEW.template.md" "$PW_PROJECTS_DIR/$P3/analysis/review/RFC.review.md"
pwtest_rc 0 "breakdown: RFC staging excluded from approval discovery" "$PF3" breakdown "$P3"
# 2) …but its unresolved comments still block breakdown through the independent gate:
mkdir -p "$PW_PROJECTS_DIR/$P3/rfc"; : > "$PW_PROJECTS_DIR/$P3/rfc/META.md"
_open_item "$PW_PROJECTS_DIR/$P3/analysis/review/RFC.review.md"
pwtest_rc 1 "breakdown: real open RFC comment blocks" "$PF3" breakdown "$P3"
pwtest_err "RFC has open items" "names the independent RFC gate"
pwtest_fix "RFC gate refusal actionable"
rm -f "$PW_PROJECTS_DIR/$P3/analysis/review/RFC.review.md" "$PW_PROJECTS_DIR/$P3/rfc/META.md"
# 3) stale approval: latest row approved AND a REAL open item → the consumer refuses,
# naming unresolved items (not a bogus "not approved"):
_open_item "$PW_PROJECTS_DIR/$P3/task/review/PLAN.review.md"
pwtest_rc 1 "execute: approved-but-open PLAN is stale approval" "$PF3" execute "$P3"
pwtest_err "unresolved items" "stale approval named by its real cause"
pwtest_fix "stale approval refusal actionable"
rm -rf "$PW_PROJECTS_DIR/$P3"
# 4) reopened history: an approved row superseded by the agent's auto-reopen row is NOT
# consumable — a historical approval never satisfies the gate:
P4=pre-reopen; rm -rf "$PW_PROJECTS_DIR/$P4"; cp -a "$F2" "$PW_PROJECTS_DIR/$P4"
_rv_add "$PW_PROJECTS_DIR/$P4/task/review/PLAN.review.md" '| pwtest | approved |' '| 2026-10-05 12:10 | pw-review (auto-reopen) | in-review |'
pwtest_rc 1 "execute: reopened review falls back to unapproved" "$PF3" execute "$P4"
pwtest_err "not approved" "reopen reads as no current approval"
pwtest_fix "reopen refusal actionable"
rm -rf "$PW_PROJECTS_DIR/$P4"
# 5) never-approved (plain changes-requested row) → refused fail-closed:
P5=pre-never; rm -rf "$PW_PROJECTS_DIR/$P5"; cp -a "$F2" "$PW_PROJECTS_DIR/$P5"
sedi 's@| 2026-09-15 00:00 | pwtest | approved |@| 2026-10-05 09:00 | you | changes-requested |@' "$PW_PROJECTS_DIR/$P5/task/review/PLAN.review.md"
pwtest_rc 1 "execute: changes-requested PLAN never approved" "$PF3" execute "$P5"
pwtest_err "not approved" "no current approval, never a history read"
rm -rf "$PW_PROJECTS_DIR/$P5"
# 6) active human rejection: the latest row reads approved (auto) but an explicit human
# changes-requested was never withdrawn → refused (row kept, gate not reopened):
P6=pre-reject; rm -rf "$PW_PROJECTS_DIR/$P6"; cp -a "$F2" "$PW_PROJECTS_DIR/$P6"
_rv_add "$PW_PROJECTS_DIR/$P6/task/review/PLAN.review.md" '| pwtest | approved |' '| 2026-10-05 12:20 | pw-reviewer (auto; provider=kilotest; model=m1) | approved |'
_rv_add "$PW_PROJECTS_DIR/$P6/task/review/PLAN.review.md" '| pwtest | approved |' '| 2026-10-05 12:15 | you | changes-requested |'
pwtest_rc 1 "execute: auto-approved row over an active human rejection" "$PF3" execute "$P6"
pwtest_err "not approved" "human rejection blocks consumption regardless of the newest row"
rm -rf "$PW_PROJECTS_DIR/$P6"
# 7) review lanes: task-plan and ship resolve to the task review artifacts; unknown
# words fail closed instead of silently checking nothing:
P7=pre-lanes; rm -rf "$PW_PROJECTS_DIR/$P7"; cp -a "$F2" "$PW_PROJECTS_DIR/$P7"
pwtest_rc 0 "review lane task-plan finds task reviews" "$PF3" review "$P7" task-plan
pwtest_rc 0 "review lane ship finds mirrored task reviews" "$PF3" review "$P7" ship
pwtest_rc 1 "unknown review lane word fails closed" "$PF3" review "$P7" zzz-phase
pwtest_err "unknown review phase-word" "refusal names the bad word"
pwtest_err "analysis|plan|task-plan|task-exec|ship" "refusal lists every lane word"
pwtest_fix "lane refusal actionable"
rm -rf "$PW_PROJECTS_DIR/$P7"
# a dashboard-phase word is NOT a lane word — executing must be refused, not checked:
pwtest_rc 1 "review executing-word (phase, not lane) fails closed" "$PF3" review "$S1" executing
# F1 fresh scaffold has no task reviews → both task lanes refuse with the real condition:
pwtest_rc 1 "ship lane with no task reviews refuses (F1)" "$PF3" review "$S1" ship
pwtest_err "no task review files" "ship lane reports the real condition"
pwtest_rc 1 "task-plan lane with no task reviews refuses (F1)" "$PF3" review "$S1" task-plan
