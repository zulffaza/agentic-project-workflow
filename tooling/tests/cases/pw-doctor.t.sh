# shellcheck shell=bash
# cases/pw-doctor.t.sh — doctor's BIDIRECTIONAL sync: orphan detection (commands/agents/skills)
# and stale foreign skill-root copies (plan 20 follow-up: a stale ~/.agents/skills real-dir copy
# shadowed the fresh bundle symlink while doctor said "All synced"). Runs against a copied
# tooling skeleton + fake HOME — never the real provider installs. Also covers the request-review
# user-file checks (frame + generation prompts) and the legacy template migration.
DOCDIR="$(mktemp -d "${TMPDIR:-/tmp}/pwdoc.XXXXXX")"
REAL="$TOOL/.."
PW="$DOCDIR/bundle"; FH="$DOCDIR/home"
mkdir -p "$PW/tooling" "$FH"
cp -R "$TOOL/scripts" "$TOOL/skills" "$TOOL/agents" "$TOOL/templates" "$TOOL/prompts" "$PW/tooling/"
cp "$REAL/offboard.sh" "$PW/offboard.sh"
cp "$REAL/pw.config.sh" "$PW/pw.config.sh"
cat >> "$PW/pw.config.sh" <<CFG
# --- test overrides: two providers (kilo = file commands; codex = SKILL-layout commands),
# all dirs under \$FH ---
PW_PROVIDERS=(kilo codex claude)
# plan-22: a nested-BYOK-scoped allowlist exercises the catalog fetch (prefix-filter entries +
# short-form pattern matching against the tests/bin/kilo shim's provider-prefixed lines).
# The API-provider scope is PINNED here (hermetic): the machine's real config may narrow
# PW_KILO_API_PROVIDERS to a different BYOK (for example cliproxyapi), which would filter the
# shim's kilo/alibaba-token-plan/... lines out and make the assertion below unsatisfiable.
PW_KILO_API_PROVIDERS=(kilo alibaba-token-plan)
PW_MODEL_ALLOWLIST_KILO="alibaba-token-plan/*"
kilo_commanddir() { echo "$FH/.config/kilo/command"; }
kilo_skilldir()   { echo "$FH/.kilocode/skills"; }
kilo_agentdir()   { echo "$FH/.config/kilo/agent"; }
CFG
printf 'export PW_HOME="%s"\nexport PW_PROJECTS="%s"\nexport PW_REPOS="%s"\n' \
  "$PW" "$FH/projects" "$FH/repos" > "$PW/pw-env.sh"
DOCTOR="$PW/tooling/scripts/toolchain/pw-doctor.sh"

# 1) --fix on a bare fake HOME installs everything; a follow-up check must be clean
pwtest_rc 0 "doctor --fix installs a bare provider surface" env HOME="$FH" bash "$DOCTOR" --fix
# skill-layout provider (codex entries ARE skill dirs in ONE root): a shipped shared skill
# (pw-guide-workflow) must be installed there and must NOT be swept as an orphan entry by the
# same --fix (regression: the orphan pass deleted a same-root plain skill).
[ -e "$FH/.codex/skills/pw-guide-workflow" ] \
  && pwtest_ok "skill-layout provider carries the shared skill after --fix" \
  || pwtest_bad "skill-layout shared skill survives --fix" "missing $FH/.codex/skills/pw-guide-workflow"
# 1b) exclusive formats: bundle-generated residue in the OTHER format still loads, so the
# doctor names it and --fix removes it. The skill-format side (a) is the unique catcher: no other
# pass looks in the flat command dir. The command-format side (b) also covers the inverse.
mkdir -p "$FH/.claude/commands"
printf '<!-- pw-generated: build artifact -->\n' > "$FH/.claude/commands/pw-execute.md"
pwtest_rc 1 "skill-format wrong-format residue fails the check" env HOME="$FH" bash "$DOCTOR"
pwtest_rc 0 "--fix removes the flat residue for a skill-format provider" env HOME="$FH" bash "$DOCTOR" --fix
[ ! -e "$FH/.claude/commands/pw-execute.md" ] \
  && pwtest_ok "flat residue removed for claude" \
  || pwtest_bad "wrong-format cleanup (skill)" "residue remains after --fix"
[ -f "$FH/.claude/skills/pw-execute/SKILL.md" ] && pwtest_ok "claude entry skill kept" \
  || pwtest_bad "claude entry skill" "missing after wrong-format cleanup"
