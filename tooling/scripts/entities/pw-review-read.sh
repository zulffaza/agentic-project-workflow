#!/usr/bin/env bash
# pw-review-read.sh - read-only review facet; legacy pw-review.sh reads forward here.
#
#   pw-review-read.sh gate     <slug> <review-rel-path>
#       Latest decision; exit 0 for consumable approval, 1 for an unapproved gate.
#   pw-review-read.sh has-open <slug> <review-rel-path>
#       yes/no, exit 0/1; missing file means no.
#   pw-review-read.sh count    <slug> <review-rel-path>
#       open=N resolved=M items=K; missing file prints zero counts and exits 1.
#   pw-review-read.sh eligible <slug> <review-rel-path>
#       eligible=N open=A foldin=B awaiting=C unactionable=D; exit 0 iff N>0.
#   pw-review-read.sh scan     <slug> [--phase <analysis|plan|task-plan|task-exec|ship>]
#       Summary per review, including latest decision and By actor.
#
# Exit 2 means invalid usage, paths, or metadata. Reads never write project files.
# Bash 3.2+; old timestamp formats, actors, and approved decorations remain readable.
set -euo pipefail
if [ "${1:-}" = --selftest ]; then
  exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
. "$HERE/../lib/pw-reviewlib.sh"
PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
die() { echo "pw-review: $*" >&2; exit 2; }
proj_dir() {
  local slug="$1" base d
  case "$slug" in ''|.|..|*/*|*$'\n'*|*$'\r'*|*$'\t'*) die "invalid project slug → fix: use one project directory name" ;; esac
  [ -d "$PROJECTS_DIR/$slug" ] || die "no such project: $slug → fix: use /pw-new or check the project slug"
  base="$(cd "$PROJECTS_DIR" && pwd -P)" || return 2
  d="$(cd "$PROJECTS_DIR/$slug" && pwd -P)" || return 2
  case "$d/" in "$base/"*) ;; *) die "project escapes the projects directory → fix: select a project under the configured root" ;; esac
  printf '%s' "$d"
}
read_path() {
  local d; d="$(proj_dir "$1")" || return 2
  pw_review_contain "$d" "$2" >/dev/null || die "invalid review path: $2 → fix: keep it project-relative inside the selected project"
  printf '%s/%s' "$d" "$2"
}
cmd_gate() {
  [ $# -eq 2 ] || die 'usage: gate <slug> <review-rel-path>'
  local f decision; f="$(read_path "$1" "$2")" || return 2
  [ -f "$f" ] || die "no such review file: $2 → fix: /pw-review $1 init <artifact-path>"
  decision="$(_signoff_latest_decision "$f")" || die "no Sign-off table rows found in $2 → fix: restore the review table through the agent"
  echo "$decision"
  if _review_approval_valid "$f"; then return 0; fi
  if _decision_is_approved "$decision"; then
    if _review_has_open_marker "$f"; then
      echo "pw-review: approval in $2 is STALE for gate consumers; unresolved item/question remains → fix: /pw-review $1 $2, then explicitly approve after resolving the work" >&2
    else
      echo "pw-review: an explicit human changes-requested remains active in $2 → fix: only the human can explicitly withdraw that rejection or approve" >&2
    fi
  fi
  return 1
}
cmd_has_open() {
  [ $# -eq 2 ] || die 'usage: has-open <slug> <review-rel-path>'
  local f; f="$(read_path "$1" "$2")" || return 2
  if [ -f "$f" ] && _review_has_open_marker "$f"; then echo yes; return 0; fi
  echo no; return 1
}
cmd_eligible() {
  [ $# -eq 2 ] || die 'usage: eligible <slug> <review-rel-path>'
  local f counts e; f="$(read_path "$1" "$2")" || return 2
  [ -f "$f" ] || die "no such review file: $2 → fix: /pw-review $1 init <artifact-path>"
  counts="$(_review_eligible_counts "$f")"; echo "$1: $2 → $counts"
  e="${counts#eligible=}"; e="${e%% *}"; [ "${e:-0}" -gt 0 ]
}
cmd_count() {
  [ $# -eq 2 ] || die 'usage: count <slug> <review-rel-path>'
  local f stripped counts items; f="$(read_path "$1" "$2")" || return 2
  [ -f "$f" ] || { echo 'open=0 resolved=0'; return 1; }
  stripped="$(_comment_blanked "$f")"
  counts="$(_review_item_headings "$f" | awk "$_MD_STTAG"'
    { id=$0; sub(/^#+ /,"",id); sub(/[^A-Za-z0-9].*$/,"",id)
      tag=sttag($0,id)
      if(tag=="OPEN" || tag=="PENDING" || tag=="CONFLICT") open++
      if(tag=="RESOLVED" || tag=="ANSWERED") resolved++ }
    END {printf "open=%d resolved=%d",open+0,resolved+0}')"
  items="$(printf '%s\n' "$stripped" | awk '
    /^## Items/ {p=1; next}
    p && /^## / {p=0}
    p && /^###+ / && !/<YYYY-MM-DD/ && !/<§section/ {n++}
    END {print n+0}')"
  echo "$counts items=${items:-0}"
}
cmd_scan() {
  local slug="" phase="" d f rel counts open resolved decision actor parts summary lane
  local files=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) [ $# -ge 2 ] || die '--phase requires an argument'; phase="$2"; shift 2 ;;
      --phase=*) phase="${1#--phase=}"; shift ;;
      -h|--help) pw_usage ;;
      -*) die "unknown option: $1 → fix: see --help" ;;
      *) [ -z "$slug" ] || die 'scan accepts one project slug → fix: see --help'; slug="$1"; shift ;;
    esac
  done
  [ -n "$slug" ] || die 'usage: scan <slug> [--phase <phase>]'
  case "$phase" in ''|analysis|plan|task-plan|task-exec|ship) ;; *) die "unknown review phase '$phase' → fix: use analysis, plan, task-plan, task-exec, or ship" ;; esac
  d="$(proj_dir "$slug")" || return 2
  for rel in analysis/review task/review; do
    [ -d "$d/$rel" ] || continue
    pw_review_contain "$d" "$rel" >/dev/null || die "review directory escapes project: $rel → fix: remove the external symlink"
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$d/$rel" -name '*.review.md' -print0 2>/dev/null)
  done
  [ ${#files[@]} -gt 0 ] || { echo 'No review files found'; return 0; }
  for f in "${files[@]}"; do
    rel="${f#$d/}"; f="$(read_path "$slug" "$rel")" || return 2
    lane="$(pw_review_lane "$rel")"
    case "$phase" in
      analysis) [ "$lane" = analysis ] || continue ;;
      plan) [ "$lane" = plan ] || continue ;;
      task-plan|task-exec|ship) [ "$lane" = task ] || continue ;;
    esac
    counts="$(cmd_count "$slug" "$rel" 2>/dev/null || true)"
    open="$(printf '%s' "$counts" | sed -n 's/open=\([0-9]*\).*/\1/p')"; open="${open:-0}"
    resolved="$(printf '%s' "$counts" | sed -n 's/.*resolved=\([0-9]*\).*/\1/p')"; resolved="${resolved:-0}"
    decision="$(_signoff_latest_decision "$f")" || decision=""
    actor="$(_signoff_latest_actor "$f")" || actor=""
    parts=""; [ "$open" -eq 0 ] || parts="$open open"
    if [ "$resolved" -gt 0 ]; then parts="${parts:+$parts, }$resolved resolved"; fi
    summary="$rel:${parts:+ $parts}"
    if [ -n "$decision" ]; then summary="$summary ($decision${actor:+ · $actor})"; fi
    echo "$summary"
  done
  return 0
}
[ $# -ge 1 ] || pw_usage
case "$1" in -h|--help) pw_usage ;; esac
op="$1"; shift
case "$op" in
  gate) cmd_gate "$@" ;;
  has-open) cmd_has_open "$@" ;;
  count) cmd_count "$@" ;;
  eligible) cmd_eligible "$@" ;;
  scan) cmd_scan "$@" ;;
  *) die "unknown read operator: $op → fix: see --help" ;;
esac
