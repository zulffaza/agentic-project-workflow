#!/usr/bin/env bash
# Generate per-provider slash-command files from the ONE canonical spec in ./commands/.
# Canonical files are provider-neutral: frontmatter `description`, `args`, optional `agent`,
# and a body using the {{ARGS}} placeholder.
#
# Add a provider = add a profile to the `PROVIDERS` list + a `render_<provider>` function.
# Then re-run this script. Provider command files are BUILD ARTIFACTS — never hand-edit them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANON_DIR="$HERE/commands"

# --- resolve the three roots from this script's own location -----------------
# Canonical command bodies use {{PW_HOME}}/{{PW_PROJECTS}}/{{PW_REPOS}} tokens so the
# SOURCE stays machine-independent; we stamp the real absolute paths into the generated
# (build-artifact) command files here. PW_HOME = the bundle dir (base/), then up two.
PW_HOME="$(cd "$HERE/.." && pwd)"
PW_PROJECTS="${PW_PROJECTS:-$(cd "$PW_HOME/.." && pwd)}"
PW_REPOS="${PW_REPOS:-$(cd "$PW_PROJECTS/.." && pwd)}"

# --- providers to emit for -------------------------------------------------
# Default: every known provider. Override by passing provider names as args
# (bootstrap.sh passes only the CLIs it actually detected on this machine).
PROVIDERS=(claude kilo)
if [ "$#" -gt 0 ]; then PROVIDERS=("$@"); fi

claude_outdir() { echo "$HOME/.claude/commands"; }
kilo_outdir()   { echo "$HOME/.config/kilo/command"; }

# --- frontmatter/body helpers (parse the canonical file) -------------------
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

# --- per-provider renderers ------------------------------------------------
# Each reads: $name $desc $args $agent $bodytext  and prints the provider file.
render_claude() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$args"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}
render_kilo() {
  printf -- '---\ndescription: %s\n' "$desc"
  [ -n "$agent" ] && printf -- 'agent: %s\n' "$agent"
  printf -- '---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}

# --- drive -----------------------------------------------------------------
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
