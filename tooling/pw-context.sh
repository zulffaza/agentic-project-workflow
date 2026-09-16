#!/usr/bin/env bash
# ============================================================================
# pw-context.sh — deterministic context-doc editing (the context-doc entity)
#
#   pw-context.sh req-init   <slug>
#       Create context/REQUIREMENTS.md from context/_REQUIREMENTS.template.md
#       if missing (idempotent — an existing brief is never touched). Prints
#       the reminder to add its provenance row to context/INDEX.md.
#
#   pw-context.sh add-input  <slug> --file <f> --what <w> --source <s> [--trust <t>]
#       Append one row to context/INDEX.md's inputs table:
#       | <f> | <w> | <s> | <today> | <t|—> |. Replaces the template's empty
#       placeholder row when it is the insertion point; never touches `_e.g._`
#       example rows. "|" in values is escaped. A2 flag-segment shape (each
#       value runs until the next --flag — see tooling/docs/conventions.md).
#
#   pw-context.sh add-repo   <slug> <repo> <base> <why...>
#       Append one row to context/INDEX.md's "Repos in scope" table:
#       | <repo> | <base> | <why> |. A1 rest-of-line shape: everything after
#       <base> is the why. NEVER touches /pw-adopt's `<!-- pw-adopt-scope:… -->`
#       marker rows (append-only below them); same placeholder-row handling.
#
# Exit codes: 0 success · 2 usage/state error (stderr carries a → fix: hint).
# Portable bash 3.2+. Project slug resolves under $PW_PROJECTS_DIR.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
. "$HERE/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"
LIB="$HERE/pw-lib.sh"

