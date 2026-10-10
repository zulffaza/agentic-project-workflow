# shellcheck shell=bash
# prepare/import handoff (plan 36): frozen packets, schema-validated external reports,
# replay/stale semantics, bounded-cycle budget, advisory-only imports, and the new
# context/rfc/close surfaces. No model is ever launched by these operators.
HREVIEW="$(pwtest_script pw-review.sh)"
HCFG="$(pwtest_script pw-config.sh)"

# ---------------------------------------------------------------- scratch project (docs)
HD=handoff-demo
rm -rf "$PW_PROJECTS_DIR/$HD"
mkdir -p "$PW_PROJECTS_DIR/$HD/analysis" "$PW_PROJECTS_DIR/$HD/context" "$PW_PROJECTS_DIR/$HD/rfc" "$PW_PROJECTS_DIR/$HD/task"
printf -- '- **Status:** context\n- **One-liner:** handoff fixture\n' > "$PW_PROJECTS_DIR/$HD/README.md"
: > "$PW_PROJECTS_DIR/$HD/LOG.md"
printf '# Retry policy\n\n## 1. Goal\nPredictable retries.\n\n## 2. Approach\nExponential backoff.\n' > "$PW_PROJECTS_DIR/$HD/analysis/retry-policy.md"
HDP="$PW_PROJECTS_DIR/$HD"
HRV=analysis/review/retry-policy.review.md

# --- A) prepare: packet contents, byte-identical snapshot, no overwrite on retry ---------
pwtest_rc 0 "prepare freezes one analysis unit" "$HREVIEW" prepare "$HD" analysis/retry-policy.md --pass-id p-a1
pwtest_re 'pass p-a1 frozen \(surface=analysis' "prepare reports the frozen pass"
for hf in manifest.json request.md snapshot/analysis/retry-policy.md; do
  [ -f "$HDP/review/ai/p-a1/$hf" ] && pwtest_ok "packet carries $hf" || pwtest_bad "packet file missing" "$hf"
done
grep -q '"state": "prepared"' "$HDP/review/ai/p-a1/manifest.json" \
  && pwtest_ok "fresh packet state=prepared" || pwtest_bad "packet state" "$(grep '"state"' "$HDP/review/ai/p-a1/manifest.json")"
grep -q '"round": 1' "$HDP/review/ai/p-a1/manifest.json" \
  && pwtest_ok "first pass is round 1" || pwtest_bad "round" "first pass not round 1"
grep -q 'pw-review-report/1' "$HDP/review/ai/p-a1/request.md" \
  && pwtest_ok "reviewer request carries the report schema" || pwtest_bad "request schema" "request.md lost the report schema"
cmp -s "$HDP/analysis/retry-policy.md" "$HDP/review/ai/p-a1/snapshot/analysis/retry-policy.md" \
  && pwtest_ok "snapshot copy is byte-identical" || pwtest_bad "snapshot bytes" "snapshot differs from the artifact"
[ -f "$HDP/$HRV" ] && pwtest_ok "prepare initialized the import target review file" || pwtest_bad "import target" "$HRV missing"
pwtest_rc 0 "prepare retry shows the existing packet" "$HREVIEW" prepare "$HD" analysis/retry-policy.md
pwtest_re 'already exists: review/ai/p-a1' "retry does not overwrite without --refresh"
grep -q '"state": "prepared"' "$HDP/review/ai/p-a1/manifest.json" \
  && pwtest_ok "retry left the packet untouched" || pwtest_bad "retry clobbered" "packet state changed"

