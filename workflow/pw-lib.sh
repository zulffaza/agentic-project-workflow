#!/usr/bin/env bash
# pw-lib.sh — mechanical helpers the /pw-* commands call so the load-bearing, format-sensitive
# steps (dashboard Status, LOG.md, phase read) are deterministic instead of hand-edited prose.
#
#   pw-lib.sh status <slug> <phase>      set dashboard Status: (validated) + auto-log the change
#   pw-lib.sh log    <slug> <actor> <msg...>   append a timestamped LOG.md line
#   pw-lib.sh phase  <slug>              print the current Status value (for scoping/status)
#   pw-lib.sh selftest                   run an isolated round-trip test
#
# Portable across Claude Code and KiloCode executors (plain bash; call by absolute path).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # …/base/workflow
PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"  # …/projects  (override for tests)
VALID_PHASES="context analysis breakdown executing review done"

die() { echo "pw-lib: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

cmd_log() {
  [ $# -ge 3 ] || die "usage: log <slug> <actor> <msg...>"
  local slug="$1" actor="$2"; shift 2
  local d; d="$(proj_dir "$slug")"
  printf '%s | %s | %s\n' "$(date '+%F %H:%M')" "$actor" "$*" >> "$d/LOG.md"
}

cmd_status() {
  [ $# -eq 2 ] || die "usage: status <slug> <phase>   (phase: $VALID_PHASES)"
  local slug="$1" phase="$2"
  case " $VALID_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $VALID_PHASES)";; esac
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  grep -q '^- \*\*Status:\*\*' "$f" || die "no '- **Status:**' line in $f"
  awk -v p="$phase" '!d && /^- \*\*Status:\*\*/ {print "- **Status:** " p; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" status "Status -> $phase"
  echo "$slug: Status -> $phase"
}

cmd_phase() {
  [ $# -eq 1 ] || die "usage: phase <slug>"
  local f; f="$(proj_dir "$1")/README.md"
  [ -f "$f" ] || die "no README.md in project $1"
  grep -m1 '^- \*\*Status:\*\*' "$f" | sed 's/^- \*\*Status:\*\*[[:space:]]*//'
}

cmd_selftest() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n  <!-- comment stays -->\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$0" status demo analysis >/dev/null
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$0" phase demo)"
  [ "$got" = "analysis" ] || die "selftest FAIL: phase='$got' (expected analysis)"
  grep -q '<!-- comment stays -->' "$tmp/demo/README.md" || die "selftest FAIL: clobbered trailing comment"
  grep -q '| status | Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing"
  PW_PROJECTS_DIR="$tmp" "$0" log demo analyze "wrote analysis/x.md" >/dev/null
  grep -q '| analyze | wrote analysis/x.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing"
  echo "selftest OK"
}

case "${1:-}" in
  status)   shift; cmd_status "$@" ;;
  log)      shift; cmd_log "$@" ;;
  phase)    shift; cmd_phase "$@" ;;
  selftest) cmd_selftest ;;
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
