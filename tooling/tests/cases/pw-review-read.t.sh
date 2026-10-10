# shellcheck shell=bash
# Direct read facet and legacy aliases must consume identical review state.
READ_FACET="$(pwtest_script pw-review-read.sh)"
READ_ALIAS="$(pwtest_script pw-review.sh)"
READ_PLAN=task/review/PLAN.review.md
pwtest_rc 0 "read facet advertises its operators" "$READ_FACET" --help
pwtest_re 'gate|has-open|eligible|scan' "read facet usage is available"
pwtest_rc 0 "read facet accepts the clean fixture approval" "$READ_FACET" gate "$S2" "$READ_PLAN"
pwtest_re '^approved' "read facet preserves decision token"
pwtest_rc 0 "read facet counts real items" "$READ_FACET" count "$S2" "$READ_PLAN"
pwtest_re 'open=0' "template and examples do not count as open"
pwtest_eq "legacy count forwards with identical output" \
  "$("$READ_ALIAS" count "$S2" "$READ_PLAN")" "$("$READ_FACET" count "$S2" "$READ_PLAN")"
pwtest_rc 1 "read facet false open predicate is not an error" "$READ_FACET" has-open "$S2" "$READ_PLAN"
pwtest_re '^no$' "false open predicate prints no"
pwtest_rc 1 "read facet has no eligible stub work" "$READ_FACET" eligible "$S2" "$READ_PLAN"
pwtest_re 'eligible=0' "eligible predicate ignores stubs"
pwtest_rc 0 "read facet task-plan scope selects task files" "$READ_FACET" scan "$S2" --phase task-plan
pwtest_re 'task/review/T04.review.md' "task-plan scope includes its actual artifact"
if grep -qE 'PLAN.review.md|analysis/review/' "$PWTEST_OUT"; then
  pwtest_bad "task-plan scope excludes other lanes" "scan leaked another artifact family"
else
  pwtest_ok "task-plan scope excludes other lanes"
fi
pwtest_rc 0 "read facet ship scope selects mirrored task files" "$READ_FACET" scan "$S2" --phase ship
pwtest_re 'task/review/T04.review.md' "ship scope includes mirrored task review"
pwtest_rc 2 "read facet rejects unknown lane" "$READ_FACET" scan "$S2" --phase unknown-phase
pwtest_fix "invalid read lane offers supported choices"
pwtest_rc 2 "read facet rejects project traversal" "$READ_FACET" count ../ "$READ_PLAN"
pwtest_rc 2 "read facet rejects review traversal" "$READ_FACET" count "$S2" ../README.md
pwtest_rc 1 "missing read file preserves false predicate contract" "$READ_FACET" has-open "$S2" task/review/missing.review.md
pwtest_re '^no$' "missing file prints no"
READ_CONFLICT=review-read-conflict
rm -rf "$PW_PROJECTS_DIR/$READ_CONFLICT"; cp -a "$F2" "$PW_PROJECTS_DIR/$READ_CONFLICT"
READ_CONFLICT_PATH="$PW_PROJECTS_DIR/$READ_CONFLICT/task/review/PLAN.review.md"
printf '\n#### R90 · §2 — [RESOLVED] (you, 2026-10-05 01:00) <!-- pw-item-status: resolved --> <!-- pw-item-status: open -->\nUnresolved conflicting metadata.\n---\n' >> "$READ_CONFLICT_PATH"
pwtest_rc 1 "conflicting machine markers block gate approval" "$READ_FACET" gate "$READ_CONFLICT" "$READ_PLAN"
pwtest_rc 0 "count shares the fail-closed status classifier" "$READ_FACET" count "$READ_CONFLICT" "$READ_PLAN"
pwtest_re 'open=1 resolved=0' "conflict is reported as an open blocker, not resolved"
pwtest_rc 1 "malformed conflict supplies no automatic repair authority" "$READ_FACET" eligible "$READ_CONFLICT" "$READ_PLAN"
pwtest_re 'eligible=0' "a malformed deeper heading does not start repair"
rm -rf "$PW_PROJECTS_DIR/$READ_CONFLICT"

# shared five-lane discovery (pw-reviewlib.sh): the context lane is scanned like any other
mkdir -p "$PW_PROJECTS_DIR/$S2/context/review"
printf '# readiness\n\n### R1 · §Scope — [OPEN] (pwtest, 2026-10-05 10:00) <!-- pw-item-status: open -->\n' > "$PW_PROJECTS_DIR/$S2/context/review/CONTEXT.review.md"
pwtest_rc 0 "scan covers the context lane" "$READ_FACET" scan "$S2" --phase context
pwtest_re 'context/review/CONTEXT\.review\.md: 1 open' "context review listed with its open count"
rm -rf "$PW_PROJECTS_DIR/$S2/context/review"
