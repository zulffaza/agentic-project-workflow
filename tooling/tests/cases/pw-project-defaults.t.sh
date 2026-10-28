# shellcheck shell=bash
# cases/pw-project-defaults.t.sh — global project defaults, creation-time snapshots, role-model
# tuning, decision-ready lint stages, and the repair-admission guard (plan 58).

GPD="$ROOT/project-defaults"
rm -rf "$GPD"; mkdir -p "$GPD/projects"
GPCFG="$GPD/pw.config.sh"
# Creation validates the resolved snapshot against the provider catalog (plan 61). The fixture's
# role model must therefore exist in the deterministic kilo shim's catalog.
export PWTEST_KILO_CATALOG_EXTRA="command_code/model"
printf '%s\n' '# synthetic global config for plan 58' 'PW_PROVIDERS=(kilo)' 'PW_MAX_SELF_REPAIR=3' > "$GPCFG"
gpd() { PW_PROJECTS_DIR="$GPD/projects" PW_PROJECTS="$GPD/projects" PW_REPOS="$GPD/repos" PW_CONFIG_FILE="$GPCFG" "$(pwtest_script pw-config.sh)" "$@"; }
gpd_scaffold() { PW_PROJECTS="$GPD/projects" PW_REPOS="$GPD/repos" PW_CONFIG_FILE="$GPCFG" "$(pwtest_script scaffold.sh)" --project "$1"; }
gpd_re() { printf '%s\n' "$2" | grep -qE -- "$1" && pwtest_ok "$3" || pwtest_bad "$3" "no /$1/ in [$2]"; }

# --- global operator: validated writes into the ONE existing config file -------------------
pwtest_rc 0 "global set routing" gpd global set --key routing --value headless
pwtest_eq "global get routing" "headless" "$(gpd global get --key routing 2>/dev/null)"
grep -q '^PW_PROJECT_DEFAULT_ROUTING="headless"$' "$GPCFG" \
  && pwtest_ok "managed block holds the quoted literal" \
  || pwtest_bad "managed block holds the quoted literal" "no managed assignment in $GPCFG"
grep -q 'PW_PROVIDERS=(kilo)' "$GPCFG" \
  && pwtest_ok "unrelated shell settings preserved" \
  || pwtest_bad "unrelated shell settings preserved" "global set rewrote surrounding bytes"
bash -n "$GPCFG" && pwtest_ok "managed file remains valid shell" || pwtest_bad "managed file remains valid shell" "bash -n failed"

pwtest_rc 0 "global set review-trigger batch" gpd global set --key review-trigger --set all=completion --set ship=manual
rt="$(gpd global get --key review-trigger 2>/dev/null)"
gpd_re 'analysis=completion' "$rt" "expanded baseline lands"
gpd_re 'ship=manual' "$rt" "named member overrides baseline regardless of order"
if gpd global set --key review-trigger --set ship=manual --set ship=completion >/dev/null 2>&1; then
  pwtest_bad "duplicate named member refused" "accepted a duplicate member"
else
  pwtest_ok "duplicate named member refused"
fi

before_hash="$(shasum -a 256 "$GPCFG" | awk '{print $1}')"
if gpd global set --key max-parallel --value 0 >/dev/null 2>&1; then
  pwtest_bad "invalid range refused" "max-parallel=0 accepted"
else pwtest_ok "invalid range refused"; fi
if gpd global set --key routing --value 'auto;rm -rf /' >/dev/null 2>&1; then
  pwtest_bad "shell metacharacters refused" "accepted a value carrying ';'"
else pwtest_ok "shell metacharacters refused"; fi
pwtest_eq "failed writes leave the file byte-identical" "$before_hash" "$(shasum -a 256 "$GPCFG" | awk '{print $1}')"

# --- role tuning: complete binding, capability-gated ---------------------------------------
pwtest_rc 0 "global ai-model with kilo variant" gpd global set --key ai-model --set analyst=kilo:command_code/model --variant high
gm="$(gpd global get --key ai-model 2>/dev/null)"
gpd_re 'analyst=kilo:command_code/model' "$gm" "global get keeps provider:model"
gpd_re 'variant:high' "$gm" "global get keeps tuning"
if gpd global set --key ai-model --set analyst=claude:opus --variant high >/dev/null 2>&1; then
  pwtest_bad "unsupported provider control refused" "claude --variant was accepted"
