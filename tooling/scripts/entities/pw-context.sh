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
#   pw-context.sh ensure-input <slug> --file <f> --what <w> --source <s> [--trust <t>]
#       Keyed upsert for the inputs table (assisted preparation's repeat-run path):
#       identity = the normalized "File / link" cell (trim + one backtick pair +
#       \| unescape + space collapse; URL query parameters and case preserved).
#       No row → append (add-input shape); one row → update its what/source/trust
#       cells in place, keeping the original date; identical content → no write at
#       all. Duplicate rows for the key that do not all agree stop with a conflict
#       report (never deleted, nothing written). Phase context only.
#
#   pw-context.sh ensure-repo <slug> <repo> <base> <why...>
#       Keyed upsert for the "Repos in scope" table: identity = normalized
#       (repo, base). No row → append; one row → update its why in place; identical
#       → no write. Same repo on DIFFERENT bases stays two rows. NEVER touches
#       /pw-adopt's marker rows. Duplicates stop with a conflict. Phase context only.
#
#   pw-context.sh fetch    <slug> [--ignore-errors]
#       Fetch the CLI-handleable URLs (jira/gh/glab) in INDEX.md's provenance table;
#       Web/Lark rows print as agent-handled. (was pw-context-fetch.sh)
#
#   pw-context.sh adopt-snapshot <slug> <repo> <branch> [mr-url]
#       Snapshot git state for adoption; resolves the base from the MR target
#       (host-based forge resolution) and emits structured key: value lines.
#       (was pw-adopt-snapshot.sh)
#
#   pw-context.sh adopt    <slug> <repo> <branch> <base> [mr-url]
#       The CONTINUATION workflow's adoption record: append/upsert ONE unit into
#       context/ADOPTED.md keyed by repo@branch (never clobbers earlier units),
#       keep INDEX.md's provenance + "Repos in scope" rows in lockstep (hidden
#       pw-adopt-scope markers), and set the dashboard Adopted: pointer.
#       (was pw-lib.sh adopt — the context-doc entity owns these tables per S1a)
#
# Exit codes: 0 success · 2 usage/state error (stderr carries a → fix: hint).
# Portable bash 3.2+. Project slug resolves under $PW_PROJECTS_DIR.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"
ST="$HERE/pw-status.sh"

die() { echo "pw-context: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: /pw-new $1)"; printf '%s' "$d"; }
_log() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" log "$1" "$2" "$3" >/dev/null; }

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
  echo "  /pw-context $slug add-input --file REQUIREMENTS.md --what 'project brief' --source 'written by you' --trust 'owner brief'"
}

# Preparation writes context only (pw-preflight.sh prepare mirrors this gate). The manual
# row operators (add-input/add-repo) deliberately stay phase-free — they predate assisted
# preparation and keep their contract.
_require_context_phase() {
  local slug="$1" raw tok
  raw="$(PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" phase "$slug" 2>/dev/null || true)"
  tok="$(pw_phase_token "${raw:-missing}")"
  [ "$tok" = "context" ] || die "preparation writes context only — the README says: ${raw:-none} → fix: if you really mean to redo this project's context, reopen its analysis and PLAN reviews first with /pw-review, then run: /pw-status $slug rewind context, then re-run preparation"
}

