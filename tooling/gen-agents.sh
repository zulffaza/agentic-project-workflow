#!/usr/bin/env bash
# Generate per-provider sub-agent files from the ONE canonical spec in ./agents/.
# Canonical files are provider-neutral: frontmatter `description`, `displayName`, `role`,
# optional `claude_tools` / `model`, and a body using {{PW_*}} path tokens. Each provider's
# render_<prov>_agent hook (see pw-common.sh) wraps the body in that provider's frontmatter.
#
# Sibling of gen-commands.sh — agents seed exactly like slash-commands. You do NOT edit this
# script to change providers; set PW_PROVIDERS + any hooks in ../pw.config.sh. The per-provider
# agent files are BUILD ARTIFACTS — never hand-edit them.
#
# Usage: gen-agents.sh [--outdir DIR] [provider ...]
#   --outdir DIR   write to DIR/<provider>/ instead of each provider's real agent dir (pw-doctor)
#   provider ...   restrict to these providers (default: PW_PROVIDERS from config)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
CANON_DIR="$HERE/agents"
PW_HOME="$(cd "$HERE/.." && pwd)"                       # repo root (the bundle)
. "$HERE/pw-common.sh"                                  # roots + config + provider hooks

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
  if ! pw_provider_has_agent_hooks "$prov"; then
    echo "  $prov: no agent hooks (agentdir/render_${prov}_agent) — skipping" >&2; continue
  fi
  if [ -n "$OUTDIR_OVERRIDE" ]; then outdir="$OUTDIR_OVERRIDE/$prov"; else outdir="$("${prov}_agentdir")"; fi
  mkdir -p "$outdir"
  for f in "$CANON_DIR"/*.md; do
    [ "$(basename "$f")" = "README.md" ] && continue
    agentname="$(basename "$f" .md)"
    desc="$(fm "$f" description)"
    displayName="$(fm "$f" displayName)"
    role="$(fm "$f" role)"
    claude_tools="$(fm "$f" claude_tools)"
    model="$(fm "$f" model)"
    bodytext="$(body "$f")"
    # stamp real absolute paths into the build artifact
    bodytext="${bodytext//\{\{PW_HOME\}\}/$PW_HOME}"
    bodytext="${bodytext//\{\{PW_PROJECTS\}\}/$PW_PROJECTS}"
    bodytext="${bodytext//\{\{PW_REPOS\}\}/$PW_REPOS}"
    "render_${prov}_agent" > "$outdir/$agentname.md"
    count=$((count+1))
  done
  n=$(( $(ls "$CANON_DIR"/*.md | wc -l) - 1 ))   # minus README.md
  echo "✓ $prov  → $outdir  ($n agents)"
done
echo "Generated $count files from $CANON_DIR"
