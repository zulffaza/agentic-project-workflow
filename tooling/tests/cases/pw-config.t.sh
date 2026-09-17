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
pl_config
