#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — onboard this machine to the project-workflow pipeline.
#
# Run once after cloning the bundle (or after a machine reset). It is idempotent
# and NON-DESTRUCTIVE: it never overwrites an existing skill install unless you
# pass --force, and it never edits your shell profile.
#
#   ./bootstrap.sh            install for every detected provider CLI
#   ./bootstrap.sh --force    re-link the skill even if already present
#   ./bootstrap.sh --check    detect + report only; change nothing
#
# It:
#   1. resolves the three path roots from its own location,
#   2. detects which agent CLIs you have (claude, kilo, … — extensible below),
#   3. installs the project-workflow skill into each detected provider,
#   4. generates the /pw-* slash-commands for each detected provider,
#   5. writes pw-env.sh (source it to get $PW_HOME/$PW_PROJECTS/$PW_REPOS).
#
# Different teammates have different CLIs — that's the designed-for case. You get
# commands + skill only for the providers you actually have installed.
# ============================================================================
set -euo pipefail

MODE="install"
for a in "$@"; do
  case "$a" in
    --force) MODE="force" ;;
    --check|--dry-run) MODE="check" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $a (try --help)" >&2; exit 1 ;;
  esac
done

# --- 1. resolve roots (override PW_REPOS/PW_PROJECTS if your repos live elsewhere) ---
PW_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"
SKILL_SRC="$PW_HOME/skill/project-workflow"   # <name>/SKILL.md — the shippable skill

echo "project-workflow bootstrap"
echo "  PW_HOME     = $PW_HOME"
echo "  PW_PROJECTS = $PW_PROJECTS"
echo "  PW_REPOS    = $PW_REPOS   (git repos live here; override with PW_REPOS=… ./bootstrap.sh)"
echo

# --- 2. provider profiles ----------------------------------------------------
# To onboard a NEW provider: add its name to PROVIDERS and define <name>_bin /
# <name>_skilldir. Command output dirs are defined in workflow/gen-commands.sh.
PROVIDERS=(claude kilo)

claude_bin() { echo claude; }                       # CLI name to look for on PATH
claude_skilldir() { echo "$HOME/.claude/skills"; }  # <dir>/<skill-name>/SKILL.md

kilo_bin() { echo kilo; }
kilo_skilldir() { echo "$HOME/.kilocode/skills"; }  # adjust if your kilo reads skills elsewhere

# --- detect ------------------------------------------------------------------
DETECTED=()
for p in "${PROVIDERS[@]}"; do
  bin="$("${p}_bin")"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  ✓ detected $p  ($(command -v "$bin"))"
    DETECTED+=("$p")
  else
    echo "  – $p not found (no '$bin' on PATH) — skipping"
  fi
done
echo

if [ "${#DETECTED[@]}" -eq 0 ]; then
  echo "No supported agent CLI found (looked for: ${PROVIDERS[*]})."
  echo "Install one, or add your provider (see ONBOARDING.md → 'Register a new provider')."
  echo "Scaffolding still works: \$PW_HOME/scaffold.sh <slug>."
fi

if [ "$MODE" = "check" ]; then
  echo "[--check] detection only; no changes made."
  exit 0
fi

# --- 3. install the skill per detected provider (symlink; copy fallback) -----
install_skill() {
  local dir="$1" name; name="$(basename "$SKILL_SRC")"
  local target="$dir/$name"
  mkdir -p "$dir"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$MODE" != "force" ]; then
      echo "    skill: already present at $target (leaving as-is; --force to re-link)"
      return
    fi
  fi
  if ln -sfn "$SKILL_SRC" "$target" 2>/dev/null; then
    echo "    skill: linked $target → $SKILL_SRC"
  else
    rm -rf "$target"; cp -R "$SKILL_SRC" "$target"
    echo "    skill: copied $SKILL_SRC → $target"
  fi
}
for p in "${DETECTED[@]}"; do
  echo "  $p:"
  install_skill "$("${p}_skilldir")"
done
echo

# --- 4. generate slash-commands for the detected providers only --------------
if [ "${#DETECTED[@]}" -gt 0 ]; then
  echo "  generating /pw-* commands:"
  PW_PROJECTS="$PW_PROJECTS" PW_REPOS="$PW_REPOS" \
    "$PW_HOME/workflow/gen-commands.sh" "${DETECTED[@]}" | sed 's/^/    /'
  echo
fi

# --- 5. write the env file ---------------------------------------------------
ENV_FILE="$PW_HOME/pw-env.sh"
cat > "$ENV_FILE" <<EOF
# Written by bootstrap.sh — source this for the path vars used across the docs.
#   source "$ENV_FILE"
export PW_HOME="$PW_HOME"
export PW_PROJECTS="$PW_PROJECTS"
export PW_REPOS="$PW_REPOS"
EOF
echo "  wrote $ENV_FILE"
echo

# --- verify + next steps -----------------------------------------------------
echo "  self-test: $("$PW_HOME/workflow/pw-lib.sh" selftest 2>&1 | tail -1)"
echo
echo "Done. To make the path vars available in your shell now:"
echo "    source \"$ENV_FILE\""
echo "(optional) add that line to your ~/.zshrc so it persists."
echo
echo "Verify end-to-end:  \$PW_HOME/scaffold.sh demo   then   /pw-status demo"
