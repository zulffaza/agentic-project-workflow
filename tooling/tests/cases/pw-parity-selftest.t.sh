# shellcheck shell=bash
# cases/pw-lib-wiring.t.sh — per-script selftest entry + spine invocations.
for s in $PWTEST_AUTOMATION; do
  grep -q -- '--selftest' "$TOOL/$s" \
    && pwtest_ok "$s exposes --selftest" || pwtest_bad "$s exposes --selftest" "no entry"
done
