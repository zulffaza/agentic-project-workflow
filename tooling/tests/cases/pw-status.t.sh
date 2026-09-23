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
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `status` — Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing/wrong format"
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
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `analyze` — wrote analysis/x\.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing/wrong format"
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
pl_status

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
LOG
pwtest_rc 0 "provider-audit filtered to clean rows exits 0" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T01 T05
pwtest_rc 1 "provider-audit names the filtered offender" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit T04
# report-only: audit must never mutate LOG.md
before="$(cat "$PA/LOG.md")"
env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PAE" provider-audit paaudit >/dev/null 2>&1
[ "$before" = "$(cat "$PA/LOG.md")" ] && pwtest_ok "provider-audit mutates nothing (LOG.md byte-identical)" || pwtest_bad "audit mutating" "LOG.md changed"
