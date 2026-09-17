# shellcheck shell=bash
# cases/pw-pipeline-monitor.t.sh
pwtest_rc 0 "monitor SUCCESS exits 0" env PWTEST_PIPELINE='[{"status":"success"}]' "$(pwtest_script pw-pipeline-monitor.sh)" "$S2" T02 --interval 1 --timeout 1
pwtest_re 'SUCCESS|green|passed|no failing' "success vocab"
pwtest_rc any "monitor reports FAILED state → non-zero" env PWTEST_PIPELINE='[{"status":"failed"}]' "$(pwtest_script pw-pipeline-monitor.sh)" "$S2" T03 --interval 1 --timeout 1
[ "$PWTEST_RC" != 0 ] && pwtest_ok "failed pipeline non-zero (rc $PWTEST_RC)" || pwtest_bad "failed pipeline" "exit 0 — would pass a red CI (defect)"
pwtest_rc any "unknown pipeline fast-fails" env PWTEST_PIPELINE='' "$(pwtest_script pw-pipeline-monitor.sh)" "$S2" T02 --interval 0 --timeout 1
[ "$PWTEST_RC" -ge 2 ] && pwtest_ok "unknown → fast-fail rc=$PWTEST_RC" || pwtest_bad "fast-fail" "rc=$PWTEST_RC still 'running'?"
pwtest_fix "fast-fail says why"
pwtest_rc 2 "monitor unknown project" "$(pwtest_script pw-pipeline-monitor.sh)" nope-xyz T01