mkdir -p "$FH/.kilocode/skills/pw-execute"
printf '<!-- pw-generated: build artifact -->\n' > "$FH/.kilocode/skills/pw-execute/SKILL.md"
pwtest_rc 1 "command-format wrong-format residue fails the check" env HOME="$FH" bash "$DOCTOR"
pwtest_rc 0 "--fix removes the skill residue for a command-format provider" env HOME="$FH" bash "$DOCTOR" --fix
[ ! -e "$FH/.kilocode/skills/pw-execute" ] \
  && pwtest_ok "skill residue removed for kilo" \
  || pwtest_bad "wrong-format cleanup (command)" "residue remains after --fix"
[ -f "$FH/.config/kilo/command/pw-execute.md" ] && pwtest_ok "kilo entry command kept" \
  || pwtest_bad "kilo entry command" "missing after wrong-format cleanup"

pwtest_rc 0 "doctor clean after fix" env HOME="$FH" bash "$DOCTOR"
# plan-22: catalog fetched ONCE and filtered locally (entries are prefix filters, never `kilo
# models` args — the shim errors on slash args, pinning that), allowlist patterns validated
# against the provider-prefixed lines (short form), and the session-liveness surface reachable.
grep -qE 'model allowlist "alibaba-token-plan/\*": [1-9][0-9]* match\(es\) in the live catalog' "$PWTEST_OUT" \
  && pwtest_ok "allowlist validated against nested-BYOK catalog lines" \
  || pwtest_bad "allowlist validation" "$(grep -a 'model allowlist' "$PWTEST_OUT" | head -2 | tr '\n' ' ')"
grep -qa "can't check" "$PWTEST_OUT" \
  && pwtest_bad "doctor must not skip the check for slash entries" "$(grep -a "can't check" "$PWTEST_OUT" | head -1)" \
  || pwtest_ok "no silent 'can't check' with a slash-scoped entry"
grep -qE 'session liveness: kilo surface reachable' "$PWTEST_OUT" \
  && pwtest_ok "session-liveness probe row present + reachable" \
  || pwtest_bad "session liveness row" "$(grep -a 'session liveness' "$PWTEST_OUT" | head -1)"

# 2) orphans: installed pw-named artifacts the bundle no longer generates must be NAMED.
#    --fix removes ONLY bundle-generated residue (the generator marker appended to every
#    rendered artifact); a foreign/hand-made file sharing the namespace is reported + SKIPPED,
#    never deleted (content-check-and-skip).
echo stale > "$FH/.config/kilo/command/pw-gone.md"
echo stale > "$FH/.config/kilo/agent/pw-gone.md"
mkdir -p "$FH/.kilocode/skills/pw-goneskill"
printf 'stale\n<!-- pw-generated: build artifact — regenerate with /pw-doctor --fix; never hand-edit -->\n' > "$FH/.config/kilo/command/pw-marked-gone.md"
mkdir -p "$FH/.kilocode/skills/pw-markedskill"
printf 'stale\n<!-- pw-generated: build artifact — regenerate with /pw-doctor --fix; never hand-edit -->\n' > "$FH/.kilocode/skills/pw-markedskill/SKILL.md"
pwtest_rc 1 "orphans fail the check" env HOME="$FH" bash "$DOCTOR"
grep -q "pw-gone.md" "$PWTEST_BOTH" && grep -q "pw-goneskill" "$PWTEST_BOTH" \
  && pwtest_ok "orphan report names each orphan" \
  || pwtest_bad "orphan report names" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"

# 3) --fix removes the MARKED residue; unmarked entries are reported and skipped.
pwtest_rc 0 "doctor --fix removes marked orphans and keeps foreign ones" env HOME="$FH" bash "$DOCTOR" --fix
[ ! -e "$FH/.config/kilo/command/pw-marked-gone.md" ] && [ ! -e "$FH/.kilocode/skills/pw-markedskill" ] \
  && pwtest_ok "marked orphans removed" \
  || pwtest_bad "marked orphans" "marked residue still present"
grep -q "SKIPPED 'pw-gone.md'" "$PWTEST_BOTH" \
  && pwtest_ok "foreign orphan skipped by name" \
  || pwtest_bad "foreign skip report" "$(grep -a SKIPPED "$PWTEST_BOTH" | head -2 | tr '\n' ' ')"
