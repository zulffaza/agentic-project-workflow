#!/usr/bin/env bash
# Generate per-provider human entry points from the ONE canonical source in
# tooling/skills/human/<name>/SKILL.md.
#
# Two EXCLUSIVE output formats (pw_provider_entry_format):
#   skill    — invocable, explicit-only skill dir (<name>/SKILL.md + optional policy sidecar).
#              Claude Code, Cursor, Codex. No command copy is generated.
#   command  — native command file (<name>.md). KiloCode, OpenCode. No entry skill is installed.
#
# Shared procedural skills (tooling/skills/model/*) are installed separately by bootstrap.sh;
# they never duplicate a human entry name.
#
# You do NOT edit this script to change providers — set PW_PROVIDERS (and any provider
# hooks) in ../pw.config.sh. Provider files are BUILD ARTIFACTS — never hand-edit them.
#
# Usage: gen-commands.sh [--outdir DIR] [provider ...]
#   --outdir DIR   write to DIR/<provider>/ instead of each provider's real dir (used by pw-doctor)
#   provider ...   restrict to these providers (default: PW_PROVIDERS from config)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/scripts/toolchain
CANON_DIR="$HERE/../../skills/human"
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

# Appended to every rendered artifact: the doctor's orphan sweep removes ONLY entries carrying
# this bundle marker (content-check-and-skip for anything else).
GEN_MARKER='<!-- pw-generated: build artifact — regenerate with /pw-doctor --fix; never hand-edit -->'

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

# Generic skill renderer for providers that declare `entry_format: skill` without their own
# render_<prov>_entry_skill hook. Explicit-only invocation and $ARGUMENTS are the contract.
generic_entry_skill() {
  printf -- '---\nname: %s\ndescription: %s\n' "$name" "$(pw_yaml_quote "$desc")"
  [ -n "$args" ] && printf -- 'argument-hint: %s\n' "$(pw_yaml_quote "$args")"
  printf -- 'disable-model-invocation: true\n---\n%s' "${bodytext//\{\{ARGS\}\}/\$ARGUMENTS}"
}

# --- drive -------------------------------------------------------------------
count=0
for prov in "${PROVIDERS[@]}"; do
  fmt="$(pw_provider_entry_format "$prov")"
  case "$fmt" in skill|command) ;; *) echo "gen-commands: $prov: unknown entry_format '$fmt' → fix: return skill or command" >&2; exit 1 ;; esac
  if [ -n "$OUTDIR_OVERRIDE" ]; then
    outdir="$OUTDIR_OVERRIDE/$prov"
  elif [ "$fmt" = "skill" ]; then
    outdir="$("${prov}_skilldir")"
  else
    outdir="$("${prov}_commanddir")"
  fi
  mkdir -p "$outdir"
  for d in "$CANON_DIR"/*/; do
    f="${d}SKILL.md"
    [ -f "$f" ] || continue
    name="$(basename "${d%/}")"
    desc="$(fm "$f" description)"
    args="$(fm "$f" args)"
    agent="$(fm "$f" agent)"
    bodytext="$(body "$f")"
    # stamp real absolute paths into the build artifact
    bodytext="${bodytext//\{\{PW_HOME\}\}/$PW_HOME}"
    bodytext="${bodytext//\{\{PW_PROJECTS\}\}/$PW_PROJECTS}"
    bodytext="${bodytext//\{\{PW_REPOS\}\}/$PW_REPOS}"
    if [ "$fmt" = "skill" ]; then
      # A stale SYMLINK at any write target would make `>` write THROUGH it into the bundle.
      [ -L "$outdir/$name" ] && rm -f "$outdir/$name"
      mkdir -p "$outdir/$name"
      [ -L "$outdir/$name/SKILL.md" ] && rm -f "$outdir/$name/SKILL.md"
      if declare -f "render_${prov}_entry_skill" >/dev/null 2>&1; then
        "render_${prov}_entry_skill" > "$outdir/$name/SKILL.md"
      else
        generic_entry_skill > "$outdir/$name/SKILL.md"
      fi
      printf '%s\n' "$GEN_MARKER" >> "$outdir/$name/SKILL.md"
      if declare -f "render_${prov}_skill_policy" >/dev/null 2>&1; then
        mkdir -p "$outdir/$name/agents"
        [ -L "$outdir/$name/agents/openai.yaml" ] && rm -f "$outdir/$name/agents/openai.yaml"
        "render_${prov}_skill_policy" > "$outdir/$name/agents/openai.yaml"
      fi
    else
      [ -L "$outdir/$name.md" ] && rm -f "$outdir/$name.md"
      "render_${prov}_command" > "$outdir/$name.md"
      printf '%s\n' "$GEN_MARKER" >> "$outdir/$name.md"
    fi
    count=$((count+1))
  done
  echo "✓ $prov  → $outdir  ($(ls -d "$CANON_DIR"/*/ | wc -l | tr -d ' ') entries, $fmt format)"
done
echo "Generated $count entry files from $CANON_DIR"
