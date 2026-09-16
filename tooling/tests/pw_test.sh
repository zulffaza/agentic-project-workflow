#!/usr/bin/env bash
# ============================================================================
# pw_test.sh — the tooling change-testing harness (plan 16).
#
#   tooling/tests/pw_test.sh                        default tiers T0,T1,T2,T4 (T3 needs --corpus-dir)
#   tooling/tests/pw_test.sh --tier T0,T1           select tiers (comma list)
#   tooling/tests/pw_test.sh --only doc-lint        filter T1 case files by name
#   tooling/tests/pw_test.sh --corpus-dir DIR       run T3 read-only over real projects
#   tooling/tests/pw_test.sh --capture T2|gates|both    record current behavior as expectations (REVIEW the diff!)
#   tooling/tests/pw_test.sh --mutation [filter]    meta-test: revert documented fixes, expect failures
#   tooling/tests/pw_test.sh -v                     per-check lines
#
# Exit 0 = everything selected passed. Cumulative reporting (all failures listed).
# Fixtures are GENERATED from template/ each run; only the CORPUS (T3) is read-only.
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

# fixtures (once; T1/T2/T3-independent):
echo "TEST materializing fixtures from template/ …"
F1="$(pwtest_build_f1 pwt-f1-scaffold)" || { echo "pwtest: F1 build failed" >&2; exit 2; }
F2="$(pwtest_build_f2 pwt-f2-mid)" || { echo "pwtest: F2 build failed" >&2; exit 2; }
export PWTEST_F2="$F2"
F3="$(pwtest_build_f3 pwt-f3-hostile)" || { echo "pwtest: F3 build failed" >&2; exit 2; }
export TOOL
S1=pwt-f1-scaffold; S2=pwt-f2-mid; S3=pwt-f3-hostile; export S1 S2 S3 F1 F2 F3

if [ -n "$CAPTURE" ]; then
  mkdir -p "$HERE/expectations"; touch "$HERE/expectations/battery.tsv" "$HERE/expectations/gates.tsv" "$HERE/expectations/unwired.ok" "$HERE/expectations/mutations.tsv"
  CAPTURE="$CAPTURE" pwtest_capture "$CAPTURE" || exit 1; exit 0
fi
if [ -n "$MUTATION" ]; then
  PWTEST_INNER=1; export PWTEST_INNER
  pwtest_run_mutations "$MUTATION" "$HERE/pw_test.sh"; exit $?
fi

IFS=',' read -r -a _tlist <<< "$TIERS"
for t in "${_tlist[@]:-}"; do
  case "$t" in
    T0) static_t0 ;;
    T1) # per-script case files
        for cf in "$HERE"/cases/*.t.sh; do
          [ "$ONLY" ] && { printf '%s' "$(basename "$cf")" | grep -q -- "$ONLY" || continue; }
          echo "TEST case $(basename "$cf" .t.sh)"
          . "$cf"
        done ;;
    T2) battery_t2 ;;
    T3) corpus_t3 "$CORPUS" ;;
    T4) static_t4 ;;
    *) echo "pw_test: unknown tier '$t'" >&2; exit 2 ;;
  esac
done
pwtest_summary
