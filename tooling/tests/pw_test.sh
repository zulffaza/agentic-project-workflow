#!/usr/bin/env bash
# ============================================================================
# pw_test.sh — the tooling change-testing harness (plan 16).
#
#   tooling/tests/pw_test.sh                        default tiers T0,T1,T2,T4 (T3 needs --corpus-dir)
#   tooling/tests/pw_test.sh --tier T0,T1           select tiers (comma list)
#   tooling/tests/pw_test.sh --only doc-lint        filter T1 case files by name
#                                                   (resolved once; a no-match T1 filter exits 2)
#   tooling/tests/pw_test.sh --corpus-dir DIR       run T3 read-only over real projects
#   tooling/tests/pw_test.sh --capture T2|gates|both    record current behavior as expectations (REVIEW the diff!)
#   tooling/tests/pw_test.sh --mutation [filter]    meta-test: revert documented fixes, expect failures
#   tooling/tests/pw_test.sh -v                     per-check lines
#   env PWTEST_MUT_JOBS=N                           sweep parallelism (auto min(ncpu,8); 1 = serial live-tree)
#   env PWTEST_MUT_TIMEOUT=N                        per-child watchdog seconds (default 300; timeout = HUNG, sweep continues)
#   env PWTEST_MUT_CACHE=DIR                        sweep fixture-cache dir (default $TMPDIR/pwtest-fixture-cache)
#   env PWTEST_FIXTURE_CACHE=DIR                    standalone fixture cache (set by the sweep for its children; empty = off)
#
# Exit 0 = everything selected passed. Cumulative reporting (all failures listed).
# Fixtures are GENERATED from template/ but only when the selected tiers/cases consume them
# (T0/T4 build none); sweep children copy from a pristine recipe-hash-keyed cache. Only the
# CORPUS (T3) is read-only. Mechanics + authoring rules: docs/testing.md §Inside the harness.
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # tooling/tests
TOOL="$(dirname "$HERE")"                                      # tooling/
export PW_HOME="$(cd "$TOOL/.." && pwd)"
export TOOL PWTEST_TOOLING_DIR="$TOOL" PWTEST_TEMPLATE_DIR="$(cd "$TOOL/.." && pwd)/template"
export PWTEST_F2=""                                            # f3 needs f2's dir afterwards

TIERS=""; ONLY=""; CAPTURE=""; MUTATION=""; CORPUS="${PW_CORPUS_DIR:-}"
PWTEST_VERBOSE=0; export PWTEST_VERBOSE
while [ $# -gt 0 ]; do
  case "$1" in
    --tier)  TIERS="$2"; shift 2 ;;
    --only)  ONLY="$2"; shift 2 ;;
    --corpus-dir) CORPUS="$2"; shift 2 ;;
    --capture)   CAPTURE="$2"; shift 2 ;;
    --mutation)  MUTATION="${2:-all}"; [ $# -gt 1 ] && shift; shift ;;
    -v|--verbose) PWTEST_VERBOSE=1; shift ;;
    -h|--help) grep '^#   ' "$0" | sed 's/^#   //;s/^# //'; exit 0 ;;
    *) echo "pw_test: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$TIERS" ] && TIERS="T0,T1,T2,T4"   # T3 only with --corpus-dir (or -corpus in list)
[ -n "$CORPUS" ] && case ",$TIERS," in *T3*) : ;; *) TIERS="$TIERS,T3" ;; esac

export PWTEST_TESTSDIR="$HERE"
. "$HERE/pw_test_lib.sh"
. "$HERE/static.sh"
. "$HERE/battery.sh"
. "$HERE/corpus.sh"
. "$HERE/mutate.sh"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pwtest.XXXXXX")"
trap '_pwtest_cleanup' EXIT
pwtest_env_init "$ROOT"

# per-section wall-clock timing (plan 19 Phase 0): TIME <section> <n>s on stderr.
# date +%s, not SECONDS: a case file sourced into this shell can clobber SECONDS and
# silently skew every later tier total (T1 per-case attribution made this visible).
_PWTIME_LAST="$(date +%s)"
_pwtest_mark() { local _n; _n="$(date +%s)"; printf 'TIME %s %ss\n' "$1" $((_n - ${_PWTIME_LAST:-0})); _PWTIME_LAST=$_n; } >&2

export TOOL
S1=pwt-f1-scaffold; S2=pwt-f2-mid; S3=pwt-f3-hostile; export S1 S2 S3
IFS=',' read -r -a _tlist <<< "$TIERS"

# T1 case selection is resolved ONCE, before fixtures or cases run. The same list
# drives the fixture scan, execution and the evidence line, so a filter cannot
# select one set for scanning and another for execution.
_t1_list=""
_t1_count=0
_t1_active=0
case ",$TIERS," in *T1*) _t1_active=1 ;; esac
if [ -n "$ONLY" ]; then
  printf '' | grep -q -- "$ONLY" 2>/dev/null
  _only_rc=$?
  if [ "$_only_rc" -gt 1 ]; then
    echo "pw_test: invalid --only pattern: $ONLY" >&2
    exit 2
  fi
