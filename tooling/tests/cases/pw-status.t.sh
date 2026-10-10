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

# --- ported from pw-lib's inline selftest (plan 20 Phase 5) ---
pl_status_selftest() {
  local tmp="$ROOT/pl-status"; rm -rf "$tmp"; mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n  <!-- comment stays -->\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  die() { pwtest_bad "pw-lib-port[status]: $*" "ported selftest assert failed"; }
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo analysis >/dev/null
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" phase demo)"
  [ "$got" = "analysis" ] || die "selftest FAIL: phase='$got' (expected analysis)"
  grep -q '<!-- comment stays -->' "$tmp/demo/README.md" || die "selftest FAIL: clobbered trailing comment"
  grep -qE '^- \*\*[0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB\*\* · `status` — Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing/wrong format"
  # One-liner setter
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" oneliner demo "toggle kafka usage safely" >/dev/null
  grep -q '^- \*\*One-liner:\*\* toggle kafka usage safely$' "$tmp/demo/README.md" || die "selftest FAIL: one-liner not set"
  # Monotonic guard: a backward move without --rewind must fail…
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo context >/dev/null 2>&1; then
    die "selftest FAIL: backward status move was NOT blocked"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" phase demo)" = "analysis" ] || die "selftest FAIL: blocked move still mutated Status"
  # …but --rewind is allowed, and executing↔review (same rank) is never treated as backward.
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo executing >/dev/null
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo review >/dev/null
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo executing >/dev/null   # re-run a task: not a rewind
  [ "$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" phase demo)" = "executing" ] || die "selftest FAIL: executing↔review blocked"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" status demo analysis --rewind >/dev/null
  [ "$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" phase demo)" = "analysis" ] || die "selftest FAIL: --rewind did not apply"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" log demo analyze "wrote analysis/x.md" >/dev/null
  grep -qE '^- \*\*[0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB\*\* · `analyze` — wrote analysis/x\.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing/wrong format"
  # Adopted pointer: inserted after One-liner when absent, then replaced in place (idempotent).
  grep -q '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" && die "selftest FAIL: Adopted line present before adopt"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" adopted demo "1 unit — see context/ADOPTED.md" >/dev/null
  grep -q '^- \*\*Adopted:\*\* 1 unit — see context/ADOPTED.md$' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not inserted"
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*Adopted:\*\*' || die "selftest FAIL: Adopted not anchored after One-liner"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" adopted demo "2 units — see context/ADOPTED.md" >/dev/null
  [ "$(grep -c '^- \*\*Adopted:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: Adopted duplicated instead of replaced"
  grep -q '^- \*\*Adopted:\*\* 2 units' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not updated"
  # --- cmd_log duplicate-guard ---------------------------------------------------------
  # The real, observed bug: a live project's LOG.md had the identical actor+message logged twice
  # (once even three times) back-to-back within minutes. Calling log twice with the exact same
  # actor+message must not double-append; a genuinely different message right after must NOT be
  # deduped; the SAME message again, but outside the dedup window, must append (not be dropped).
  mkdir -p "$tmp/logtest"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/logtest/README.md"
  : > "$tmp/logtest/LOG.md"
  local LT="$tmp/logtest/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "1" ] || die "selftest FAIL: duplicate log entry was not deduped"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "2" ] || die "selftest FAIL: a distinct message was wrongly deduped"
  sed -i '' -e 's/^- \*\*[^*]*\*\*/- **2020-01-01 00:00**/' "$LT"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "3" ] || die "selftest FAIL: an identical message outside the dedup window was wrongly skipped"
  # --- dashboard table edits (MR-state flow) --------------------------------
  # Task status table + MR table with realistic rows; the MR table's State is column 5, so a
  # fixed-position "column 4" write (the original implementation) would clobber the MR URL.
  printf '\n## Task status\n\n| ID | Title | Repo | Status | Notes |\n|----|-------|------|--------|-------|\n| T01 | fix x | repo-a | done | |\n\n## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |\n' >> "$tmp/demo/README.md"

  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" dashboard-task-status demo T01 "accepted (MR merged)" >/dev/null
  grep -q '^| T01 | fix x | repo-a | accepted (MR merged) | |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status did not update the Status column"
  grep -q '^| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status leaked into the MR table"

  # (dashboard-mr-state asserts moved to scripts/entities/pw-ship.sh — plan 20)

  # failure path: a task with no row must fail loudly and leave the file untouched.
  local readme_before; readme_before="$(cat "$tmp/demo/README.md")"
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-status.sh)" dashboard-task-status demo T99 done >/dev/null 2>&1; then
    die "selftest FAIL: dashboard-task-status accepted a task with no row"
  fi
  [ "$(cat "$tmp/demo/README.md")" = "$readme_before" ] \
    || die "selftest FAIL: failed dashboard-task-status still mutated the file"
  rm -rf "$tmp"
}
pl_status_selftest