else pwtest_ok "unsupported provider control refused"; fi
if gpd global set --key ai-model --set analyst=kilo:m --reasoning max >/dev/null 2>&1; then
  pwtest_bad "unverified capability refused" "kilo --reasoning was guessed as supported"
else pwtest_ok "unverified capability refused"; fi
if gpd global set --key ai-model --set analyst=kilo:a --set reviewer=kilo:b --variant high >/dev/null 2>&1; then
  pwtest_bad "tuning requires exactly one role" "accepted tuned multi-role batch"
else pwtest_ok "tuning requires exactly one role"; fi

# --- model-check capability discovery ------------------------------------------------------
mc="$(gpd model-check --provider kilo --model command_code/model)"
gpd_re 'variant' "$mc" "model-check lists the variant control"
gpd_re 'unknown' "$mc" "model-check distinguishes unknown capability"
pwtest_rc 0 "model-check validates a supported tuning" gpd model-check --provider kilo --model command_code/model --variant high
if gpd model-check --provider kilo --model command_code/model --variant impossible >/dev/null 2>&1; then
  pwtest_bad "model-check refuses a non-listed value" "impossible variant accepted"
else pwtest_ok "model-check refuses a non-listed value"; fi
pwtest_rc 0 "model-check json" gpd model-check --provider kilo --model command_code/model --json
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["capabilities"]["variant"] and d["permission"]=="allowed"' "$PWTEST_OUT" \
  && pwtest_ok "model-check json carries capabilities and permission" \
  || pwtest_bad "model-check json carries capabilities and permission" "$(head -c 200 "$PWTEST_OUT")"

# The comments-analysis lane is a normal global role: its default rides into a NEW project like
# every other spawn lane (and nowhere else).
pwtest_rc 0 "global set ship-comment-analyst" gpd global set --key ai-model --set ship-comment-analyst=kilo:command_code/model
gpd_re 'ship-comment-analyst=kilo:command_code/model' "$(gpd global get --key ai-model 2>/dev/null)" "global get lists the comments-analysis lane"

# --- creation snapshot: new project inherits, existing is untouched ------------------------
pwtest_rc 0 "scaffold inherits global defaults" gpd_scaffold demo-defaults
R="$GPD/projects/demo-defaults/README.md"
gpd_re 'analyst=kilo:command_code/model' "$(grep '^- \*\*AI Models:\*\*' "$R")" "dashboard inherits the tuned role"
gpd_re 'analyst=variant:high' "$(grep '^- \*\*AI Model Tuning:\*\*' "$R")" "dashboard inherits companion tuning"
gpd_re 'ship-comment-analyst=kilo:command_code/model' "$(grep '^- \*\*AI Models:\*\*' "$R")" "dashboard inherits the comments-analysis lane"
gpd_re 'analysis=completion' "$(grep '^- \*\*Review Trigger:\*\*' "$R")" "dashboard inherits review trigger"
gpd_re 'ship=manual' "$(grep '^- \*\*Review Trigger:\*\*' "$R")" "dashboard keeps named review-trigger member"
gpd_re 'routing=headless' "$(grep '^- \*\*Project Defaults:\*\*' "$R")" "dashboard captures the PLAN seed"
pwtest_rc 0 "show json carries structured bindings" gpd show --project demo-defaults --json
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["ai_model"]["roles"]["analyst"]["variant"]=="high" and any(r["key"].startswith("ai-model") for r in d["rows"])' "$PWTEST_OUT" \
  && pwtest_ok "show --json adds structured bindings without dropping rows" \
  || pwtest_bad "show --json adds structured bindings without dropping rows" "$(head -c 300 "$PWTEST_OUT")"
