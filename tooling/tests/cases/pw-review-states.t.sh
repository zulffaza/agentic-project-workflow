# shellcheck shell=bash
# cases/pw-review-states.t.sh — plan 31 core contract: selected-list initialization
# (init-docs), current-phase init-all, pass entry (start) with the eligible-work matrix,
# feedback-cycle transitions, auto-signoff guards (binding/identity/human-rejection/
# consumed-phase confirmation), gate fail-closed, path/injection guards, WIB timestamps
# with legacy readers. All on PRIVATE clones of F2 — the shared fixtures are never mutated.
. "$TOOL/scripts/lib/pw-mdlib.sh"
E="$(pwtest_script pw-review.sh)"
ST="$(pwtest_script pw-status.sh)"
CFG="$(pwtest_script pw-config.sh)"
PLAN="task/review/PLAN.review.md"

# rowfix <literal> <label> <file> — fixed-string membership. The template's visible prose
# names the same actors as sign-off rows, so row assertions must match the FULL row text
# literally, never via regex fragments that could also hit prose.
rowfix() { _comment_blanked "$3" | grep -qF -- "$1" && pwtest_ok "$2" || pwtest_bad "$2" "no [$1] in $3"; }
# rowcount <literal> <file> — occurrences of a full literal row substring (| ... | cells).
rowcount() { local n; n="$(_comment_blanked "$2" | grep -cF -- "$1" || true)"; echo "${n:-0}"; }

# ============================================================ A) init-docs selection
AD=st-authdocs; rm -rf "$PW_PROJECTS_DIR/$AD"; cp -a "$F2" "$PW_PROJECTS_DIR/$AD"
A="$PW_PROJECTS_DIR/$AD"
cp "$A/analysis/fixture.md" "$A/analysis/extra.md"
pwtest_rc 0 "init-docs single" "$E" init-docs "$AD" task/T01.md
[ -f "$A/task/review/T01.review.md" ] && pwtest_ok "single list entry created its review" || pwtest_bad "init-docs single" "T01 review missing"
rm -f "$A/task/review/T02.review.md" "$A/task/review/T03.review.md"
pwtest_rc 0 "init-docs multiple with duplicate" "$E" init-docs "$AD" task/T02.md task/T03.md task/T02.md
[ -f "$A/task/review/T02.review.md" ] && [ -f "$A/task/review/T03.review.md" ] \
  && pwtest_ok "all selected reviews created" || pwtest_bad "init-docs multiple" "missing created files"
n_created="$(grep -c '^created ' "$PWTEST_OUT" || true)"
[ "${n_created:-0}" = 2 ] && pwtest_ok "duplicate path created exactly one file" || pwtest_bad "dedupe" "created=$n_created want 2"
printf '\nhistory kept\n' >> "$A/task/review/T02.review.md"
pwtest_rc 0 "init-docs rerun idempotent" "$E" init-docs "$AD" task/T02.md
grep -q 'history kept' "$A/task/review/T02.review.md" && pwtest_ok "rerun preserved existing review" || pwtest_bad "init-docs clobber" "content lost"
pwtest_rc 2 "init-docs rejects list with missing document" "$E" init-docs "$AD" analysis/extra.md analysis/ghost.md
[ ! -f "$A/analysis/review/extra.review.md" ] \
  && pwtest_ok "valid entry NOT created when the list is invalid" || pwtest_bad "partial validation" "wrote despite invalid list"
pwtest_fix "invalid-list refusal actionable"
pwtest_rc 2 "init-docs rejects README" "$E" init-docs "$AD" README.md
pwtest_rc 2 "init-docs rejects template" "$E" init-docs "$AD" analysis/_TEMPLATE.md
pwtest_rc 2 "init-docs rejects RFC staging" "$E" init-docs "$AD" analysis/RFC.md
pwtest_rc 2 "init-docs rejects review path as artifact" "$E" init-docs "$AD" "$PLAN"
pwtest_rc 2 "init-docs rejects directory target" "$E" init-docs "$AD" analysis
pwtest_rc 2 "init-docs rejects dotdot escape" "$E" init-docs "$AD" ../../etc/hosts
ln -s /etc/passwd "$A/analysis/evil.md"
pwtest_rc 2 "init-docs rejects out-of-project symlink" "$E" init-docs "$AD" analysis/evil.md
ln -s fixture.md "$A/analysis/alias.md"
pwtest_rc 2 "init-docs refuses in-project symlinked doc" "$E" init-docs "$AD" analysis/alias.md
rm -f "$A/analysis/evil.md" "$A/analysis/alias.md"
chmod 500 "$A/analysis/review"
pwtest_rc 2 "init-docs reports write failures" "$E" init-docs "$AD" analysis/extra.md
pwtest_re 'FAILED' "per-file FAILED line reported"
pwtest_re '1 failed' "failure counted in the summary"
chmod 700 "$A/analysis/review"
pwtest_rc 0 "init-docs rerun finishes after failure cleared" "$E" init-docs "$AD" analysis/extra.md
pwtest_re '1 created' "rerun created the missing file"

