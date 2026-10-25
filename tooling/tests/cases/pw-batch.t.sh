# shellcheck shell=bash
# cases/pw-batch.t.sh — /pw-batch coordination entry (plan 59): closed allowlist, literal
# payload framing, explicit human decisions, stop-first reporting, help discoverability,
# and exclusive provider delivery. The entry has NO entity script; these checks pin the
# contract text, the help surface, and the absence of a second mutation engine.
C="$(pwtest_script pw-help.sh)"
TOOLDIR="${TOOL:-$PWTEST_TOOLING_DIR}"
B="$TOOLDIR/skills/human/pw-batch/SKILL.md"
R="$TOOLDIR/skills/model/pw-guide-workflow/references/batch.md"

# 1) canonical entry: frontmatter, orchestration load, reference pointer, no script
[ -f "$B" ] && pwtest_ok "pw-batch human entry exists" || pwtest_bad "entry" "missing $B"
pwtest_grep_file '^name: pw-batch$' "entry name" "$B"
pwtest_grep_file '^scope: mixed$' "entry scope mixed" "$B"
pwtest_grep_file '^scope-forms: ".*preview=global' "entry classifies preview globally" "$B"
pwtest_grep_file '^scope-forms: ".*=project' "entry classifies the project selector" "$B"
pwtest_grep_file '`pw-orchestration`' "entry loads shared orchestration rules" "$B"
pwtest_grep_file 'references/batch.md' "entry points at the batch reference" "$B"
[ -f "$R" ] && pwtest_ok "batch reference exists" || pwtest_bad "reference" "missing $R"
[ -f "$TOOLDIR/scripts/entities/pw-batch.sh" ] \
  && pwtest_bad "no second mutation engine" "pw-batch.sh must not exist (coordination only)" \
  || pwtest_ok "no pw-batch.sh entity script"
grep -qF 'pw-batch.sh' "$B" \
  && pwtest_bad "no fabricated helper" "the entry names a pw-batch.sh helper" \
  || pwtest_ok "entry names no fabricated helper"

# 2) allowlist block: present, complete, and pointed at real commands
grep -qF '<!-- batch-ops:begin -->' "$B" && pwtest_ok "allowlist begin marker" || pwtest_bad "allowlist begin" "missing"
grep -qF '<!-- batch-ops:end -->' "$B" && pwtest_ok "allowlist end marker" || pwtest_bad "allowlist end" "missing"
OPS="$(awk '/<!-- batch-ops:begin -->/{on=1;next} /<!-- batch-ops:end -->/{on=0} on' "$B")"
[ -n "$OPS" ] && pwtest_ok "allowlist block is non-empty" || pwtest_bad "allowlist" "empty block"
for _need in '/pw-context' '/pw-review' '/pw-config' '/pw-status' '/pw-help' '/pw-doctor' '/pw-ship stack'; do
  printf '%s' "$OPS" | grep -qF "$_need" && pwtest_ok "allowlist owner $_need" || pwtest_bad "allowlist owner" "missing $_need"
done
for _op in req-init add-input add-repo init init-all item answer signoff model-check '--all' '--guidance' stack '/pw-ship ready' '/pw-ship draft' '--draft'; do
  printf '%s' "$OPS" | grep -qF -- "$_op" && pwtest_ok "allowlist form $_op" || pwtest_bad "allowlist form" "missing $_op"
done
printf '%s' "$OPS" | grep -qF 'Refused forms include' \
  && pwtest_ok "allowlist states the refused forms" || pwtest_bad "refusals" "Refused forms line missing"
printf '%s' "$OPS" | grep -qF 'concrete publication confirmation' \
  && pwtest_ok "shipment retains concrete publication confirmation" || pwtest_bad "shipment confirmation" "missing"
printf '%s' "$OPS" | grep -qF 'readiness apply must carry the token' \
  && pwtest_ok "readiness apply is token-bound" || pwtest_bad "readiness token" "missing"
for _bad in prepare import auto-signoff materialize model-resolve '--fix' '--apply' 'stack adopt' update rewind; do
  printf '%s' "$OPS" | grep -qF -- "$_bad" && pwtest_ok "excluded form named: $_bad" || pwtest_bad "exclusions" "missing $_bad"
done
_rows="$(printf '%s\n' "$OPS" | sed -n 's/^| `\(\/pw-[a-z-]*\).*/\1/p' | sort -u)"
[ "$(printf '%s\n' "$_rows" | grep -c .)" -ge 7 ] \
  && pwtest_ok "allowlist names at least seven owning commands" \
  || pwtest_bad "allowlist rows" "expected >=7 command rows, got: $(printf '%s' "$_rows" | tr '\n' ' ')"
for _c in $_rows; do
  [ -d "$TOOLDIR/skills/human/${_c#/}" ] && pwtest_ok "allowlist owner exists: $_c" || pwtest_bad "allowlist owner" "$_c is not a canonical entry"
done

# 3) non-negotiable contract anchors (mutations C354-C357 pin these)
for _anchor in \
  'Never infer approval from resolved comments' \
  'On failure, refusal, or uncertainty, stop.' \
  'Preview writes nothing.' \
  'No implicit repair.' \
  'no continue-on-error, rollback claim, or automatic replay'; do
  grep -qF "$_anchor" "$B" && pwtest_ok "contract anchor: $_anchor" || pwtest_bad "contract anchor" "missing: $_anchor"
done