pwtest_rc 0 "project ai-model json" gpd get --project demo-defaults --key ai-model --json
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["roles"]["analyst"]["tuning"]=="variant:high" and d["roles"]["analyst"]["model"]=="command_code/model" and d["roles"]["analyst"]["variant"]=="high" and d["roles"]["analyst"]["reasoning"]=="" and d["roles"]["analyst"]["effort"]=="" and d["roles"]["analyst"]["provider"]=="kilo"' "$PWTEST_OUT" \
  && pwtest_ok "structured read keeps the complete binding and separate tuning fields" \
  || pwtest_bad "structured read keeps the complete binding and separate tuning fields" "$(head -c 300 "$PWTEST_OUT")"
pwtest_eq "plain read stays role=model compatible" "researcher=— analyst=kilo:command_code/model writer-task=— reviewer=— verifier=— ship-comment-analyst=kilo:command_code/model" \
  "$(gpd get --project demo-defaults --key ai-model)"

gpd global set --key routing --value auto >/dev/null
gpd_re 'routing=headless' "$(grep '^- \*\*Project Defaults:\*\*' "$R")" "existing snapshot survives a later global change"

# --- pre-PLAN project overrides ------------------------------------------------------------
pwtest_rc 0 "pre-PLAN routing override" gpd set --project demo-defaults --key routing --value subagent
gpd_re '^subagent' "$(gpd get --project demo-defaults --key routing 2>/dev/null)" "pre-PLAN get reads the seed"
gpd_re 'routing=subagent' "$(grep '^- \*\*Project Defaults:\*\*' "$R")" "pre-PLAN set persists in the dashboard seed"

# --- breakdown materialization (once; explicit PLAN values win) ----------------------------
P="$GPD/projects/demo-defaults/task"; mkdir -p "$P"
cp "$GPD/projects/demo-defaults/task/_TEMPLATE-orchestration-plan.md" "$P/PLAN.md"
pwtest_rc 0 "materialize seed into PLAN" gpd materialize --project demo-defaults
gpd_re 'Routing.*subagent' "$(grep -n 'Routing' "$P/PLAN.md" | head -3)" "PLAN receives the captured routing"
gpd_re 'AI execution limit.*3' "$(grep -n 'AI execution limit' "$P/PLAN.md")" "PLAN receives the captured execution limit"
gpd set --project demo-defaults --key routing --value auto >/dev/null
gpd_re 'Routing.*auto' "$(grep -n 'Routing' "$P/PLAN.md" | head -3)" "post-PLAN set targets PLAN authority"
gpd materialize --project demo-defaults >/dev/null
gpd_re 'Routing.*auto' "$(grep -n 'Routing' "$P/PLAN.md" | head -3)" "materialize never overwrites an explicit PLAN value"

# --- decision-ready lint stages -----------------------------------------------------------
if [ -d "$PWTEST_F2/analysis/review" ]; then
  AD="$PWTEST_F2/analysis/stage-fixture.md"; RV="$PWTEST_F2/analysis/review/stage-fixture.review.md"
  cp "$PWTEST_F2/analysis/fixture.md" "$AD"
  cp "$PWTEST_F2/analysis/review/fixture.review.md" "$RV" 2>/dev/null || cp "$PWTEST_F2/_REVIEW.template.md" "$RV"
  sed -i '' -e 's|^\*\*Chosen approach:\*\*.*|**Chosen approach:** _pending your review_|' "$AD"
  awk '!/Q0/' "$RV" > "$RV.nq" && mv "$RV.nq" "$RV"
  printf '\n### Q0 · §4 — which approach should we proceed with? [PENDING]\nDecide between §4 options.\n' >> "$RV"
  pwtest_rc 1 "ready stage rejects the pending approach even with a linked Q0" "$(pwtest_script pw-doc.sh)" lint --kind analysis --project "$S2" --file stage-fixture --stage ready
  pwtest_rc 0 "reviewable stage accepts pending with a linked Q0" "$(pwtest_script pw-doc.sh)" lint --kind analysis --project "$S2" --file stage-fixture --stage reviewable
  cp "$RV" "$RV.bak"; awk '!/Q0/' "$RV.bak" > "$RV"
  pwtest_rc 1 "reviewable stage rejects pending without a linked question" "$(pwtest_script pw-doc.sh)" lint --kind analysis --project "$S2" --file stage-fixture --stage reviewable
  mv "$RV.bak" "$RV"; rm -f "$AD" "$RV"
