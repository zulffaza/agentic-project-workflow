# shellcheck shell=bash
# Cross-script review journey on a private fixture copy, never a live project.
. "$TOOL/scripts/lib/pw-mdlib.sh"
FLOW=reviewflow
FLOW_DIR="$PW_PROJECTS_DIR/$FLOW"
rm -rf "$FLOW_DIR"
cp -a "$F2" "$FLOW_DIR"
FLOW_REVIEW="$(pwtest_script pw-review.sh)"
FLOW_STATUS="$(pwtest_script pw-status.sh)"
FLOW_PREFLIGHT="$(pwtest_script pw-preflight.sh)"
FLOW_CFG="$(pwtest_script pw-config.sh)"
FLOW_PLAN=task/review/PLAN.review.md

# Explicit initialization must not silently populate another artifact or phase.
rm -f "$FLOW_DIR/task/review/T01.review.md" "$FLOW_DIR/task/review/T02.review.md" "$FLOW_DIR/task/review/T03.review.md"
pwtest_rc 0 "selected init creates only T01 and T03" "$FLOW_REVIEW" init-docs "$FLOW" task/T01.md task/T03.md
[ -f "$FLOW_DIR/task/review/T01.review.md" ] && [ -f "$FLOW_DIR/task/review/T03.review.md" ] \
  && [ ! -f "$FLOW_DIR/task/review/T02.review.md" ] \
  && pwtest_ok "explicit list has no unselected sibling" \
  || pwtest_bad "explicit list isolation" "selected/unselected review set differs"

pwtest_rc 0 "fixture explicitly rewinds to analysis" "$FLOW_STATUS" status "$FLOW" analysis --rewind
rm -f "$FLOW_DIR/task/review/T02.review.md"
pwtest_rc 0 "analysis init-all stays in its phase" "$FLOW_REVIEW" init-all "$FLOW"
[ ! -f "$FLOW_DIR/task/review/T02.review.md" ] \
  && pwtest_ok "analysis init-all leaves future task reviews absent" \
  || pwtest_bad "phase initialization isolation" "created task review during analysis"

# Earlier-phase feedback is valid content, but must block consumers even if its
# original human approval is preserved pending explicit reopen confirmation.
pwtest_rc 0 "project enters executing for earlier-phase feedback" "$FLOW_STATUS" status "$FLOW" executing
pwtest_rc 0 "earlier PLAN feedback is recorded" "$FLOW_REVIEW" add-item "$FLOW" "$FLOW_PLAN" --section '§2' --text 'Recheck the dependency order before continuing.'
pwtest_rc 1 "PLAN gate refuses approval with new open feedback" "$FLOW_REVIEW" gate "$FLOW" "$FLOW_PLAN"
pwtest_rc 0 "status surfaces the stale PLAN approval blocker" "$FLOW_STATUS" "$FLOW" --skip-cli-check
pwtest_re 'Unapproved PLAN review' "status consumes the same approval predicate as the gate"
pwtest_re 'blocked by unresolved work' "status distinguishes recorded approval from usable approval"
pwtest_rc 1 "execution preflight refuses stale PLAN approval" "$FLOW_PREFLIGHT" execute "$FLOW"
pwtest_fix "execution stale approval refusal has recovery guidance"
pwtest_rc 2 "repair of consumed PLAN needs confirmation" "$FLOW_REVIEW" start "$FLOW" "$FLOW_PLAN"
pwtest_rc 0 "explicit confirmation starts PLAN repair" "$FLOW_REVIEW" start "$FLOW" "$FLOW_PLAN" --confirm-earlier
pwtest_eq "started repair uses operational decision" "$(_signoff_latest_decision "$FLOW_DIR/$FLOW_PLAN")" changes-requested
pwtest_eq "started repair has agent attribution" "$(_signoff_latest_actor "$FLOW_DIR/$FLOW_PLAN")" 'pw-review (repair)'
pwtest_rc 0 "resolve the real PLAN request" "$FLOW_REVIEW" resolve "$FLOW" "$FLOW_PLAN" R1 --reply 'Dependency order checked and corrected in the plan.'
pwtest_rc 1 "resolved repair still awaits approval" "$FLOW_REVIEW" gate "$FLOW" "$FLOW_PLAN"
pwtest_rc 0 "human explicitly reapproves PLAN" "$FLOW_REVIEW" signoff "$FLOW" "$FLOW_PLAN" approved --by reviewer-owner
pwtest_rc 0 "clean latest human approval unblocks PLAN" "$FLOW_REVIEW" gate "$FLOW" "$FLOW_PLAN"
pwtest_rc 0 "execution preflight accepts the repaired and approved PLAN" "$FLOW_PREFLIGHT" execute "$FLOW"