# ============================================================ B) init-all phase scope
set_phase() { sed -i '' "s|^- \*\*Status:\*\*.*|- **Status:** $2|" "$PW_PROJECTS_DIR/$1/README.md"; }
IA=st-initall; rm -rf "$PW_PROJECTS_DIR/$IA"; cp -a "$F2" "$PW_PROJECTS_DIR/$IA"
I="$PW_PROJECTS_DIR/$IA"
rm -rf "$I/task/review" "$I/analysis/review"
set_phase "$IA" analysis
cp "$I/analysis/fixture.md" "$I/analysis/RFC.md"
pwtest_rc 0 "init-all at analysis creates analysis topics only" "$E" init-all "$IA"
[ -f "$I/analysis/review/fixture.review.md" ] && pwtest_ok "analysis review created" || pwtest_bad "init-all analysis" "fixture review missing"
[ ! -f "$I/analysis/review/RFC.review.md" ] && pwtest_ok "RFC excluded" || pwtest_bad "init-all RFC" "RFC.review.md created"
[ ! -d "$I/task/review" ] && pwtest_ok "no later-phase reviews side-effected" || pwtest_bad "init-all leakage" "task reviews created during analysis"
rm -rf "$I/analysis/review"
set_phase "$IA" breakdown
pwtest_rc 0 "init-all at breakdown" "$E" init-all "$IA"
[ -f "$I/task/review/PLAN.review.md" ] && pwtest_ok "PLAN review created at breakdown" || pwtest_bad "init-all breakdown" "PLAN review missing"
[ ! -d "$I/analysis/review" ] && pwtest_ok "no analysis reviews at breakdown" || pwtest_bad "init-all leakage" "analysis review created during breakdown"
rm -rf "$I/task/review"
set_phase "$IA" executing
pwtest_rc 0 "init-all at executing" "$E" init-all "$IA"
[ -f "$I/task/review/T01.review.md" ] && pwtest_ok "task result reviews created at executing" || pwtest_bad "init-all executing" "T0 reviews missing"
[ ! -f "$I/task/review/PLAN.review.md" ] && pwtest_ok "PLAN not back-filled at executing" || pwtest_bad "init-all leakage" "PLAN review created at executing"
rm -rf "$I/task/review" "$I/analysis/review"
set_phase "$IA" context
pwtest_rc 0 "init-all at context is a no-op" "$E" init-all "$IA"
pwtest_re "no review files to initialize" "context explains nothing to init"
[ ! -d "$I/analysis/review" ] && pwtest_ok "context created nothing" || pwtest_bad "context leakage" "reviews created at context"
set_phase "$IA" done
pwtest_rc 0 "init-all at done is a no-op" "$E" init-all "$IA"
pwtest_re "creates nothing here" "done requires explicit selection"
[ ! -d "$I/task/review" ] && pwtest_ok "done created nothing" || pwtest_bad "done leakage" "reviews created at done"
set_phase "$IA" "executed — 11/11 done (verify ok)"
pwtest_rc 2 "init-all fails closed on unknown phase" "$E" init-all "$IA"
pwtest_fix "unknown-phase refusal carries repair hint"
[ ! -d "$I/task/review" ] && pwtest_ok "unknown phase created nothing" || pwtest_bad "fail-closed leak" "writes despite unknown phase"
set_phase "$IA" executing
pwtest_rc 0 "init-all rerun preserves prior reviews" "$E" init-all "$IA"

# ============================================================ C) start: eligible-work matrix
SM=st-start; rm -rf "$PW_PROJECTS_DIR/$SM"; cp -a "$F2" "$PW_PROJECTS_DIR/$SM"
S="$PW_PROJECTS_DIR/$SM"
set_phase "$SM" analysis
RVX=analysis/review/fixture.review.md
BEFORE="$(_comment_blanked "$S/$RVX" | sed -n '/^## Sign-off/,$p')"
pwtest_rc 0 "start on empty work set is clean" "$E" start "$SM" "$RVX"
AFTER="$(_comment_blanked "$S/$RVX" | sed -n '/^## Sign-off/,$p')"
[ "$BEFORE" = "$AFTER" ] && pwtest_ok "clean pass added no sign-off row" || pwtest_bad "clean pass transition" "sign-off history changed"
pwtest_re '__clean__' "start reports the clean verdict"
pwtest_rc 1 "eligible on empty file says no work" "$E" eligible "$SM" "$RVX"
pwtest_re 'eligible=0' "eligible counter reads stubs as zero"
pwtest_rc 0 "add-item makes work eligible" "$E" add-item "$SM" "$RVX" --section '§2 Scope' --text widen the scope row
pwtest_rc 0 "eligible now reports real work" "$E" eligible "$SM" "$RVX"
pwtest_re 'eligible=1 open=1' "open item with body is actionable"
pwtest_rc 0 "start appends pass entry" "$E" start "$SM" "$RVX"
rowfix '| pw-review (repair) | changes-requested |' "repair pass recorded changes-requested" "$S/$RVX"
pwtest_grep_file '^Gate: changes-requested \(pw-review \(repair\)\)$' "generated Gate header derived (script-free)" "$S/$RVX"
pwtest_rc 0 "start rerun same attempt idempotent" "$E" start "$SM" "$RVX"
pwtest_re '__resume__' "same-actor rerun reports a resume"
[ "$(rowcount '| pw-review (repair) | changes-requested |' "$S/$RVX")" = 1 ] \
  && pwtest_ok "same attempt did not duplicate the row" || pwtest_bad "pass-entry idempotence" "second identical row"
