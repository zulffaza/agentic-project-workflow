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
SKILL_DIR="$PW_HOME/tooling/skill"   # every subdir with a SKILL.md here is a shippable skill

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
echo "  memory    = ${PW_MEMORY:-none}   (optional; see tooling/docs/memory.md)"
echo "  forge     = auto-detect (${#PW_FORGE_HOSTS[@]} host override(s))   (optional; see tooling/docs/forges.md)"
echo "  rfc       = ${PW_RFC_BACKEND:-markdown}   (optional; see tooling/docs/rfc.md)"
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

# Live model catalog for one Agent Provider, one line per model id (provider-prefix included),
# or nothing on any failure — every call site treats "nothing" as "can't check", never an error.
# Only kilo/opencode have a queryable catalog at all (claude has a fixed alias set — see
# docs/EXECUTION.md); callers check that before ever reaching here.
_pw_doctor_model_catalog() {
  local prov="$1" ap
  case "$prov" in
    kilo)
      if [ "${#PW_KILO_API_PROVIDERS[@]}" -gt 0 ]; then
        for ap in "${PW_KILO_API_PROVIDERS[@]}"; do kilo models "$ap" 2>/dev/null || true; done
      else
        kilo models 2>/dev/null || true
      fi
      ;;
    opencode) opencode models 2>/dev/null || true ;;
  esac
  return 0
}

# --- per provider ------------------------------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for p in "${PW_PROVIDERS[@]}"; do
  if ! pw_provider_has_hooks "$p"; then
    echo "  $p: missing hooks (bin/skilldir/commanddir/render_*_command) in pw.config.sh — skipping"; echo; continue
  fi
  echo "  $p:"
  bin="$("${p}_bin")"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "    ✓ CLI detected ($(command -v "$bin"))"
  else
    echo "    – CLI '$bin' enabled but not on PATH"
  fi

  # skills — compare the WHOLE directory tree of EACH shipped skill (SKILL.md + any
  # references/*.md), not just the single SKILL.md file, so drift in a reference file is actually
  # caught on a copy-fallback filesystem (a symlink install is trivially "in sync" since diff -rq
  # dereferences it). Loops every tooling/skill/*/ dir — adding a new skill needs no change here.
  skilldir="$("${p}_skilldir")"
  for skill_src in "$SKILL_DIR"/*/; do
    [ -f "${skill_src}SKILL.md" ] || continue
    skill_src="${skill_src%/}"; skill_name="$(basename "$skill_src")"
    starget="$skilldir/$skill_name"
    if [ ! -e "$starget" ]; then
      echo "    ✗ skill '$skill_name' NOT installed ($starget)"; issues=$((issues+1))
      if [ "$FIX" -eq 1 ]; then
        mkdir -p "$skilldir"
        ln -sfn "$skill_src" "$starget" 2>/dev/null || cp -R "$skill_src" "$starget"
        echo "      fixed: installed skill '$skill_name'"
      fi
    elif diff -rq "$starget" "$skill_src" >/dev/null 2>&1; then
      echo "    ✓ skill '$skill_name' up to date"
    else
      echo "    ✗ skill '$skill_name' STALE (differs from bundle)"; issues=$((issues+1))
      if [ "$FIX" -eq 1 ]; then
        # rm -rf FIRST, unconditionally: if $starget is a real (non-symlink) directory, `ln -sfn`
        # against an *existing directory* target doesn't fail or replace it — it silently nests a
        # new symlink INSIDE it (standard multi-arg `ln` semantics), leaving the stale copy in
        # place. Removing first avoids that ambiguity entirely, for both the symlink and copy path.
        rm -rf "$starget"
        ln -sfn "$skill_src" "$starget" 2>/dev/null || cp -R "$skill_src" "$starget"
        echo "      fixed: refreshed skill '$skill_name' from bundle"
      fi
    fi
  done

  # commands: generate to temp, diff against what's installed
  odir="$("${p}_commanddir")"
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

  # agents: generate to a SEPARATE temp subdir (the commands check already populated $tmp/$p),
  # diff against what's installed (only if provider has agent hooks)
  if pw_provider_has_agent_hooks "$p"; then
    adir="$("${p}_agentdir")"
    "$HERE/gen-agents.sh" --outdir "$tmp/agents" "$p" >/dev/null 2>&1
    adrift=0; amissing=0
    for exp in "$tmp/agents/$p"/*.md; do
      n="$(basename "$exp")"
      if [ ! -f "$adir/$n" ]; then amissing=$((amissing+1))
      elif ! cmp -s "$exp" "$adir/$n"; then adrift=$((adrift+1)); fi
    done
    if [ $((adrift+amissing)) -eq 0 ]; then
      echo "    ✓ agents in sync ($adir)"
    else
      echo "    ✗ agents OUT OF SYNC ($adir): $adrift changed, $amissing missing"; issues=$((issues+1))
      if [ "$FIX" -eq 1 ]; then
        "$HERE/gen-agents.sh" "$p" >/dev/null && echo "      fixed: regenerated agents"
      fi
    fi
  fi

  # --- model availability (INFORMATIONAL ONLY — never touches $issues or the exit code; a ⚠
  # here never blocks or fails pw-doctor, per design) --------------------------------------
  upper="$(printf '%s' "$p" | tr '[:lower:]' '[:upper:]')"
  allow_var="PW_MODEL_ALLOWLIST_${upper}"
  allow="${!allow_var:-}"
  if [ -z "$allow" ]; then
    echo "    · model allowlist: none set (unrestricted — every model is allowed, the default)"
  elif [ "$p" = "claude" ]; then
    echo "    · model allowlist: \"$allow\" — can't verify live (Claude Code has a fixed alias"
    echo "        set, not a queryable catalog; see docs/EXECUTION.md's model table)"
  elif ! command -v "$bin" >/dev/null 2>&1; then
    echo "    · model allowlist: \"$allow\" — can't check ($bin not on PATH)"
  else
    catalog="$(_pw_doctor_model_catalog "$p")"
    if [ -z "$catalog" ]; then
      echo "    · model allowlist: \"$allow\" — can't check (no models returned by '$bin models')"
    else
      IFS=',' read -ra allow_pats <<< "$allow"
      for allow_pat in "${allow_pats[@]}"; do
        allow_pat="$(printf '%s' "$allow_pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        n=0
        while IFS= read -r line; do
          case "$line" in $allow_pat) n=$((n+1)) ;; esac
        done <<< "$catalog"
        if [ "$n" -gt 0 ]; then
          echo "    ✓ model allowlist \"$allow_pat\": $n match(es) in the live catalog"
        else
          echo "    ⚠ model allowlist \"$allow_pat\": 0 matches — possible typo, deprecated id, or not covered by your authenticated API Providers"
        fi
      done
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
