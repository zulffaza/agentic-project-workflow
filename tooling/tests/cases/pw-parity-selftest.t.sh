# shellcheck shell=bash
# cases/pw-parity-selftest.t.sh — per-script selftest entry + spine invocations.
for s in $PWTEST_AUTOMATION; do
  grep -q -- '--selftest' "$(pwtest_script "$s")" \
    && pwtest_ok "$s exposes --selftest" || pwtest_bad "$s exposes --selftest" "no entry"
done
