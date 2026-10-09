# shellcheck shell=bash
# cases/pw-test-harness.t.sh — selftest of the harness machinery itself (plan 19):
# lazy fixture selection + recipe-hash + pristine-fixture cache store/restore.
# Deliberately NO $F/$S var references (bare pwt-f* literals only) so the lazy scan
# builds nothing for this case — keeps its own --only child fast and proves skip.
TH=pwtest-harness

# a) T0 child builds no fixtures at all — and must not MATERIALIZE any either (a cache-hit
# line proves the lazy scan selected fixtures even though nothing was built; this is what
# keeps the C42 mutation "scan always sets NEED flags" detectable in a warm-cache sweep)
_arc=0; bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T0 </dev/null >"$PWTEST_ROOT/$TH.a.out" 2>&1 || _arc=$?
pwtest_eq "T0 child exits 0" 0 "$_arc"
grep -q 'TEST fixtures built: none' "$PWTEST_ROOT/$TH.a.out" && ! grep -q 'fixtures cache-hit' "$PWTEST_ROOT/$TH.a.out" \
  && pwtest_ok "T0 child builds no fixtures" \
  || pwtest_bad "T0 child builds no fixtures" "expected 'built: none' with no fixture materialization in child output"

# b) T4 child likewise. Its exit-0 assert includes the pw-doctor sync check, which
# compares the tree against the provider installs under $HOME — those belong to the
# PARENT bundle, so inside a disposable sweep copy (PWTEST_INNER) the check is about a
# different tree by construction (pre-existing coupling, same one section f) skips for
# "live tree untouched"). The lazy-fixtures assert stays universal; the sync assert
# remains fully enforced in every real-tree run.
_arc=0; bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T4 </dev/null >"$PWTEST_ROOT/$TH.b.out" 2>&1 || _arc=$?
_th_install_only() {
  awk '/^  FAIL / { n++; if ($0 !~ /^  FAIL T4 pw-doctor reports in sync .*OUT OF SYNC/) bad=1 }
       END { exit !(n == 1 && !bad) }'
}
printf '%s\n' '  FAIL T4 pw-doctor reports in sync — OUT OF SYNC' | _th_install_only \
  && pwtest_ok "inner T4 allows only the expected install mismatch" \
  || pwtest_bad "inner T4 install mismatch classifier" "expected sole sync failure was rejected"
if printf '%s\n' '  FAIL T4 pw-doctor reports in sync — OUT OF SYNC' '  FAIL unrelated check' | _th_install_only; then
  pwtest_bad "inner T4 rejects additional failures" "an unrelated failure was hidden by the sync mismatch"
else
  pwtest_ok "inner T4 rejects additional failures"
fi
if [ -n "${PWTEST_INNER:-}" ]; then
  # serial single-row children run against the live tree (rc 0 expected); parallel
  # workers run a bundle copy whose T4 must be red ONLY through the install-coupling.
  if [ "$_arc" = 0 ]; then pwtest_ok "T4 child exits 0 (inner, live tree)"
   elif [ "$_arc" = 1 ] && _th_install_only < "$PWTEST_ROOT/$TH.b.out"; then pwtest_ok "inner T4 child red is install-coupling only"
  else pwtest_bad "inner T4 child red is install-coupling only" "rc=$_arc without the expected sync mismatch: $(grep -m1 FAIL "$PWTEST_ROOT/$TH.b.out")"
  fi
else
  pwtest_eq "T4 child exits 0" 0 "$_arc"
fi
grep -q 'TEST fixtures built: none' "$PWTEST_ROOT/$TH.b.out" && ! grep -q 'fixtures cache-hit' "$PWTEST_ROOT/$TH.b.out" \
  && pwtest_ok "T4 child builds no fixtures" \
  || pwtest_bad "T4 child builds no fixtures" "expected 'built: none' with no fixture materialization in child output"

