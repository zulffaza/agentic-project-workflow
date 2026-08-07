#!/usr/bin/env bash
# ============================================================================
# offboard.sh — the exact inverse of bootstrap.sh: cleanly remove this
# bundle's INSTALLED artifacts from a machine, per provider — the
# project-workflow skill, generated /pw-* commands, and seeded sub-agents
# (pw-orchestrator, pw-executor).
#
#   ./offboard.sh                        dry-run: report what WOULD be removed
#   ./offboard.sh --yes                  actually remove it
#   ./offboard.sh --provider kilo        scope to one/more providers (comma-separated)
#   ./offboard.sh --all-known            also sweep built-in providers (claude, kilo) even
#                                        if no longer listed in PW_PROVIDERS — catches files
#                                        orphaned by disabling a provider in pw.config.sh
#
# SAFETY:
#  - Dry-run by default, always. Nothing is removed without --yes.
#  - Even with --yes, a file is only removed if its content EXACTLY MATCHES what this bundle
#    would generate right now (the same `cmp -s` check pw-doctor.sh uses). Anything that
#    differs — hand-edited, or just a foreign file that happens to share a name — is reported
#    and skipped, never guessed at.
#  - The skill "install" is only removed if it's literally a symlink pointing at THIS bundle's
#    tooling/skill/project-workflow, or a directory copy whose SKILL.md content matches it.
#
# NEVER touched, by design: pw.config.sh (your config), $PW_PROJECTS/* (your project data —
# a different kind of thing from installed tooling), this bundle's own repo, pw-env.sh, and
# any `source .../pw-env.sh` line you may have added to a shell rc file.
#
# KNOWN LIMITATION: a fully custom provider whose hooks were later deleted entirely from
# pw.config.sh can't have its install paths recomputed — there's nothing left to compute them
# from. Best-effort only; not tracked by a separate install manifest. --all-known covers the
# two built-ins (claude, kilo), which always have hooks available regardless of PW_PROVIDERS.
# ============================================================================
set -euo pipefail

YES=0
ALL_KNOWN=0
PROVIDER_ARG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --all-known) ALL_KNOWN=1; shift ;;
    --provider) PROVIDER_ARG="${2:-}"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown arg: $1 (try --help)" >&2; exit 1 ;;
  esac
done

# --- resolve roots the same way bootstrap.sh does ----------------------------
PW_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"
SKILL_SRC="$PW_HOME/tooling/skill/project-workflow"
export PW_PROJECTS PW_REPOS

# shared plumbing: sources pw.config.sh (if present; falls back to the example) + provider hooks.
# Never creates pw.config.sh — offboarding must never write new files.
. "$PW_HOME/tooling/pw-common.sh"

# --- known built-ins (always have hooks, regardless of PW_PROVIDERS membership) ---
KNOWN_PROVIDERS=(claude kilo)

echo "project-workflow offboard"
echo "  PW_HOME     = $PW_HOME"
if [ "$YES" -eq 1 ]; then
  echo "  mode        = APPLY (--yes) — will actually remove matched files"
else
  echo "  mode        = dry-run (default) — pass --yes to actually remove anything)"
fi
echo

# --- resolve provider scope ---------------------------------------------------
SCOPE=()
if [ -n "$PROVIDER_ARG" ]; then
  IFS=',' read -ra SCOPE <<< "$PROVIDER_ARG"
else
  SCOPE=("${PW_PROVIDERS[@]}")
fi
if [ "$ALL_KNOWN" -eq 1 ]; then
  for kp in "${KNOWN_PROVIDERS[@]}"; do
    seen=0
    for s in "${SCOPE[@]:-}"; do [ "$s" = "$kp" ] && seen=1; done
    [ "$seen" -eq 0 ] && SCOPE+=("$kp")
  done
fi
echo "  providers   = ${SCOPE[*]:-<none>}"
echo

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

REMOVE_PATHS=()   # every path confirmed safe to remove, across all providers
removed_count=0
skipped_count=0