fi
pwtest_rc 2 "missing analysis selector is still a usage error" "$(pwtest_script pw-doc.sh)" lint --kind analysis --project "$S2" --stage reviewable

# --- repair admission + completion check -------------------------------------------------
if [ -d "$PWTEST_F2/task/review" ]; then
  RR="$PWTEST_F2/task/review/T04.review.md"
  cp "$RR" "$RR.bak58"
  "$(pwtest_script pw-review.sh)" add-item --project "$S2" --file task/review/T04.review.md --section Verification --text "Repair admission fixture item." >/dev/null 2>&1 || true
  pwtest_rc 2 "repair-mode start refuses without a receipt" "$(pwtest_script pw-review.sh)" start --project "$S2" --file task/review/T04.review.md
  pwtest_err 'repair pass needs --receipt' "receipt-less start names the missing receipt"
  pwtest_fix "receipt-less start refusal names the fix"
  pwtest_rc 0 "repair start with receipt" "$(pwtest_script pw-review.sh)" start --project "$S2" --file task/review/T04.review.md --receipt r58
  pwtest_rc 0 "repair-check confirms admission" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt r58
  pwtest_rc 1 "repair-check rejects a different receipt" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt other
  # An item added INSIDE the admitted pass is ordinary feedback, not a new admission: the
  # receipt must still correlate (the latest-row-only check used to fail here).
  "$(pwtest_script pw-review.sh)" add-item --project "$S2" --file task/review/T04.review.md --section Verification --text "Item added inside the active repair pass." >/dev/null 2>&1 || true
  pwtest_rc 0 "repair-check survives an in-pass feedback item" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt r58
  # A later MACHINE row (an AI pass entry) moves the latest row off the repair row. Correlation
  # must still find the admitted receipt and refuse only a later human/approval decision.
  pwtest_rc 0 "later AI pass entry is recorded" "$(pwtest_script pw-review.sh)" start --project "$S2" --file task/review/T04.review.md --phase task-plan --pass p61 --provider kilo --model m --confirm-earlier
  pwtest_rc 0 "repair-check correlates past a later machine row" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt r58
  item="$(grep -oE '^### R[0-9]+' "$RR" | head -1 | sed 's/### //')"
  if [ -n "$item" ]; then
    before="$(shasum -a 256 "$RR" | awk '{print $1}')"
    pwtest_rc 2 "unguarded resolve is refused for a receipt-bearing repair" "$(pwtest_script pw-review.sh)" resolve --project "$S2" --file task/review/T04.review.md --item "$item" --reply "fixed"
    pwtest_eq "unguarded refusal leaves bytes unchanged" "$before" "$(shasum -a 256 "$RR" | awk '{print $1}')"
    pwtest_rc 2 "guarded resolve refuses without matching admission" "$(pwtest_script pw-review.sh)" resolve --project "$S2" --file task/review/T04.review.md --item "$item" --repair-receipt other --reply "fixed"
    pwtest_eq "refused resolution leaves bytes unchanged" "$before" "$(shasum -a 256 "$RR" | awk '{print $1}')"
    pwtest_rc 0 "guarded resolve accepts the admission receipt" "$(pwtest_script pw-review.sh)" resolve --project "$S2" --file task/review/T04.review.md --item "$item" --repair-receipt r58 --reply "fixed"
  fi
  mv "$RR.bak58" "$RR"
fi