# c) recipe hash: deterministic, and sensitive to the template tree
_h1="$(_pwtest_recipe_hash)"; _h2="$(_pwtest_recipe_hash)"
[ "$_h1" = "$_h2" ] && pwtest_ok "recipe hash deterministic" || pwtest_bad "recipe hash deterministic" "$_h1 != $_h2"
_pwt_fake="$PWTEST_ROOT/$TH-fakebundle"; mkdir -p "$_pwt_fake/template" "$_pwt_fake/tooling/tests"
echo seed > "$_pwt_fake/template/x.md"
( PW_HOME="$_pwt_fake"; _pwtest_recipe_hash ) >"$PWTEST_ROOT/$TH.h.out" 2>&1
_h3="$(cat "$PWTEST_ROOT/$TH.h.out")"
[ -n "$_h3" ] && [ "$_h3" != "$_h1" ] && pwtest_ok "recipe hash tracks the template tree" \
  || pwtest_bad "recipe hash tracks the template tree" "fake-bundle hash [$_h3] vs real [$_h1]"

# d) mutation crash-safety stack stays BOUNDED across push/pop (the exponential-pop
#    rebuild was the plan-17 parent-side "hang" — children done, tree clean, CPU spin)
_savestack="${PWTEST_MUT_STACK:-}"
PWTEST_MUT_STACK=""
_pwt_mutable_push "f1|b1"; _pwt_mutable_push "f2|b2"; _pwt_mutable_push "f3|b3"
_pwt_mutable_pop "f2|b2"
pwtest_eq "mutable stack bounded after pop" 2 "$(printf '%s\n' "$PWTEST_MUT_STACK" | grep -c .)"
_pwt_mutable_pop "f1|b1"; _pwt_mutable_pop "f3|b3"
[ -z "$PWTEST_MUT_STACK" ] && pwtest_ok "mutable stack drains to empty" \
  || pwtest_bad "mutable stack drains" "leftover [$PWTEST_MUT_STACK]"
PWTEST_MUT_STACK="$_savestack"

# e) cache store/restore round-trip (only when this run built all three fixtures)
if [ -d "$PW_PROJECTS_DIR/pwt-f1-scaffold" ] && [ -d "$PW_PROJECTS_DIR/pwt-f2-mid" ] && [ -d "$PW_PROJECTS_DIR/pwt-f3-hostile" ]; then
  _tc="$PWTEST_ROOT/$TH-cache"
  PWTEST_FIXTURE_CACHE="$_tc" _pwtest_cache_store; unset PWTEST_FIXTURE_CACHE
  _cd="$_tc/$_h1"
  [ -f "$_cd/.done-pwt-f2-mid" ] && [ -d "$_cd/projects/pwt-f2-mid" ] && [ -d "$_cd/repos/api" ] \
    && pwtest_ok "cache stores fixtures + root under recipe hash" \
    || pwtest_bad "cache stores fixtures + root under recipe hash" "no $_cd/.done-pwt-f2-mid"
  # a child pointed at the cache must hit it (F2) instead of building (~seconds, not ~45).
  # The family list grows with the case's fixture refs (F1 joined when pw-context gained its
  # context-phase ensure block), so assert containment — F2 restored FROM CACHE — not the
  # exact string.
  PWTEST_FIXTURE_CACHE="$_tc" bash "$PWTEST_TESTSDIR/pw_test.sh" --tier T1 --only pw-context </dev/null >"$PWTEST_ROOT/$TH.d.out" 2>&1
  _drc=$?
  grep -qE 'TEST fixtures cache-hit: .*F2' "$PWTEST_ROOT/$TH.d.out" && [ "$_drc" = 0 ] \
    && pwtest_ok "cache-hit child restores F2 and passes" \
    || pwtest_bad "cache-hit child restores F2 and passes" "rc=$_drc; $(grep -E 'fixtures|FAIL' "$PWTEST_ROOT/$TH.d.out" | head -2 | tr '\n' ' ')"
  # cached fixture must stay pristine despite the child's mutating cases
  [ ! -e "$_cd/projects/pwt-f2-mid/task/T95.md" ] && [ ! -e "$_cd/projects/pwt-f2-mid/task/ctxedit.md" ] \
    && pwtest_ok "cache stays pristine after child mutations" \
    || pwtest_bad "cache stays pristine after child mutations" "child leaked fixture edits into the cache"
else
  pwtest_skip "cache store/restore" "this run built no fixtures (lazy) — covered by the full harness"