plan_provider() {
  local p="$1"
  echo "  $p:"

  # --- skill ---
  local skilldir starget sfile
  skilldir="$("${p}_skilldir")"
  starget="$skilldir/project-workflow"
  sfile="$starget/SKILL.md"
  if [ -L "$starget" ]; then
    local real; real="$(readlink "$starget")"
    if [ "$real" = "$SKILL_SRC" ]; then
      echo "    skill: → remove symlink $starget (-> $SKILL_SRC)"
      REMOVE_PATHS+=("$starget")
    else
      echo "    skill: SKIPPED — $starget is a symlink to a different target ($real), not ours"
      skipped_count=$((skipped_count+1))
    fi
  elif [ -d "$starget" ]; then
    if [ -f "$sfile" ] && cmp -s "$sfile" "$SKILL_SRC/SKILL.md"; then
      echo "    skill: → remove directory copy $starget (content matches bundle)"
      REMOVE_PATHS+=("$starget")
    else
      echo "    skill: SKIPPED — $starget exists but isn't a symlink to us and its content"
      echo "           doesn't match (foreign, or hand-edited) — not touching it"
      skipped_count=$((skipped_count+1))
    fi
  else
    echo "    skill: not installed, nothing to do"
  fi

  # --- commands: regenerate to a temp dir, only remove exact matches ---
  local odir rm_c=0 skip_c=0 absent_c=0
  odir="$("${p}_outdir")"
  "$PW_HOME/tooling/gen-commands.sh" --outdir "$tmp/cmd" "$p" >/dev/null 2>&1 || true
  if [ -d "$tmp/cmd/$p" ]; then
    for exp in "$tmp/cmd/$p"/*.md; do
      n="$(basename "$exp")"
      if [ ! -f "$odir/$n" ]; then
        absent_c=$((absent_c+1))
      elif cmp -s "$exp" "$odir/$n"; then
        REMOVE_PATHS+=("$odir/$n"); rm_c=$((rm_c+1))
      else
        echo "    command SKIPPED (modified/foreign): $odir/$n"
        skip_c=$((skip_c+1))
      fi
    done
  fi
  echo "    commands: $rm_c to remove, $skip_c skipped (modified/foreign), $absent_c already absent  ($odir)"
  skipped_count=$((skipped_count+skip_c))

  # --- agents (only if this provider has agent-seeding hooks) ---
  if pw_provider_has_agent_hooks "$p"; then
    local adir rm_a=0 skip_a=0 absent_a=0
    adir="$("${p}_agentdir")"
    "$PW_HOME/tooling/gen-agents.sh" --outdir "$tmp/agents" "$p" >/dev/null 2>&1 || true
    if [ -d "$tmp/agents/$p" ]; then
      for exp in "$tmp/agents/$p"/*.md; do
        n="$(basename "$exp")"
        if [ ! -f "$adir/$n" ]; then
          absent_a=$((absent_a+1))
        elif cmp -s "$exp" "$adir/$n"; then
          REMOVE_PATHS+=("$adir/$n"); rm_a=$((rm_a+1))
        else
          echo "    agent SKIPPED (modified/foreign): $adir/$n"
          skip_a=$((skip_a+1))
        fi
      done
    fi
    echo "    agents:   $rm_a to remove, $skip_a skipped (modified/foreign), $absent_a already absent  ($adir)"
    skipped_count=$((skipped_count+skip_a))
  fi
  echo
}

for p in "${SCOPE[@]:-}"; do
  [ -z "$p" ] && continue
  if ! pw_provider_has_hooks "$p"; then
    echo "  $p: no hooks defined (bin/skilldir/outdir/render) — cannot compute install paths,"
    echo "      skipping (known limitation — see the header comment)"
    echo
    continue
  fi
  plan_provider "$p"
done

# --- apply (or not) -----------------------------------------------------------
if [ "$YES" -eq 1 ]; then
  for path in "${REMOVE_PATHS[@]:-}"; do
    [ -z "$path" ] && continue
    rm -rf "$path"   # safe for a symlink too — removes the link entry, never follows it
    removed_count=$((removed_count+1))
  done
  echo "Removed $removed_count file(s)/symlink(s) across ${#SCOPE[@]} provider(s); $skipped_count skipped (modified/foreign)."
else
  echo "[dry-run] Would remove ${#REMOVE_PATHS[@]} file(s)/symlink(s) across ${#SCOPE[@]} provider(s); $skipped_count would be skipped (modified/foreign)."
  echo "Re-run with --yes to actually remove them."
fi
echo

# --- what this deliberately never touches -------------------------------------
proj_count=0
if [ -d "$PW_PROJECTS" ]; then
  for d in "$PW_PROJECTS"/*/; do
    [ -d "$d" ] || continue
    dd="$(cd "$d" && pwd)"
    [ "$dd" = "$PW_HOME" ] && continue
    proj_count=$((proj_count+1))
  done
fi

echo "Not touched, by design:"
echo "  - pw.config.sh — delete it yourself for a clean slate, or keep it in case you reinstall."
echo "  - \$PW_PROJECTS ($PW_PROJECTS) — $proj_count project(s) still there. That's your history,"
echo "    not tooling; this script never deletes project data."
echo "  - This bundle's own folder ($PW_HOME) — this only undoes what got installed INTO your"
echo "    provider configs, not the bundle itself. Remove the folder yourself if you're done."
echo "  - Any 'source .../pw-env.sh' line you added to a shell rc file — remove that yourself."