# --- B) import: validated findings/questions, notes, advisory-only, replay ----------------
cat > "$ROOT/handoff-report.json" <<'JSON'
{
  "schema": "pw-review-report/1",
  "pass_id": "p-a1",
  "verdict": "findings",
  "scope": "analysis/retry-policy.md",
  "coverage": ["read the full document", "no external sources checked"],
  "findings": [
    {"key":"F1","severity":"high","artifact":"analysis/retry-policy.md","anchor":"§2 Approach","issue":"Max attempts is not configurable.","evidence":"§2 fixes 5 attempts with no config path.","correction":"State where the limit comes from."},
    {"key":"F2","severity":"low","artifact":"analysis/retry-policy.md","anchor":"§2 Approach","issue":"Jitter range unspecified.","evidence":"§2 says jitter without a range.","correction":"Name the jitter range."}
  ],
  "questions": [{"key":"Q1","artifact":"analysis/retry-policy.md","anchor":"§1 Goal","question":"Is idempotency guaranteed downstream?"}],
  "reviewer": {"provider":"codex","model":"gpt-x"}
}
JSON
pwtest_rc 0 "import validates and files the report" "$HREVIEW" import "$HD" --report "$ROOT/handoff-report.json"
pwtest_re 'verdict=findings' "import recap carries the verdict"
pwtest_re 'items: R1 R2' "both findings were filed"
pwtest_re 'questions: Q1' "the question was filed"
H_ITEMS="$(grep -cE '^### R[0-9]+ · §2 Approach — \[OPEN\] \(pw-reviewer \(external\),' "$HDP/$HRV")"
[ "$H_ITEMS" = "2" ] && pwtest_ok "two distinct findings on one anchor both filed" || pwtest_bad "anchor dedupe too eager" "open review items on §2: $H_ITEMS"
grep -qE '^### Q[0-9]+ · §1 Goal — \[PENDING\] \(pw-reviewer \(external\),' "$HDP/$HRV" \
  && pwtest_ok "question imported with external attribution" || pwtest_bad "question attribution" "external question heading missing"
grep -qE '^### R[0-9]+ · §2 Approach — \[OPEN\] \(pw-reviewer \(external\)' "$HDP/$HRV" \
  && pwtest_ok "finding attribution names the external origin" || pwtest_bad "finding attribution" "external actor missing"
grep -q '"state": "imported"' "$HDP/review/ai/p-a1/manifest.json" \
  && pwtest_ok "pass state=imported" || pwtest_bad "pass state" "$(grep '"state"' "$HDP/review/ai/p-a1/manifest.json")"
[ -f "$HDP/review/ai/p-a1/report.json" ] \
  && pwtest_ok "validated report copy stored in the pass dir" || pwtest_bad "report copy" "report.json missing"
grep -q 'mode=external' "$HDP/REVIEWER-NOTES.md" \
  && pwtest_ok "notes entry appended with external mode" || pwtest_bad "notes entry" "no mode=external entry"
grep -q 'ADVISORY ONLY' "$HDP/REVIEWER-NOTES.md" \
  && pwtest_ok "notes state the advisory-only provenance" || pwtest_bad "notes provenance" "ADVISORY ONLY marker missing"
H_AUTO_ROWS="$(grep -cE '^\| [^|]*\| pw-reviewer \(auto' "$HDP/$HRV" 2>/dev/null || true)"
[ -z "$H_AUTO_ROWS" ] && H_AUTO_ROWS=0
pwtest_rc 0 "identical replay is a no-op" "$HREVIEW" import "$HD" --report "$ROOT/handoff-report.json"
pwtest_re 'already imported \(identical report\)' "replay reports the no-op"
[ "$(grep -cE '^### R[0-9]+ · §2 Approach' "$HDP/$HRV")" = "2" ] \
  && pwtest_ok "replay added no duplicate items" || pwtest_bad "replay duplicated" "item count changed on replay"
H_AUTO_ROWS2="$(grep -cE '^\| [^|]*\| pw-reviewer \(auto' "$HDP/$HRV" 2>/dev/null || true)"
[ -z "$H_AUTO_ROWS2" ] && H_AUTO_ROWS2=0
[ "$H_AUTO_ROWS" = "$H_AUTO_ROWS2" ] \
  && pwtest_ok "external import wrote no approval/auto row" || pwtest_bad "external import wrote approval bookkeeping" "auto rows went $H_AUTO_ROWS -> $H_AUTO_ROWS2"

# --- C) freshness: stale snapshot refuses, retains evidence, records state ----------------
pwtest_rc 0 "prepare round 2 via --refresh" "$HREVIEW" prepare "$HD" analysis/retry-policy.md --refresh --pass-id p-a2
pwtest_re 'round=2/3' "refresh counted the next round"
printf '\n## 3. Limits\nOne more section.\n' >> "$HDP/analysis/retry-policy.md"
cat > "$ROOT/handoff-stale.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-a2","verdict":"clean","scope":"analysis/retry-policy.md","coverage":["full"],"findings":[]}
JSON
pwtest_rc 2 "stale snapshot import refused" "$HREVIEW" import "$HD" --report "$ROOT/handoff-stale.json"
pwtest_err 'fingerprint mismatch' "refusal names the freshness cause"
grep -q '"state": "stale"' "$HDP/review/ai/p-a2/manifest.json" \
  && pwtest_ok "stale pass recorded as evidence" || pwtest_bad "stale state" "manifest not marked stale"
