# shellcheck shell=bash
# cases/config.t.sh — the config entity (created plan 20 Phase 5; ai-review/model-check
# + ai-model sections ported from pw-lib's inline selftest).

# --- ported from pw-lib's inline selftest (plan 20 Phase 5) ---
pl_config_selftest() {
  local tmp="$ROOT/pl-config"; rm -rf "$tmp"; mkdir -p "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  die() { pwtest_bad "pw-lib-port[config]: $*" "ported selftest assert failed"; }
  # --- AI-assisted review -------------------------------------------------
  # ai-review: get on a project with no AI Review line yet auto-creates it, all-off; set updates
  # exactly one phase, leaving the other four untouched; invalid phase/mode rejected.
  local got_ai; got_ai="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=off task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review default line wrong: '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2 plan auto >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review set did not update only 'plan': '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2 analysis advisory >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2)"
  [ "$got_ai" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review 2nd set clobbered the 1st: '$got_ai'"
  [ "$(grep -c '^- \*\*AI Review:\*\*' "$tmp/demo2/README.md")" = "1" ] || die "selftest FAIL: AI Review line duplicated"
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2 bogus-phase auto >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid phase"
  fi
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2 plan bogus-mode >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid mode"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-review demo2)" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: rejected ai-review calls still mutated the line"


  # --- model-check: empty/unset allowlist = all models allowed (the default rule) ---
  local mc
  mc="$(PW_MODEL_ALLOWLIST_CLAUDE="" "$(pwtest_script pw-config.sh)" model-check claude some-random-model-nobody-configured)" \
    || die "selftest FAIL: model-check refused with an empty allowlist (should always pass)"
  echo "$mc" | grep -q "all models allowed" || die "selftest FAIL: model-check's empty-allowlist message didn't state the 'all models allowed' rule"
  # a configured allowlist passes a matching model...
  PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$(pwtest_script pw-config.sh)" model-check claude sonnet >/dev/null \
    || die "selftest FAIL: model-check refused a model matching its configured allowlist"
  # ...glob patterns match...
  PW_MODEL_ALLOWLIST_KILO="command_code/deepseek/*" "$(pwtest_script pw-config.sh)" model-check kilo command_code/deepseek/deepseek-v4-flash >/dev/null \
    || die "selftest FAIL: model-check refused a model matching a glob pattern in its allowlist"
  # ...and refuses one that doesn't, without silently passing.
  if PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$(pwtest_script pw-config.sh)" model-check claude opus >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a model NOT in its configured allowlist"
  fi
  # ...cursor provider (2026-09): the rules are provider-generic, but the bracket-param quirk is
  # cursor-specific and worth locking: catalog ids carry 'gpt-5.6-sol-high[effort=high]' style
  # suffixes; model-check's shell `case` GLOB treats a bracket literal-ish (char class), so docs
  # steer allowlist patterns to the suffix-free id part with '*' — here we assert the plain, glob,
  # and refuse paths so a future refactor can't silently change that contract.
  mc="$(PW_MODEL_ALLOWLIST_CURSOR="" "$(pwtest_script pw-config.sh)" model-check cursor cursor-grok-4.6-low)" \
    || die "selftest FAIL: model-check refused cursor with an empty allowlist (should always pass)"
  PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*,gpt-5*" "$(pwtest_script pw-config.sh)" model-check cursor gpt-5.6-sol >/dev/null \
    || die "selftest FAIL: model-check refused cursor model matching an allowlist glob"
  if PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*" "$(pwtest_script pw-config.sh)" model-check cursor gpt-5.6-everything >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a cursor model NOT in its configured allowlist"
  fi
  # ai-model: the lane row exists, defaults to all-—, updates one lane only, clears back, refuses
  # the executor lane and a bare model name. Regression guard behind the row: a model line that
  # duplicated a task's `Execute with:` would silently drift from it — the executor is pinned in
  # its task file, never here (§5.1). The row IS advisory on kilo at Task-spawn time (a headless
  # session carries it instead, §8c) — recorded in the result, never silently ignored.
  local got_m; got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model default line wrong: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2 researcher kilo:command_code/x >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2)"
  [ "$got_m" = "researcher=kilo:command_code/x analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model set not isolated to researcher: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2 researcher — >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model clear-to-default failed: '$got_m'"
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2 executor claude:sonnet >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted the executor lane (the task file binds the executor)"
  fi
  if PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2 analyst sonnet-no-provider >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted a row without <provider>:<model> form"
  fi
  grep -q '^- \*\*AI Models:\*\*' "$tmp/demo2/README.md" \
    || die "selftest FAIL: ai-model line vanished after clears"
  rm -rf "$tmp"
}
pl_config_selftest

# --- model-resolve: the AVAILABILITY axis (catalog + api-provider prefix scope) -------------
# Uses the tests/bin/kilo|opencode shims + fixture configs via PW_CONFIG_FILE, so the checks
# never depend on the maintainer machine's real pw.config.sh.
CFG_SCOPED="$PWTEST_TESTSDIR/pw.config.test.sh"          # PW_KILO_API_PROVIDERS=(kilo/alibaba-token-plan)
CFG_OPEN="$PWTEST_TESTSDIR/pw.config.test.noscope.sh"    # entries unset → no filtering
MR="$(pwtest_script pw-config.sh)"

# nested BYOK: the row's model part (no `kilo/` prefix) resolves to the CANONICAL catalog line.
mr_out="$(PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo alibaba-token-plan/test-model 2>/dev/null)" \
  || pwtest_bad "model-resolve nested BYOK" "refused an in-catalog in-scope model"
[ "$mr_out" = "kilo/alibaba-token-plan/test-model" ] \
  && pwtest_ok "model-resolve prints the canonical nested-BYOK id" \
  || pwtest_bad "model-resolve canonical id" "got '$mr_out'"
# a row already carrying the full catalog line matches exactly too.
mr_out2="$(PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo kilo/alibaba-token-plan/test-model 2>/dev/null)" \
  && [ "$mr_out2" = "kilo/alibaba-token-plan/test-model" ] \
  && pwtest_ok "model-resolve accepts the exact catalog line" \
  || pwtest_bad "model-resolve exact line" "got '$mr_out2'"
# The prefix is SEMANTIC, not cosmetic (maintainer-verified 2026-09-23): `alibaba-token-plan/<m>`
# is a DIRECT BYOK provider line and `kilo/alibaba-token-plan/<m>` is the same BYOK under the
# gateway — different connections. When both exist, matching is exact-first: the row binds the
# line it literally names, never whichever the catalog happens to print first.
mr_out3="$(PWTEST_KILO_CATALOG_EXTRA='alibaba-token-plan/test-model' PW_CONFIG_FILE="$CFG_OPEN" \
  "$MR" model-resolve kilo alibaba-token-plan/test-model 2>/dev/null)" \
  && [ "$mr_out3" = "alibaba-token-plan/test-model" ] \
  && pwtest_ok "model-resolve exact line wins over the gateway-prefixed form" \
  || pwtest_bad "model-resolve exact-preferred" "got '$mr_out3'"
# …and a coexisting DIRECT line that is OUT of scope is a hard exit 2 — never silently re-bound
# to the in-scope gateway line.
PW_CONFIG_FILE="$CFG_SCOPED" PWTEST_KILO_CATALOG_EXTRA='alibaba-token-plan/test-model' \
  "$MR" model-resolve kilo alibaba-token-plan/test-model >/dev/null 2>"$ROOT/mr3.err"
[ "$?" = 2 ] && pwtest_ok "out-of-scope direct line exits 2 (no silent gateway re-bind)" \
  || pwtest_bad "direct out-of-scope" "rc=$?; $(head -c 120 "$ROOT/mr3.err")"
# the gateway-only fallback still resolves, but announces the substitution on stderr.
PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo alibaba-token-plan/other-model >/dev/null 2>"$ROOT/mr4.err" \
  && grep -q "gateway-nested" "$ROOT/mr4.err" \
  && pwtest_ok "gateway fallback is announced on stderr" \
  || pwtest_bad "gateway fallback note" "rc/note missing: $(head -c 120 "$ROOT/mr4.err")"
# not in the catalog → exit 1 + candidates/fix line.
PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo alibaba-token-plan/gone-xyz >/dev/null 2>"$ROOT/mr1.err"
[ "$?" = 1 ] && pwtest_ok "model-resolve exit 1 for a catalog miss" || pwtest_bad "model-resolve exit 1" "rc=$?"
grep -qE 'not in the live catalog|→ fix:' "$ROOT/mr1.err" \
  && pwtest_ok "catalog-miss refusal is actionable" || pwtest_bad "catalog-miss fix" "$(head -c 120 "$ROOT/mr1.err")"
# in the catalog but OUT of the configured prefix scope → exit 2 naming the scope (the
# `kilo:`→`kilo/alibaba-token-plan` migration case).
PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo command_code/MiniMaxAI/MiniMax-M3 >/dev/null 2>"$ROOT/mr2.err"
[ "$?" = 2 ] && pwtest_ok "model-resolve exit 2 for out-of-scope provider" || pwtest_bad "model-resolve exit 2" "rc=$?; $(head -c 120 "$ROOT/mr2.err")"
grep -qE 'OUTSIDE the PW_KILO_API_PROVIDERS scope|kilo/alibaba-token-plan' "$ROOT/mr2.err" \
  && pwtest_ok "out-of-scope refusal names the current scope" || pwtest_bad "out-of-scope fix" "$(head -c 140 "$ROOT/mr2.err")"
# no scope configured → every catalog line is in scope (the fallback rule).
PW_CONFIG_FILE="$CFG_OPEN" "$MR" model-resolve kilo command_code/MiniMaxAI/MiniMax-M3 >/dev/null 2>&1 \
  && pwtest_ok "empty entries = no filtering (in scope)" \
  || pwtest_bad "empty entries fallback" "refused with no scope configured"
# the axis is generic: opencode nested id resolves the same way.
PW_CONFIG_FILE="$CFG_OPEN" "$MR" model-resolve opencode testprov/nested/deep-model >/dev/null 2>&1 \
  && pwtest_ok "opencode axis resolves (prefix semantics generic)" \
  || pwtest_bad "opencode axis" "refused an in-catalog id"
# claude (no catalog) + unknown provider + CLI-off-PATH all FAIL OPEN as unverified — never a
# false dead, so a non-zero is always a positive determination safe to hard-stop on.
"$MR" model-resolve claude anything >/dev/null 2>&1 \
  && pwtest_ok "claude unverified → exit 0" || pwtest_bad "claude unverified" "refused"
"$MR" model-resolve kilotest anything >/dev/null 2>&1 \
  && pwtest_ok "unknown provider unverified → exit 0" || pwtest_bad "unknown provider" "refused"
mkdir -p "$ROOT/nobin"
PATH="$ROOT/nobin:/usr/bin:/bin" PW_CONFIG_FILE="$CFG_SCOPED" "$MR" model-resolve kilo alibaba-token-plan/test-model >/dev/null 2>&1 \
  && pwtest_ok "CLI off PATH → unverified, never a false dead" \
  || pwtest_bad "CLI off PATH fallback" "refused as if dead"
