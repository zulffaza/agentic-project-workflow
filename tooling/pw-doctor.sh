#!/usr/bin/env bash
# ============================================================================
# pw-doctor.sh — verify the installed skill + generated /pw-* commands are in
# sync with THIS bundle, per enabled provider. Reports drift; --fix repairs it.
#
#   tooling/pw-doctor.sh          check only (exit 1 if anything is out of sync)
#   tooling/pw-doctor.sh --fix    repair drift (re-install skill, regenerate commands)
#
# "In sync" = what bootstrap/gen-commands WOULD produce now equals what's installed.
# It generates commands to a temp dir and diffs them, so it catches a moved bundle,
# edited sources, or a stale skill.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
SKILL_SRC="$PW_HOME/tooling/skill/project-workflow"

FIX=0
case "${1:-}" in
  --fix) FIX=1 ;;
  "" ) ;;
  -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) echo "unknown arg: $1 (try --help)" >&2; exit 1 ;;
esac

issues=0
echo "pw-doctor — project-workflow sync check"
echo "  PW_HOME   = $PW_HOME"
echo "  providers = ${PW_PROVIDERS[*]}   (from pw.config.sh)"
echo

# --- config + env ------------------------------------------------------------
if [ -f "$PW_HOME/pw.config.sh" ]; then
  echo "  ✓ pw.config.sh present"
else
  echo "  – pw.config.sh missing (running on example defaults; ./bootstrap.sh creates it)"
fi

ENV_FILE="$PW_HOME/pw-env.sh"
if [ -f "$ENV_FILE" ]; then
  envhome="$(sed -n 's/^export PW_HOME="\(.*\)"$/\1/p' "$ENV_FILE")"
  if [ "$envhome" = "$PW_HOME" ]; then
    echo "  ✓ pw-env.sh matches PW_HOME"
  else
    echo "  ✗ pw-env.sh is stale (PW_HOME=$envhome)"; issues=$((issues+1))
    if [ "$FIX" -eq 1 ]; then
      printf '# Written by pw-doctor --fix.\nexport PW_HOME="%s"\nexport PW_PROJECTS="%s"\nexport PW_REPOS="%s"\n' \
        "$PW_HOME" "$PW_PROJECTS" "$PW_REPOS" > "$ENV_FILE"
      echo "      fixed: rewrote pw-env.sh"
    fi
  fi
else
  echo "  – pw-env.sh missing (source it after ./bootstrap.sh)"
fi
echo

# --- per provider ------------------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for p in "${PW_PROVIDERS[@]}"; do
  if ! pw_provider_has_hooks "$p"; then
    echo "  $p: missing hooks (bin/skilldir/outdir/render) in pw.config.sh — skipping"; echo; continue
  fi
  echo "  $p:"
  bin="$("${p}_bin")"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "    ✓ CLI detected ($(command -v "$bin"))"
  else
    echo "    – CLI '$bin' enabled but not on PATH"
  fi

  # skill
  skilldir="$("${p}_skilldir")"; sfile="$skilldir/project-workflow/SKILL.md"
  if [ ! -e "$sfile" ]; then
    echo "    ✗ skill NOT installed ($skilldir/project-workflow)"; issues=$((issues+1))
    if [ "$FIX" -eq 1 ]; then
      mkdir -p "$skilldir"
      ln -sfn "$SKILL_SRC" "$skilldir/project-workflow" 2>/dev/null || cp -R "$SKILL_SRC" "$skilldir/project-workflow"
      echo "      fixed: installed skill"
    fi
  elif cmp -s "$sfile" "$SKILL_SRC/SKILL.md"; then
    echo "    ✓ skill up to date"
  else
    echo "    ✗ skill STALE (differs from bundle)"; issues=$((issues+1))
    if [ "$FIX" -eq 1 ]; then
      ln -sfn "$SKILL_SRC" "$skilldir/project-workflow" 2>/dev/null || cp -f "$SKILL_SRC/SKILL.md" "$sfile"
      echo "      fixed: refreshed skill from bundle"
    fi
  fi

  # commands: generate to temp, diff against what's installed
  odir="$("${p}_outdir")"
  "$HERE/gen-commands.sh" --outdir "$tmp" "$p" >/dev/null
  drift=0; missing=0
  for exp in "$tmp/$p"/*.md; do
    n="$(basename "$exp")"
    if [ ! -f "$odir/$n" ]; then missing=$((missing+1))
    elif ! cmp -s "$exp" "$odir/$n"; then drift=$((drift+1)); fi
  done
  if [ $((drift+missing)) -eq 0 ]; then
    echo "    ✓ commands in sync ($odir)"
  else
    echo "    ✗ commands OUT OF SYNC ($odir): $drift changed, $missing missing"; issues=$((issues+1))
    if [ "$FIX" -eq 1 ]; then
      "$HERE/gen-commands.sh" "$p" >/dev/null && echo "      fixed: regenerated commands"
    fi
  fi
  echo
done

# --- verdict -----------------------------------------------------------------
if [ "$issues" -eq 0 ]; then
  echo "All synced ✓"
  exit 0
fi
if [ "$FIX" -eq 1 ]; then
  echo "$issues issue(s) — fixes applied above. Re-run pw-doctor.sh to confirm."
  exit 0
fi
echo "$issues issue(s) out of sync. Fix with:  $HERE/pw-doctor.sh --fix   (or ./bootstrap.sh)"
exit 1