[ ! -f "$HDP/review/ai/p-a2/report.json" ] \
  && pwtest_ok "stale refusal stored no validated report" || pwtest_bad "stale import" "a report copy exists"

# --- D) validator refusals (each writes nothing) ------------------------------------------
H_MF_D_BEFORE="$(cat "$HDP/review/ai/p-a2/manifest.json")"
sed 's/"verdict":"clean"/"verdict":"weird"/' "$ROOT/handoff-stale.json" > "$ROOT/bad-verdict.json"
pwtest_rc 2 "verdict enum enforced" "$HREVIEW" import "$HD" --report "$ROOT/bad-verdict.json"
pwtest_err 'verdict must be' "refusal names the verdict enum"
cat > "$ROOT/bad-clean.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-a2","verdict":"clean","scope":"analysis/retry-policy.md","coverage":[],
 "findings":[{"key":"F9","severity":"low","artifact":"analysis/retry-policy.md","anchor":"§1","issue":"x","evidence":"y","correction":"z"}]}
JSON
pwtest_rc 2 "clean verdict with findings refused" "$HREVIEW" import "$HD" --report "$ROOT/bad-clean.json"
pwtest_err 'inconsistent' "clean/findings inconsistency named"
cat > "$ROOT/bad-artifact.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-a2","verdict":"findings","scope":"analysis/retry-policy.md","coverage":[],
 "findings":[{"key":"F1","severity":"low","artifact":"analysis/somewhere-else.md","anchor":"§1","issue":"x","evidence":"y","correction":"z"}]}
JSON
pwtest_rc 2 "artifact outside the frozen inputs refused" "$HREVIEW" import "$HD" --report "$ROOT/bad-artifact.json"
pwtest_err 'not a reviewed input' "artifact membership named"
cat > "$ROOT/bad-injection.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-a2","verdict":"findings","scope":"analysis/retry-policy.md","coverage":[],
 "findings":[{"key":"F1","severity":"low","artifact":"analysis/retry-policy.md","anchor":"§1","issue":"## Injected heading","evidence":"y","correction":"z"}]}
JSON
pwtest_rc 2 "markdown-heading injection refused" "$HREVIEW" import "$HD" --report "$ROOT/bad-injection.json"
pwtest_err 'must not contain markdown headings' "injection refusal named"
echo '{"verdict":"clean"}' > "$ROOT/no-pass.json"
pwtest_rc 2 "report without pass_id refused" "$HREVIEW" import "$HD" --report "$ROOT/no-pass.json"
pwtest_err 'carries no' "missing pass id named"
cat > "$ROOT/unprepared.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-ghost","verdict":"clean","scope":"analysis/retry-policy.md","coverage":[],"findings":[]}
JSON
pwtest_rc 2 "unprepared report refused (never a structured import)" "$HREVIEW" import "$HD" --report "$ROOT/unprepared.json"
pwtest_err 'no prepared packet' "unprepared refusal named"
[ "$H_MF_D_BEFORE" = "$(cat "$HDP/review/ai/p-a2/manifest.json")" ] \
  && pwtest_ok "validator refusals left the manifest untouched" || pwtest_bad "refusal purity" "manifest mutated by a refused import"
# wrong project: the same prepared pass imported into a different project refuses on binding
mkdir -p "$PW_PROJECTS_DIR/$S2/review/ai"
rm -rf "$PW_PROJECTS_DIR/$S2/review/ai/p-a2"; cp -a "$HDP/review/ai/p-a2" "$PW_PROJECTS_DIR/$S2/review/ai/"
pwtest_rc 2 "pass imported under the wrong project refused" "$HREVIEW" import "$S2" --report "$ROOT/handoff-stale.json"
pwtest_err 'belongs to project' "project binding named"
rm -rf "$PW_PROJECTS_DIR/$S2/review/ai"

# --- E) bounded-cycle budget ---------------------------------------------------------------
pwtest_rc 0 "repair round inside the default budget" "$HREVIEW" prepare "$HD" analysis/retry-policy.md --repair --pass-id p-a3
pwtest_re 'round=3/3' "third pass counted as the last budgeted round"
pwtest_rc 0 "shrink the budget to 2" "$HCFG" project set "$HD" review-rounds 2
pwtest_rc 2 "repair beyond the budget refused" "$HREVIEW" prepare "$HD" analysis/retry-policy.md --repair
pwtest_fix "budget refusal carries a fix hint"
pwtest_err 'budget' "refusal names the budget"
pwtest_rc 0 "deliberate --refresh remains available" "$HREVIEW" prepare "$HD" analysis/retry-policy.md --refresh --pass-id p-a4
pwtest_rc 0 "passes reader lists the packets" "$HREVIEW" passes "$HD"
pwtest_re 'review/ai/p-a1: surface=analysis state=imported' "passes shows the imported pass"
pwtest_re 'state=stale' "passes shows the stale pass"

