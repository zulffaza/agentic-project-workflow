# shellcheck shell=bash
# cases/pw-project-defaults.t.sh — global project defaults, creation-time snapshots, role-model
# tuning, decision-ready lint stages, and the repair-admission guard (plan 58).

GPD="$ROOT/project-defaults"
rm -rf "$GPD"; mkdir -p "$GPD/projects"
GPCFG="$GPD/pw.config.sh"
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

# --- creation snapshot: new project inherits, existing is untouched ------------------------
pwtest_rc 0 "scaffold inherits global defaults" gpd_scaffold demo-defaults
R="$GPD/projects/demo-defaults/README.md"
gpd_re 'analyst=kilo:command_code/model' "$(grep '^- \*\*AI Models:\*\*' "$R")" "dashboard inherits the tuned role"
gpd_re 'analyst=variant:high' "$(grep '^- \*\*AI Model Tuning:\*\*' "$R")" "dashboard inherits companion tuning"
gpd_re 'analysis=completion' "$(grep '^- \*\*Review Trigger:\*\*' "$R")" "dashboard inherits review trigger"
gpd_re 'ship=manual' "$(grep '^- \*\*Review Trigger:\*\*' "$R")" "dashboard keeps named review-trigger member"
gpd_re 'routing=headless' "$(grep '^- \*\*Project Defaults:\*\*' "$R")" "dashboard captures the PLAN seed"
pwtest_rc 0 "project ai-model json" gpd get --project demo-defaults --key ai-model --json
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["roles"]["analyst"]["tuning"]=="variant:high" and d["roles"]["analyst"]["model"]=="command_code/model"' "$PWTEST_OUT" \
  && pwtest_ok "structured read keeps the complete binding" \
  || pwtest_bad "structured read keeps the complete binding" "$(head -c 200 "$PWTEST_OUT")"
pwtest_eq "plain read stays role=model compatible" "researcher=— analyst=kilo:command_code/model writer-task=— reviewer=— verifier=—" \
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
  pwtest_rc 0 "repair start with receipt" "$(pwtest_script pw-review.sh)" start --project "$S2" --file task/review/T04.review.md --receipt r58
  pwtest_rc 0 "repair-check confirms admission" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt r58
  pwtest_rc 1 "repair-check rejects a different receipt" "$(pwtest_script pw-review.sh)" repair-check --project "$S2" --file task/review/T04.review.md --receipt other
  item="$(grep -oE '^### R[0-9]+' "$RR" | head -1 | sed 's/### //')"
  if [ -n "$item" ]; then
    before="$(shasum -a 256 "$RR" | awk '{print $1}')"
    pwtest_rc 2 "guarded resolve refuses without matching admission" "$(pwtest_script pw-review.sh)" resolve --project "$S2" --file task/review/T04.review.md --item "$item" --repair-receipt other --reply "fixed"
    pwtest_eq "refused resolution leaves bytes unchanged" "$before" "$(shasum -a 256 "$RR" | awk '{print $1}')"
    pwtest_rc 0 "guarded resolve accepts the admission receipt" "$(pwtest_script pw-review.sh)" resolve --project "$S2" --file task/review/T04.review.md --item "$item" --repair-receipt r58 --reply "fixed"
  fi
  mv "$RR.bak58" "$RR"
fi