pwtest_rc 0 "configure analysis advisory" "$CFG" ai-review "$SM" analysis advisory
pwtest_rc 0 "advisory pass with actual identity" "$E" start "$SM" "$RVX" --phase analysis --provider kilo --model openai/actual-review-model
rowfix '| pw-reviewer (advisory; provider=kilo; model=openai/actual-review-model) | changes-requested |' "advisory pass attributed to the actual reviewer" "$S/$RVX"
pwtest_rc 0 "advisory rerun idempotent" "$E" start "$SM" "$RVX" --phase analysis --provider kilo --model openai/actual-review-model
[ "$(rowcount '| pw-reviewer (advisory; provider=kilo; model=openai/actual-review-model) | changes-requested |' "$S/$RVX")" = 1 ] \
  && pwtest_ok "same reviewer same attempt stayed idempotent" || pwtest_bad "retry attribution" "duplicated or lost"
pwtest_rc 0 "pass without identity records unknown" "$E" start "$SM" "$RVX" --phase analysis
rowfix '| pw-reviewer (advisory; provider=unknown; model=unknown) | changes-requested |' "unconfirmed identity printed as unknown" "$S/$RVX"
# legacy stored `off` reads as effective ADVISORY (migration): the value is refused on write
# with an actionable hint, and a dashboard still carrying it allows explicit pass entry (the
# normalization is what keeps a manual review from being silently dead).
pwtest_rc 2 "ai-review refuses the removed off value" "$CFG" ai-review "$SM" plan off
pwtest_fix "off refusal actionable"
sed -i '' 's/plan=advisory/plan=off/' "$S/README.md"
pwtest_rc 0 "legacy off still enables an explicit pass (normalized to advisory)" "$E" start "$SM" "$PLAN" --phase plan
pwtest_re 'pass entry' "start ran under the normalized mode"
pwtest_rc 2 "lane mismatch refuses (analysis file, ship phase)" "$E" start "$SM" "$RVX" --phase ship --provider kilo --model m
pwtest_rc 2 "lane mismatch refuses (PLAN file, task-exec phase)" "$E" start "$SM" "$PLAN" --phase task-exec
[ "$(rowcount ' changes-requested |' "$S/$RVX")" = 3 ] \
  && pwtest_ok "refusals wrote nothing (3 recorded attempts only)" || pwtest_bad "refusal purity" "CR rows=$(rowcount ' changes-requested |' "$S/$RVX")"