# A clean AI pass does not fabricate a changes-requested event, but can use the
# existing guarded auto approval path and must name the actual reviewer.
FLOW_TASK=task/review/T01.review.md
pwtest_rc 0 "configure task-exec auto policy" "$FLOW_CFG" ai-review "$FLOW" task-exec auto
FLOW_BEFORE="$(_comment_blanked "$FLOW_DIR/$FLOW_TASK" | sed -n '/^## Sign-off/,$p')"
pwtest_rc 0 "empty independent pass has no pass-entry transition" "$FLOW_REVIEW" start "$FLOW" "$FLOW_TASK" --phase task-exec --provider kilo --model openai/actual-review-model
pwtest_eq "empty pass leaves signoff history unchanged" "$(_comment_blanked "$FLOW_DIR/$FLOW_TASK" | sed -n '/^## Sign-off/,$p')" "$FLOW_BEFORE"
pwtest_rc 0 "clean auto pass records actual identity" "$FLOW_REVIEW" auto-signoff "$FLOW" "$FLOW_TASK" task-exec --provider kilo --model openai/actual-review-model
pwtest_eq "AI approval retains exact model identity" "$(_signoff_latest_actor "$FLOW_DIR/$FLOW_TASK")" 'pw-reviewer (auto; provider=kilo; model=openai/actual-review-model)'
pwtest_rc 0 "scan displays decision and actual AI reviewer" "$FLOW_REVIEW" scan "$FLOW" --phase task-exec
pwtest_re 'provider=kilo; model=openai/actual-review-model' "scan exposes actual AI reviewer identity"

# Human rejection is not cleared by a clean AI pass or its operational metadata.
pwtest_rc 0 "human rejection is recorded distinctly" "$FLOW_REVIEW" signoff "$FLOW" "$FLOW_TASK" changes-requested --by reviewer-owner
pwtest_rc 0 "feedback queues work without withdrawing human rejection" "$FLOW_REVIEW" add-item "$FLOW" "$FLOW_TASK" --section '§4' --text 'Check that the implementation still meets the rejected acceptance condition.'
pwtest_rc 0 "AI pass records its operational row after the rejection" "$FLOW_REVIEW" start "$FLOW" "$FLOW_TASK" --phase task-exec --provider kilo --model openai/fallback-review-model
pwtest_rc 0 "resolve work while retaining human rejection history" "$FLOW_REVIEW" resolve "$FLOW" "$FLOW_TASK" R1 --reply 'Acceptance condition checked; human rejection remains a separate decision.'
pwtest_rc 2 "clean auto cannot override explicit human rejection" "$FLOW_REVIEW" auto-signoff "$FLOW" "$FLOW_TASK" task-exec --provider kilo --model openai/fallback-review-model
pwtest_rc 0 "human explicitly withdraws rejection" "$FLOW_REVIEW" signoff "$FLOW" "$FLOW_TASK" in-review --by reviewer-owner
pwtest_rc 0 "clean auto can proceed after explicit withdrawal" "$FLOW_REVIEW" auto-signoff "$FLOW" "$FLOW_TASK" task-exec --provider kilo --model openai/fallback-review-model
pwtest_eq "new approval credits fallback reviewer" "$(_signoff_latest_actor "$FLOW_DIR/$FLOW_TASK")" 'pw-reviewer (auto; provider=kilo; model=openai/fallback-review-model)'

# An RFC comment staging file is not another analysis approval gate.
pwtest_rc 0 "fixture explicitly rewinds for RFC scope check" "$FLOW_STATUS" status "$FLOW" analysis --rewind
mkdir -p "$FLOW_DIR/analysis/review"
printf '# RFC comment staging\n\n## Items\n\n' > "$FLOW_DIR/analysis/review/RFC.review.md"
pwtest_rc 0 "breakdown ignores clean RFC staging as an approval gate" "$FLOW_PREFLIGHT" breakdown "$FLOW"
printf '### R1 · §1 — [OPEN] (reviewer, 2026-10-05 00:00) <!-- pw-item-status: open -->\nAddress this pulled comment.\n---\n' >> "$FLOW_DIR/analysis/review/RFC.review.md"
pwtest_rc 1 "breakdown still blocks unresolved RFC comments" "$FLOW_PREFLIGHT" breakdown "$FLOW"
pwtest_fix "unresolved RFC comment refusal has recovery guidance"

# The public command must advertise selected paths rather than the legacy two-path API.
pwtest_rc 0 "public init help renders selected document interface" "$(pwtest_script pw-help.sh)" command pw-review "$FLOW"
pwtest_re '/pw-review .* init ' "public selected init is discoverable"
pwtest_re 'artifact-path|document-path|doc-path' "public init help names document paths"

rm -rf "$FLOW_DIR"