# --- legacy/outdated project: global defaults must never leak in ---------------------------
mkdir -p "$GPD/projects/legacy"
printf -- '- **Status:** context\n- **One-liner:** legacy project\n' > "$GPD/projects/legacy/README.md"
: > "$GPD/projects/legacy/LOG.md"
pwtest_rc 0 "legacy ensure succeeds" gpd ensure --project legacy
LR="$GPD/projects/legacy/README.md"
gpd_re 'context=manual' "$(grep '^- \*\*Review Trigger:\*\*' "$LR")" "legacy project keeps manual scheduling, not the global completion default"
gpd_re 'analyst=—' "$(grep '^- \*\*AI Models:\*\*' "$LR")" "legacy project keeps unbound roles, not global model defaults"
gpd_re 'context=advisory' "$(grep '^- \*\*AI Review:\*\*' "$LR")" "legacy project keeps advisory review, not global defaults"
pwtest_rc 0 "legacy get routing without PLAN or seed" gpd get --project legacy --key routing
gpd_re 'auto' "$(cat "$PWTEST_OUT")" "legacy routing falls back to the built-in default, not the global headless value"
pwtest_rc 0 "legacy get execution-limit without PLAN or seed" gpd get --project legacy --key execution-limit
pwtest_rc 0 "legacy get max-parallel without PLAN or seed" gpd get --project legacy --key max-parallel
pwtest_rc 0 "legacy show" gpd show --project legacy
gpd_re 'built-in default' "$(cat "$PWTEST_OUT")" "legacy source is labelled built-in, not pending seed or managed global"
if grep -q 'pending PLAN seed' "$PWTEST_OUT"; then pwtest_bad "legacy get/show do not claim a pending seed" "no seed exists yet the output claims one"; else pwtest_ok "legacy get/show do not claim a pending seed"; fi
if grep -q 'pw.config.sh managed global' "$PWTEST_OUT"; then
  pwtest_bad "legacy show never cites a managed global source" "managed-global source leaked into an existing project"
else
  pwtest_ok "legacy show never cites a managed global source"
fi

# --- plan 61: complete role bindings, reset semantics, dispatch, write safety ---------------
# Public project setter accepts the documented tuning controls (the supported command used to
# reject them with "unknown option").
pwtest_rc 0 "supported project set accepts --variant" gpd set --project demo-defaults --key ai-model --set analyst=kilo:command_code/model --variant high
gpd_re 'analyst=variant:high' "$(grep '^- \*\*AI Model Tuning:\*\*' "$R")" "supported setter persists tuning"
gpd get --project demo-defaults --key ai-model --json > "$GPD/tuned.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["roles"]["analyst"]["variant"]=="high"' "$GPD/tuned.json" \
  && pwtest_ok "supported setter round-trips through structured read" \
  || pwtest_bad "supported setter round-trips through structured read" "variant missing after project set"

# A replacement without tuning resets the whole binding.
pwtest_rc 0 "untuned replacement" gpd set --project demo-defaults --key ai-model --set analyst=kilo:command_code/MiniMaxAI/MiniMax-M3
if grep '^- \*\*AI Model Tuning:\*\*' "$R" | grep -q 'analyst='; then
  pwtest_bad "replacement clears stale companion tuning" "analyst tuning survived the model replacement"
else pwtest_ok "replacement clears stale companion tuning"; fi

# Global replacement without tuning resets that role too.
gpd global set --key ai-model --set reviewer=kilo:command_code/model --variant high >/dev/null
gpd global set --key ai-model --set reviewer=kilo:command_code/MiniMaxAI/MiniMax-M3 >/dev/null
if gpd global show 2>/dev/null | grep -q 'reviewer=.*variant:high'; then
  pwtest_bad "global replacement clears stale companion tuning" "reviewer kept variant:high"
else pwtest_ok "global replacement clears stale companion tuning"; fi
gpd global unset --key ai-model >/dev/null

# Clearing a role clears its tuning too.
gpd set --project demo-defaults --key ai-model --set analyst=kilo:command_code/model --variant low >/dev/null
pwtest_rc 0 "clearing a tuned role" gpd set --project demo-defaults --key ai-model --set analyst=—
if grep -q 'analyst=' "$R" && grep '^- \*\*AI Model Tuning:\*\*' "$R" | grep -q 'analyst='; then
  pwtest_bad "clearing a role clears its tuning" "stale analyst tuning survived the clear"
else pwtest_ok "clearing a role clears its tuning"; fi

# Deprecated alias persists the same complete binding (it used to write the model and drop tuning).
pwtest_rc 0 "alias keeps tuning" gpd ai-model --project demo-defaults --set analyst=kilo:command_code/model --variant minimal
gpd_re 'analyst=variant:minimal' "$(grep '^- \*\*AI Model Tuning:\*\*' "$R")" "alias persists tuning"

# Tuning on a non-ai-model key is refused.
if gpd set --project demo-defaults --key routing --value auto --variant high >/dev/null 2>&1; then
  pwtest_bad "tuning flags are ai-model only" "routing accepted --variant"
