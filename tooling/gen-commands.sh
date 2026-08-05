#!/usr/bin/env bash
# Generate per-provider slash-command files from the ONE canonical spec in ./commands/.
# Canonical files are provider-neutral: frontmatter `description`, `args`, optional `agent`,
# and a body using the {{ARGS}} placeholder + {{PW_*}} path tokens.
#
# You do NOT edit this script to change providers — set PW_PROVIDERS (and any provider
# hooks) in ../pw.config.sh. This script only defines the built-in defaults.
# Provider command files are BUILD ARTIFACTS — never hand-edit them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/
CANON_DIR="$HERE/commands"

# --- roots (canonical bodies use {{PW_*}} tokens; we stamp real paths here) ---
PW_HOME="$(cd "$HERE/.." && pwd)"                       # repo root (the bundle)
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"

# --- load local config (enabled providers + optional overrides) --------------
if   [ -f "$PW_HOME/pw.config.sh" ];         then . "$PW_HOME/pw.config.sh"
elif [ -f "$PW_HOME/pw.config.example.sh" ]; then . "$PW_HOME/pw.config.example.sh"
fi
declare -p PW_PROVIDERS >/dev/null 2>&1 || PW_PROVIDERS=(claude kilo)

# --- built-in provider defaults (config-defined functions win) ---------------
declare -f claude_outdir >/dev/null 2>&1 || claude_outdir() { echo "$HOME/.claude/commands"; }
declare -f kilo_outdir   >/dev/null 2>&1 || kilo_outdir()   { echo "$HOME/.config/kilo/command"; }
declare -f render_claude >/dev/null 2>&1 || render_claude() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
declare -f render_kilo >/dev/null 2>&1 || render_kilo() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}

# --- providers: CLI args > PW_PROVIDERS from config > fallback ----------------
PROVIDERS=("${PW_PROVIDERS[@]}")
if [ "$#" -gt 0 ]; then PROVIDERS=("$@"); fi

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
  outdir="$("${prov}_outdir")"
  mkdir -p "$outdir"
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
    "render_${prov}" > "$outdir/$name.md"
    count=$((count+1))
  done
  echo "✓ $prov  → $outdir  ($(ls "$CANON_DIR"/*.md | wc -l | tr -d ' ') commands)"
done
echo "Generated $count files from $CANON_DIR"
