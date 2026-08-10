#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh — onboard this machine to the project-workflow pipeline.
#
# Run once after cloning the bundle (or after a machine reset). Idempotent and
# NON-DESTRUCTIVE: never overwrites an existing skill install unless you pass
# --force, and never edits your shell profile.
#
#   ./bootstrap.sh            install for every ENABLED provider (see pw.config.sh)
#   ./bootstrap.sh --force    re-link the skill even if already present
#   ./bootstrap.sh --check    detect + report only; change nothing
#
# It:
#   1. resolves the three path roots from its own location,
#   2. reads pw.config.sh for which agent CLIs you use (PW_PROVIDERS),
#   3. installs every shipped skill (tooling/skill/*/) into each enabled+detected provider,
#   4. generates the /pw-* slash-commands for them,
#   5. writes pw-env.sh (source it for $PW_HOME/$PW_PROJECTS/$PW_REPOS).
#
# You never edit THIS script to change providers — edit pw.config.sh.
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
SKILL_DIR="$PW_HOME/tooling/skill"   # every subdir with a SKILL.md here is a shippable skill

# --- 2. load config (create it from the example on first run) ----------------
# --check must change nothing, so it reads the example in place without creating the file.
CONFIG="$PW_HOME/pw.config.sh"
if [ ! -f "$CONFIG" ] && [ "$MODE" != "check" ]; then
  cp "$PW_HOME/pw.config.example.sh" "$CONFIG"
  echo "created $CONFIG from the example — edit it to set your providers."
fi
# shared plumbing: sources pw.config.sh + defines the built-in provider hooks
. "$PW_HOME/tooling/pw-common.sh"

echo "project-workflow bootstrap"
echo "  PW_HOME     = $PW_HOME"
echo "  PW_PROJECTS = $PW_PROJECTS"
echo "  PW_REPOS    = $PW_REPOS   (git repos live here; override with PW_REPOS=… ./bootstrap.sh)"
echo "  providers   = ${PW_PROVIDERS[*]}   (from pw.config.sh)"
echo "  memory      = ${PW_MEMORY:-none}   (optional; ${PW_MEMORY:+configured — }see tooling/docs/memory.md)"
echo "  forge       = auto-detect (${#PW_FORGE_HOSTS[@]} host override(s))   (optional; see tooling/docs/forges.md)"
echo "  rfc         = ${PW_RFC_BACKEND:-markdown}   (optional; see tooling/docs/rfc.md)"
echo

# --- detect (enabled AND present on PATH) ------------------------------------
DETECTED=()
for p in "${PW_PROVIDERS[@]}"; do
  if ! pw_provider_has_hooks "$p"; then
    echo "  ! provider '$p' is missing hooks (bin/skilldir/outdir/render) — define them in pw.config.sh; skipping"
    continue
  fi
  bin="$("${p}_bin")"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  ✓ $p enabled + detected  ($(command -v "$bin"))"
    DETECTED+=("$p")
  else
    echo "  – $p enabled but not found (no '$bin' on PATH) — skipping"
  fi
done
echo

if [ "${#DETECTED[@]}" -eq 0 ]; then
  echo "No enabled provider CLI is installed. Set PW_PROVIDERS in $CONFIG,"
  echo "install a supported CLI, or add your provider (see ONBOARDING.md)."
  echo "Scaffolding still works: \$PW_HOME/tooling/scaffold.sh <slug>."
fi

if [ "$MODE" = "check" ]; then
  echo "[--check] detection only; no changes made."
  exit 0
fi

# --- 3. install every shipped skill, per detected provider (symlink; copy fallback) ------------
install_skill() {
  local dir="$1" src="$2" name; name="$(basename "$src")"
  local target="$dir/$name"
  mkdir -p "$dir"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$MODE" != "force" ]; then
      echo "    skill: '$name' already present at $target (leaving as-is; --force to re-link)"
      return
    fi
    # --force + target already exists: rm -rf it FIRST. If $target is a real (non-symlink)
    # directory, `ln -sfn` against an *existing directory* target doesn't fail or replace it —
    # it silently nests a new symlink INSIDE it (standard multi-arg `ln` semantics), leaving the
    # stale copy in place underneath. Removing first avoids that ambiguity entirely.
    rm -rf "$target"
  fi
  if ln -sfn "$src" "$target" 2>/dev/null; then
    echo "    skill: linked $target → $src"
  else
    rm -rf "$target"; cp -R "$src" "$target"
    echo "    skill: copied $src → $target"
  fi
}
for p in "${DETECTED[@]}"; do
  echo "  $p:"
  skdir="$("${p}_skilldir")"
  for src in "$SKILL_DIR"/*/; do
    [ -f "${src}SKILL.md" ] || continue   # skip any non-skill subdir
    install_skill "$skdir" "${src%/}"
  done
done
echo

# --- 4. generate slash-commands for the detected providers only --------------
if [ "${#DETECTED[@]}" -gt 0 ]; then
  echo "  generating /pw-* commands:"
  PW_PROJECTS="$PW_PROJECTS" PW_REPOS="$PW_REPOS" \
    "$PW_HOME/tooling/gen-commands.sh" "${DETECTED[@]}" | sed 's/^/    /'
  echo

  echo "  seeding sub-agents (pw-orchestrator, pw-executor, pw-reviewer):"
  PW_PROJECTS="$PW_PROJECTS" PW_REPOS="$PW_REPOS" \
    "$PW_HOME/tooling/gen-agents.sh" "${DETECTED[@]}" | sed 's/^/    /'
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
echo "  self-test: $("$PW_HOME/tooling/pw-lib.sh" selftest 2>&1 | tail -1)"
echo
echo "Done. To make the path vars available in your shell now:"
echo "    source \"$ENV_FILE\""
echo "(optional) add that line to your ~/.zshrc so it persists."
echo
echo "Verify end-to-end (in your agent CLI):  /pw-new demo   then   /pw-status demo"
