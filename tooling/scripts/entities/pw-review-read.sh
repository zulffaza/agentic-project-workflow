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
#   pw-review-read.sh scan     <slug> [--phase <context|analysis|plan|task-plan|task-exec|ship|rfc|close>]
#       Summary per review, including latest decision and By actor. Scans the
#       analysis/review, task/review, context/review, rfc/review, and review/ lanes.
#   pw-review-read.sh passes   <slug> [--json]
#       One line per review/ai/ handoff pass: pass-id, surface, state, artifact, verdict.
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
  counts="$(pw_review_item_counts "$f")"
  items="$(printf '%s\n' "$stripped" | awk '
    /^## Items/ {p=1; next}
    p && /^## / {p=0}
    p && /^###+ / && !/<YYYY-MM-DD/ && !/<DD MMMM YYYY/ && !/<§section/ {n++}
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
  case "$phase" in ''|context|analysis|plan|task-plan|task-exec|ship|rfc|close) ;; *) die "unknown review surface '$phase' → fix: use context, analysis, plan, task-plan, task-exec, ship, rfc, or close" ;; esac
  d="$(proj_dir "$slug")" || return 2
  # discovery through the shared lane walk (pw-reviewlib.sh): the same five lanes the
  # status surfaces cover — never a second directory list living here.
  local scanout="" esc_rel=""
  scanout="$(pw_review_files "$d")" || {
    esc_rel="$(printf '%s\n' "$scanout" | awk -F'\t' '$1=="escape"{print $2; exit}')"
    die "review directory escapes project: ${esc_rel:-review} → fix: remove the external symlink"
  }
  while IFS=$'\t' read -r _kind _lane f; do
    [ "$_kind" = file ] || continue
    files+=("$f")
  done <<EOF
$scanout
EOF
  [ ${#files[@]} -gt 0 ] || { echo 'No review files found'; return 0; }
  for f in "${files[@]}"; do
    rel="${f#$d/}"; f="$(read_path "$slug" "$rel")" || return 2
    lane="$(pw_review_lane "$rel")"
    case "$phase" in
      context) [ "$lane" = context ] || continue ;;
      analysis) [ "$lane" = analysis ] || continue ;;
      plan) [ "$lane" = plan ] || continue ;;
      task-plan|task-exec|ship) [ "$lane" = task ] || continue ;;
      rfc) [ "$lane" = rfccontent ] || continue ;;
      close) [ "$lane" = close ] || continue ;;
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
cmd_passes() {
  local slug="$1" json="${2:-}" d root pd mf any=0 pid _pv
  case "$json" in ''|--json) ;; *) die "passes: unknown option: $json (try --help)" ;; esac
  d="$(proj_dir "$slug")" || return 2
  root="$d/review/ai"
  [ -d "$root" ] || { echo 'No AI review passes found'; return 0; }
  _pfield() { # <manifest> <key> — the scalar after the first "key": (nested import object ok)
    local line
    line="$(grep -m1 "\"$2\":" "$1" 2>/dev/null || true)"
    printf '%s' "$line" | awk -v k="\"$2\":" '
      { i = index($0, k); if (!i) exit; s = substr($0, i + length(k)); sub(/^[ \t]+/, "", s)
        if (substr(s,1,1) == "\"") { s = substr(s,2); sub(/".*$/, "", s) } else { sub(/[,}].*$/, "", s) }
        print s }'
  }
  for pd in "$root"/*/; do
    mf="$pd/manifest.json"
    [ -f "$mf" ] || continue
    any=1
    pid="$(basename "${pd%/}")"
    _pv="$(_pfield "$mf" verdict)"; [ -n "$_pv" ] || _pv="—"
    if [ "$json" = "--json" ]; then
      printf '{"pass_id": "%s", "surface": "%s", "state": "%s", "artifact": "%s", "verdict": "%s", "round": "%s"}\n' \
        "$pid" "$(_pfield "$mf" surface)" "$(_pfield "$mf" state)" "$(_pfield "$mf" artifact)" \
        "$_pv" "$(_pfield "$mf" round)"
    else
      printf 'review/ai/%s: surface=%s state=%s artifact=%s round=%s verdict=%s\n' \
        "$pid" "$(_pfield "$mf" surface)" "$(_pfield "$mf" state)" "$(_pfield "$mf" artifact)" \
        "$(_pfield "$mf" round)" "$_pv"
    fi
  done
  [ "$any" = 1 ] || echo 'No AI review passes found'
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
  passes) cmd_passes "$@" ;;
  *) die "unknown read operator: $op → fix: see --help" ;;
esac