else pwtest_ok "tuning flags are ai-model only"; fi

# Deterministic dispatch mapping: kilo variant rides the headless argument array.
pwtest_rc 0 "spawn-args json for kilo" gpd spawn-args --project demo-defaults --role analyst --json
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["supported"] is True and d["provider"]=="kilo" and d["variant"]=="minimal" and d["args"]==["-m","command_code/model","--variant","minimal"]' "$PWTEST_OUT" \
  && pwtest_ok "spawn-args carries the exact complete binding" \
  || pwtest_bad "spawn-args carries the exact complete binding" "$(cat "$PWTEST_OUT")"

# A hand-edited binding the route cannot express stops before spawn.
cp "$R" "$R.bak61"
sed -i '' -e 's|^- \*\*AI Model Tuning:\*\*.*|- **AI Model Tuning:** analyst=reasoning:low|' "$R"
if gpd spawn-args --project demo-defaults --role analyst --json >/dev/null 2>&1; then
  pwtest_bad "unbindable tuning refuses dispatch" "kilo reasoning was silently dropped"
else pwtest_ok "unbindable tuning refuses dispatch"; fi
mv "$R.bak61" "$R"

# Creation validates one inherited snapshot before publishing; an unavailable binding refuses.
gpd global set --key ai-model --set reviewer=kilo:definitely-not-a-model >/dev/null 2>&1 || true
if gpd_scaffold reject-invalid-default >/dev/null 2>&1; then
  pwtest_bad "creation refuses an unavailable inherited model" "scaffold published a project with a dead model"
else pwtest_ok "creation refuses an unavailable inherited model"; fi
[ ! -e "$GPD/projects/reject-invalid-default" ] \
  && pwtest_ok "refused creation leaves no destination" \
  || pwtest_bad "refused creation leaves no destination" "a partial project was published"
# A hand-edited global review axis is also part of the snapshot: creation refuses it.
BADAXIS="$GPD/pw.config.badaxis.sh"
printf '%s\n' 'PW_PROVIDERS=(kilo)' 'PW_PROJECT_DEFAULT_AI_REVIEW="analysis=maybe"' > "$BADAXIS"
if PW_PROJECTS_DIR="$GPD/projects" PW_PROJECTS="$GPD/projects" PW_CONFIG_FILE="$BADAXIS" "$(pwtest_script pw-config.sh)" validate-defaults >/dev/null 2>&1; then
  pwtest_bad "creation validation refuses a bad review axis" "analysis=maybe passed the gate"
else pwtest_ok "creation validation refuses a bad review axis"; fi
gpd global unset --key ai-model >/dev/null 2>&1 || true

# Unset reports the real fallback (earlier human assignment), not the removed managed value.
GPCFG2="$GPD/pw.config.sh.2"
printf '%s\n' 'PW_PROVIDERS=(kilo)' 'PW_PROJECT_DEFAULT_ROUTING="subagent"' > "$GPCFG2"
gpd2() { PW_PROJECTS_DIR="$GPD/projects" PW_PROJECTS="$GPD/projects" PW_REPOS="$GPD/repos" PW_CONFIG_FILE="$GPCFG2" "$(pwtest_script pw-config.sh)" "$@"; }
gpd2 global set --key routing --value headless >/dev/null
unset_out="$(gpd2 global unset --key routing 2>/dev/null)"
gpd_re 'subagent' "$unset_out" "unset prints the earlier human assignment"
gpd_re 'earlier pw.config.sh assignment' "$unset_out" "unset names the restored source"
pwtest_eq "next process sees the same fallback" "subagent" "$(gpd2 global get --key routing 2>/dev/null)"

# Write safety: symlink refused, mode preserved, held lock refused quickly without a write.
SYMCFG="$GPD/pw.config.symlink.sh"
ln -sf "$GPCFG2" "$SYMCFG"
if PW_PROJECTS_DIR="$GPD/projects" PW_CONFIG_FILE="$SYMCFG" "$(pwtest_script pw-config.sh)" global set --key routing --value auto >/dev/null 2>&1; then
  pwtest_bad "symlinked config refused" "the write replaced the symlink"