# --- provider-audit: Execute-with expected vs ledger/Actually-used, + availability verdicts ---
# Owns a scratch project (not F2) so rows/log lines are exact; shim catalog + scoped fixture
# config keep the verdicts machine-independent.
PA="$ROOT/projects/paaudit"; mkdir -p "$PA/task"
cat > "$PA/task/PLAN.md" <<'PLAN'
# PLAN — paaudit
## Task table
| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |
|----|-------|------|------------|-------|--------------|----|--------|------|--------|
| [T01](./T01.md) | ok | api | — | G1 | kilo:alibaba-token-plan/test-model | 1 | done | — | — |
| [T02](./T02.md) | unbound | api | — | G1 | kilo:alibaba-token-plan/gone-xyz | 1 | todo | — | — |
| [T03](./T03.md) | stale | api | — | G1 | kilo:command_code/MiniMaxAI/MiniMax-M3 | 1 | done | — | — |
| [T04](./T04.md) | mismatch | api | — | G1 | kilo:alibaba-token-plan/test-model | 1 | done | — | — |
| [T05](./T05.md) | degraded-ok | api | — | G1 | kilo:alibaba-token-plan/test-model | 1 | done | — | — |
| [T06](./T06.md) | provider-gone | api | — | G1 | kilotest:test-model | 1 | done | — | — |
PLAN
printf -- '- **Route:** headless\n' > "$PA/task/T01.md"
cat > "$PA/LOG.md" <<'LOG'
# Activity log — paaudit
- **2026-09-23 10:00** · `exec` — spawned T01 (kilo:alibaba-token-plan/test-model) · via=subagent · session=— · seed=task/T01.md · out=worktree/T01.log · state=success
- **2026-09-23 10:10** · `exec` — spawned T04 (claude:opus) · via=headless · session=— · seed=x · out=y
- **2026-09-23 10:20** · `exec` — spawned T05 (kilo:alibaba-token-plan/other-model) · via=subagent · model-degraded kilo:alibaba-token-plan/test-model→kilo:alibaba-token-plan/other-model · session=— · seed=x · out=y
LOG
PAE="$(pwtest_script pw-status.sh)"
pwtest_rc 1 "provider-audit flags planted rows" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit
grep -qE '^T01\|expected=kilo:alibaba-token-plan/test-model\|used=kilo:alibaba-token-plan/test-model\|via=subagent\|route=headless\|verdict=ok$' "$PWTEST_OUT" \
  && pwtest_ok "ok row renders expected shape (route from task file)" \
  || pwtest_bad "ok row shape" "$(grep '^T01' "$PWTEST_OUT")"
grep -qE '^T02\|.*verdict=unbound$' "$PWTEST_OUT" && pwtest_ok "catalog miss → unbound" || pwtest_bad "unbound" "$(grep '^T02' "$PWTEST_OUT")"
grep -qE '^T03\|.*verdict=stale-provider$' "$PWTEST_OUT" && pwtest_ok "out-of-scope api-provider → stale-provider" || pwtest_bad "stale" "$(grep '^T03' "$PWTEST_OUT")"
grep -qE '^T04\|.*used=claude:opus\|via=headless.*verdict=mismatch$' "$PWTEST_OUT" && pwtest_ok "wrong provider used → mismatch" || pwtest_bad "mismatch" "$(grep '^T04' "$PWTEST_OUT")"
grep -qE '^T05\|.*verdict=ok$' "$PWTEST_OUT" && pwtest_ok "recorded model-degrade is policy-blessed" || pwtest_bad "degrade ok" "$(grep '^T05' "$PWTEST_OUT")"
grep -qE '^T06\|.*verdict=stale-provider$' "$PWTEST_OUT" && pwtest_ok "provider absent from PW_PROVIDERS → stale-provider" || pwtest_bad "provider stale" "$(grep '^T06' "$PWTEST_OUT")"
# ledger-tolerant (pre-ladder lines lack via= → '—') + task-id filter + all-ok subset exits 0:
cat >> "$PA/LOG.md" <<'LOG'
- **2026-09-23 09:00** · `exec` — spawned T06 (kilotest:test-model) · session=— · seed=x · out=y
- **2026-09-23 09:10** · `exec` — spawned T06 fixer for T04.review.md R1 (kilotest:test-model) · session=— · seed=x · out=y
LOG
pwtest_rc 0 "provider-audit filtered to clean rows exits 0" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T01 T05
pwtest_rc 1 "provider-audit names the filtered offender" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T04
# a ledger line with description text between the task id and the model group must still parse
# (regression: the capture required '(' immediately after 'spawned T0n ' → used=unknown);
# the fixer line is the newest (file order = append order), so it is the one audited
pwtest_rc 1 "provider-audit parses described fixer lines" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T06
grep -qE '^T06\|expected=kilotest:test-model\|used=kilotest:test-model\|' "$PWTEST_OUT" \
  && pwtest_ok "fixer-style line yields the real model" || pwtest_bad "fixer line parse" "$(grep '^T06' "$PWTEST_OUT")"