RMQ=st-mixedq; rm -rf "$PW_PROJECTS_DIR/$RMQ"; cp -a "$F2" "$PW_PROJECTS_DIR/$RMQ"
M="$PW_PROJECTS_DIR/$RMQ"; set_phase "$RMQ" analysis
MRV=analysis/review/fixture.review.md
printf '\n### Q7 · §3 Approach — [PENDING] (agent, 2026-09-15 09:00) <!-- pw-item-status: open -->\nwhich rollout order?\n\n> ↳ **you** (2026-09-15 10:00): canary first.\n\n---\n' >> "$M/$MRV"
pwtest_rc 0 "answered pending question is actionable" "$E" start "$RMQ" "$MRV"
pwtest_re '__entered__' "fold-in work triggered pass entry"
pwtest_rc 0 "resolve Q7" "$E" resolve "$RMQ" "$MRV" Q7 --reply 'folded: canary-first order'
printf '\n### Q8 · §3 Approach — [PENDING] (agent, 2026-09-15 11:00) <!-- pw-item-status: open -->\nstill waiting on the human\n\n---\n' >> "$M/$MRV"
pwtest_rc 0 "unanswered question is NOT a repair pass" "$E" start "$RMQ" "$MRV"
pwtest_re '__clean__' "waiting-human-only stays clean"
pwtest_re 'awaiting=1' "the blocker is reported without inventing a row"
MFM=st-malformed; rm -rf "$PW_PROJECTS_DIR/$MFM"; cp -a "$F2" "$PW_PROJECTS_DIR/$MFM"
F2P="$PW_PROJECTS_DIR/$MFM"; set_phase "$MFM" analysis
FRV=analysis/review/fixture.review.md
printf '\n### R8 · §9 — [OPEN] (you, 2026-09-15 09:00) <!-- pw-item-status: open -->\n\n---\n' >> "$F2P/$FRV"
pwtest_rc 0 "empty-body open item is unactionable" "$E" start "$MFM" "$FRV"
pwtest_re '__clean__' "malformed-only added no row"
pwtest_re 'unactionable=1' "malformed entry reported (not counted eligible)"
UK=st-unknown; rm -rf "$PW_PROJECTS_DIR/$UK"; cp -a "$F2" "$PW_PROJECTS_DIR/$UK"
U="$PW_PROJECTS_DIR/$UK"; set_phase "$UK" analysis
sed -i '' 's/^| 2026-09-15 00:00 | pwtest | approved |$/| 2026-09-15 00:00 | pwtest | rejected |/' "$U/$PLAN"
pwtest_rc 0 "seed eligible work on unknown-state file" "$E" add-item "$UK" "$PLAN" --section '§1' --text make the pass eligible
pwtest_err 'unrecognized latest decision' "unknown decision reported at feedback time, table not invented"
pwtest_rc 2 "start refuses unknown decision" "$E" start "$UK" "$PLAN"
pwtest_fix "unknown-decision refusal carries repair hint"
grep -q '| pwtest | rejected |' "$U/$PLAN" && pwtest_ok "history preserved on refusal" || pwtest_bad "unknown-decision" "row rewritten"
pwtest_rc 1 "gate fails closed on unknown decision" "$E" gate "$UK" "$PLAN"
printf '# no table here\n## Items\n' > "$U/analysis/review/notable.review.md"
pwtest_rc 2 "gate dies on table with no rows" "$E" gate "$UK" analysis/review/notable.review.md
pwtest_fix "missing-table gate refusal actionable"
EC=st-earlier; rm -rf "$PW_PROJECTS_DIR/$EC"; cp -a "$F2" "$PW_PROJECTS_DIR/$EC"
C="$PW_PROJECTS_DIR/$EC"
set_phase "$EC" executing
pwtest_rc 2 "earlier analysis repair needs confirmation" "$E" start "$EC" analysis/review/fixture.review.md
pwtest_fix "confirm-earlier hint offered"
[ "$(rowcount '| pw-review (repair) |' "$C/analysis/review/fixture.review.md")" = 0 ] \
  && pwtest_ok "no transition before confirmation" || pwtest_bad "pre-confirm refusal wrote state" "repair row existed"
pwtest_rc 2 "earlier PLAN repair without flag" "$E" start "$EC" "$PLAN"
pwtest_rc 0 "seed PLAN work under preserved approval" "$E" add-item "$EC" "$PLAN" --section '§2' --text recheck dependency order
pwtest_rc 0 "confirmed earlier repair proceeds" "$E" start "$EC" "$PLAN" --confirm-earlier
rowfix '| pw-review (repair) | changes-requested |' "confirmed repair recorded" "$C/$PLAN"
pwtest_rc 0 "confirmed retry of the same attempt is a resume" "$E" start "$EC" "$PLAN" --confirm-earlier
pwtest_re '__resume__' "same-actor retry does not duplicate the row"
set_phase "$EC" "executed — drifted"
pwtest_rc 2 "non-canonical phase refuses start" "$E" start "$EC" "$PLAN"
pwtest_fix "phase repair hint present"
set_phase "$EC" executing
grep -E 'pass entry' "$C/LOG.md" | grep -qE 'provider=n/a|provider=kilo' && pwtest_ok "LOG recorded the pass audit" || pwtest_bad "pass audit" "no mode/identity in LOG"

# ============================================================ D) feedback-cycle transitions
FB=st-feedback; rm -rf "$PW_PROJECTS_DIR/$FB"; cp -a "$F2" "$PW_PROJECTS_DIR/$FB"
B="$PW_PROJECTS_DIR/$FB"; set_phase "$FB" analysis
BRV=analysis/review/fixture.review.md
pwtest_rc 0 "gate approved before feedback" "$E" gate "$FB" "$BRV"
pwtest_rc 0 "add-item after approval (human)" "$E" add-item "$FB" "$BRV" --section '§1 Goal' --text reword the goal
rowfix '| pw-review (feedback) | in-review |' "one feedback row queued" "$B/$BRV"
pwtest_rc 1 "gate now blocks the stale approval" "$E" gate "$FB" "$BRV"
pwtest_rc 0 "second add-item no second toggle" "$E" add-item "$FB" "$BRV" --section '§1 Goal' --text second ask
[ "$(rowcount '| pw-review (feedback) | in-review |' "$B/$BRV")" = 1 ] \
  && pwtest_ok "repeats in the same queued cycle add no row" || pwtest_bad "feedback idempotence" "second feedback row"
