# shellcheck shell=bash
# cases/pw-test-harness.t.sh — selftest of the harness machinery itself (plan 19):
# lazy fixture selection + recipe-hash + pristine-fixture cache store/restore.
# Deliberately NO $F/$S var references (bare pwt-f* literals only) so the lazy scan
# builds nothing for this case — keeps its own --only child fast and proves skip.
TH=pwtest-harness

# a) T0 child builds no fixtures at all
_arc=0; bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T0 </dev/null >"$PWTEST_ROOT/$TH.a.out" 2>&1 || _arc=$?
pwtest_eq "T0 child exits 0" 0 "$_arc"
grep -q 'TEST fixtures built: none' "$PWTEST_ROOT/$TH.a.out" && pwtest_ok "T0 child builds no fixtures" \
  || pwtest_bad "T0 child builds no fixtures" "expected 'built: none' in child output"

# b) T4 child likewise
_arc=0; bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T4 </dev/null >"$PWTEST_ROOT/$TH.b.out" 2>&1 || _arc=$?
pwtest_eq "T4 child exits 0" 0 "$_arc"
grep -q 'TEST fixtures built: none' "$PWTEST_ROOT/$TH.b.out" && pwtest_ok "T4 child builds no fixtures" \
  || pwtest_bad "T4 child builds no fixtures" "expected 'built: none' in child output"

# c) recipe hash: deterministic, and sensitive to the template tree
_h1="$(_pwtest_recipe_hash)"; _h2="$(_pwtest_recipe_hash)"
[ "$_h1" = "$_h2" ] && pwtest_ok "recipe hash deterministic" || pwtest_bad "recipe hash deterministic" "$_h1 != $_h2"
_pwt_fake="$PWTEST_ROOT/$TH-fakebundle"; mkdir -p "$_pwt_fake/template" "$_pwt_fake/tooling/tests"
echo seed > "$_pwt_fake/template/x.md"
( PW_HOME="$_pwt_fake"; _pwtest_recipe_hash ) >"$PWTEST_ROOT/$TH.h.out" 2>&1
_h3="$(cat "$PWTEST_ROOT/$TH.h.out")"
[ -n "$_h3" ] && [ "$_h3" != "$_h1" ] && pwtest_ok "recipe hash tracks the template tree" \
  || pwtest_bad "recipe hash tracks the template tree" "fake-bundle hash [$_h3] vs real [$_h1]"

# d) cache store/restore round-trip (only when this run built all three fixtures)
if [ -d "$PW_PROJECTS_DIR/pwt-f1-scaffold" ] && [ -d "$PW_PROJECTS_DIR/pwt-f2-mid" ] && [ -d "$PW_PROJECTS_DIR/pwt-f3-hostile" ]; then
  _tc="$PWTEST_ROOT/$TH-cache"
  PWTEST_FIXTURE_CACHE="$_tc" _pwtest_cache_store; unset PWTEST_FIXTURE_CACHE
  _cd="$_tc/$_h1"
  [ -f "$_cd/.done-pwt-f2-mid" ] && [ -d "$_cd/projects/pwt-f2-mid" ] && [ -d "$_cd/repos/api" ] \
    && pwtest_ok "cache stores fixtures + root under recipe hash" \
    || pwtest_bad "cache stores fixtures + root under recipe hash" "no $_cd/.done-pwt-f2-mid"
  # a child pointed at the cache must hit it (F2) instead of building (~seconds, not ~45)
  PWTEST_FIXTURE_CACHE="$_tc" bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T1 --only pw-context </dev/null >"$PWTEST_ROOT/$TH.d.out" 2>&1
  _drc=$?
  grep -q 'TEST fixtures cache-hit: F2' "$PWTEST_ROOT/$TH.d.out" && [ "$_drc" = 0 ] \
    && pwtest_ok "cache-hit child restores F2 and passes" \
    || pwtest_bad "cache-hit child restores F2 and passes" "rc=$_drc; $(grep -E 'fixtures|FAIL' "$PWTEST_ROOT/$TH.d.out" | head -2 | tr '\n' ' ')"
  # cached fixture must stay pristine despite the child's mutating cases
  [ ! -e "$_cd/projects/pwt-f2-mid/task/T95.md" ] && [ ! -e "$_cd/projects/pwt-f2-mid/task/ctxedit.md" ] \
    && pwtest_ok "cache stays pristine after child mutations" \
    || pwtest_bad "cache stays pristine after child mutations" "child leaked fixture edits into the cache"
else
  pwtest_skip "cache store/restore" "this run built no fixtures (lazy) — covered by the full harness"
fi