[ -e "$FH/.config/kilo/command/pw-gone.md" ] && [ -e "$FH/.config/kilo/agent/pw-gone.md" ] && [ -e "$FH/.kilocode/skills/pw-goneskill" ] \
  && pwtest_ok "foreign orphans left in place" \
  || pwtest_bad "foreign orphans" "a foreign orphan was deleted"
# check-only re-run keeps the skipped orphan as a live finding (never silently clean).
pwtest_rc 1 "a skipped orphan still fails a check-only re-run" env HOME="$FH" bash "$DOCTOR"
grep -q "pw-goneskill" "$PWTEST_BOTH" \
  && pwtest_ok "skipped orphan still named on re-run" \
  || pwtest_bad "skipped orphan re-run" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
# The skipped foreign entries are the operator's call — clear them by hand here so the rest of
# the case can reach a clean state (nothing in the harness deletes unmarked entries anymore).
rm -rf "$FH/.config/kilo/command/pw-gone.md" "$FH/.config/kilo/agent/pw-gone.md" "$FH/.kilocode/skills/pw-goneskill"

# 4) foreign skill root: a stale real-dir copy under ~/.agents/skills is caught + symlinked
mkdir -p "$FH/.agents/skills"
cp -R "$PW/tooling/skills/model/pw-guide-workflow" "$FH/.agents/skills/pw-guide-workflow"
echo "stale line" >> "$FH/.agents/skills/pw-guide-workflow/SKILL.md"
pwtest_rc 1 "stale foreign skill copy fails the check" env HOME="$FH" bash "$DOCTOR"
grep -q "foreign skill copy STALE" "$PWTEST_BOTH" \
  && pwtest_ok "foreign copy named in report" \
  || pwtest_bad "foreign copy named" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
pwtest_rc 0 "--fix resolves the foreign copy" env HOME="$FH" bash "$DOCTOR" --fix
[ -L "$FH/.agents/skills/pw-guide-workflow" ] && pwtest_ok "--fix replaced foreign copy with bundle symlink" \
  || pwtest_bad "--fix foreign symlink" "not a symlink: $FH/.agents/skills/pw-guide-workflow"

# 5) a foreign copy that MATCHES the bundle (identical real dir) stays tolerated
rm -rf "$FH/.agents/skills/pw-guide-workflow"
cp -R "$PW/tooling/skills/model/pw-guide-workflow" "$FH/.agents/skills/pw-guide-workflow"
pwtest_rc 0 "identical foreign copy passes (only staleness is a defect)" env HOME="$FH" bash "$DOCTOR"

# 5b) a dangling legacy link into a retired bundle layout (older checkout/worktree) is bundle
# residue, not a foreign skill: the doctor names it and --fix removes it.
mkdir -p "$FH/.kilocode/skills"
ln -s "$DOCDIR/old/tooling/skill/project-workflow" "$FH/.kilocode/skills/project-workflow"
pwtest_rc 1 "dangling legacy bundle link fails the check" env HOME="$FH" bash "$DOCTOR"
pwtest_rc 0 "--fix removes the dangling legacy link" env HOME="$FH" bash "$DOCTOR" --fix
[ ! -L "$FH/.kilocode/skills/project-workflow" ] \
  && pwtest_ok "dangling legacy link removed" \
  || pwtest_bad "legacy link removal" "still present: $FH/.kilocode/skills/project-workflow"

# 6) strict-YAML frontmatter guard (kilo 7.8.8 regression): a canonical source with an
# unquoted flow-leading `args:` is NAMED (manual fix) and --fix must NOT report success —
# the doctor never rewrites canonical sources. Restoring the source returns to clean.
sed -i '' 's#^args: .*#args: [--fix | --project <slug> [--fix]]#' "$PW/tooling/skills/human/pw-doctor/SKILL.md"
pwtest_rc 1 "canonical flow-leading args fails the check" env HOME="$FH" bash "$DOCTOR"
grep -q "canonical tooling/skills/human/pw-doctor/SKILL.md" "$PWTEST_BOTH" && grep -q "quote it" "$PWTEST_BOTH" \
  && pwtest_ok "canonical frontmatter issue is named with the fix" \
  || pwtest_bad "canonical frontmatter issue named" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