pwtest_rc 0 "reviewer files an item mid-cycle" "$E" add-item "$FB" "$BRV" --section '§1 Goal' --actor pw-reviewer --text reviewer finding
[ "$(rowcount '| pw-review (feedback) | in-review |' "$B/$BRV")" = 1 ] \
  && pwtest_ok "internal writer did not toggle" || pwtest_bad "anti-churn" "extra feedback row"
pwtest_rc 0 "start (repair) enters the pass" "$E" start "$FB" "$BRV"
FB_ROWS="$(rowcount '| in-review |' "$B/$BRV")"
pwtest_rc 0 "agent item during active agent pass" "$E" add-item "$FB" "$BRV" --section '§2' --actor pw-reviewer --text more findings
[ "$(rowcount '| in-review |' "$B/$BRV")" = "$FB_ROWS" ] \
  && pwtest_ok "active-pass state/actor attribution preserved" || pwtest_bad "pass-state churn" "in-review rows grew"
pwtest_rc 0 "human records changes-requested" "$E" signoff "$FB" "$BRV" changes-requested --by faza
pwtest_rc 0 "human asks a question then answers it" "$E" add-question "$FB" "$BRV" --section '§2' --text which lane first
QID="$(grep -oE '^### Q[0-9]+' "$B/$BRV" | tail -1 | sed 's/^### //')"
BEFORE_F="$(rowcount '| pw-review (feedback) | in-review |' "$B/$BRV")"
pwtest_rc 0 "human answers while CR active" "$E" answer "$FB" "$BRV" "$QID" --text the green lane
AFTER_F="$(rowcount '| pw-review (feedback) | in-review |' "$B/$BRV")"
[ "$AFTER_F" = "$((BEFORE_F + 1))" ] && pwtest_ok "human feedback over human rejection queued exactly one row" || pwtest_bad "human re-queue" "before=$BEFORE_F after=$AFTER_F"
pwtest_rc 0 "repeat answer adds none" "$E" answer "$FB" "$BRV" "$QID" --text correction too
[ "$(rowcount '| pw-review (feedback) | in-review |' "$B/$BRV")" = "$AFTER_F" ] \
  && pwtest_ok "same queued cycle unchanged" || pwtest_bad "queue churn" "duplicate feedback row"
EBA=st-earlyfb; rm -rf "$PW_PROJECTS_DIR/$EBA"; cp -a "$F2" "$PW_PROJECTS_DIR/$EBA"
EB="$PW_PROJECTS_DIR/$EBA"; set_phase "$EBA" executing
pwtest_rc 0 "earlier-phase add-item records feedback" "$E" add-item "$EBA" "$PLAN" --section '§2' --text recheck dependency order
pwtest_err 'preserved' "pending-confirmation note explains preserved approval"
grep -qF -- '| pwtest | approved |' "$EB/$PLAN" && pwtest_ok "approval row preserved on earlier-phase feedback" || pwtest_bad "earlier feedback" "approval lost"
[ "$(rowcount '| pw-review (feedback) | in-review |' "$EB/$PLAN")" = 0 ] \
  && pwtest_ok "no in-review transition pending confirmation" || pwtest_bad "earlier feedback" "state toggled without confirmation"
pwtest_rc 1 "open item still blocks the consumed gate" "$E" gate "$EBA" "$PLAN"
MF=st-mftable; rm -rf "$PW_PROJECTS_DIR/$MF"; cp -a "$F2" "$PW_PROJECTS_DIR/$MF"
G="$PW_PROJECTS_DIR/$MF"; set_phase "$MF" analysis
SL="$(grep -n '^## Sign-off' "$G/$BRV" | head -1 | cut -d: -f1)"
head -n "$SL" "$G/$BRV" > "$G/$BRV.trim" && mv "$G/$BRV.trim" "$G/$BRV"
grep -q '^## Sign-off' "$G/$BRV" || pwtest_bad "table-strip setup" "Sign-off heading gone"
pwtest_rc 0 "add-item works despite malformed table" "$E" add-item "$MF" "$BRV" --section '§1' --text the ask survives
pwtest_err 'no Sign-off table rows' "malformed table reported, not invented"
grep -qF 'the ask survives' "$G/$BRV" && pwtest_ok "valid feedback recorded on malformed file" || pwtest_bad "feedback lost" "item not written"