# 4) reference procedure: literal framing, ordering, stop/recovery, prohibitions
for _anchor in \
  'The item header ends with `--stdin`' \
  'De-indent by the opening fence' \
  'Structural validation covers the whole list' \
  'Semantic validation stays with the owning helper' \
  'Run each item in order' \
  'Never replay the whole list after an interruption' \
  'No arbitrary shell' \
  'No new script'; do
  grep -qF "$_anchor" "$R" && pwtest_ok "reference anchor: $_anchor" || pwtest_bad "reference anchor" "missing: $_anchor"
done

# 5) help discovery and rendering
pwtest_rc 0 "overview renders" "$C" overview
grep -qF '/pw-batch' "$PWTEST_OUT" && pwtest_ok "overview lists pw-batch" || pwtest_bad "overview" "pw-batch absent"
pwtest_rc 0 "command how-to renders" "$C" command --name pw-batch
for _h in 'Supported operations in this first release' '| `/pw-review` |' '| `/pw-config global` |' 'Refused forms include' 'completed writes remain, with no rollback or automatic replay' 'A `signoff` item records a decision only when it names the review file and decision' 'Literal review text ends the item with `--stdin`' 'Not batch items: `pw-new`, `pw-adopt`' 'Later candidates: status update, review packet prepare/import' '$ /pw-batch preview --project <project-slug>' '$ /pw-batch apply --project <project-slug>'; do
  grep -qF "$_h" "$PWTEST_OUT" && pwtest_ok "help renders: $_h" || pwtest_bad "help render" "missing: $_h"
done
pwtest_rc 0 "command --json renders" "$C" command --name pw-batch --json
python3 - "$PWTEST_OUT" <<'PYBP' && pwtest_ok "help json: mixed scope, two global modes, no fabricated facet" || pwtest_bad "help json" "shape"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cmd"] == "pw-batch", d.get("cmd")
assert d["scope"] == "mixed", d.get("scope")
ops = {o["name"]: o for o in d["ops"]}
assert set(ops) == {"preview", "apply"}, sorted(ops)
assert all(o["scope"] == "global" for o in ops.values()), ops
assert all(o["facet"] == "" for o in ops.values()), ops
assert d["scripts"] == [], d.get("scripts")
PYBP
pwtest_rc 0 "find locates the batch surface" "$C" find --term batch
grep -qF 'skills/human/pw-batch/SKILL.md' "$PWTEST_OUT" \
  && pwtest_ok "find names the batch entry" || pwtest_bad "find" "entry path absent"

# project view: global modes never receive the project selector
BX=batchp; rm -rf "$PW_PROJECTS_DIR/$BX"; cp -a "$F2" "$PW_PROJECTS_DIR/$BX"
pwtest_rc 0 "project view renders" "$C" project --project "$BX" --name pw-batch
grep -qF 'global forms (no project)' "$PWTEST_OUT" \
  && pwtest_ok "project view keeps the global footer" || pwtest_bad "project view" "missing global footer"
grep -qF '/pw-batch preview --project' "$PWTEST_OUT" \
  && pwtest_bad "project injection" "global preview got the project flag" \
  || pwtest_ok "project view does not inject the project into global forms"

# 6) provider delivery: exactly one artifact per provider, in its exclusive format
GEN="$PWTEST_ROOT/batchgen"
"$TOOLDIR/scripts/toolchain/gen-commands.sh" --outdir "$GEN" claude cursor codex kilo opencode >/dev/null 2>&1
for _p in claude cursor codex; do
  [ -f "$GEN/$_p/pw-batch/SKILL.md" ] && pwtest_ok "$_p installs pw-batch as a skill" || pwtest_bad "$_p batch entry" "skill dir missing"
  [ ! -e "$GEN/$_p/pw-batch.md" ] && pwtest_ok "$_p has no command-format duplicate" || pwtest_bad "$_p duplicate" "pw-batch.md also emitted"
  if [ "$_p" = codex ]; then
    grep -qF 'allow_implicit_invocation: false' "$GEN/$_p/pw-batch/agents/openai.yaml" \
      && pwtest_ok "$_p pw-batch is explicit-only" || pwtest_bad "$_p explicit-only" "policy missing"
  else
    grep -qF 'disable-model-invocation: true' "$GEN/$_p/pw-batch/SKILL.md" \
      && pwtest_ok "$_p pw-batch is explicit-only" || pwtest_bad "$_p explicit-only" "policy missing"
  fi
done
for _p in kilo opencode; do
  [ -f "$GEN/$_p/pw-batch.md" ] && pwtest_ok "$_p installs pw-batch as a command" || pwtest_bad "$_p batch entry" "command file missing"
  [ ! -d "$GEN/$_p/pw-batch" ] && pwtest_ok "$_p has no skill-format duplicate" || pwtest_bad "$_p duplicate" "skill dir also emitted"
done
_seen=0
for _p in claude cursor codex; do [ -e "$GEN/$_p/pw-batch/SKILL.md" ] && _seen=$((_seen+1)); [ -e "$GEN/$_p/pw-batch.md" ] && _seen=$((_seen+1)); done
for _p in kilo opencode; do [ -e "$GEN/$_p/pw-batch.md" ] && _seen=$((_seen+1)); [ -e "$GEN/$_p/pw-batch/SKILL.md" ] && _seen=$((_seen+1)); done
pwtest_eq "each provider exposes the batch entry exactly once" "5" "$_seen"