pwtest_rc 1 "doctor --fix cannot silently clear a canonical issue" env HOME="$FH" bash "$DOCTOR" --fix
grep -q "need a hand fix" "$PWTEST_BOTH" \
  && pwtest_ok "--fix output points at the manual canonical fix" \
  || pwtest_bad "--fix manual note" "$(tail -2 "$PWTEST_BOTH" | tr '\n' ' ')"
cp "$TOOL/skills/human/pw-doctor/SKILL.md" "$PW/tooling/skills/human/pw-doctor/SKILL.md"
pwtest_rc 0 "restored canonical source returns to clean" env HOME="$FH" bash "$DOCTOR" --fix

# 7) request-review user files: --fix seeds the new default frame + both prompts; a
# customized file is never overwritten; custom paths are reported, never created. The harness
# exports a custom template path, so these runs clear the review-request settings to default.
doctordef() { env HOME="$FH" PW_REVIEW_REQUEST_TEMPLATE_FILE= PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE= \
  PW_REVIEW_REQUEST_NOTE_PROMPT_FILE= bash "$DOCTOR" "$@"; }
pwtest_rc 0 "--fix seeds the default frame and prompts" doctordef --fix
[ -f "$PW/user/templates/review-request.md" ] && pwtest_ok "--fix seeded the default frame under user/templates/" \
  || pwtest_bad "--fix seeded the default frame" "missing $PW/user/templates/review-request.md"
[ -f "$PW/user/prompts/review-request-summary.md" ] && pwtest_ok "--fix seeded the default summary prompt" \
  || pwtest_bad "--fix seeded the summary prompt" "missing $PW/user/prompts/review-request-summary.md"
[ -f "$PW/user/prompts/review-request-note.md" ] && pwtest_ok "--fix seeded the default note prompt" \
  || pwtest_bad "--fix seeded the note prompt" "missing $PW/user/prompts/review-request-note.md"
printf 'customized summary prompt\n' > "$PW/user/prompts/review-request-summary.md"
pwtest_rc 0 "a customized prompt passes the health check" doctordef
pwtest_eq "doctor never overwrites a customized prompt" 'customized summary prompt' \
  "$(cat "$PW/user/prompts/review-request-summary.md")"

# 8) legacy template migration: when the new default is absent, a readable legacy copy migrates
# byte-for-byte; an invalid (empty) new frame is a manual finding (never reseeded over).
rm -f "$PW/user/templates/review-request.md"
mkdir -p "$PW/user-templates"
printf 'legacy frame with my layout\n' > "$PW/user-templates/review-request.md"
pwtest_rc 1 "missing new default with a readable legacy file fails the check (pending migration)" doctordef
pwtest_rc 0 "--fix migrates the legacy frame byte-for-byte" doctordef --fix
pwtest_eq "migrated frame keeps the legacy customization" 'legacy frame with my layout' \
  "$(cat "$PW/user/templates/review-request.md")"
[ -f "$PW/user-templates/review-request.md" ] && pwtest_ok "legacy file is kept for rollback" \
  || pwtest_bad "legacy file kept" "legacy file gone"
printf '' > "$PW/user/templates/review-request.md"
pwtest_rc 1 "an invalid default frame is a manual finding (never reseeded over)" doctordef --fix
pwtest_eq "--fix preserves an existing invalid frame" '' "$(cat "$PW/user/templates/review-request.md")"
rm -f "$PW/user/templates/review-request.md"
pwtest_rc 1 "check-only reports a missing custom prompt path without creating it" \
  env HOME="$FH" PW_REVIEW_REQUEST_TEMPLATE_FILE= PW_REVIEW_REQUEST_NOTE_PROMPT_FILE="$FH/custom-note.md" bash "$DOCTOR"
grep -q 'review prompt (note)' "$PWTEST_BOTH" && pwtest_ok "doctor names the missing custom note prompt" \
  || pwtest_bad "doctor names the custom note prompt" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
[ ! -e "$FH/custom-note.md" ] && pwtest_ok "doctor never creates a custom prompt path" \
  || pwtest_bad "doctor never creates a custom prompt path" "file created"
pwtest_rc 0 "doctor --fix re-migrates the frame for a clean final check" doctordef --fix
cp "$TOOL/templates/review-request.md" "$PW/user/templates/review-request.md"
pwtest_rc 0 "doctor checks prompt health even when providers are synchronized" \
  env HOME="$FH" PW_REVIEW_REQUEST_TEMPLATE_FILE= PW_REVIEW_REQUEST_NOTE_PROMPT_FILE="$PW/user/prompts/review-request-note.md" bash "$DOCTOR"
