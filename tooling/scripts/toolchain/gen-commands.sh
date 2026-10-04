#!/usr/bin/env bash
# Generate per-provider slash-command files from the ONE canonical spec in ./commands/.
# Canonical files are provider-neutral: frontmatter `description`, `args`, optional `agent`,
# and a body using the {{ARGS}} placeholder + {{PW_*}} path tokens.
#
# You do NOT edit this script to change providers — set PW_PROVIDERS (and any provider
# hooks) in ../pw.config.sh. Provider command files are BUILD ARTIFACTS — never hand-edit them.
#
# Usage: gen-commands.sh [--outdir DIR] [provider ...]
#   --outdir DIR   write to DIR/<provider>/ instead of each provider's real dir (used by pw-doctor)
#   provider ...   restrict to these providers (default: PW_PROVIDERS from config)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
CANON_DIR="$HERE/../../commands"
PW_HOME="$(cd "$HERE/../../.." && pwd)"                       # repo root (the bundle)
. "$HERE/../lib/pw-common.sh"                                  # roots + config + provider hooks

# --- args: --outdir DIR and/or an explicit provider list ---------------------
OUTDIR_OVERRIDE=""
ARGS_PROVIDERS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --outdir) OUTDIR_OVERRIDE="$2"; shift 2 ;;
    *) ARGS_PROVIDERS+=("$1"); shift ;;
  esac
done
PROVIDERS=("${PW_PROVIDERS[@]}")
[ "${#ARGS_PROVIDERS[@]}" -gt 0 ] && PROVIDERS=("${ARGS_PROVIDERS[@]}")

# --- frontmatter/body helpers (parse the canonical file) ---------------------
fm() {  # fm <file> <key> -> value of that frontmatter key (empty if absent)
  awk -v k="$2" '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {exit}
    infm { if ($0 ~ "^"k":") { sub("^"k":[ \t]*",""); print; exit } }
  ' "$1"
}
body() {  # body <file> -> everything after the closing --- of frontmatter
  awk 'c==2{print} $0=="---"{c++}' "$1"
}

# --- drive -------------------------------------------------------------------
count=0
for prov in "${PROVIDERS[@]}"; do
  if [ -n "$OUTDIR_OVERRIDE" ]; then outdir="$OUTDIR_OVERRIDE/$prov"; else outdir="$("${prov}_commanddir")"; fi
  mkdir -p "$outdir"
  # Command layout (pw_provider_command_style): "flat" = <name>.md files (claude/kilo/opencode/
  # cursor); "skill" = <name>/SKILL.md dirs for providers with NO native command surface (codex —
  # custom prompts removed upstream in codex-cli 0.117.0; commands ship as skills). In the skill
  # layout an optional render_<prov>_skill_policy hook writes agents/openai.yaml beside SKILL.md.
  style="$(pw_provider_command_style "$prov")"
  for f in "$CANON_DIR"/*.md; do
    name="$(basename "$f" .md)"
    desc="$(fm "$f" description)"
    args="$(fm "$f" args)"
    agent="$(fm "$f" agent)"
    bodytext="$(body "$f")"
    # stamp real absolute paths into the build artifact
    bodytext="${bodytext//\{\{PW_HOME\}\}/$PW_HOME}"
    bodytext="${bodytext//\{\{PW_PROJECTS\}\}/$PW_PROJECTS}"
    bodytext="${bodytext//\{\{PW_REPOS\}\}/$PW_REPOS}"
    if [ "$style" = "skill" ]; then
      # A stale SYMLINK at the target (e.g. a bundle skill from before the collision-skip policy)
      # would make `>` write THROUGH it into the bundle — remove links before writing.
      [ -L "$outdir/$name" ] && rm -f "$outdir/$name"
      mkdir -p "$outdir/$name"
      "render_${prov}_command" > "$outdir/$name/SKILL.md"
      if declare -f "render_${prov}_skill_policy" >/dev/null 2>&1; then
        mkdir -p "$outdir/$name/agents"
        "render_${prov}_skill_policy" > "$outdir/$name/agents/openai.yaml"
      fi
    else
      "render_${prov}_command" > "$outdir/$name.md"
    fi
    count=$((count+1))
  done
  echo "✓ $prov  → $outdir  ($(ls "$CANON_DIR"/*.md | wc -l | tr -d ' ') commands, $style layout)"
done
echo "Generated $count files from $CANON_DIR"