# ============================================================ E) auto-signoff guards
AS=st-autosign; rm -rf "$PW_PROJECTS_DIR/$AS"; cp -a "$F2" "$PW_PROJECTS_DIR/$AS"
A2="$PW_PROJECTS_DIR/$AS"
pwtest_rc 0 "configure everything auto" "$CFG" ai-review "$AS" analysis auto
pwtest_rc 0 "configure task-exec auto" "$CFG" ai-review "$AS" task-exec auto
set_phase "$AS" analysis
pwtest_rc 2 "phase-lane mismatch refused" "$E" auto-signoff "$AS" "$PLAN" analysis
pwtest_rc 2 "task-exec phase on PLAN file refused" "$E" auto-signoff "$AS" "$PLAN" task-exec
mkdir -p "$A2/analysis/review"
printf '# RFC comment staging\n\n## Items\n\n### R1 · §1 — [OPEN] (you, 2026-09-15 00:00) <!-- pw-item-status: open -->\ncomment\n---\n' > "$A2/analysis/review/RFC.review.md"
pwtest_rc 2 "RFC staging never gets approval" "$E" auto-signoff "$AS" analysis/review/RFC.review.md analysis
pwtest_rc 0 "seed a real open item" "$E" add-item "$AS" "$BRV" --section '§1' --text needs rework before approval
pwtest_rc 2 "auto refuses with open items" "$E" auto-signoff "$AS" "$BRV" analysis
cp "$A2/analysis/fixture.md" "$A2/analysis/extra.md"
pwtest_rc 0 "init the clean file" "$E" init-docs "$AS" analysis/extra.md
pwtest_rc 0 "clean auto pass names the actual reviewer" "$E" auto-signoff "$AS" analysis/review/extra.review.md analysis --provider kilo --model openai/actual-review-model
rowfix '| pw-reviewer (auto; provider=kilo; model=openai/actual-review-model) | approved |' "auto row carries actual provider+model" "$A2/analysis/review/extra.review.md"
[ "$(rowcount '| approved ✅ |' "$A2/analysis/review/extra.review.md")" = 0 ] && pwtest_ok "no legacy emoji written" || pwtest_bad "legacy write" "new rows must be plain approved"
cp "$A2/analysis/fixture.md" "$A2/analysis/ghost-ok.md"
pwtest_rc 0 "init second clean file" "$E" init-docs "$AS" analysis/ghost-ok.md
pwtest_rc 0 "auto with unknown identity" "$E" auto-signoff "$AS" analysis/review/ghost-ok.review.md analysis
rowfix '| pw-reviewer (auto; provider=unknown; model=unknown) | approved |' "unconfirmed identity printed unknown" "$A2/analysis/review/ghost-ok.review.md"
HR=st-humanreject; rm -rf "$PW_PROJECTS_DIR/$HR"; cp -a "$F2" "$PW_PROJECTS_DIR/$HR"
H="$PW_PROJECTS_DIR/$HR"; set_phase "$HR" analysis
HRV=analysis/review/fixture.review.md
pwtest_rc 0 "configure HR auto" "$CFG" ai-review "$HR" analysis auto
pwtest_rc 0 "human rejects" "$E" signoff "$HR" "$HRV" changes-requested --by faza
pwtest_rc 0 "reviewer files items over the rejection" "$E" add-item "$HR" "$HRV" --section '§1' --actor pw-reviewer --text reviewer note only
pwtest_rc 0 "repair pass queues its own row" "$E" start "$HR" "$HRV"
grep -qF -- '| faza | changes-requested |' "$H/$HRV" && pwtest_ok "human rejection row preserved" || pwtest_bad "rejection lost" "human row gone"
RID="$(grep -oE '^### R[0-9]+' "$H/$HRV" | tail -1 | sed 's/^### //')"
pwtest_rc 0 "resolve the reviewer item" "$E" resolve "$HR" "$HRV" "$RID" --reply 'addressed'
pwtest_rc 2 "clean auto cannot override human rejection" "$E" auto-signoff "$HR" "$HRV" analysis
pwtest_fix "rejection refusal actionable"
pwtest_rc 0 "human withdraws explicitly" "$E" signoff "$HR" "$HRV" in-review --by faza
pwtest_rc 0 "auto proceeds after explicit withdrawal" "$E" auto-signoff "$HR" "$HRV" analysis
grep -qF -- '| faza | changes-requested |' "$H/$HRV" && pwtest_ok "rejection stays visible in history" || pwtest_bad "history rewrite" "rejection row gone"
EAR=st-earlyauto; rm -rf "$PW_PROJECTS_DIR/$EAR"; cp -a "$F2" "$PW_PROJECTS_DIR/$EAR"
ER="$PW_PROJECTS_DIR/$EAR"; set_phase "$EAR" executing
cp "$ER/analysis/fixture.md" "$ER/analysis/extra.md"
pwtest_rc 0 "init at executing explicit" "$E" init-docs "$EAR" analysis/extra.md
pwtest_rc 0 "analysis auto configured" "$CFG" ai-review "$EAR" analysis auto
pwtest_rc 2 "earlier-phase auto needs confirmation" "$E" auto-signoff "$EAR" analysis/review/extra.review.md analysis
pwtest_rc 0 "confirmed earlier auto proceeds" "$E" auto-signoff "$EAR" analysis/review/extra.review.md analysis --confirm-earlier