fi
if [ "$_t1_active" = 1 ]; then
  for _t1_cf in "$HERE"/cases/*.t.sh; do
    [ -f "$_t1_cf" ] || continue
    if [ -n "$ONLY" ]; then
      printf '%s' "$(basename "$_t1_cf")" | grep -q -- "$ONLY" || continue
    fi
    _t1_list="${_t1_list}${_t1_cf}"$'\n'
    _t1_count=$((_t1_count+1))
  done
  if [ -n "$ONLY" ] && [ "$_t1_count" -eq 0 ]; then
    echo "pw_test: --only '$ONLY' matched no T1 case files → fix: check the case-name pattern or drop --only" >&2
    exit 2
  fi
  _t1_names=""
  while IFS= read -r _t1_cf; do
    [ -n "$_t1_cf" ] || continue
    _t1_names="$_t1_names $(basename "$_t1_cf" .t.sh)"
  done <<< "$_t1_list"
  echo "TEST T1 selected: $_t1_count case(s):$_t1_names" >&2
elif [ -n "$ONLY" ]; then
  echo "TEST note: --only '$ONLY' does not apply: T1 is not selected" >&2
fi

if [ -n "$CAPTURE" ]; then
  NEED_F1=1; NEED_F2=1; NEED_F3=1     # battery captures against all fixtures
  _pwtest_materialize
  mkdir -p "$HERE/expectations"; touch "$HERE/expectations/battery.tsv" "$HERE/expectations/gates.tsv" "$HERE/expectations/unwired.ok" "$HERE/expectations/mutations.tsv"
  CAPTURE="$CAPTURE" pwtest_capture "$CAPTURE" || exit 1; exit 0
fi
if [ -n "$MUTATION" ]; then
  # the parent spawns children that materialize their own fixtures — it needs none (plan 19 F1)
  PWTEST_INNER=1; export PWTEST_INNER
  pwtest_run_mutations "$MUTATION" "$HERE/pw_test.sh"; exit $?
fi

# fixtures: build only what the selected tiers/case files consume (plan 19 F1).
# PWTEST_FORCE_FIXTURES=1 builds all three regardless (cache warm); PWTEST_WARM=1 exits
# right after materialization (used by the mutation parent to seed the shared cache).
[ "${PWTEST_FORCE_FIXTURES:-}" = 1 ] && { NEED_F1=1; NEED_F2=1; NEED_F3=1; }
for _pwt_t in "${_tlist[@]:-}"; do
  case "$_pwt_t" in
    T0|T4) _pwtest_scan "$HERE/static.sh" ;;
    T1) while IFS= read -r _pwt_cf; do
          [ -n "$_pwt_cf" ] || continue
          _pwtest_scan "$_pwt_cf"
        done <<< "$_t1_list" ;;
    T2) _pwtest_scan "$HERE/battery.sh" ;;
    T3) _pwtest_scan "$HERE/corpus.sh" ;;
  esac
done
_pwtest_materialize
_pwtest_mark fixtures
[ "${PWTEST_WARM:-}" = 1 ] && { pwtest_summary; exit $?; }

for _pwt_t in "${_tlist[@]:-}"; do
  # note: case files are sourced and may clobber short vars (t/cf) — the runner uses _pwt_* only
  case "$_pwt_t" in
    T0) static_t0 ;;
    T1) # per-script case files — each case gets its own TIME line (date-based: sourced
        # case files may clobber SECONDS, so tier totals must not depend on it).
        if [ "$_t1_count" -eq 0 ]; then
          echo "TEST note: no T1 case files selected" >&2
        else
          while IFS= read -r _pwt_cf; do
            [ -n "$_pwt_cf" ] || continue
            echo "TEST case $(basename "$_pwt_cf" .t.sh)"
            _pwt_c0="$(date +%s)"
            . "$_pwt_cf"
            _pwt_c1="$(date +%s)"
            printf 'TIME case %s %ss\n' "$(basename "$_pwt_cf" .t.sh)" $(( _pwt_c1 - _pwt_c0 )) >&2
            _pwtest_record_case_duration "$(basename "$_pwt_cf" .t.sh)" "$(( _pwt_c1 - _pwt_c0 ))"
          done <<< "$_t1_list"
        fi ;;
    T2) battery_t2 ;;
    T3) corpus_t3 "$CORPUS" ;;
    T4) static_t4 ;;
    *) echo "pw_test: unknown tier '$_pwt_t'" >&2; exit 2 ;;
  esac
  _pwtest_mark "$_pwt_t"
done
pwtest_summary
