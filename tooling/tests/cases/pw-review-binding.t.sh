# shellcheck shell=bash
. "$TOOL/scripts/lib/pw-reviewlib.sh"
# Each auto policy owns exactly its documented artifact family.
for B_PHASE in analysis plan task-plan task-exec ship; do
  for B_LANE in analysis plan task rfc other; do
    B_EXPECT=1
    case "$B_PHASE:$B_LANE" in
      analysis:analysis|plan:plan|task-plan:task|task-exec:task|ship:task) B_EXPECT=0 ;;
    esac
    B_RC=0; pw_review_phase_lane_ok "$B_PHASE" "$B_LANE" || B_RC=$?
    pwtest_eq "approval policy family $B_PHASE/$B_LANE" "$B_RC" "$B_EXPECT"
  done
done
B_PROJECT=review-binding
rm -rf "$PW_PROJECTS_DIR/$B_PROJECT"; cp -a "$F2" "$PW_PROJECTS_DIR/$B_PROJECT"
B_CFG="$(pwtest_script pw-config.sh)"; B_REVIEW="$(pwtest_script pw-review.sh)"
pwtest_rc 0 "task-plan auto policy configured independently" "$B_CFG" ai-review "$B_PROJECT" task-plan auto
pwtest_rc 0 "PLAN policy stays advisory" "$B_CFG" ai-review "$B_PROJECT" plan advisory
pwtest_rc 2 "task-plan auto cannot approve PLAN under its different policy" "$B_REVIEW" auto-signoff "$B_PROJECT" task/review/PLAN.review.md task-plan --confirm-earlier
pwtest_rc 0 "fixture enters normal task-result review" "$(pwtest_script pw-status.sh)" status "$B_PROJECT" review
pwtest_rc 0 "task-result feedback is recorded during review" "$B_REVIEW" add-item "$B_PROJECT" task/review/T04.review.md --section '§4' --text 'Recheck this task result.'
pwtest_rc 0 "current task result needs no earlier-gate confirmation" "$B_REVIEW" start "$B_PROJECT" task/review/T04.review.md
rm -rf "$PW_PROJECTS_DIR/$B_PROJECT"

# A callback runs inside a conditional transaction, where errexit cannot protect it.
# Import only the trusted callback and inject a header-splice failure.
. "$TOOL/scripts/lib/pw-mdlib.sh"
. <(awk '/^_start_body\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$TOOL/scripts/entities/pw-review.sh")
B_CALLBACK="$ROOT/start-callback.review.md"
printf '# Review\nGate: see Sign-off\n## Items\n### R1 · §1 — [OPEN] (you, 2026-10-05 12:00) <!-- pw-item-status: open -->\nA real actionable request.\n---\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-10-05 11:00 | you | approved |\n' > "$B_CALLBACK"
B_BEFORE="$(cksum < "$B_CALLBACK")"
ST_BY='pw-review (repair)'; ST_REL='callback.review.md'; _START_REPORT="$ROOT/start-report"
pw_review_gate_refresh() { return 1; }
B_RC=0; pw_review_staged "$B_CALLBACK" _start_body || B_RC=$?
pwtest_eq "start callback propagates header failure" "$B_RC" 1
pwtest_eq "failed start callback publishes no transition" "$(cksum < "$B_CALLBACK")" "$B_BEFORE"
unset -f _start_body pw_review_gate_refresh
. "$TOOL/scripts/lib/pw-reviewlib.sh"
