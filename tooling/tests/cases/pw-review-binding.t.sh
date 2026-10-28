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
pwtest_rc 0 "task-plan auto policy configured independently" "$B_CFG" set --project "$B_PROJECT" --key ai-review --set task-plan=auto
pwtest_rc 0 "PLAN policy stays advisory" "$B_CFG" set --project "$B_PROJECT" --key ai-review --set plan=advisory
pwtest_rc 2 "task-plan auto cannot approve PLAN under its different policy" "$B_REVIEW" auto-signoff --project "$B_PROJECT" --file task/review/PLAN.review.md --phase task-plan --confirm-earlier
pwtest_rc 0 "fixture enters normal task-result review" "$(pwtest_script pw-status.sh)" status --project "$B_PROJECT" --phase review
pwtest_rc 0 "task-result feedback is recorded during review" "$B_REVIEW" add-item --project "$B_PROJECT" --file task/review/T04.review.md --section '§4' --text 'Recheck this task result.'
pwtest_rc 0 "current task result needs no earlier-gate confirmation" "$B_REVIEW" start --project "$B_PROJECT" --file task/review/T04.review.md --receipt rr1
rm -rf "$PW_PROJECTS_DIR/$B_PROJECT"

# A callback runs inside a conditional transaction, where errexit cannot protect it.
# Import only the trusted callback and inject a header-splice failure.
. "$TOOL/scripts/lib/pw-mdlib.sh"
# Source from a real file: `. <(awk …)` is racy on bash 3.2 (the source builtin can read
# EOF before the external awk writes), which silently defined nothing and made the two
# assertions below pass on "command not found" instead of the transaction under test.
B_BODY="$ROOT/start-body.sh"
awk '/^_start_body\(\) \{/{p=1} p{print} p&&/^}/{exit}' "$TOOL/scripts/entities/pw-review.sh" > "$B_BODY"
. "$B_BODY"
declare -F _start_body >/dev/null && pwtest_ok "start callback extracted" || pwtest_bad "start callback extracted" "awk produced no _start_body definition (retry the extraction)"
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

# Plan 46: an explicit human rejection survives a fresh pass-correlated operational entry —
# the entry may record that a pass began, but a clean pass can still not override the human.
B2=bind-reject46; rm -rf "$PW_PROJECTS_DIR/$B2"; cp -a "$F2" "$PW_PROJECTS_DIR/$B2"
B2RV=analysis/review/fixture.review.md; B2F="$PW_PROJECTS_DIR/$B2/$B2RV"
pwtest_rc 0 "rejection: rewind the dashboard to analysis" "$(pwtest_script pw-status.sh)" status --project "$B2" --phase analysis --rewind
pwtest_rc 0 "rejection: auto mode configured" "$B_CFG" set --project "$B2" --key ai-review --set analysis=auto
pwtest_rc 0 "rejection: human records changes-requested" "$B_REVIEW" signoff --project "$B2" --file "$B2RV" --decision changes-requested --by reviewer-owner
pwtest_rc 0 "rejection: a fresh operational entry is still allowed" "$B_REVIEW" start --project "$B2" --file "$B2RV" --phase analysis --pass p-bind-rej1 --provider kilo --model m
pwtest_grep_file '\| pw-reviewer \(auto; provider=kilo; model=m; pass=p-bind-rej1\) \| in-review \|' "rejection: entry row recorded" "$B2F"
pwtest_grep_file '\| reviewer-owner \| changes-requested \|' "rejection: human row preserved" "$B2F"
pwtest_rc 2 "rejection: clean pass cannot auto-approve over it" "$B_REVIEW" auto-signoff --project "$B2" --file "$B2RV" --phase analysis --pass p-bind-rej1 --provider kilo --model m
pwtest_err 'human changes-requested is still active' "rejection: refusal names the human rejection"
rm -rf "$PW_PROJECTS_DIR/$B2"