fi

# f) parallel sweep (F5): two file-groups on two workers, run on disposable copies — both
#    rows caught, live tree never mutated. Gated on a warm cache (else the nested warm
#    build would cost ~48 s in every standalone run) and depth-1 (no recursion).
if [ -n "${PWTEST_FIXTURE_CACHE:-}" ] && [ -z "${PWTEST_MUT_NESTED:-}" ]; then
  _np="$PWTEST_ROOT/mut-nested"; mkdir -p "$_np"
  PWTEST_MUT_NESTED=1 PWTEST_MUT_JOBS=2 bash "$PWTEST_TESTSDIR/pw_test.sh" --mutation 'C10-|C12-' </dev/null >"$_np/out.log" 2>&1
  _nrc=$?
  [ "$_nrc" = 0 ] && grep -q '2 mutations, 2 caught, 0 hung' "$_np/out.log" \
    && pwtest_ok "parallel mini-sweep (2 workers) catches both rows" \
    || pwtest_bad "parallel mini-sweep (2 workers) catches both rows" "rc=$_nrc: $(grep -E 'mutate:|FAIL' "$_np/out.log" | head -1)"
  if [ -d "$PW_HOME/.git" ]; then
    git -C "$PW_HOME" diff --quiet -- tooling/scripts/entities/pw-worktree.sh tooling/scripts/entities/pw-status.sh \
      && pwtest_ok "live tree untouched by parallel workers" \
      || pwtest_bad "live tree untouched by parallel workers" "worker mutated the live tree"
  else
    pwtest_skip "live tree untouched" "running from a bundle copy (no .git) — copies are disposable by construction"
  fi
fi

# g) F3 cache-restore re-points worktree links (C111 catcher). A cache built in another
#    root carries stale absolute links; pw-ship's mr-state asserts read through F3's
#    restored worktrees and every sweep child uses the cache — an un-repaired F3 link
#    made those baseline-red, which mutate.sh's rc-classification would have silently
#    counted as "caught". Craft build-root -> cache -> restore-root, then check the link.
_FR="$PWTEST_ROOT/f3repair"; rm -rf "$_FR"; mkdir -p "$_FR/build/projects/pwt-f3-hostile/worktree/api" "$_FR/build/repos"
git init -q --bare "$_FR/build/seed.git" 2>/dev/null
git clone -q "$_FR/build/seed.git" "$_FR/build/repos/api" >/dev/null 2>&1
( cd "$_FR/build/repos/api" && printf seed > seed.txt && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 \
  && git branch wt1 >/dev/null 2>&1 \
  && git worktree add "$_FR/build/projects/pwt-f3-hostile/worktree/api/T01-thing" wt1 >/dev/null 2>&1 )
_FRH="$(_pwtest_recipe_hash)"; _FRC="$_FR/cache/$_FRH"; mkdir -p "$_FRC/projects"
cp -a "$_FR/build/projects/pwt-f3-hostile" "$_FRC/projects/" 2>/dev/null
cp -a "$_FR/build/repos" "$_FRC/repos" 2>/dev/null; mkdir -p "$_FRC/seeds"; cp -a "$_FR/build/seed.git" "$_FRC/seeds/api.git" 2>/dev/null
: > "$_FRC/.done-pwt-f3-hostile"
rm -rf "$_FR/build"                                   # stale links now point at a dead root
_FR_R="$_FR/restore"; mkdir -p "$_FR_R/projects" "$_FR_R/repos" "$_FR_R/seeds"
( export PWTEST_ROOT="$_FR_R" PW_PROJECTS_DIR="$_FR_R/projects" PW_REPOS="$_FR_R/repos" \
      PWTEST_FIXTURE_CACHE="$_FR/cache" NEED_F1=0 NEED_F2=0 NEED_F3=1
  _pwtest_materialize >/dev/null 2>&1 || true )
if git -C "$_FR_R/projects/pwt-f3-hostile/worktree/api/T01-thing" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pwtest_ok "F3 cache-restore repairs worktree links"
else
  pwtest_bad "F3 cache-restore repairs worktree links" "restored worktree cannot resolve its gitdir"
fi
rm -rf "$_FR"