# Conservative identity normalization for table-cell keys: trim, drop one surrounding
# backtick pair, unescape \| → |, collapse whitespace runs to one space. URL query
# parameters, case, and path shape are preserved (never merge distinct documents).
_norm_key() {
  local v="$1"
  v="$(printf '%s' "$v" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$v" in
    \`*\`) v="${v#\`}"; v="${v%\`}" ;;
  esac
  printf '%s' "$v" | sed -e 's/\\|/|/g' -e 's/[[:space:]][[:space:]]*/ /g'
}

# _table_data_rows <file> <header-prefix>
# One TAB-separated line per data row of the table whose header line starts with
# <header-prefix>: "NR<TAB>cell1<TAB>cell2<TAB>…". Escaped pipes (\|) never split
# cells (placeholder sentinel). Scan stops at the next "## " heading. Separator rows
# are skipped; blank placeholder rows are emitted (their cells normalize to "").
_table_data_rows() {
  awk -v hdr="$2" '
    index($0, hdr) == 1 { inT = 1; next }
    inT && /^## / { exit }
    inT && /^\|/ {
      if ($0 ~ /^\|[ \t:|+-]*\|[ \t]*$/) next
      line = $0; gsub(/\\\|/, "\001", line)
      n = split(line, c, "|")
      out = NR
      for (i = 2; i < n; i++) { gsub("\001", "|", c[i]); out = out "\t" c[i] }
      print out
    }' "$1"
}

# A2 flag-segment parsing shared by add-input/ensure-input: each value runs until the
# next --flag token, so the script behaves identically whether the agent hands it
# pre-quoted argv or a human types the slash-command shape verbatim in a shell.
# _parse_input_flags <op> "$@" → sets FILEV/WHAT/SOURCE/TRUST.
_parse_input_flags() {
  local _op="$1"; shift
  local flag val
  FILEV=""; WHAT=""; SOURCE=""; TRUST=""
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
        [ -n "$val" ] || die "$_op: $flag requires a value → fix: --file <f> --what <w> --source <s> [--trust <t>], each value runs until the next --flag"
        ;;
      --file=*)   val="${flag#--file=}";   flag="--file" ;;
      --what=*)   val="${flag#--what=}";   flag="--what" ;;
      --source=*) val="${flag#--source=}"; flag="--source" ;;
      --trust=*)  val="${flag#--trust=}";  flag="--trust" ;;
      *) die "$_op: unknown option: $flag → fix: expected --file <f> --what <w> --source <s> [--trust <t>]" ;;
    esac
    case "$flag" in
      --file)   FILEV="$val" ;;
      --what)   WHAT="$val" ;;
      --source) SOURCE="$val" ;;
      --trust)  TRUST="$val" ;;
    esac
  done
  [ -n "$FILEV" ]  || die "$_op: --file is required → fix: the artifact's filename in context/ (or a bare URL)"
  [ -n "$WHAT" ]    || die "$_op: --what is required → fix: one phrase saying what the input is"
  [ -n "$SOURCE" ]  || die "$_op: --source is required → fix: where it came from (ticket key / URL / person)"
  [ -n "$TRUST" ]   || TRUST="—"
}

# ---------------------------------------------------------------- add-input
cmd_add_input() {
  local slug="$1"; shift
  _parse_input_flags add-input "$@"
  local d; d="$(proj_dir "$slug")"
  local f="$d/context/INDEX.md"
  [ -f "$f" ] || die "no context/INDEX.md in $slug → fix: restore it from $PW_HOME/template/context/INDEX.md"
  local row ts
  ts="$(pw_now_wib)" || die "add-input: cannot format event timestamp → fix: check the date command and retry"
  row="| $(_esc "$FILEV") | $(_esc "$WHAT") | $(_esc "$SOURCE") | $ts | $(_esc "$TRUST") |"
  _append_or_replace_row "$f" '| File / link |' "$row"
  _log "$slug" you "added context input to INDEX.md: $FILEV"
  echo "$slug: context/INDEX.md → input row added: $FILEV"
}

# ---------------------------------------------------------------- ensure-input
# Keyed upsert so a preparation rerun neither duplicates a provenance row nor clobbers
# user corrections: match on the normalized File / link cell; update that row's
# what/source/trust in place (original date preserved) only when the content changed.
cmd_ensure_input() {
  local slug="$1"; shift
  _parse_input_flags ensure-input "$@"
  local d; d="$(proj_dir "$slug")"
  _require_context_phase "$slug"
  local f="$d/context/INDEX.md"
  [ -f "$f" ] || die "no context/INDEX.md in $slug → fix: restore it from $PW_HOME/template/context/INDEX.md"
  local key; key="$(_norm_key "$FILEV")"
  local rows; rows="$(_table_data_rows "$f" '| File / link |')"
  local n=0 line cfile cwhat csrc cdate ctrust
  local first_line="" first_date="" all_in=1 all_eq=1 fwhat="" fsrc="" ftrust="" where=""
  while IFS=$'\t' read -r line cfile cwhat csrc cdate ctrust; do
    [ -n "$line" ] || continue
    [ "$(_norm_key "$cfile")" = "$key" ] || continue
    n=$((n+1)); where="$where $line"
    [ "$(_norm_key "$cwhat")" = "$(_norm_key "$WHAT")" ] \
      && [ "$(_norm_key "$csrc")" = "$(_norm_key "$SOURCE")" ] \
      && [ "$(_norm_key "$ctrust")" = "$(_norm_key "$TRUST")" ] || all_in=0
    if [ "$n" -eq 1 ]; then
      first_line="$line"
      first_date="$(printf '%s' "$cdate" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      fwhat="$(_norm_key "$cwhat")"; fsrc="$(_norm_key "$csrc")"; ftrust="$(_norm_key "$ctrust")"
    else
      { [ "$(_norm_key "$cwhat")" = "$fwhat" ] && [ "$(_norm_key "$csrc")" = "$fsrc" ] \
        && [ "$(_norm_key "$ctrust")" = "$ftrust" ]; } || all_eq=0
    fi
  done <<< "$rows"
  if [ "$n" -gt 1 ] && [ "$all_in$all_eq" != "11" ]; then
    die "duplicate input rows for '$FILEV' disagree (line(s):$where) → fix: resolve the duplicates by hand in context/INDEX.md, then re-run preparation"
  fi
  if [ "$n" -ge 1 ] && [ "$all_in" = 1 ]; then
    echo "$slug: context/INDEX.md → input row already present (unchanged): $FILEV"
    return 0
  fi
  local row ts
  ts="$(pw_now_wib)" || die "ensure-input: cannot format event timestamp → fix: check the date command and retry"
  if [ "$n" -eq 0 ]; then
    row="| $(_esc "$FILEV") | $(_esc "$WHAT") | $(_esc "$SOURCE") | $ts | $(_esc "$TRUST") |"
    _append_or_replace_row "$f" '| File / link |' "$row"
    _log "$slug" prepare "registered context input in INDEX.md: $FILEV"
    echo "$slug: context/INDEX.md → input row added: $FILEV"
  else
    row="| $(_esc "$FILEV") | $(_esc "$WHAT") | $(_esc "$SOURCE") | $first_date | $(_esc "$TRUST") |"
    local tmp; tmp="$(mktemp)"; printf '%s\n' "$row" > "$tmp"
    md_replace_line "$f" "$first_line" "$tmp"; rm -f "$tmp"
    _log "$slug" prepare "updated context input in INDEX.md: $FILEV"
    echo "$slug: context/INDEX.md → input row updated: $FILEV"
  fi
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

# ---------------------------------------------------------------- ensure-repo
# Keyed upsert (identity = normalized (repo, base)) so preparation reruns neither duplicate
# a guess nor clobber user edits: a changed why updates that row in place; the same repo on
# a DIFFERENT base stays a separate row. /pw-adopt's marker rows are never touched.
cmd_ensure_repo() {
  [ $# -ge 4 ] || die "usage: ensure-repo <slug> <repo> <base> <why...>   (why is rest-of-line, unquoted)"
  local slug="$1" repo="$2" base="$3"; shift 3
  local why="$*"
  [ -n "$repo" ] && [ -n "$base" ] || die "ensure-repo: <repo> and <base> must not be empty → fix: pass the repo dir name and its likely base branch"
  [ -n "$(printf '%s' "$why" | tr -d '[:space:]')" ] || die "ensure-repo: <why> is empty → fix: say why the repo is in scope (rest of the line after <base>)"
  local d; d="$(proj_dir "$slug")"
  _require_context_phase "$slug"
  local f="$d/context/INDEX.md"
  [ -f "$f" ] || die "no context/INDEX.md in $slug → fix: restore it from $PW_HOME/template/context/INDEX.md"
  local rkey bkey; rkey="$(_norm_key "$repo")"; bkey="$(_norm_key "$base")"
  local rows; rows="$(_table_data_rows "$f" '| Repo (in')"
  local n=0 line crow cbase cwhy
  local first_line="" all_in=1 all_eq=1 fwhy="" where=""
  while IFS=$'\t' read -r line crow cbase cwhy; do
    [ -n "$line" ] || continue
    case "$cwhy" in *"pw-adopt-scope:"*) continue ;; esac
    [ "$(_norm_key "$crow")" = "$rkey" ] || continue
    [ "$(_norm_key "$cbase")" = "$bkey" ] || continue
    n=$((n+1)); where="$where $line"
    [ "$(_norm_key "$cwhy")" = "$(_norm_key "$why")" ] || all_in=0
    if [ "$n" -eq 1 ]; then
      first_line="$line"; fwhy="$(_norm_key "$cwhy")"
    else
      [ "$(_norm_key "$cwhy")" = "$fwhy" ] || all_eq=0
    fi
  done <<< "$rows"
  if [ "$n" -gt 1 ] && [ "$all_in$all_eq" != "11" ]; then
    die "duplicate (repo, base) rows for '$repo' on '$base' disagree (line(s):$where) → fix: resolve the duplicates by hand in context/INDEX.md, then re-run preparation"
  fi
  if [ "$n" -ge 1 ] && [ "$all_in" = 1 ]; then
    echo "$slug: context/INDEX.md → repos-in-scope row already present (unchanged): $repo (base: $base)"
    return 0
  fi
  local row
  row="| \`$(_esc "$repo")\` | \`$(_esc "$base")\` | $(_esc "$why") |"
  if [ "$n" -eq 0 ]; then
    _append_or_replace_row "$f" '| Repo (in' "$row"
    _log "$slug" prepare "registered repo in INDEX.md scope table: $repo@$base"
    echo "$slug: context/INDEX.md → repos-in-scope row added: $repo (base: $base)"
  else
    local tmp; tmp="$(mktemp)"; printf '%s\n' "$row" > "$tmp"
    md_replace_line "$f" "$first_line" "$tmp"; rm -f "$tmp"
    _log "$slug" prepare "updated repo in INDEX.md scope table: $repo@$base"
    echo "$slug: context/INDEX.md → repos-in-scope row updated: $repo (base: $base)"
  fi
}


# --- context-doc fetch/adopt operators (merged plan 20 Phase 3) ---

cmd_fetch() {
  IGNORE_ERRORS=0
  SLUG=""

  for arg in "$@"; do
    case "$arg" in
      --ignore-errors) IGNORE_ERRORS=1 ;;
      -h|--help) pw_usage ;;
      -*) die "unknown option: $arg" ;;
      *) SLUG="$arg" ;;
    esac
  done

  [ -n "$SLUG" ] || die "usage: fetch <slug> [--ignore-errors]"

  D="$(proj_dir "$SLUG")"
  INDEX="$D/context/INDEX.md"

  [ -f "$INDEX" ] || die "context/INDEX.md not found — run /pw-context <slug> to build the context pack"

  ERRORS=()
  SEP_RE='^[-: ]+$'   # markdown table separator cells ("---", ":---:", …)

  # Extract URLs from INDEX.md
  while IFS='|' read -r file _what _source _date _trust; do
    file="$(echo "$file" | pw_trim)"
    link="$file"   # provenance table col 1 = "File / link" — filename, bare URL, ticket key, or md link
  
    # Skip header/separator rows
    [[ "$file" =~ ^File ]] && continue
    [[ "$file" =~ $SEP_RE ]] && continue
    [ -z "$link" ] && continue
  
    # Extract URL from link field
    URL=""
    if echo "$link" | grep -q 'http'; then
      URL="$(echo "$link" | grep -o 'https\?://[^ )]*' || echo "")"
    elif echo "$link" | grep -qE '^[A-Z]+-[0-9]+$'; then
      # Bare Jira ticket
      URL="$link"
    fi
  
    [ -n "$URL" ] || continue
  
    echo "Fetching: $file ($URL)"
  
    # Dispatch to right CLI based on URL pattern
    FETCHED=0
  
    # Jira URL or bare ticket
    if echo "$URL" | grep -qE '(atlassian\.net/browse|[A-Z]+-[0-9]+)'; then
      if command -v jira >/dev/null 2>&1; then
        TICKET="$(echo "$URL" | grep -oE '[A-Z]+-[0-9]+' | head -1)"
        if jira issue view "$TICKET" 2>/dev/null; then
          FETCHED=1
        fi
      fi
    fi
  
    # GitHub issue/PR URL
    if [ "$FETCHED" -eq 0 ] && echo "$URL" | grep -q 'github.com'; then
      if command -v gh >/dev/null 2>&1; then
        if echo "$URL" | grep -q '/issues/'; then
          if gh issue view "$URL" 2>/dev/null; then
            FETCHED=1
          fi
        elif echo "$URL" | grep -q '/pull/'; then
          if gh pr view "$URL" 2>/dev/null; then
            FETCHED=1
          fi
        fi
      fi
    fi
  
    # GitLab issue/MR URL
    if [ "$FETCHED" -eq 0 ] && echo "$URL" | grep -q 'gitlab.com'; then
      if command -v glab >/dev/null 2>&1; then
        if echo "$URL" | grep -q '/-/issues/'; then
          if glab issue view "$URL" 2>/dev/null; then
            FETCHED=1
          fi
        elif echo "$URL" | grep -q '/-/merge_requests/'; then
          if glab mr view "$URL" 2>/dev/null; then
            FETCHED=1
          fi
        fi
      fi
    fi
  
    # Lark URL (not scriptable — skip)
    if echo "$URL" | grep -qE '(lark|feishu|doubao)\.com'; then
      echo "  (Lark URL — agent handles via platform skill)"
      continue
    fi
  
    # Fallback: no CLI handled this row. HTTP(S) rows are agent work (WebFetch / platform skill),
    # never a script error — fall through per the analysis fetch rules. Only non-URL rows (bare
    # ticket keys needing a missing jira CLI) are real errors.
    if [ "$FETCHED" -eq 0 ]; then
      if echo "$URL" | grep -q '^http'; then
        echo "  (no CLI fetched this — agent handles via WebFetch / platform skill)"
      elif [ "$IGNORE_ERRORS" -eq 1 ]; then
        echo "  $file — NOT fetched (--ignore-errors); treat with reduced confidence"
      else
        ERRORS+=("$file: cannot fetch $URL (no suitable CLI)")
      fi
    fi
  
    echo
  
  # Provenance-table rows only ("| … |"); strip the outer pipes so IFS splitting aligns.
  # Stop at "## Repos in scope" — that table's rows are (repo, base) pairs, never fetch targets.
  done < <(awk '/^## Repos in scope/{stop=1} !stop && /^\|/{s=$0; sub(/^[| \t]+/,"",s); sub(/[| \t]+$/,"",s); print s}' "$INDEX" || true)

  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "pw-context fetch: ${#ERRORS[@]} error(s):" >&2
    for err in "${ERRORS[@]}"; do
      echo "  - $err" >&2
    done
    exit 1
  fi

  echo "Context fetch complete"
}

cmd_adopt_snapshot() {
  [ $# -ge 3 ] || die "usage: adopt-snapshot <slug> <repo> <branch> [mr-url]"

  SLUG="$1"
  REPO="$2"
  BRANCH="$3"
  MR_URL="${4:-}"

  D="$(proj_dir "$SLUG")"
  REPO_DIR="$REPOS_DIR/$REPO"

  [ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR → fix: pass the repo dir name (repos live under $REPOS_DIR — clone it there first)"

  # Validate branch exists
  if ! git -C "$REPO_DIR" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    die "branch not found: $BRANCH → fix: fetch the branch first: git -C $REPO_DIR fetch origin"
  fi

  # Resolve base branch
  BASE=""
  BASE_SOURCE=""

  if [ -n "$MR_URL" ]; then
    # Extract base from MR target. Host-based forge resolution (like the mr-state block) — the old
    # "url contains gitlab|github" substring test is dead on self-hosted forges (source.golabs.io):
    # it skipped the target lookup and silently shipped an "unconfirmed" inferred base.
    mr_host="$(printf '%s' "$MR_URL" | sed -E 's|^.*@||; s|^https?://||; s|[:/].*||')"
    if [ "$mr_host" = "github.com" ]; then
      if command -v gh >/dev/null 2>&1; then
        MR_NUM="$(echo "$MR_URL" | grep -o 'pull/[0-9]*' | sed 's/pull\///')"
        if [ -n "$MR_NUM" ]; then
          BASE="$(gh pr view "$MR_NUM" --json baseRefName 2>/dev/null | grep -o '"baseRefName":"[^"]*"' | sed 's/"baseRefName":"//;s/"//' || echo "")"
          [ -n "$BASE" ] && BASE_SOURCE="from MR target"
        fi
      fi
    elif [ -n "$mr_host" ]; then
      if command -v glab >/dev/null 2>&1; then
        MR_IID="$(echo "$MR_URL" | grep -o 'merge_requests/[0-9]*' | sed 's/merge_requests\///')"
        if [ -n "$MR_IID" ]; then
          BASE="$(GITLAB_HOST="$mr_host" glab api "projects/:id/merge_requests/$MR_IID" 2>/dev/null | grep -o '"target_branch":"[^"]*"' | sed 's/"target_branch":"//;s/"//' || echo "")"
          [ -n "$BASE" ] && BASE_SOURCE="from MR target"
        fi
      fi
    fi
  fi

  # Fallback: infer base via merge-base
  if [ -z "$BASE" ]; then
    # Try common default branches
    for default_branch in master main develop; do
      if git -C "$REPO_DIR" rev-parse --verify "origin/$default_branch" >/dev/null 2>&1; then
        BASE="$default_branch"
        BASE_SOURCE="inferred, unconfirmed — no MR target"
        break
      fi
    done
  fi

  [ -n "$BASE" ] || die "cannot determine base branch (no MR and no default branch found)"

  # Snapshot git state
  COMMIT_COUNT=0
  FILES_CHANGED=0

  if git -C "$REPO_DIR" rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
    COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..$BRANCH" 2>/dev/null | wc -l | pw_trim)"
    FILES_CHANGED="$(git -C "$REPO_DIR" diff --stat "origin/$BASE...$BRANCH" 2>/dev/null | tail -1 | grep -o '[0-9]* file' | sed 's/ file//' || echo "0")"
  fi

  # Output structured data
  echo "repo: $REPO"
  echo "branch: $BRANCH"
  echo "base: $BASE ($BASE_SOURCE)"
  echo "mr-url: ${MR_URL:-none}"
  echo "commits: $COMMIT_COUNT"
  echo "files-changed: $FILES_CHANGED"
}

# Deterministically append/upsert ONE adoption unit into context/ADOPTED.md, keyed by repo@branch.
# Append-only per unit (new units go at EOF; re-adopting the same repo@branch updates that unit's
# Base/MR in place) — so adopting a 2nd branch can NEVER clobber the 1st (the bug free-form editing
# caused). The agent fills each unit's prose after; the structure/IDs/count are owned here.
#   adopt <slug> <repo> <branch> <base> [mr]
cmd_adopt() {
  [ $# -ge 4 ] || die "usage: adopt <slug> <repo> <branch> <base> [mr-url]"
  local slug="$1" repo="$2" branch="$3" base="$4" mr="${5:-none yet}"
  local d; d="$(proj_dir "$slug")"; local cdir="$d/context"; local f="$cdir/ADOPTED.md"
  mkdir -p "$cdir"
  local key="$repo @ $branch"
  if [ ! -f "$f" ]; then
    {
      printf '# Adopted work — %s   (CONTINUATION workflow)\n\n' "$slug"
      printf 'Builds on existing in-progress branches. Serialization is PER-BRANCH: tasks on the same\n'
      printf 'branch run serially in its shared worktree; tasks on different branches run in parallel.\n'
      printf 'Unit headings/IDs + the Base/MR lines are managed by `/pw-adopt` — do NOT hand-edit\n'
      printf 'them or the dashboard; fill the prose under each unit. [🤖🧑 both]\n'
    } > "$f"
  fi
  local uid; uid="$(awk -v key="$key" '
    /^## A[0-9]+ · / {
      h=$0; sub(/^## /,"",h);          # "A1 · <repo> @ <branch>"
      u=h; sub(/ .*/,"",u);            # first token = unit id
      if (length(h) >= length(key) && substr(h, length(h)-length(key)+1) == key) { print u; exit }
    }' "$f")"
  if [ -n "$uid" ]; then
    awk -v u="$uid" -v base="$base" -v mr="$mr" '
      $0 ~ ("^## " u " · ") { inU=1; print; next }
      inU && /^## A[0-9]+ · / { inU=0 }
      inU && /^- Base: / { print "- Base: " base; next }
      inU && /^- MR: /   { print "- MR: " mr;   next }
      { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    local n; n="$(grep -cE '^## A[0-9]+ · ' "$f" 2>/dev/null || true)"; : "${n:=0}"
    uid="A$((n+1))"
    {
      printf '\n## %s · %s @ %s\n' "$uid" "$repo" "$branch"
      printf -- '- Base: %s\n' "$base"
      printf -- '- MR: %s\n' "$mr"
      printf '### Already done\n<!-- pw-adopt %s already-done: replace with the commit list + diffstat summary -->\n' "$uid"
      printf '### Remaining work\n🧑 <!-- pw-adopt %s remaining: fill with what to change on top of this branch -->\n' "$uid"
    } >> "$f"
  fi
  _index_provenance_ensure "$cdir/INDEX.md" || die "adopt: cannot stamp provenance → fix: check the date command and retry"
  _scope_upsert "$cdir/INDEX.md" "$repo" "$branch" "$base" "$mr"
  local count; count="$(grep -cE '^## A[0-9]+ · ' "$f" 2>/dev/null || true)"; : "${count:=0}"
  "$ST" adopted "$slug" "$count unit(s) — continuation; see context/ADOPTED.md" >/dev/null
  _log "$slug" adopt "unit $uid: $repo@$branch (base $base, MR $mr)"
  echo "$slug: adopted $uid ($key) — base $base, MR $mr  [$count unit(s)]"
}

# ---------------------------------------------------------------- dispatch
[ $# -ge 1 ] || pw_usage
case "$1" in -h|--help) pw_usage ;; esac
OP="$1"; shift
case "$OP" in
  req-init)  cmd_req_init "$@" ;;
  add-input) cmd_add_input "$@" ;;
  ensure-input) cmd_ensure_input "$@" ;;
  ensure-repo)  cmd_ensure_repo "$@" ;;
  fetch)          cmd_fetch "$@" ;;
  adopt-snapshot) cmd_adopt_snapshot "$@" ;;
  adopt)          cmd_adopt "$@" ;;
  add-repo)  cmd_add_repo "$@" ;;
  -h|--help) pw_usage ;;
  *) die "unknown operator: $OP → fix: see --help (req-init, add-input, ensure-input, add-repo, ensure-repo, fetch, adopt-snapshot, adopt)" ;;
esac
