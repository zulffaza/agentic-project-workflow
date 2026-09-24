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
  local got_m; got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" project get demo2 ai-model 2>/dev/null)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model default line wrong: '$got_m'"
  # write-time validation (permission + availability + provider membership) rides the shim
  # catalog + noscope fixture config: only rows that can actually bind are accepted.
  PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" \
    "$(pwtest_script pw-config.sh)" project set demo2 ai-model researcher kilo:command_code/MiniMaxAI/MiniMax-M3 >/dev/null 2>&1 || die "selftest FAIL: project set ai-model refused a resolvable in-scope row"
  got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" project get demo2 ai-model 2>/dev/null)"
  [ "$got_m" = "researcher=kilo:command_code/MiniMaxAI/MiniMax-M3 analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model set not isolated to researcher: '$got_m'"
  # a catalog miss is refused AT WRITE TIME (not discovered at spawn), leaving the line intact:
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" \
     "$(pwtest_script pw-config.sh)" project set demo2 ai-model researcher kilo:command_code/gone-xyz >/dev/null 2>&1; then
    die "selftest FAIL: project set ai-model accepted a model missing from the live catalog"
  fi
  # a provider absent from PW_PROVIDERS is refused the same way:
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" \
     "$(pwtest_script pw-config.sh)" project set demo2 ai-model analyst ghostprov:some-model >/dev/null 2>&1; then
    die "selftest FAIL: project set ai-model accepted a provider that is not enabled"
  fi
  got_m="$(PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" project get demo2 ai-model 2>/dev/null)"
  [ "$got_m" = "researcher=kilo:command_code/MiniMaxAI/MiniMax-M3 analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: refused ai-model sets still mutated the line: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-config.sh)" ai-model demo2 researcher — >/dev/null 2>&1
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

# --- project scope: show / get / set / ensure + global show + state refusals ------------------
# Own scratch project (no F2 needed): a minimal dashboard + PLAN skeleton exercising both
# writer paths — replace-existing-bullet and insert-after-anchor.
PRJ="$ROOT/projects/pcfg-demo"; mkdir -p "$PRJ/task"
printf -- '- **Status:** context\n- **One-liner:** cfg fixture\n' > "$PRJ/README.md"
: > "$PRJ/LOG.md"
printf '## Breakdown rules / execution routing (project-specific)\n- **Routing overrides:** none\n\n## Execution strategy\n- Max parallelism: <n> concurrent executors.\n- **AI execution limit:** <n> (default 3)\n- **Produced by:** <provider>\n\n## Task table\n| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |\n|----|-------|------|------------|-------|--------------|----|--------|------|--------|\n' > "$PRJ/task/PLAN.md"
PC="$(pwtest_script pw-config.sh)"
PCS="env PW_CONFIG_FILE=$PWTEST_TESTSDIR/pw.config.test.sh PW_PROJECTS_DIR=$ROOT/projects $PC"

# ensure: both explicit config lines appear (absent line = defect doctrine), idempotent.
pwtest_rc 0 "project ensure inserts config lines" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project ensure pcfg-demo
grep -qE '^- \*\*AI Review:\*\* analysis=off plan=off' "$PRJ/README.md" \
  && pwtest_ok "AI Review line ensured with explicit off values" || pwtest_bad "ensure review line" "$(grep -c 'AI Review' "$PRJ/README.md")"
grep -qE '^- \*\*AI Models:\*\* researcher=—' "$PRJ/README.md" \
  && pwtest_ok "AI Models line ensured with explicit — rows" || pwtest_bad "ensure models line" "$(grep -c 'AI Models' "$PRJ/README.md")"
_before_ensure2="$(cat "$PRJ/README.md")"
pwtest_rc 0 "project ensure idempotent" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project ensure pcfg-demo
[ "$_before_ensure2" = "$(cat "$PRJ/README.md")" ] && pwtest_ok "second ensure is a no-op" || pwtest_bad "ensure not idempotent" "README changed twice"

# get: unset values report the effective floor, not silence.
pwtest_rc 0 "project get routing (unset)" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project get pcfg-demo routing
pwtest_re 'unset — effective: auto' "unset routing names the effective floor"

# set: enum validation refuses first…
pwtest_rc 2 "project set refuses a bad routing value" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo routing turbo
# …and accepts the strict rung (headless) via the insert-anchor path (no bullet existed).
pwtest_rc 0 "project set routing headless (strict)" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo routing headless
grep -qE '^- \*\*Routing:\*\* headless$' "$PRJ/task/PLAN.md" \
  && pwtest_ok "routing bullet inserted after the routing section anchor" || pwtest_bad "routing insert" "$(grep 'Routing' "$PRJ/task/PLAN.md")"
# existing-bullet replace: execution-limit + produced-by; max-parallel keeps its sentence shape.
pwtest_rc 0 "project set execution-limit" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo execution-limit 5
grep -qE '^- \*\*AI execution limit:\*\* 5$' "$PRJ/task/PLAN.md" && pwtest_ok "limit bullet replaced" || pwtest_bad "limit bullet" "$(grep 'execution limit' "$PRJ/task/PLAN.md")"
pwtest_rc 2 "execution-limit refuses non-integer" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo execution-limit many
pwtest_rc 2 "execution-limit refuses out-of-range" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo execution-limit 100
pwtest_rc 0 "project set max-parallel" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo max-parallel 4
grep -qE '^- Max parallelism: 4 concurrent executors\.$' "$PRJ/task/PLAN.md" && pwtest_ok "max-parallel keeps its sentence" || pwtest_bad "max-parallel line" "$(grep 'Max parallelism' "$PRJ/task/PLAN.md")"
# produced-by validates against the CURRENT global config: kilotest is not enabled in
# pw.config.test.sh (kilo claude cursor)…
pwtest_rc 2 "produced-by refuses an unlisted provider" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo produced-by kilotest
# …but replaces cleanly when it is (f2 fixture config).
pwtest_rc 0 "produced-by accepts an enabled provider" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.f2.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo produced-by kilotest
grep -qE '^- \*\*Produced by:\*\* kilotest$' "$PRJ/task/PLAN.md" && pwtest_ok "produced-by bullet replaced (placeholder gone)" || pwtest_bad "produced-by bullet" "$(grep 'Produced by' "$PRJ/task/PLAN.md")"

# state/data keys: show-only, refused by get and set with the owning flow named.
pwtest_rc 2 "project get refuses state key" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project get pcfg-demo status
pwtest_err "state/data" "refusal explains state/data"
pwtest_rc 2 "project set refuses data key" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo base-branches master
pwtest_err "owning flow" "refusal names the owning flow"

# ai-review through project: same validated writer as the (deprecated) bare verb.
pwtest_rc 0 "project set ai-review plan auto" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo ai-review plan auto
pwtest_rc 0 "project get ai-review shows it" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project get pcfg-demo ai-review
pwtest_re 'plan=auto' "ai-review write landed"
# BATCH set: several phase=mode pairs in ONE command → one write, one LOG line.
_before_log="$(grep -c '^- ' "$PRJ/LOG.md")"
pwtest_rc 0 "project set ai-review batch" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo ai-review analysis=advisory task-plan=auto ship=off
pwtest_rc 0 "batch get reflects all pairs" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project get pcfg-demo ai-review
pwtest_re 'analysis=advisory plan=auto task-plan=auto task-exec=off ship=off' "all three pairs landed, untouched kept"
_after_log="$(grep -c '^- ' "$PRJ/LOG.md")"
[ "$(( _after_log - _before_log ))" = 1 ] \
  && pwtest_ok "batch is one LOG line" || pwtest_bad "batch log" "$((_after_log-_before_log)) new lines (want 1)"
# all-or-nothing: a batch with one illegal pair must write NOTHING.
_aim_before="$(grep -m1 '^- \*\*AI Models:\*\*' "$PRJ/README.md" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//')"
if PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo ai-model \
   "researcher=kilo:command_code/MiniMaxAI/MiniMax-M3" "analyst=ghostprov:m" >/dev/null 2>&1; then
  pwtest_bad "batch all-or-nothing" "refused-batch returned 0"
else
  pwtest_ok "batch refuses when ANY pair is invalid"
fi
_aim_after="$(grep -m1 '^- \*\*AI Models:\*\*' "$PRJ/README.md" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//')"
[ "$_aim_before" = "$_aim_after" ] && pwtest_ok "refused batch wrote nothing (validated before write)" || pwtest_bad "batch atomicity" "line changed: '$_aim_after'"
# batch ai-model with all-valid pairs lands in one write + one log.
pwtest_rc 0 "project set ai-model batch valid" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo ai-model \
  "researcher=kilo:command_code/MiniMaxAI/MiniMax-M3" "reviewer=—"
pwtest_rc 0 "batch ai-model get" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project get pcfg-demo ai-model
pwtest_re 'researcher=kilo:command_code/MiniMaxAI/MiniMax-M3 analyst=— writer-task=— reviewer=— verifier=—' "model batch landed both kinds of pair"
# rfc-target delegates to the rfc entity (META gets created + stamped).
pwtest_rc 0 "project set rfc-target" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project set pcfg-demo rfc-target "https://example/rfcs/42"
grep -qF 'https://example/rfcs/42' "$PRJ/rfc/META.md" 2>/dev/null && pwtest_ok "rfc-target persisted to META" || pwtest_bad "rfc-target META" "$(cat "$PRJ/rfc/META.md" 2>/dev/null | head -3)"

# show lists kinds + json parses; LOG.md recorded the writes; global show is pure read.
pwtest_rc 0 "project show lists the whole surface" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project show pcfg-demo
pwtest_re 'routing[[:space:]]+config' "show row: routing is config-kind"
pwtest_re 'status[[:space:]]+state' "show row: status is state-kind"
# discoverability (owner 09-24): the settable vocabulary ships IN the show output's footer —
# you never have to open a doc to learn what can change and to which values.
pwtest_re 'settable keys: routing' "show footer lists settable keys + value shapes"
pwtest_re 'show-only .flows derive' "show footer names the show-only kinds"
pwtest_rc 0 "project show --json parses" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" project show pcfg-demo --json
python3 -c "import json,sys; d=json.load(sys.stdin); assert d['slug']=='pcfg-demo' and any(r['key']=='routing' and r['stored']=='headless' for r in d['rows'])" < "$PWTEST_OUT" \
  && pwtest_ok "json carries the written values" || pwtest_bad "json shape" "$(head -c 120 "$PWTEST_OUT")"
grep -qE '· `config` — routing -> headless' "$PRJ/LOG.md" && pwtest_ok "every set logs to LOG.md" || pwtest_bad "LOG lines" "$(grep -c '^- ' "$PRJ/LOG.md")"
LOGN="$(grep -c '^- ' "$PRJ/LOG.md")"; READMEB="$(cat "$PRJ/README.md")"
pwtest_rc 0 "global show" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" global show
pwtest_re 'providers[[:space:]]+: kilo claude cursor' "global show lists providers"
pwtest_re 'route-default' "global show lists the route floor"
[ "$(grep -c '^- ' "$PRJ/LOG.md")" = "$LOGN" ] && [ "$READMEB" = "$(cat "$PRJ/README.md")" ] \
  && pwtest_ok "global show mutates nothing (read-only floor view)" || pwtest_bad "global show mutated" "LOG/README changed"
# deprecated shims still work but announce the pointer on stderr.
pwtest_rc 0 "bare ai-review still functions (shim)" env PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.sh" PW_PROJECTS_DIR="$ROOT/projects" "$PC" ai-review pcfg-demo
pwtest_err 'deprecated' "bare verb prints the deprecation pointer"

# --- plan 23: `pin` — the dual-holder batch key riding the KI-1 propagator ---
# Same write-time validation as ai-model (membership + model-check + model-resolve via the shim
# catalog + noscope fixture config), all-or-nothing batches, ONE log line, both holders per pin.
p23_pin_selftest() {
  local tmp="$ROOT/p23-pin"; rm -rf "$tmp"; mkdir -p "$tmp/pinproj/task"
  printf -- '- **Status:** breakdown\n- **One-liner:** pin fixture\n' > "$tmp/pinproj/README.md"
  : > "$tmp/pinproj/LOG.md"
  cat > "$tmp/pinproj/task/PLAN.md" <<'PLAN'
# PLAN — pinproj
## Task table
| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |
|----|-------|------|------------|-------|--------------|----|--------|------|--------|
| [T01](./T01.md) | a | api | — | G1 | claude:sonnet | 1 | todo | — | — |
| [T02](./T02.md) | b | api | T01 | G1 | claude:sonnet | 1 | todo | — | — |
PLAN
  printf -- '- **Status:** todo\n- **Execute with:** claude:sonnet\n' > "$tmp/pinproj/task/T01.md"
  printf -- '- **Status:** todo\n- **Execute with:** claude:sonnet\n' > "$tmp/pinproj/task/T02.md"
  die() { pwtest_bad "plan-23 pin: $*" "selftest assert failed"; }
  local CFG NOSCOPE GOOD
  CFG="$(pwtest_script pw-config.sh)"; NOSCOPE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh"
  GOOD="kilo:command_code/MiniMaxAI/MiniMax-M3"

  # single pin → BOTH holders + exactly one LOG line
  PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin "T01=$GOOD" >/dev/null
  grep -q "^- \*\*Execute with:\*\* $GOOD\$" "$tmp/pinproj/task/T01.md" || die "task-file holder not written"
  grep -qF "| $GOOD | 1 | todo |" "$tmp/pinproj/task/PLAN.md" || die "PLAN cell holder not written"
  [ "$(grep -c 'pin T01 ->' "$tmp/pinproj/LOG.md")" = "1" ] || die "expected exactly one LOG line for the single pin"

  # batch → both pins, both holders, ONE log line
  PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T01=claude:opus T02=claude:haiku >/dev/null
  grep -q '^- \*\*Execute with:\*\* claude:opus$' "$tmp/pinproj/task/T01.md" || die "batch T01 file holder not written"
  grep -q '^- \*\*Execute with:\*\* claude:haiku$' "$tmp/pinproj/task/T02.md" || die "batch T02 file holder not written"
  grep -q '| claude:haiku | 1 | todo |' "$tmp/pinproj/task/PLAN.md" || die "batch T02 PLAN cell not written"
  grep -q '| claude:opus | 1 | todo |' "$tmp/pinproj/task/PLAN.md" || die "batch T01 PLAN cell not written"
  [ "$(grep -c 'pin set: T01=claude:opus T02=claude:haiku' "$tmp/pinproj/LOG.md")" = "1" ] || die "batch LOG line missing or doubled"

  # all-or-nothing: a catalog-miss pair refuses the WHOLE batch — the valid pair is not written
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin "T01=$GOOD" T02=kilo:command_code/gone-xyz >/dev/null 2>&1; then
    die "catalog-miss pair was not refused at write time"
  fi
  grep -q '^- \*\*Execute with:\*\* claude:opus$' "$tmp/pinproj/task/T01.md" || die "refused batch still wrote the valid pair (not all-or-nothing)"
  # provider not enabled → refused
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T01=ghostprov:m >/dev/null 2>&1; then
    die "provider absent from PW_PROVIDERS was accepted"
  fi
  # malformed id / missing task file / missing PLAN row → refused
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin X9=claude:opus >/dev/null 2>&1; then die "non-T0n id accepted"; fi
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T99=claude:opus >/dev/null 2>&1; then die "missing task file accepted"; fi
  printf -- '- **Status:** todo\n- **Execute with:** claude:sonnet\n' > "$tmp/pinproj/task/T03.md"
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T03=claude:opus >/dev/null 2>&1; then die "task with no PLAN row accepted"; fi
  rm -f "$tmp/pinproj/task/T03.md"
  # a task file WITHOUT the Execute-with field is refused at validation (nothing half-written)
  printf -- '- **Status:** todo\n' > "$tmp/pinproj/task/T04.md"
  awk '/^\| \[T02\]/ { print; print "| [T04](./T04.md) | d | api | — | G1 | claude:sonnet | 1 | todo | — | — |"; next } { print }' \
    "$tmp/pinproj/task/PLAN.md" > "$tmp/pinproj/task/PLAN.md.tmp" && mv "$tmp/pinproj/task/PLAN.md.tmp" "$tmp/pinproj/task/PLAN.md"
  if PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T04=claude:opus >/dev/null 2>&1; then die "task without the Execute-with field accepted"; fi
  rm -f "$tmp/pinproj/task/T04.md"

  # clear to — (both holders)
  PW_PROJECTS_DIR="$tmp" PW_CONFIG_FILE="$NOSCOPE" "$CFG" project set pinproj pin T02=— >/dev/null
  grep -q '^- \*\*Execute with:\*\* —$' "$tmp/pinproj/task/T02.md" || die "clear did not write the task file"
  grep -q '| — | 1 | todo |' "$tmp/pinproj/task/PLAN.md" || die "clear did not write the PLAN cell"

  # read side: get pin (list) + get pin.T0n (one)
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$CFG" project get pinproj pin | tr '\n' ' ')"
  [ "$got" = "T01=claude:opus T02=— " ] || die "get pin list wrong: '$got'"
  got="$(PW_PROJECTS_DIR="$tmp" "$CFG" project get pinproj pin.T01)"
  [ "$got" = "claude:opus" ] || die "get pin.T01 wrong: '$got'"

  # discoverability: the show footer carries the pin vocabulary
  PW_PROJECTS_DIR="$tmp" "$CFG" project show pinproj | grep -qF 'pin[T0n=provider:model|—]' || die "show footer missing the pin key vocabulary"
  rm -rf "$tmp"
  pwtest_ok "plan-23 pin key: dual-holder batches, all-or-nothing, clear, get, footer (all asserts passed)"
}
p23_pin_selftest
