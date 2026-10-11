#!/usr/bin/env bash
# pw-review-read.sh - read-only review facet; legacy pw-review.sh reads forward here.
#
#   pw-review-read.sh gate     --project <slug> --file <review-rel-path>
#       Latest decision; exit 0 for consumable approval, 1 for an unapproved gate.
#   pw-review-read.sh has-open --project <slug> --file <review-rel-path>
#       yes/no, exit 0/1; missing file means no.
#   pw-review-read.sh count    --project <slug> --file <review-rel-path>
#       open=N resolved=M items=K; missing file prints zero counts and exits 1.
#   pw-review-read.sh eligible --project <slug> --file <review-rel-path>
#       eligible=N open=A foldin=B awaiting=C unactionable=D; exit 0 iff N>0.
#   pw-review-read.sh scan     --project <slug> [--phase <context|analysis|plan|task-plan|task-exec|ship|rfc|close>]
#       Summary per review, including latest decision and By actor. Scans the
#       analysis/review, task/review, context/review, rfc/review, and review/ lanes.
#   pw-review-read.sh passes   --project <slug> [--json]
#       One line per review/ai/ handoff pass: pass-id, surface, state, artifact, verdict.
#
# Named-argument grammar: operation words first, every value named; --project
# selects the project in every project form. Scalar values are ONE token (quote spaces).
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
# _parse_rf <op> "$@" — shared named-grammar parse for the file-scoped readers
# (--project/--file only); sets RP_SLUG, RP_REL.
RP_SLUG=""; RP_REL=""
_parse_rf() {
  local _op="$1"; shift
  local a v
  RP_SLUG=""; RP_REL=""
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --file=*)    v="${a#*=}"; a="--file" ;;
    esac
    case "$a" in
      --project|--file)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) RP_SLUG="$v" ;; --file) RP_REL="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "$_op --project <slug> --file <review-rel-path>" ;;
      *) _pw_positional "$a" "$_op --project <slug> --file <review-rel-path>" ;;
    esac
  done
  [ -n "$RP_SLUG" ] || die "$_op: --project is required → fix: $_op --project <slug> --file <review-rel-path>"
  [ -n "$RP_REL" ] || die "$_op: --file is required → fix: the review file's project-relative path"
}
cmd_gate() {
  _parse_rf gate "$@"
  local f decision; f="$(read_path "$RP_SLUG" "$RP_REL")" || return 2
  [ -f "$f" ] || die "no such review file: $RP_REL → fix: /pw-review init --project $RP_SLUG --file $RP_REL --doc <doc-rel-path>"
  decision="$(_signoff_latest_decision "$f")" || die "no Sign-off table rows found in $RP_REL → fix: restore the review table through the agent"
  echo "$decision"
  if _review_approval_valid "$f"; then return 0; fi
  if _decision_is_approved "$decision"; then
    if _review_has_open_marker "$f"; then
      echo "pw-review: approval in $RP_REL is STALE for gate consumers; unresolved item/question remains → fix: resolve the open items, then approve explicitly: /pw-review signoff --project $RP_SLUG --file $RP_REL --decision approved" >&2
    else
      echo "pw-review: an explicit human changes-requested remains active in $RP_REL → fix: only the human can explicitly withdraw that rejection or approve" >&2
    fi
  fi
  return 1
}
cmd_has_open() {
  _parse_rf has-open "$@"
  local f; f="$(read_path "$RP_SLUG" "$RP_REL")" || return 2
  if [ -f "$f" ] && _review_has_open_marker "$f"; then echo yes; return 0; fi
  echo no; return 1
}
cmd_eligible() {
  _parse_rf eligible "$@"
  local f counts e; f="$(read_path "$RP_SLUG" "$RP_REL")" || return 2
  [ -f "$f" ] || die "no such review file: $RP_REL → fix: /pw-review init --project $RP_SLUG --file $RP_REL --doc <doc-rel-path>"
  counts="$(_review_eligible_counts "$f")"; echo "$RP_SLUG: $RP_REL → $counts"
  e="${counts#eligible=}"; e="${e%% *}"; [ "${e:-0}" -gt 0 ]
}
cmd_count() {
  _parse_rf count "$@"
  local f stripped counts items; f="$(read_path "$RP_SLUG" "$RP_REL")" || return 2
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
  local slug="" phase="" d f rel counts open resolved decision actor parts summary lane a v
  local files=()
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --phase=*)   v="${a#*=}"; a="--phase" ;;
    esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --phase)   [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --phase; v="$1"; shift; }; phase="$v" ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "scan --project <slug> [--phase <phase>]" ;;
      *) _pw_positional "$a" "scan --project <slug> [--phase <phase>]" ;;
    esac
  done
  [ -n "$slug" ] || die "scan: --project is required → fix: scan --project <slug> [--phase <phase>]"
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
    counts="$(cmd_count --project "$slug" --file "$rel" 2>/dev/null || true)"
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
  local slug="" json="" d root pd mf any=0 pid _pv a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --json) json="--json" ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "passes --project <slug> [--json]" ;;
      *) _pw_positional "$a" "passes --project <slug> [--json]" ;;
    esac
  done
  [ -n "$slug" ] || die "passes: --project is required → fix: passes --project <slug> [--json]"
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
