#!/usr/bin/env bash
# selftest_entry.sh <script-basename> — shared `--selftest` runner (no -e; fixtures fresh).
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"           # tooling/
name="$1"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
(
  set +eu; set -o pipefail 2>/dev/null || true
  export PW_HOME="$(cd "$here/.." && pwd)"
  export TOOL="$here" PWTEST_TOOLING_DIR="$here" PWTEST_TESTSDIR="$here/tests"
  export PWTEST_TEMPLATE_DIR="$(cd "$here/.." && pwd)/template" PWTEST_VERBOSE="${PWTEST_VERBOSE:-0}"
  # pw_test_lib needs PWTEST_TESTSDIR for the bin/ shim dir:
  . "$here/tests/pw_test_lib.sh"
  pwtest_env_init "$ROOT"
  S1=pwt-f1-scaffold S2=pwt-f2-mid S3=pwt-f3-hostile; export S1 S2 S3
  _pwtest_scan "$here/tests/cases/$name.t.sh"    # build only the fixtures this case consumes
  _pwtest_materialize
  . "$here/tests/cases/$name.t.sh"
  pwtest_summary
) ; exit $?