# --- F) new surfaces: context / rfc / close ------------------------------------------------
# context refuses before its input exists…
pwtest_rc 2 "prepare context without a brief refused" "$HREVIEW" prepare "$HD" context
pwtest_fix "context refusal points at the context flow"
printf '# Requirements\n\n- **Outcome:** predictable retries\n\n## Open decisions\n- rollout order?\n' > "$HDP/context/REQUIREMENTS.md"
pwtest_rc 0 "prepare context readiness packet" "$HREVIEW" prepare "$HD" context --pass-id p-ctx1
pwtest_re 'surface=context, unit=context/REQUIREMENTS.md' "context packet frozen"
[ -f "$HDP/context/review/CONTEXT.review.md" ] \
  && pwtest_ok "context review record created" || pwtest_bad "context record" "CONTEXT.review.md missing"
grep -q '"path": "context/REQUIREMENTS.md"' "$HDP/review/ai/p-ctx1/manifest.json" \
  && pwtest_ok "context packet snapshots the brief" || pwtest_bad "context inputs" "REQUIREMENTS not snapshotted"
if grep -q '"path": "context/INDEX.md"' "$HDP/review/ai/p-ctx1/manifest.json"; then
  pwtest_bad "context inputs" "a missing INDEX was snapshotted"
else
  pwtest_ok "context packet lists only existing inputs"
fi
# …rfc refuses before rfc/RFC.md exists…
pwtest_rc 2 "prepare rfc without a content doc refused" "$HREVIEW" prepare "$HD" rfc
printf '# RFC — retry policy\n\n## Summary\nBackoff change.\n' > "$HDP/rfc/RFC.md"
pwtest_rc 0 "prepare rfc content packet" "$HREVIEW" prepare "$HD" rfc --pass-id p-rfc1
[ -f "$HDP/rfc/review/RFC-CONTENT.review.md" ] \
  && pwtest_ok "local RFC content record created (distinct from staging)" || pwtest_bad "rfc record" "RFC-CONTENT.review.md missing"
# …close works from its evidence set without a single artifact
pwtest_rc 0 "prepare close record packet" "$HREVIEW" prepare "$HD" close --pass-id p-close1
pwtest_re 'surface=close' "close packet frozen"
[ -f "$HDP/review/CLOSE.review.md" ] \
  && pwtest_ok "close record created" || pwtest_bad "close record" "review/CLOSE.review.md missing"
# a close report identifies its evidence set (no single artifact) and imports cleanly
cat > "$ROOT/handoff-close.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-close1","verdict":"clean","scope":"close evidence set","coverage":["evidence bundle read"],"findings":[]}
JSON
pwtest_rc 0 "close report imports with its evidence-set scope" "$HREVIEW" import "$HD" --report "$ROOT/handoff-close.json"
pwtest_re 'verdict=clean' "close import recap carries the clean verdict"
pwtest_rc 0 "scan shows the rfc content lane" "$HREVIEW" scan "$HD" --phase rfc
pwtest_re 'rfc/review/RFC-CONTENT.review.md' "rfc scan selects the content record"
pwtest_rc 0 "scan shows the close lane" "$HREVIEW" scan "$HD" --phase close
pwtest_re 'review/CLOSE.review.md' "close scan selects the close record"
pwtest_rc 2 "scan rejects unknown surfaces" "$HREVIEW" scan "$HD" --phase nope
# auto-signoff on the new lanes (clean records, mode auto) + staging still refused
pwtest_rc 0 "auto modes for the new lanes" "$HCFG" project set "$HD" ai-review context=auto rfc=auto close=auto
pwtest_rc 0 "auto-signoff context readiness" "$HREVIEW" auto-signoff "$HD" context/review/CONTEXT.review.md context
pwtest_rc 0 "auto-signoff rfc content" "$HREVIEW" auto-signoff "$HD" rfc/review/RFC-CONTENT.review.md rfc
pwtest_rc 0 "auto-signoff close record" "$HREVIEW" auto-signoff "$HD" review/CLOSE.review.md close
pwtest_rc 0 "seed the staging review via legacy init" "$HREVIEW" init "$HD" analysis/review/RFC.review.md analysis/RFC.md
pwtest_rc 2 "RFC staging still never approves" "$HREVIEW" auto-signoff "$HD" analysis/review/RFC.review.md rfc
pwtest_err 'staging never receives an approval' "staging refusal names the doctrine"

