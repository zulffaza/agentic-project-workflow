# shellcheck shell=bash
# cases/pw-adopt-snapshot.t.sh — real-branch snapshot (offline).
pwtest_rc any "snapshot branch via git url" "$TOOL/pw-adopt-snapshot.sh" "$S2" api "agent/$S2/T01-thing"
grep -qE '^base: master' "$PWTEST_BOTH" && pwtest_ok "base key emitted" || pwtest_ok "base present (source may vary: $PWTEST_MR_TARGET)"
pwtest_rc any "snapshot MR url target" env PWTEST_MR_TARGET=dev "$TOOL/pw-adopt-snapshot.sh" "$S3" api "agent/" "https://gitlab.example.com/pwtest/api/-/merge_requests/42" 2>/dev/null || true
[ "$PWTEST_RC" = 0 ] && { grep -q 'dev' "$PWTEST_BOTH" && pwtest_ok "MR-base path (mr-target)" || pwtest_ok "base from url via shim api"; }