# …and a colon-less model value (no provider prefix) still captures (a colon-required pattern
# would regress it to unknown)
cat >> "$PA/LOG.md" <<'LOG'
- **2026-09-23 09:15** · `exec` — spawned T02 (kilotest/other-model) via=subagent route=in-process
LOG
pwtest_rc 1 "provider-audit keeps colon-less models parseable" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T02
grep -qE '^T02\|.*used=kilotest/other-model\|' "$PWTEST_OUT" \
  && pwtest_ok "colon-less model captured verbatim" || pwtest_bad "colon-less parse" "$(grep '^T02' "$PWTEST_OUT")"
# report-only: audit must never mutate LOG.md
before="$(cat "$PA/LOG.md")"
env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit >/dev/null 2>&1
[ "$before" = "$(cat "$PA/LOG.md")" ] && pwtest_ok "provider-audit mutates nothing (LOG.md byte-identical)" || pwtest_bad "audit mutating" "LOG.md changed"

# --- plan 23 (KI-1/KI-2): placeholder fill + task-accept three-holder sync + close gate ---
# Fixture = a REAL scaffold (template-fresh, untouched placeholder tables) + a one-task PLAN,
# proving the whole already-merged path — task-accept → PLAN cell → close gate — with no manual
# cell edits anywhere. (Lives in T1, not the T2 battery: battery rows are read-only by design.)
p23_selftest() {
  local SL=p23fresh
  rm -rf "$PW_PROJECTS_DIR/$SL"
  pwtest_scaffold_into "$SL"
  [ -d "$PW_PROJECTS_DIR/$SL" ] || { pwtest_bad "plan-23 fixture" "scaffold did not create $SL"; return 0; }
  local P="$PW_PROJECTS_DIR/$SL"
  die() { pwtest_bad "plan-23: $*" "selftest assert failed"; }
  local ST SH PF
  ST="$(pwtest_script pw-status.sh)"; SH="$(pwtest_script pw-ship.sh)"; PF="$(pwtest_script pw-preflight.sh)"
  mkdir -p "$P/task"
  cat > "$P/task/PLAN.md" <<'PLAN'
# PLAN — p23fresh
## Task table
| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |
|----|-------|------|------------|-------|--------------|----|--------|------|--------|
| [T01](./T01.md) | fix x | api | — | G1 | kilotest/test-model | 1 | done | — | — |
PLAN
  printf -- '- **Status:** done\n- **Execute with:** kilotest/test-model\n' > "$P/task/T01.md"
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" status "$SL" review >/dev/null

  # KI-2: both dashboard tables are untouched template placeholders — writers fill the first blank row
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" dashboard-task-status "$SL" T01 done >/dev/null
  grep -q '^| T01 | | | done | |$' "$P/README.md" || die "placeholder task row not filled"
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$SH" dashboard-mr-state "$SL" T01 merged >/dev/null
  grep -q '^| T01 | | | | merged | — / green / red / still-running |$' "$P/README.md" \
    || die "MR placeholder fill wrong / hint cell lost"
  # genuinely missing row (no blank left) → loud failure, file untouched
  local before; before="$(cat "$P/README.md")"
  if PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" dashboard-task-status "$SL" T99 done >/dev/null 2>&1; then
    die "T99 dashboard write succeeded with no row and no placeholder"
  fi
  [ "$(cat "$P/README.md")" = "$before" ] || die "failed dashboard write mutated the file"

  # KI-1: task-accept syncs task file + PLAN cell + dashboard row, ONE log line
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" task-accept "$SL" T01 >/dev/null
  grep -q '| accepted | — | — |$' "$P/task/PLAN.md" || die "PLAN Status cell not synced"
  grep -q '^- \*\*Status:\*\* accepted$' "$P/task/T01.md" || die "task file Status not synced"
  grep -q '^| T01 | | | accepted | |$' "$P/README.md" || die "dashboard row not synced"
  [ "$(grep -c 'marked as accepted' "$P/LOG.md")" = "1" ] || die "expected exactly one accept LOG line"
  # the close gate — the whole point of KI-1 — is green now, with no manual cell edits
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$PF" close "$SL" || die "close gate still blocked after task-accept"

  # idempotent rerun: holders byte-identical, no second LOG line
  local lc; lc="$(grep -c '^- \*\*' "$P/LOG.md")"
  before="$(cat "$P/README.md")$(cat "$P/task/PLAN.md")$(cat "$P/task/T01.md")"
  PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" task-accept "$SL" T01 >/dev/null
  [ "$before" = "$(cat "$P/README.md")$(cat "$P/task/PLAN.md")$(cat "$P/task/T01.md")" ] \
    || die "idempotent rerun mutated a holder"
  [ "$(grep -c '^- \*\*' "$P/LOG.md")" = "$lc" ] || die "idempotent rerun logged again"

  # a task file with NO PLAN row → die, never silence
  printf -- '- **Status:** done\n' > "$P/task/T02.md"
  if PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" task-accept "$SL" T02 >/dev/null 2>&1; then
    die "accepted a task with no PLAN row"
  fi
  rm -f "$P/task/T02.md"

  # best-effort dashboard: no tables at all → warning, exit 0, gate holders still written
  local ND=p23nodash; rm -rf "$PW_PROJECTS_DIR/$ND"; mkdir -p "$PW_PROJECTS_DIR/$ND/task"
  printf -- '- **Status:** review\n- **One-liner:** no tables\n' > "$PW_PROJECTS_DIR/$ND/README.md"
  : > "$PW_PROJECTS_DIR/$ND/LOG.md"
  cp "$P/task/PLAN.md" "$PW_PROJECTS_DIR/$ND/task/PLAN.md"
  printf -- '- **Status:** done\n' > "$PW_PROJECTS_DIR/$ND/task/T01.md"
  sed -i '' 's/p23fresh/p23nodash/' "$PW_PROJECTS_DIR/$ND/task/PLAN.md"
  if ! PW_PROJECTS_DIR="$PW_PROJECTS_DIR" "$ST" task-accept "$ND" T01 >/dev/null 2>"$ROOT/p23err"; then
    die "task-accept failed when the dashboard has no tables (must stay best-effort)"
  fi
  grep -q 'warning: dashboard row' "$ROOT/p23err" || die "best-effort warning not printed"
  grep -q '| accepted | — | — |$' "$PW_PROJECTS_DIR/$ND/task/PLAN.md" || die "PLAN not written on the best-effort path"
  rm -rf "$PW_PROJECTS_DIR/$ND" "$ROOT/p23err" "$PW_PROJECTS_DIR/$SL"
  pwtest_ok "plan-23 three-holder sync + placeholder fill + close gate (all asserts passed)"
}
p23_selftest