die() { echo "pw-context: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }
_log() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$LIB" log "$1" "$2" "$3" >/dev/null; }

# Pipe-escape a table cell value.
_esc() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# True if a table row is the template's empty placeholder (every cell blank).
_is_placeholder_row() {
  printf '%s' "$1" | grep -qE '^\|([[:space:]]*\|)+[[:space:]]*$'
}

# _append_or_replace_row <index-file> <header-prefix> <row>
# Insert <row> after the last row of the table whose header row starts with the literal
# <header-prefix> (scan stops at the next "## " heading — md_table_last_row_line). If that
# last row is the empty placeholder, REPLACE it instead (the placeholder exists to
# be filled). Never edits any other row — `_e.g._` examples and pw-adopt marker
# rows are ordinary rows we only ever append below.
_append_or_replace_row() {
  local f="$1" hdr="$2" row="$3"
  local last; last="$(md_table_last_row_line "$f" "$hdr")"
  [ "$last" -gt 0 ] || die "no table with header matching '$hdr' found in ${f##*/} → fix: restore the table header from template/context/INDEX.md"
  local tmp; tmp="$(mktemp)"; printf '%s\n' "$row" > "$tmp"
  local lastline; lastline="$(sed -n "${last}p" "$f")"
  if _is_placeholder_row "$lastline"; then
    md_replace_line "$f" "$last" "$tmp"
  else
    md_insert_lines_after "$f" "$last" "$tmp"
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------- req-init
cmd_req_init() {
  [ $# -eq 1 ] || die "usage: req-init <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local f="$d/context/REQUIREMENTS.md" tmpl="$d/context/_REQUIREMENTS.template.md"
  if [ -f "$f" ]; then
    echo "$slug: context/REQUIREMENTS.md already exists (left untouched)"
    return 0
  fi
  [ -f "$tmpl" ] || die "no context/_REQUIREMENTS.template.md in $slug → fix: the project predates the template; copy it from $PW_HOME/template/context/_REQUIREMENTS.template.md"
  cp "$tmpl" "$f"
  _log "$slug" you "created context/REQUIREMENTS.md from template"
  echo "$slug: created context/REQUIREMENTS.md — fill it in, then add its provenance row:"
  echo "  pw-context.sh add-input $slug --file REQUIREMENTS.md --what 'project brief' --source 'written by you' --trust 'owner brief'"
}

# ---------------------------------------------------------------- add-input
# A2 flag-segment parsing is implemented NATIVELY here (each value runs until the
# next --flag token), so the script behaves identically whether the agent hands it
# pre-quoted argv or a human types the slash-command shape verbatim in a shell.
cmd_add_input() {
  local slug="$1"; shift
  local FILEV="" WHAT="" SOURCE="" TRUST="" flag val
  while [ $# -gt 0 ]; do
    flag="$1"; shift
    val=""
    case "$flag" in
      --file|--what|--source|--trust)
        # A2: the value runs until the next --flag token (ANY token starting with --,
        # known or not — an unknown one then dies below instead of being silently
        # swallowed into the previous value).
        while [ $# -gt 0 ]; do
          case "$1" in --*) break ;; esac
          val="${val:+$val }$1"; shift
        done
        [ -n "$val" ] || die "add-input: $flag requires a value → fix: --file <f> --what <w> --source <s> [--trust <t>], each value runs until the next --flag"
        ;;
      --file=*)   val="${flag#--file=}";   flag="--file" ;;
      --what=*)   val="${flag#--what=}";   flag="--what" ;;
      --source=*) val="${flag#--source=}"; flag="--source" ;;
      --trust=*)  val="${flag#--trust=}";  flag="--trust" ;;
      *) die "add-input: unknown option: $flag → fix: expected --file <f> --what <w> --source <s> [--trust <t>]" ;;
    esac
    case "$flag" in
      --file)   FILEV="$val" ;;
      --what)   WHAT="$val" ;;
      --source) SOURCE="$val" ;;
      --trust)  TRUST="$val" ;;
    esac
  done
  [ -n "$FILEV" ]  || die "add-input: --file is required → fix: the artifact's filename in context/ (or a bare URL)"
  [ -n "$WHAT" ]    || die "add-input: --what is required → fix: one phrase saying what the input is"
  [ -n "$SOURCE" ]  || die "add-input: --source is required → fix: where it came from (ticket key / URL / person)"
  [ -n "$TRUST" ]   || TRUST="—"
  local d; d="$(proj_dir "$slug")"
  local f="$d/context/INDEX.md"
  [ -f "$f" ] || die "no context/INDEX.md in $slug → fix: restore it from $PW_HOME/template/context/INDEX.md"
  local row
  row="| $(_esc "$FILEV") | $(_esc "$WHAT") | $(_esc "$SOURCE") | $(date '+%F') | $(_esc "$TRUST") |"
  _append_or_replace_row "$f" '| File / link |' "$row"
  _log "$slug" you "added context input to INDEX.md: $FILEV"
  echo "$slug: context/INDEX.md → input row added: $FILEV"
}

# ---------------------------------------------------------------- add-repo
cmd_add_repo() {
  [ $# -ge 4 ] || die "usage: add-repo <slug> <repo> <base> <why...>   (why is rest-of-line, unquoted)"
  local slug="$1" repo="$2" base="$3"; shift 3
  local why="$*"
  [ -n "$(printf '%s' "$why" | tr -d '[:space:]')" ] || die "add-repo: <why> is empty → fix: say why the repo is in scope (rest of the line after <base>)"
  local d; d="$(proj_dir "$slug")"
  local f="$d/context/INDEX.md"
  [ -f "$f" ] || die "no context/INDEX.md in $slug → fix: restore it from $PW_HOME/template/context/INDEX.md"
  local row
  row="| \`$(_esc "$repo")\` | \`$(_esc "$base")\` | $(_esc "$why") |"
  _append_or_replace_row "$f" '| Repo (in' "$row"
  _log "$slug" you "added repo to INDEX.md scope table: $repo@$base"
  echo "$slug: context/INDEX.md → repos-in-scope row added: $repo (base: $base)"
}

# ---------------------------------------------------------------- dispatch
[ $# -ge 1 ] || pw_usage
case "$1" in -h|--help) pw_usage ;; esac
OP="$1"; shift
case "$OP" in
  req-init)  cmd_req_init "$@" ;;
  add-input) cmd_add_input "$@" ;;
  add-repo)  cmd_add_repo "$@" ;;
  -h|--help) pw_usage ;;
  *) die "unknown operator: $OP → fix: expected req-init | add-input | add-repo (see --help)" ;;
esac