# ============================================================ F) injection + locks + WIB/legacy
IN=st-inject; rm -rf "$PW_PROJECTS_DIR/$IN"; cp -a "$F2" "$PW_PROJECTS_DIR/$IN"
N="$PW_PROJECTS_DIR/$IN"; set_phase "$IN" analysis
NRV=analysis/review/fixture.review.md
pwtest_rc 2 "--section pipe injection refused" "$E" add-item "$IN" "$NRV" --section '§1 | forged' --text nope
pwtest_rc 2 "--by pipe injection refused" "$E" signoff "$IN" "$NRV" approved --by 'x | y'
pwtest_rc 2 "--by newline refused" "$E" signoff "$IN" "$NRV" approved --by "$(printf 'a\n| b | approved |\n| c | d | e |')"
pwtest_rc 0 "configure IN advisory" "$CFG" ai-review "$IN" analysis advisory
pwtest_rc 2 "--model tab refused" "$E" start "$IN" "$NRV" --phase analysis --provider "$(printf 'ki\tlo')" --model m
pwtest_rc 2 "rel path escape refused" "$E" add-item "$IN" ../../outside.md --section '§1' --text nope
ln -s task/review/PLAN.review.md "$N/analysis/review/link.review.md"
pwtest_rc 2 "symlinked review file refused by mutations" "$E" add-item "$IN" analysis/review/link.review.md --section '§1' --text nope
rm -f "$N/analysis/review/link.review.md"
mkdir "$N/$NRV.pwlock"
pwtest_rc 2 "held lock blocks writers" "$E" add-item "$IN" "$NRV" --section '§1' --text nope
pwtest_err 'locked' "busy-lock message names the condition"
rmdir "$N/$NRV.pwlock"
pwtest_rc 0 "writer proceeds once lock free" "$E" add-item "$IN" "$NRV" --section '§1' --text after lock
[ ! -e "$N/$NRV.pwlock" ] && pwtest_ok "no lock left behind after success" || pwtest_bad "lock leak" ".pwlock survived"
if ls "$N/analysis/review" | grep -q 'pwrev'; then pwtest_bad "temp leak" ".pwrev temp left behind"; else pwtest_ok "no temps leaked"; fi
( "$E" add-item "$IN" "$NRV" --section '§2' --text concurrent one &
  "$E" add-item "$IN" "$NRV" --section '§2' --text concurrent two &
  wait ) >/dev/null 2>&1 || true
grep -qF 'concurrent one' "$N/$NRV" && grep -qF 'concurrent two' "$N/$NRV" \
  && pwtest_ok "both concurrent items survived (serialized)" || pwtest_bad "lost update" "a concurrent item vanished"
pwtest_grep_file '^Gate: in-review \(pw-review \(feedback\)\)$' "derived Gate header tracks the latest row" "$N/$NRV"
pwtest_rc 0 "legacy-approved file still gates" "$E" gate "$IN" "$PLAN"
printf '## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-01-01 00:00 | you | approved ✅ |\n' > "$N/analysis/review/legacy.review.md"
pwtest_rc 0 "legacy emoji decision parses" "$E" gate "$IN" analysis/review/legacy.review.md
pwtest_re 'approved ✅' "legacy decoration printed verbatim"
[ "$(_signoff_latest_actor "$N/analysis/review/legacy.review.md")" = "you" ] \
  && pwtest_ok "legacy row reads its By" || pwtest_bad "legacy actor" "misread"
pwtest_rc 2 "newline injection never forges extra rows" "$E" signoff "$IN" analysis/review/legacy.review.md approved --by "$(printf 'you |\n| 2999 | me | approved | evi')"
rows="$(grep -c '^|' <(_comment_blanked "$N/analysis/review/legacy.review.md") || true)"
[ "${rows:-0}" = 3 ] && pwtest_ok "table grew no rows on refusal" || pwtest_bad "row injection" "rows=$rows want 3"