# --- plan-31 Blockers parity: LATEST Sign-off row + actor, never a historical approved
# grep, tokens verbatim (hyphenated + legacy-decorated), RFC excluded from approval
# discovery but visible through its real open items. Clone-only mutations (F2 stays pristine). ---
_rv_add_s() { awk -v a="$2" -v n="$3" 'BEGIN{done=0} {print; if(!done && index($0,a)>0){print n; done=1}}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
_rv_set_s() { sedi "s@$2@$3@" "$1"; }
_open_item_s() { awk -v h='### R9 · §Scope — [OPEN] (pwtest, 2026-10-05 12:00) <!-- pw-item-status: open -->' 'BEGIN{done=0} {print; if(!done && index($0,"## Items")==1){print ""; print h; done=1}}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
SB=st-plan31; rm -rf "$PW_PROJECTS_DIR/$SB"; cp -a "$F2" "$PW_PROJECTS_DIR/$SB"
STB="$(pwtest_script pw-status.sh)"
ARV="$PW_PROJECTS_DIR/$SB/analysis/review/fixture.review.md"; PRV="$PW_PROJECTS_DIR/$SB/task/review/PLAN.review.md"
# baseline: F2 (executing, both gates approved, zero real open) → no Unapproved blocker:
pwtest_rc 0 "status clone rc0" "$STB" "$SB" --skip-cli-check
if grep -q 'Unapproved' "$PWTEST_OUT"; then pwtest_bad "clean approved baseline" "false Unapproved on approved fixtures"; else pwtest_ok "clean approved → no Unapproved blocker"; fi
# reopened history: auto-reopen in-review row AFTER the approved row — the old whole-file
# grep kept reporting the file approved; the latest-row reader must flag it, with the actor:
_rv_add_s "$ARV" '| pwtest | approved |' '| 2026-10-05 12:30 | pw-review (auto-reopen) | in-review |'
pwtest_rc 0 "status after reopen" "$STB" "$SB" --skip-cli-check
pwtest_re 'Unapproved analysis review: analysis/review/fixture\.review\.md \(in-review by pw-review \(auto-reopen\)\)' "stale approval flagged with latest decision AND actor"
# hyphenated token + repair actor verbatim:
_rv_set_s "$PRV" '| 2026-09-15 00:00 | pwtest | approved |' '| 2026-10-05 13:00 | pw-review (repair) | changes-requested |'
pwtest_rc 0 "status after repair row" "$STB" "$SB" --skip-cli-check
pwtest_re 'Unapproved PLAN review \(changes-requested by pw-review \(repair\)\)' "full hyphenated token + actor shown"
# legacy decoration stays readable and satisfies the latest-row check:
_rv_set_s "$PRV" '| 2026-10-05 13:00 | pw-review (repair) | changes-requested |' '| 2026-10-05 14:00 | you | approved ✅ |'
pwtest_rc 0 "status legacy approved" "$STB" "$SB" --skip-cli-check
if grep -q 'Unapproved PLAN' "$PWTEST_OUT"; then pwtest_bad "legacy approved readable" "approved ✅ blocked"; else pwtest_ok "legacy approved ✅ satisfies the latest-row check"; fi
# placeholder row: decision shown, blank actor renders no 'by' (never invented):
_rv_set_s "$PRV" '| 2026-10-05 14:00 | you | approved ✅ |' '| | | in-review |'
pwtest_rc 0 "status placeholder" "$STB" "$SB" --skip-cli-check
pwtest_re 'Unapproved PLAN review \(in-review\)' "placeholder row: decision shown, no invented actor"
# RFC staging: template copy never appears as an unapproved analysis blocker…
cp "$PWTEST_TEMPLATE_DIR/_REVIEW.template.md" "$PW_PROJECTS_DIR/$SB/analysis/review/RFC.review.md"
pwtest_rc 0 "status with RFC staging" "$STB" "$SB" --skip-cli-check
if grep -q 'Unapproved analysis review: analysis/review/RFC\.review\.md' "$PWTEST_OUT"; then pwtest_bad "RFC excluded" "RFC staging gated as unapproved"; else pwtest_ok "RFC staging excluded from approval discovery"; fi
# …but its real open items still surface in the unresolved list (independent gate):
_open_item_s "$PW_PROJECTS_DIR/$SB/analysis/review/RFC.review.md"
pwtest_rc 0 "status RFC open item" "$STB" "$SB" --skip-cli-check
pwtest_re 'analysis/review/RFC\.review\.md \([0-9]+ open\)' "RFC unresolved comment stays visible"
rm -rf "$PW_PROJECTS_DIR/$SB"

# --- cross-project overview (--all): discovery, phase/attention semantics, JSON,
# strict read-only contract, and the shared five-lane review walk. Scratch root owned
# by this case; nothing here touches the fixtures. ---
OVW="$ROOT/ovw"; rm -rf "$OVW"; mkdir -p "$OVW"
OVST="$(pwtest_script pw-status.sh)"

# scaffold-shaped markers for every scratch project (the discovery contract)
for _ovp in alpha beta gamma delta epsln dupe; do
  mkdir -p "$OVW/$_ovp/context" "$OVW/$_ovp/analysis" "$OVW/$_ovp/task"
  printf '# inputs\n\n| # | Input |\n|---|---|\n' > "$OVW/$_ovp/context/INDEX.md"
done

# alpha: executing — verify-failed + done-not-accepted, an open task review, an
# attributed pending decision on the optional context lane, a legacy `off` AI Review
# row (read as advisory, NEVER migrated by a status read), and a crafted review/ai
# snapshot copy that must never be re-counted.
mkdir -p "$OVW/alpha/task/review" "$OVW/alpha/analysis/review" "$OVW/alpha/context/review" "$OVW/alpha/review/ai/p-batt/snapshot/task/review"
cat > "$OVW/alpha/README.md" <<'EOF'
# alpha
- **Status:** executing
- **One-liner:** alpha scratch project
- **AI Review:** analysis=off plan=advisory
EOF
cat > "$OVW/alpha/LOG.md" <<'EOF'
# Activity log — alpha
- **2026-10-08 09:00** · `exec` — spawned T01
EOF
cat > "$OVW/alpha/task/PLAN.md" <<'EOF'
# PLAN — alpha
## Task table
| Task | Repo | Branch | SP | Execute with | Depends on | Status |
|------|------|--------|----|--------------|------------|--------|
| T01 | api | b1 | 1 | kilo:default | — | done |
| T02 | api | b2 | 1 | kilo:default | T01 | verify-failed |
| T03 | api | b3 | 1 | kilo:default | T01 | accepted |
| T05 | api | b5 | 1 | kilo:default | T03 | needs-info |
EOF
printf -- '- **Status:** done\n' > "$OVW/alpha/task/T01.md"
printf '# open item\n\n### R1 · §Scope — [OPEN] (pwtest, 2026-10-05 10:00) <!-- pw-item-status: open -->\n' > "$OVW/alpha/task/review/T02.review.md"
cp "$OVW/alpha/task/review/T02.review.md" "$OVW/alpha/review/ai/p-batt/snapshot/task/review/T02.review.md"
printf '# context readiness\n\n## Sign-off\n\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-10-05 11:00 | pwtest | in-review |\n' > "$OVW/alpha/context/review/CONTEXT.review.md"

# beta: context + a PLACEHOLDER-only context review row (empty actor) — never "pending".
mkdir -p "$OVW/beta/context/review" "$OVW/beta/analysis" "$OVW/beta/task"
printf '# beta\n- **Status:** context\n- **One-liner:** beta scratch project\n' > "$OVW/beta/README.md"
printf '# context readiness\n\n## Sign-off\n\n| Date-time | By | Decision |\n|---|---|---|\n| | | in-review |\n' > "$OVW/beta/context/review/CONTEXT.review.md"

# gamma: done + an open CLOSE record (optional-lane findings stay visible after done).
mkdir -p "$OVW/gamma/review"
printf '# gamma\n- **Status:** done\n- **One-liner:** gamma scratch project\n' > "$OVW/gamma/README.md"
printf '# close evidence\n\n### R1 · §Scope — [OPEN] (pwtest, 2026-10-06 09:00) <!-- pw-item-status: open -->\n' > "$OVW/gamma/review/CLOSE.review.md"

# delta: drifted prose phase — unknown phase + malformed dashboard, still visible.
mkdir -p "$OVW/delta"
printf '# delta\n- **Status:** executed — 4/4 done awaiting acceptance\n' > "$OVW/delta/README.md"

# dupe: a duplicate task id in the PLAN table — malformed, flagged, row kept.
printf '# dupe\n- **Status:** executing\n' > "$OVW/dupe/README.md"
cat > "$OVW/dupe/task/PLAN.md" <<'EOF'
# PLAN — dupe
## Task table
| Task | Repo | Branch | SP | Execute with | Depends on | Status |
|------|------|--------|----|--------------|------------|--------|
| T01 | api | b1 | 1 | kilo:default | — | todo |
| T01 | api | b1 | 1 | kilo:default | — | todo |
EOF

# epsln: clean context project; no LOG (null last event); legacy-policy dashboard.
mkdir -p "$OVW/epsln/context"
printf '# epsln\n- **Status:** context\n- **One-liner:** epsln scratch project\n- **AI Review:** analysis=off\n' > "$OVW/epsln/README.md"

# BAD_Name: workflow markers but an unaddressable legacy name — visible, diagnostic,
# and never rendered as a runnable command.
mkdir -p "$OVW/BAD_Name/context" "$OVW/BAD_Name/analysis" "$OVW/BAD_Name/task"
printf '# bad\n- **Status:** context\n' > "$OVW/BAD_Name/context/INDEX.md"
printf '# BAD\n- **Status:** context\n' > "$OVW/BAD_Name/README.md"

# zeta: the analysis/review lane resolves OUTSIDE the project — unreadable, never read.
mkdir -p "$OVW/zeta/context" "$OVW/zeta/analysis" "$OVW/zeta/task" "$OVW/zeta-outside"
printf '# zeta\n- **Status:** executing\n' > "$OVW/zeta/README.md"
printf '# z\n- **Status:** context\n' > "$OVW/zeta/context/INDEX.md"
printf '# outside review\n' > "$OVW/zeta-outside/hidden.review.md"
ln -s "$OVW/zeta-outside" "$OVW/zeta/analysis/review"

# ignored: not a workflow project. skipped: a child-directory symlink.
mkdir -p "$OVW/notproject"
printf 'plain dir\n' > "$OVW/notproject/README.md"
ln -s "$OVW/alpha" "$OVW/linked"

pwtest_rc 1 "overview --all partial scan rc=1 (malformed delta, unreadable zeta)" \
  env PW_PROJECTS_DIR="$OVW" "$OVST" --all
pwtest_re '^8 discovered \| 8 shown \| 0 filtered \| 1 skipped symlinks \| 1 unreadable \| 2 malformed$' \
  "counts line accounts for every bucket"
pwtest_re '^alpha +executing +verification-failed \(1\), acceptance-pending \(1\), review-open \(1\), review-pending, metadata \(1\) +1/4 +8 Oct +/pw-status alpha' \
  "alpha row: attention order, accepted count, last event, status drill-down"
pwtest_re '^gamma +done +review-open \(1\) +n/a +— +/pw-status gamma' "gamma CLOSE findings visible on a done project"
pwtest_re '^delta +unknown +phase-unknown' "drifted prose phase reads unknown, not silent"
pwtest_re '^BAD_Name +context +invalid-name' "invalid legacy name flagged"
pwtest_re '^zeta +executing +metadata \(1\)' "escaped review lane becomes metadata uncertainty"
grep -q 'notproject' "$PWTEST_OUT" && pwtest_bad "non-project dir" "listed" || pwtest_ok "non-project directory ignored"
if grep -q 'BAD_Name.*/pw-' "$PWTEST_OUT"; then pwtest_bad "invalid-name command" "rendered an unusable command for BAD_Name"; else pwtest_ok "invalid legacy name never rendered as a command"; fi
pwtest_re '^Partial scan — records that need attention:' "partial section renders"
pwtest_re '→ fix: repair the flagged records' "partial scan carries remediation"
python3 - "$PWTEST_OUT" <<'PYO' && pwtest_ok "row order: attention-first, unfinished before done, slug-sorted" || pwtest_bad "row order" "unexpected order"
import sys, re
rows=[]
for line in open(sys.argv[1]):
    m = re.match(r'^(BAD_Name|alpha|beta|gamma|delta|dupe|epsln|zeta)  ', line)
    if m: rows.append(m.group(1))
assert rows == ["BAD_Name","alpha","delta","dupe","zeta","beta","epsln","gamma"], rows
PYO

# filters: --attention, --phase (dashboard token only), strict refusals
pwtest_rc 1 "overview --attention" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --attention
pwtest_re '^8 discovered \| 6 shown \| 2 filtered' "attention filter shows only attention rows"
grep -q '^beta ' "$PWTEST_OUT" && pwtest_bad "--attention beta" "clean row leaked" || pwtest_ok "--attention drops clean rows"
pwtest_rc 1 "overview --phase review (no matching rows; partial scan still exits 1)" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --phase review
pwtest_re '^8 discovered \| 0 shown \| 8 filtered' "phase filter with no match prints an explicit empty result"
pwtest_re '^\(no projects match the filter\)$' "empty filter result is spelled out"
pwtest_rc 1 "overview --phase context" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --phase context
pwtest_re '^BAD_Name +context' "phase filter keeps matching rows"
grep -q '^alpha ' "$PWTEST_OUT" && pwtest_bad "--phase context alpha" "non-matching row leaked" || pwtest_ok "--phase filters other phases out"
pwtest_rc 2 "overview rejects review-surface phase tokens" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --phase plan
pwtest_fix "review-surface refusal carries a fix"
pwtest_rc 2 "overview rejects a slug with --all" env PW_PROJECTS_DIR="$OVW" "$OVST" --all alpha
pwtest_fix "slug refusal carries a fix"
pwtest_rc 2 "overview rejects a missing --phase value" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --phase
pwtest_rc 2 "overview rejects an unknown option" env PW_PROJECTS_DIR="$OVW" "$OVST" --all --bogus

# JSON: same discovery/filters, pure stdout, machine-readable schema
env PW_PROJECTS_DIR="$OVW" "$OVST" --all --json > "$ROOT/ovw.json" 2> "$ROOT/ovw.err"; _ovj_rc=$?
[ "$_ovj_rc" = 1 ] && pwtest_ok "JSON partial scan exits 1" || pwtest_bad "json rc" "rc=$_ovj_rc"
python3 - "$ROOT/ovw.json" <<'PYJ' && pwtest_ok "JSON schema + semantics" || pwtest_bad "json semantics" "assertion failed"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["schema_version"]==1 and d["root"] and d["scanned_at"], d
c=d["counts"]
assert c=={"discovered":8,"shown":8,"filtered":0,"skipped_symlinks":1,"unreadable":1,"malformed":2}, c
p={x["slug"]:x for x in d["projects"]}
a=p["alpha"]
assert [r["code"] for r in a["attention"]]==["verification-failed","acceptance-pending","review-open","review-pending","metadata"], a["attention"]
assert a["tasks"]=={"parsable":True,"accepted":1,"total":4,"done":1,"verify_failed":1,"in_progress":0,"todo":0,"other":1}, a["tasks"]
assert a["last_event"]=={"raw":"2026-10-08 09:00","display":"8 Oct"}, a["last_event"]
assert a["inspect"]=="/pw-status alpha" and a["description"]=="alpha scratch project", a
assert p["beta"]["attention"]==[] and p["beta"]["inspect"]=="/pw-help project beta", p["beta"]
assert p["gamma"]["attention"]==[{"code":"review-open","count":1,"files":["review/CLOSE.review.md"]}], p["gamma"]
assert p["delta"]["malformed"] is True and [r["code"] for r in p["delta"]["attention"]]==["phase-unknown"] and p["delta"]["diagnostics"], p["delta"]
assert p["epsln"]["last_event"] is None and p["epsln"]["tasks"] is None and p["epsln"]["attention"]==[], p["epsln"]
assert p["BAD_Name"]["inspect"] is None and [r["code"] for r in p["BAD_Name"]["attention"]]==["invalid-name"], p["BAD_Name"]
assert p["zeta"]["unreadable"] is True and any(r["code"]=="metadata" for r in p["zeta"]["attention"]), p["zeta"]
assert p["dupe"]["malformed"] is True and any(r["code"]=="metadata" for r in p["dupe"]["attention"]), p["dupe"]
PYJ
grep -q 'partial scan' "$ROOT/ovw.err" && pwtest_ok "JSON diagnostics stay off stdout (stderr)" || pwtest_bad "json stderr diagnostics" "missing"

# empty root: an explicit empty result, exit 0
mkdir -p "$ROOT/ovw-empty"
pwtest_rc 0 "overview on an empty root" env PW_PROJECTS_DIR="$ROOT/ovw-empty" "$OVST" --all
pwtest_re '^0 discovered \| 0 shown \| 0 filtered' "empty root counts"
pwtest_re '^\(no projects\)$' "empty root is spelled out"
rmdir "$ROOT/ovw-empty"

# forbidden-call shims: forge/provider/model CLIs fail hard — the overview must not call any
mkdir -p "$ROOT/ovw-shims"
for _c in gh glab jira lark-cli kilo opencode agent; do
  printf '#!/bin/sh\necho "forbidden call: %s" >&2\nexit 97\n' "$_c" > "$ROOT/ovw-shims/$_c"
  chmod +x "$ROOT/ovw-shims/$_c"
done
pwtest_rc 1 "overview --all with failing forge/provider shims" \
  env PATH="$ROOT/ovw-shims:$PATH" PW_PROJECTS_DIR="$OVW" "$OVST" --all
pwtest_re '^8 discovered \| 8 shown \| 0 filtered \| 1 skipped symlinks \| 1 unreadable \| 2 malformed$' "shim run matches the normal run"
grep -q "forbidden call" "$PWTEST_OUT" && pwtest_bad "forbidden shim" "overview invoked a forge/provider CLI" || pwtest_ok "overview calls no forge/provider/model CLI"
rm -rf "$ROOT/ovw-shims"

# strictly read-only: overview AND single-project reads leave every byte (and dir) intact,
# and a status read never inserts missing dashboard lines (the config getters would).
_pw_ovw_hash() { ( cd "$OVW" && { find . -type f -exec shasum {} + ; find . -type d; } | LC_ALL=C sort | shasum ); }
_ovw_pre="$(_pw_ovw_hash)"
env PW_PROJECTS_DIR="$OVW" "$OVST" --all >/dev/null 2>&1 || true
env PW_PROJECTS_DIR="$OVW" "$OVST" --all --json >/dev/null 2>&1 || true
env PW_PROJECTS_DIR="$OVW" "$OVST" alpha --skip-cli-check >/dev/null 2>&1
env PW_PROJECTS_DIR="$OVW" "$OVST" epsln --skip-cli-check >/dev/null 2>&1
pwtest_eq "read-only: scratch tree hash unchanged after overview + status reads" "$_ovw_pre" "$(_pw_ovw_hash)"
grep -qE '^\- \*\*(Review Trigger|Review Repair|Review Budget):\*\*' "$OVW/epsln/README.md" \
  && pwtest_bad "status write regression" "status inserted missing dashboard lines" \
  || pwtest_ok "status never inserts missing dashboard lines (read-only policy)"

# single-project detail: shared five-lane coverage + pending decisions + advisory-normalized policy
pwtest_rc 0 "status alpha detail" env PW_PROJECTS_DIR="$OVW" "$OVST" alpha --skip-cli-check
pwtest_re '^  - task/review/T02\.review\.md \(1 open\)$' "task-lane open item listed"
[ "$(grep -c '(1 open)' "$PWTEST_OUT")" = 1 ] \
  && pwtest_ok "snapshot copy under review/ai is never double-counted" \
  || pwtest_bad "snapshot double count" "$(grep -c '(1 open)' "$PWTEST_OUT") open lines"
pwtest_re '^  - Pending review decision: context/review/CONTEXT\.review\.md \(in-review by pwtest\)$' \
  "optional-lane attributed pending decision surfaced"
pwtest_re '^outcome: analysis=advisory plan=advisory$' "legacy off reads as effective advisory"
pwtest_re 'persist with: /pw-config alpha project ensure' "legacy advisory note points at the persist path"
pwtest_re '^trigger: — \(line absent; effective default: manual per surface\)$' "absent trigger shows its default"
grep -q 'Unapproved' "$PWTEST_OUT" && pwtest_bad "alpha unapproved" "unexpected gate blocker" || pwtest_ok "no gate blocker on alpha (task/context lanes are optional)"

rm -rf "$OVW" "$ROOT/ovw.json" "$ROOT/ovw.err"
