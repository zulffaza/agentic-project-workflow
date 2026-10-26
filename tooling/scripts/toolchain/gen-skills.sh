#!/usr/bin/env bash
# Render per-provider copies of the shared procedural skills in tooling/skills/model/<name>/
# into managed provider directories. Copies, never symlinks: path tokens must be stamped with
# the install's absolute paths, and the installed tree must survive bundle relocation checks.
#
# Every rendered file gets a `.pw-generated` marker at the skill root. Regeneration replaces a
# target only when it is absent, a legacy symlink to that canonical skill, or already marked
# generated. Anything else is reported and left untouched (use --force to replace deliberately).
#
# Usage: gen-skills.sh [--outdir DIR] [--force] [provider ...]
#   --outdir DIR   write DIR/<provider>/<skill>/ instead of each provider's real dir (sandbox)
#   --force        replace an unmarked target directory
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # tooling/scripts/toolchain
MODEL_DIR="$HERE/../../skills/model"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"

OUTDIR_OVERRIDE=""
FORCE=0
ARGS_PROVIDERS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --outdir) OUTDIR_OVERRIDE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) ARGS_PROVIDERS+=("$1"); shift ;;
  esac
done
PROVIDERS=("${PW_PROVIDERS[@]}")
[ "${#ARGS_PROVIDERS[@]}" -gt 0 ] && PROVIDERS=("${ARGS_PROVIDERS[@]}")

MARKER='.pw-generated'
count=0

for prov in "${PROVIDERS[@]}"; do
  if [ -n "$OUTDIR_OVERRIDE" ]; then
    outdir="$OUTDIR_OVERRIDE/$prov"
  else
    if ! declare -f "${prov}_skilldir" >/dev/null 2>&1; then
      echo "gen-skills: $prov has no _skilldir hook — skipping" >&2; continue
    fi
    outdir="$("${prov}_skilldir")"
  fi
  pw_hook_dir_ok "$outdir" || { echo "gen-skills: unsafe skill dir for $prov ('$outdir')" >&2; exit 2; }
  mkdir -p "$outdir"
  skips="$(pw_skill_skips_for "$prov")"
  rendered=0
  for src in "$MODEL_DIR"/*/; do
    [ -f "${src}SKILL.md" ] || continue
    src="${src%/}"; name="$(basename "$src")"
    if [ -n "$skips" ] && printf '%s\n' "$skips" | grep -qx "$name"; then
      echo "    · skill '$name' not installed by design (name owned by its generated command-skill)"
      continue
    fi
    target="$outdir/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
      owned=0
      if [ -L "$target" ]; then
        # A legacy install of this exact canonical skill is ours to replace.
        [ "$(readlink "$target")" = "$src" ] && owned=1
      elif [ -f "$target/$MARKER" ]; then
        owned=1
      fi
      if [ "$owned" -ne 1 ] && [ "$FORCE" -ne 1 ]; then
        echo "    ✗ skill '$name' at $target is not bundle-managed — left untouched (--force to replace)" >&2
        continue
      fi
    fi
    stage="$outdir/.$name.pwstage.$$"
    rm -rf "$stage"; mkdir -p "$stage"
    # Preserve structure and modes; never follow a symlink out of the canonical skill.
    ( cd "$src" && tar -cf - . ) | ( cd "$stage" && tar -xf - )
    while IFS= read -r -d '' f; do
      pw_stamp_tokens "$f" || { echo "gen-skills: failed to stamp $f" >&2; rm -rf "$stage"; exit 1; }
    done < <(find "$stage" -type f -name '*.md' -print0)
    printf '%s\n' "$MARKER" > "$stage/$MARKER"
    rm -rf "$target"
    mv "$stage" "$target"
    rendered=$((rendered+1)); count=$((count+1))
  done
  echo "✓ $prov  → $outdir  ($rendered procedural skills rendered)"
done

echo "Rendered $count procedural skill(s) from $MODEL_DIR"