else pwtest_ok "symlinked config refused"; fi
[ -L "$SYMCFG" ] && pwtest_ok "symlink target preserved" || pwtest_bad "symlink target preserved" "symlink became a regular file"

MODECFG="$GPD/pw.config.mode.sh"
printf '%s\n' 'PW_PROVIDERS=(kilo)' > "$MODECFG"
chmod 640 "$MODECFG"
PW_PROJECTS_DIR="$GPD/projects" PW_CONFIG_FILE="$MODECFG" "$(pwtest_script pw-config.sh)" global set --key execution-limit --value 5 >/dev/null
mode_now="$(stat -f '%Lp' "$MODECFG" 2>/dev/null || stat -c '%a' "$MODECFG")"
pwtest_eq "write preserves the file mode" "640" "$mode_now"

mkdir -p "$GPCFG2.pwlock"
before_lock="$(shasum -a 256 "$GPCFG2" | awk '{print $1}')"
if PW_GLOBAL_LOCK_TRIES=2 PW_PROJECTS_DIR="$GPD/projects" PW_CONFIG_FILE="$GPCFG2" "$(pwtest_script pw-config.sh)" global set --key routing --value auto >/dev/null 2>&1; then
  pwtest_bad "held lock refuses the write" "a concurrent writer was overwritten"
else pwtest_ok "held lock refuses the write"; fi
rmdir "$GPCFG2.pwlock"
pwtest_eq "lock refusal leaves bytes unchanged" "$before_lock" "$(shasum -a 256 "$GPCFG2" | awk '{print $1}')"

# --- plan 61 follow-up: dispatch matrix, canonical ids, write serialization -------------------
SP="$GPD/projects/spawn-demo"; mkdir -p "$SP"
cat > "$SP/README.md" <<'MD'
# spawn demo
- **AI Models:** analyst=kilo:alibaba-token-plan/test-model writer-task=claude:sonnet reviewer=cursor:cursor-test-high verifier=codex:codex-test-luna researcher=opencode:testprov/test-model ship-comment-analyst=—
- **AI Model Tuning:** analyst=variant:high writer-task=effort:high reviewer=effort:high verifier=reasoning:high
MD
GPCFG_SP="$GPD/pw.config.spawn.sh"
cat > "$GPCFG_SP" <<'CFG'
PW_PROVIDERS=(kilo claude cursor codex opencode)
CFG
gsp() { PW_PROJECTS_DIR="$GPD/projects" PW_PROJECTS="$GPD/projects" PW_REPOS="$GPD/repos" PW_CONFIG_FILE="$GPCFG_SP" "$(pwtest_script pw-config.sh)" "$@"; }

for pair in analyst:kilocanon writer-task:claudeeffort reviewer:cursorbracket verifier:codexreason researcher:opencodeplain; do
  role="${pair%%:*}"; tag="${pair#*:}"
  pwtest_rc 0 "spawn-args $role" gsp spawn-args --project spawn-demo --role "$role" --json
  python3 - "$PWTEST_OUT" "$tag" <<'PY'
import json,sys
tag=sys.argv[2]; d=json.load(open(sys.argv[1]))
want={
 'kilocanon':['-m','kilo/alibaba-token-plan/test-model','--variant','high'],
 'claudeeffort':['--model','sonnet','--effort','high'],
 'cursorbracket':['--model','cursor-test-high[effort=high]'],
 'codexreason':['-m','codex-test-luna','-c','model_reasoning_effort=high'],
 'opencodeplain':['-m','testprov/test-model'],
}[tag]
assert d['supported'] is True and d['args']==want, (tag,d)
PY
  [ "$?" = 0 ] && pwtest_ok "spawn-args maps $tag exactly" || pwtest_bad "spawn-args maps $tag exactly" "$(cat "$PWTEST_OUT")"
done

