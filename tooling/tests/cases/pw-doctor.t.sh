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
cp -R "$TOOL/scripts" "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" "$TOOL/templates" "$TOOL/prompts" "$PW/tooling/"
cp "$REAL/pw.config.sh" "$PW/pw.config.sh"
cat >> "$PW/pw.config.sh" <<CFG
# --- test overrides: single provider, all dirs under \$FH ---
PW_PROVIDERS=(kilo)
# plan-22: a nested-BYOK-scoped allowlist exercises the catalog fetch (prefix-filter entries +
# short-form pattern matching against the tests/bin/kilo shim's provider-prefixed lines)
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

# 2) orphans: installed pw-named artifacts the bundle no longer generates must be NAMED
echo stale > "$FH/.config/kilo/command/pw-gone.md"
echo stale > "$FH/.config/kilo/agent/pw-gone.md"
mkdir -p "$FH/.kilocode/skills/pw-goneskill"
pwtest_rc 1 "orphans fail the check" env HOME="$FH" bash "$DOCTOR"
grep -q "pw-gone.md" "$PWTEST_BOTH" && grep -q "pw-goneskill" "$PWTEST_BOTH" \
  && pwtest_ok "orphan report names each orphan" \
  || pwtest_bad "orphan report names" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"

# 3) --fix removes them; check is clean again
pwtest_rc 0 "doctor --fix removes orphans" env HOME="$FH" bash "$DOCTOR" --fix
[ ! -e "$FH/.config/kilo/command/pw-gone.md" ] && [ ! -e "$FH/.config/kilo/agent/pw-gone.md" ] \
  && [ ! -e "$FH/.kilocode/skills/pw-goneskill" ] && pwtest_ok "orphan files actually gone" \
  || pwtest_bad "orphan files gone" "still present under $FH"

# 4) foreign skill root: a stale real-dir copy under ~/.agents/skills is caught + symlinked
mkdir -p "$FH/.agents/skills"
cp -R "$PW/tooling/skill/project-workflow" "$FH/.agents/skills/project-workflow"
echo "stale line" >> "$FH/.agents/skills/project-workflow/SKILL.md"
pwtest_rc 1 "stale foreign skill copy fails the check" env HOME="$FH" bash "$DOCTOR"
grep -q "foreign skill copy STALE" "$PWTEST_BOTH" \
  && pwtest_ok "foreign copy named in report" \
  || pwtest_bad "foreign copy named" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
pwtest_rc 0 "--fix resolves the foreign copy" env HOME="$FH" bash "$DOCTOR" --fix
[ -L "$FH/.agents/skills/project-workflow" ] && pwtest_ok "--fix replaced foreign copy with bundle symlink" \
  || pwtest_bad "--fix foreign symlink" "not a symlink: $FH/.agents/skills/project-workflow"

# 5) a foreign copy that MATCHES the bundle (identical real dir) stays tolerated
rm -rf "$FH/.agents/skills/project-workflow"
cp -R "$PW/tooling/skill/project-workflow" "$FH/.agents/skills/project-workflow"
pwtest_rc 0 "identical foreign copy passes (only staleness is a defect)" env HOME="$FH" bash "$DOCTOR"

# 6) strict-YAML frontmatter guard (kilo 7.8.8 regression): a canonical source with an
# unquoted flow-leading `args:` is NAMED (manual fix) and --fix must NOT report success —
# the doctor never rewrites canonical sources. Restoring the source returns to clean.
sed -i '' 's#^args: .*#args: [--fix | --project <slug> [--fix]]#' "$PW/tooling/commands/pw-doctor.md"
pwtest_rc 1 "canonical flow-leading args fails the check" env HOME="$FH" bash "$DOCTOR"
grep -q "canonical tooling/commands/pw-doctor.md" "$PWTEST_BOTH" && grep -q "quote it" "$PWTEST_BOTH" \
  && pwtest_ok "canonical frontmatter issue is named with the fix" \
  || pwtest_bad "canonical frontmatter issue named" "$(grep '✗' "$PWTEST_BOTH" | tr '\n' ' ')"
pwtest_rc 1 "doctor --fix cannot silently clear a canonical issue" env HOME="$FH" bash "$DOCTOR" --fix
grep -q "need a hand fix" "$PWTEST_BOTH" \
  && pwtest_ok "--fix output points at the manual canonical fix" \
  || pwtest_bad "--fix manual note" "$(tail -2 "$PWTEST_BOTH" | tr '\n' ' ')"
cp "$TOOL/commands/pw-doctor.md" "$PW/tooling/commands/pw-doctor.md"
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

rm -rf "$DOCDIR"
