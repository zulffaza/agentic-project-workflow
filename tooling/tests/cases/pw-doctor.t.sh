# shellcheck shell=bash
# cases/pw-doctor.t.sh — doctor's BIDIRECTIONAL sync: orphan detection (commands/agents/skills)
# and stale foreign skill-root copies (plan 20 follow-up: a stale ~/.agents/skills real-dir copy
# shadowed the fresh bundle symlink while doctor said "All synced"). Runs against a copied
# tooling skeleton + fake HOME — never the real provider installs.
DOCDIR="$(mktemp -d "${TMPDIR:-/tmp}/pwdoc.XXXXXX")"
REAL="$TOOL/.."
PW="$DOCDIR/bundle"; FH="$DOCDIR/home"
mkdir -p "$PW/tooling" "$FH"
cp -R "$TOOL/scripts" "$TOOL/commands" "$TOOL/agents" "$TOOL/skill" "$PW/tooling/"
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

rm -rf "$DOCDIR"