# ============================================================ G) pure reader units (mdlib)
u_by() { if [ "$(_decision_actor_kind "$1")" = "$2" ]; then pwtest_ok "actor kind [$1] → $2"; else pwtest_bad "actor kind [$1]" "want $2 got $(_decision_actor_kind "$1")"; fi; }
u_by "you" human
u_by "faza" human
u_by "pw-review (repair)" repair
u_by "pw-review (feedback)" feedback
u_by "pw-review (auto-reopen)" reopen
u_by "pw-reviewer (auto)" reviewer
u_by "pw-reviewer (advisory; provider=kilo; model=m)" reviewer
u_by "" blank
u_by "something-ambiguous" human
RU="$N/analysis/review/rej-order.md"
printf '## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-01-01 00:00 | you | approved |\n| 2026-01-02 00:00 | faza | changes-requested |\n| 2026-01-03 00:00 | pw-review (feedback) | in-review |\n| 2026-01-04 00:00 | pw-review (repair) | changes-requested |\n' > "$RU"
if _signoff_human_rejection_active "$RU"; then pwtest_ok "human rejection active under agent bookkeeping rows"; else pwtest_bad "rejection scan" "missed the human CR"; fi
printf '| 2026-01-05 00:00 | faza | in-review |\n' >> "$RU"
if _signoff_human_rejection_active "$RU"; then pwtest_bad "rejection scan" "withdrawal not seen"; else pwtest_ok "explicit human in-review withdraws the rejection"; fi
printf '## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| x | pw-reviewer (auto) | changes-requested |\n' > "$RU"
if _signoff_human_rejection_active "$RU"; then pwtest_bad "rejection scan" "agent row counted human"; else pwtest_ok "agent CR is not a human rejection"; fi
EU="$N/analysis/review/elig-units.md"
printf '# Review\n## Items\n\n### R1 · <§section> — [OPEN] (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->\n<stub>\n\n---\n\n### R2 · §1 — [OPEN] (you, 2026-09-15 09:00) <!-- pw-item-status: open -->\n\n---\n\n### R3 · §1 — [OPEN] (you, 2026-09-15 09:00) <!-- pw-item-status: open -->\nreal ask\n\n---\n\n### R4 · §1 — [RESOLVED] (you, 2026-09-15 09:00) <!-- pw-item-status: resolved -->\ndone\n\n---\n\n## Open questions\n\n### Q1 · §2 — [PENDING] (agent, 2026-09-15 09:00) <!-- pw-item-status: open -->\nquestion\n\n> ↳ **you** (2026-09-15 09:30): answer\n\n---\n\n### Q2 · §2 — [PENDING] (agent, 2026-09-15 09:00) <!-- pw-item-status: open -->\nwaiting\n\n---\n' > "$EU"
u_counts() { local r; r="$(_review_eligible_counts "$EU")"; printf '%s' "$r" | grep -qE "$1" && pwtest_ok "eligible units: $2" || pwtest_bad "eligible units: $2" "got [$r]"; }
u_counts 'eligible=2' "real open item + fold-in answer = 2"
u_counts 'open=1' "only the body-carrying open item counts open"
u_counts 'foldin=1' "answered question counted as fold-in work"
u_counts 'awaiting=1' "unanswered pending question is awaiting-human"
u_counts 'unactionable=1' "empty-body open heading is unactionable"
ES="$N/analysis/review/stub-only.md"
printf '# Review\n## Items\n\n### R1 · <§section or anchor> — [OPEN] (you, <YYYY-MM-DD HH:MM>) <!-- pw-item-status: open -->\n<what needs to change>\n\n---\n\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| | | in-review |\n\n<!-- example\n### R9 · §1 — [OPEN] (you, 2026-08-06 10:20) [marker: pw-item-status open]\n--- -->\n' > "$ES"
r="$(_review_eligible_counts "$ES")"; printf '%s' "$r" | grep -q 'eligible=0' && pwtest_ok "stubs+examples invisible to eligible" || pwtest_bad "eligible stubs" "got [$r]"
[ "$(_signoff_latest_decision "$ES")" = "in-review" ] && [ -z "$(_signoff_latest_actor "$ES")" ] \
  && pwtest_ok "blank placeholder reads as decision with no actor" || pwtest_bad "placeholder read" "misread"
EA="$N/analysis/review/approved-stub.md"
printf '## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-15 00:00 | pwtest | approved |\n' > "$EA"
if _review_approval_valid "$EA"; then pwtest_ok "approved + stub-only is a valid approval"; else pwtest_bad "approval valid" "wrongly blocked"; fi
printf '\n### R1 · §1 — [OPEN] (you, 2026-09-16 09:00) <!-- pw-item-status: open -->\nhand-added blocker\n\n---\n' >> "$EA"
if _review_approval_valid "$EA"; then pwtest_bad "stale approval" "hand edit not seen"; else pwtest_ok "hand-added open item invalidates consumption"; fi

rm -rf "$PW_PROJECTS_DIR/$AD" "$PW_PROJECTS_DIR/$IA" "$PW_PROJECTS_DIR/$SM" "$PW_PROJECTS_DIR/$RMQ" \
       "$PW_PROJECTS_DIR/$MFM" "$PW_PROJECTS_DIR/$UK" "$PW_PROJECTS_DIR/$EC" "$PW_PROJECTS_DIR/$FB" \
       "$PW_PROJECTS_DIR/$EBA" "$PW_PROJECTS_DIR/$MF" "$PW_PROJECTS_DIR/$AS" "$PW_PROJECTS_DIR/$HR" \
       "$PW_PROJECTS_DIR/$EAR" "$PW_PROJECTS_DIR/$IN"
