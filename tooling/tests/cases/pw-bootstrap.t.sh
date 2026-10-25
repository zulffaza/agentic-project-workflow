# shellcheck shell=bash
# cases/pw-bootstrap.t.sh — plan 29: the installer round-trip in an isolated HOME.
# Covers the exclusive provider format (skills for claude, commands for kilo), the four shared
# model skills, the six worker sub-agents (no primary orchestrator), doctor in-sync, and
# offboard --yes removing exactly what bootstrap installed. Never touches real provider dirs.
BOOTDIR="$(mktemp -d "${TMPDIR:-/tmp}/pwboot.XXXXXX")"
REAL="$TOOL/.."
PW="$BOOTDIR/bundle"; FH="$BOOTDIR/home"; BIN="$BOOTDIR/bin"
mkdir -p "$PW/tooling" "$FH/projects" "$FH/repos" "$BIN"
cp -R "$TOOL/scripts" "$TOOL/skills" "$TOOL/agents" "$TOOL/templates" "$TOOL/prompts" "$PW/tooling/"
cp "$REAL/bootstrap.sh" "$REAL/offboard.sh" "$REAL/pw.config.example.sh" "$PW/"
cp "$REAL/pw.config.example.sh" "$PW/pw.config.sh"
printf '#!/bin/sh\nexit 0\n' > "$BIN/claude"; chmod +x "$BIN/claude"
cat >> "$PW/pw.config.sh" <<CFG

# --- test overrides: claude (skill format) + kilo (command format), dirs under \$FH ---
PW_PROVIDERS=(claude kilo)
claude_skilldir()   { echo "$FH/.claude/skills"; }
claude_commanddir() { echo "$FH/.claude/commands"; }
claude_agentdir()   { echo "$FH/.claude/agents"; }
kilo_commanddir()   { echo "$FH/.config/kilo/command"; }
kilo_skilldir()     { echo "$FH/.kilocode/skills"; }
kilo_agentdir()     { echo "$FH/.config/kilo/agent"; }
CFG
printf '#!/bin/sh\nexit 0\n' > "$BIN/kilo"; chmod +x "$BIN/kilo"

pwtest_rc 0 "bootstrap installs into an isolated HOME" \
  env -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS HOME="$FH" PATH="$BIN:$PATH" bash "$PW/bootstrap.sh"
pwtest_eq "claude gets 18 entry skills + 4 shared skills" \
  "$(ls -d "$FH/.claude/skills"/*/ 2>/dev/null | wc -l | tr -d ' ')" "23"
[ -d "$FH/.claude/skills/pw-execute" ] && [ ! -d "$FH/.claude/skills/pw-execute/agents" ] \
  && pwtest_ok "claude human entry is a skill dir" \
  || pwtest_bad "claude entry format" "pw-execute is not an installed skill dir"
grep -qF 'disable-model-invocation: true' "$FH/.claude/skills/pw-execute/SKILL.md" \
  && pwtest_ok "claude human entry is explicit-only" \
  || pwtest_bad "claude explicit-only" "disable-model-invocation missing"
for _s in pw-guide-workflow pw-guide-review-method pw-guide-authoring pw-orchestration; do
  [ -d "$FH/.claude/skills/$_s" ] || pwtest_bad "shared skill $_s" "not installed for claude"
done
pwtest_eq "kilo gets 19 command files and no entry skill" \
  "$(ls "$FH/.config/kilo/command"/*.md 2>/dev/null | wc -l | tr -d ' '):$(ls -d "$FH/.kilocode/skills/pw-execute" 2>/dev/null | wc -l | tr -d ' ')" "19:0"
[ -f "$FH/.config/kilo/command/pw-execute.md" ] \
  && pwtest_ok "kilo human entry is a command file" \
  || pwtest_bad "kilo entry format" "pw-execute.md missing"
pwtest_eq "six worker sub-agents, no primary orchestrator" \
  "$(ls "$FH/.claude/agents"/*.md 2>/dev/null | wc -l | tr -d ' '):$(ls "$FH/.claude/agents/pw-orchestrator.md" 2>/dev/null | wc -l | tr -d ' ')" "6:0"
[ -f "$FH/.claude/agents/pw-ship-comment-analyst.md" ] \
  && pwtest_ok "the comments-analysis worker is seeded like every other lane" \
  || pwtest_bad "comments-analysis worker seeded" "pw-ship-comment-analyst.md missing from the agent dir"
pwtest_rc 0 "doctor reports the isolated install in sync" \
  env -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS HOME="$FH" PATH="$BIN:$PATH" bash "$PW/tooling/scripts/toolchain/pw-doctor.sh"
grep -q 'All synced' "$PWTEST_BOTH" \
  && pwtest_ok "doctor prints All synced" \
  || pwtest_bad "doctor verdict" "$(grep -E '✗|OUT OF SYNC' "$PWTEST_BOTH" | head -2 | tr '\n' ' ')"
pwtest_rc 0 "offboard removes the isolated install" \
  env -u PW_PROJECTS_DIR -u PW_REPOS -u PW_PROJECTS HOME="$FH" PATH="$BIN:$PATH" bash "$PW/offboard.sh" --yes
pwtest_eq "no pw artifacts remain under the fake HOME" \
  "$(find "$FH/.claude" "$FH/.config" "$FH/.kilocode" -name 'pw-*' 2>/dev/null | wc -l | tr -d ' ')" "0"
rm -rf "$BOOTDIR"