# --- G) task code evidence: recorded, code anchors valid, freshness follows the commit ------
HC=handoff-task; rm -rf "$PW_PROJECTS_DIR/$HC"; cp -a "$F2" "$PW_PROJECTS_DIR/$HC"
HCP="$PW_PROJECTS_DIR/$HC"
# a task doc prepared while the dashboard is still at breakdown is the task-PLAN surface
sed -i '' 's/^- \*\*Status:\*\* executing/- **Status:** breakdown/' "$HCP/README.md"
pwtest_rc 0 "prepare infers the task-plan surface at breakdown" "$HREVIEW" prepare "$HC" T01 --pass-id p-t01plan
pwtest_re 'surface=task-plan' "breakdown-phase task review maps to task-plan"
sed -i '' 's/^- \*\*Status:\*\* breakdown/- **Status:** executing/' "$HCP/README.md"
pwtest_rc 0 "prepare task packet records code evidence" "$HREVIEW" prepare "$HC" T01 --pass-id p-t01
pwtest_re 'surface=task-exec' "executing-phase task review maps to task-exec"
HC_HEAD="$(git -C "$HCP/worktree/api/T01-thing" rev-parse HEAD 2>/dev/null)"
grep -q "\"head\": \"$HC_HEAD\"" "$HCP/review/ai/p-t01/manifest.json" \
  && pwtest_ok "manifest records the worktree HEAD" || pwtest_bad "code evidence" "HEAD not recorded: $HC_HEAD"
grep -q '"patch_sha256": "' "$HCP/review/ai/p-t01/manifest.json" \
  && pwtest_ok "manifest records a patch digest" || pwtest_bad "patch digest" "no patch_sha256 recorded"
# a path in a NON-recorded worktree is refused (checked before any import: refusals write nothing)
cat > "$ROOT/handoff-t01-outside.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-t01","verdict":"findings","scope":"task/T01.md","coverage":[],
 "findings":[{"key":"F2","severity":"low","artifact":"worktree/api/T02-thing/other.py","anchor":"other.py:1","issue":"x","evidence":"y","correction":"z"}]}
JSON
pwtest_rc 2 "path outside the recorded worktree refused" "$HREVIEW" import "$HC" --report "$ROOT/handoff-t01-outside.json"
pwtest_err 'not a reviewed input' "worktree membership named"
# a finding anchored INSIDE the recorded worktree is a valid reviewed input (code review)
cat > "$ROOT/handoff-t01-code.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-t01","verdict":"findings","scope":"task/T01.md","coverage":["reviewed the committed diff"],
 "findings":[{"key":"F1","severity":"medium","artifact":"worktree/api/T01-thing/dispatcher.py","anchor":"dispatcher.py:1-5","issue":"x","evidence":"y","correction":"z"}]}
JSON
pwtest_rc 0 "code-anchored finding accepted" "$HREVIEW" import "$HC" --report "$ROOT/handoff-t01-code.json"
pwtest_re 'items: R1' "the code-anchored finding was filed"
# a moved worktree HEAD invalidates the reviewed identity: the import must refuse as stale
pwtest_rc 0 "prepare the movement-test pass" "$HREVIEW" prepare "$HC" T01 --refresh --pass-id p-t01b
cat > "$ROOT/handoff-t01.json" <<'JSON'
{"schema":"pw-review-report/1","pass_id":"p-t01b","verdict":"clean","scope":"task/T01.md","coverage":["reviewed the committed diff"],"findings":[]}
JSON
git -C "$HCP/worktree/api/T01-thing" -c user.email=pwtest@example.com -c user.name=pwtest commit --allow-empty -m "post-prepare movement" >/dev/null 2>&1
pwtest_rc 2 "task code movement invalidates the snapshot" "$HREVIEW" import "$HC" --report "$ROOT/handoff-t01.json"
pwtest_err 'fingerprint mismatch' "code freshness refusal named"

rm -rf "$PW_PROJECTS_DIR/$HD" "$PW_PROJECTS_DIR/$HC"