# The mapped array reaches a real process unchanged (fake recorder, no model call).
cat > "$GPD/rec.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PW_REC_OUT"
SH
chmod +x "$GPD/rec.sh"
gsp spawn-args --project spawn-demo --role analyst --json > "$GPD/spawn-kilo.json"
python3 - "$GPD/spawn-kilo.json" "$GPD/rec.sh" "$GPD/rec.out" <<'PY'
import json,os,subprocess,sys
d=json.load(open(sys.argv[1]))
subprocess.check_call([sys.argv[2]]+d["args"], env=dict(os.environ, PW_REC_OUT=sys.argv[3]))
PY
pwtest_eq "spawn-args array reaches the provider process" "kilo/alibaba-token-plan/test-model
--variant
high" "$(tail -n +2 "$GPD/rec.out")"

# A route that cannot bind the stored control refuses before any spawn.
SU="$GPD/projects/spawn-unsupported"; mkdir -p "$SU"
printf '%s\n' '# unsupported' '- **AI Models:** ship-comment-analyst=opencode:testprov/test-model' '- **AI Model Tuning:** ship-comment-analyst=effort:high' > "$SU/README.md"
if gsp spawn-args --project spawn-unsupported --role ship-comment-analyst --json >/dev/null 2>&1; then
  pwtest_bad "unbindable route refuses dispatch" "opencode effort was dropped"
else pwtest_ok "unbindable route refuses dispatch"; fi

# A hand-edited binding naming a disabled provider also refuses before spawn.
GHOST="$GPD/projects/spawn-ghost"; mkdir -p "$GHOST"
printf '%s\n' '# ghost' '- **AI Models:** analyst=ghost:some-model' > "$GHOST/README.md"
if gsp spawn-args --project spawn-ghost --role analyst --json >/dev/null 2>&1; then
  pwtest_bad "disabled provider refuses dispatch" "ghost provider was accepted"
else pwtest_ok "disabled provider refuses dispatch"; fi

# Two synchronized writers: the per-config lock must preserve BOTH updates.
CONC="$GPD/pw.config.conc.sh"; printf '%s\n' 'PW_PROVIDERS=(kilo)' > "$CONC"
gconc() { PW_PROJECTS_DIR="$GPD/projects" PW_PROJECTS="$GPD/projects" PW_REPOS="$GPD/repos" PW_CONFIG_FILE="$CONC" "$(pwtest_script pw-config.sh)" "$@"; }
SLOW="$GPD/slow.sh"; printf '#!/bin/sh\nsleep 0.25\n' > "$SLOW"; chmod +x "$SLOW"
PW_TESTING=1 PW_GLOBAL_TEST_AFTER_STAGE="$SLOW" gconc global set --key routing --value headless >/dev/null 2>&1 &
PW_TESTING=1 PW_GLOBAL_TEST_AFTER_STAGE="$SLOW" gconc global set --key execution-limit --value 4 >/dev/null 2>&1 &
wait
pwtest_eq "concurrent writers keep routing" "headless" "$(gconc global get --key routing 2>/dev/null)"
pwtest_eq "concurrent writers keep execution-limit" "4" "$(gconc global get --key execution-limit 2>/dev/null)"

# An edit between staging and publication is observed and refused; outside bytes survive.
STALE="$GPD/pw.config.stale.sh"; printf '%s\n' 'PW_PROVIDERS=(kilo)' > "$STALE"
EDIT="$GPD/edit.sh"; cat > "$EDIT" <<'SH'
#!/bin/sh
printf '\nPW_EXTERNAL="kept"\n' >> "$1"
SH
chmod +x "$EDIT"
if PW_TESTING=1 PW_PROJECTS_DIR="$GPD/projects" PW_CONFIG_FILE="$STALE" PW_GLOBAL_TEST_AFTER_STAGE="$EDIT" \
   "$(pwtest_script pw-config.sh)" global set --key routing --value auto >/dev/null 2>&1; then
  pwtest_bad "mid-transaction edit refused" "the writer overwrote the external edit"
else pwtest_ok "mid-transaction edit refused"; fi
grep -q 'PW_EXTERNAL="kept"' "$STALE" \
  && pwtest_ok "refused write preserves the external edit" \
  || pwtest_bad "refused write preserves the external edit" "external line lost"
if grep -q 'PW_PROJECT_DEFAULT_ROUTING' "$STALE"; then
  pwtest_bad "refused write publishes no partial block" "managed routing landed"
else pwtest_ok "refused write publishes no partial block"; fi