grep -q 'review prompt (summary)' "$PWTEST_BOTH" && pwtest_ok "doctor reports both effective prompt paths" \
  || pwtest_bad "doctor reports both effective prompt paths" "$(grep 'review prompt' "$PWTEST_BOTH" | tr '\n' ' ')"

# 9) hook-dir assert: a provider hook returning an empty/relative path is a hard config error
# (never rm/ln against '/name'); and the pw-env.sh rewrite refuses shell-special paths.
cat > "$DOCDIR/badprov.config.sh" <<CFG
PW_PROVIDERS=(badprov)
badprov_bin() { echo "true"; }
badprov_skilldir() { echo ""; }
badprov_commanddir() { echo "\$HOME/.config/badprov/command"; }
badprov_agentdir() { echo "\$HOME/.config/badprov/agent"; }
render_badprov_command() { :; }
CFG
pwtest_rc 2 "doctor refuses an empty hook dir (never '/name')" \
  env HOME="$FH" PW_CONFIG_FILE="$DOCDIR/badprov.config.sh" PW_PROJECTS="$FH/projects" PW_REPOS="$FH/repos" bash "$DOCTOR"
pwtest_err "unsafe path" "hook-dir assert names the problem"

printf 'export PW_HOME="/wrong"\n' > "$PW/pw-env.sh"
pwtest_rc 0 "doctor --fix reports the stale pw-env.sh" env HOME="$FH" bash "$DOCTOR" --fix
grep -q 'pw-env.sh is stale' "$PWTEST_BOTH" && pwtest_ok "stale pw-env.sh detected" || pwtest_bad "pw-env detect" "$(grep -a pw-env "$PWTEST_BOTH" | head -1)"
printf 'export PW_HOME="/wrong"\n' > "$PW/pw-env.sh"
pwtest_rc 0 "doctor --fix refuses to rewrite pw-env.sh for shell-special paths" \
  env HOME="$FH" PW_PROJECTS="x\`y" bash "$DOCTOR" --fix
grep -q 'REFUSED: rewrite' "$PWTEST_BOTH" && pwtest_ok "env rewrite refused" || pwtest_bad "env rewrite guard" "$(grep -a pw-env "$PWTEST_BOTH" | head -1)"
grep -q '^export PW_HOME="/wrong"$' "$PW/pw-env.sh" && pwtest_ok "unsafe env file left untouched" || pwtest_bad "env purity" "file rewritten despite refusal"
pwtest_rc 0 "doctor --fix rewrites pw-env.sh once the path is plain" env HOME="$FH" bash "$DOCTOR" --fix
PW_NORM="$(cd "$PW" && pwd)"
pwtest_eq "env restored to the real bundle path" "$PW_NORM" "$(sed -n 's/^export PW_HOME="\(.*\)"$/\1/p' "$PW/pw-env.sh")"

# 10) offboard dry-run: a hand-edited directory COPY of a skill is reported + skipped; only a
# whole-tree match is queued for removal (tree content-check, not SKILL.md alone).
rm -f "$FH/.kilocode/skills/pw-guide-workflow"
cp -R "$PW/tooling/skills/model/pw-guide-workflow" "$FH/.kilocode/skills/pw-guide-workflow"
printf 'my extra notes\n' > "$FH/.kilocode/skills/pw-guide-workflow/EXTRA.md"
pwtest_rc 0 "offboard dry-run covers the hand-edited copy" env HOME="$FH" bash "$PW/offboard.sh"
grep -q 'not touching it' "$PWTEST_BOTH" \
  && pwtest_ok "hand-edited skill copy skipped" \
  || pwtest_bad "offboard tree check" "$(grep -a 'pw-guide-workflow' "$PWTEST_BOTH" | head -2 | tr '\n' ' ')"
rm -f "$FH/.kilocode/skills/pw-guide-workflow/EXTRA.md"
pwtest_rc 0 "offboard dry-run queues the identical copy" env HOME="$FH" bash "$PW/offboard.sh"
grep -q 'remove directory copy' "$PWTEST_BOTH" \
  && pwtest_ok "identical tree copy queued for removal" \
  || pwtest_bad "offboard identical copy" "$(grep -a 'pw-guide-workflow' "$PWTEST_BOTH" | head -2 | tr '\n' ' ')"

rm -rf "$DOCDIR"
