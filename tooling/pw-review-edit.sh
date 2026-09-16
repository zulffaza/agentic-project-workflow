#!/usr/bin/env bash
# ============================================================================
# pw-review-edit.sh — deterministic review-doc editing (the review-doc entity)
#
#   pw-review-edit.sh init-all      <slug>
#       Create every missing review file for the project's docs: each
#       analysis/<topic>.md, task/PLAN.md, and task/T0n.md gets its sibling
#       review/<name>.review.md via pw-lib.sh review-init (idempotent —
#       existing review files are never touched). Exit 0 always.
#
#   pw-review-edit.sh signoff       <slug> <review-rel-path> <decision> [--by <name>]
#       Append a Sign-off row: | <now> | <by|you> | <decision> |.
#       decision ∈ approved | changes-requested | in-review (anything else is
#       refused). Append-only — never edits/deletes existing rows. The first
#       sign-off replaces the template's lone "| | | in-review |" placeholder.
#       DOCTRINE (C4): human-triggered only — an agent runs this ONLY verbatim
#       on the user's explicit instruction, never on its own initiative. The
#       agent-side path stays pw-lib.sh review auto-signoff (mode=auto only).
#
#   pw-review-edit.sh add-item      <slug> <review-rel-path> --section <§anchor>
#                                   (--text <ask...> | --stdin) [--actor <name>]
#       Append the next Rn item block at the end of "## Items": heading with
#       timestamp + (actor,…) + the pw-item-status: open marker, the ask as the
#       body, and the trailing --- rule. Then reindexes "## Contents".
#       --actor defaults to "you"; only pw-review/pw-reviewer surfaces pass
#       --actor "pw-reviewer". Never edits existing text.
#
#   pw-review-edit.sh answer        <slug> <review-rel-path> <Qid>
#                                   (--text <answer...> | --stdin)
#       Append your "> ↳ **you** (<now>): …" line under question Qid (e.g. Q2).
#       Refuses if the question is missing or already [ANSWERED]. Does NOT flip
#       the status — the agent folds the answer into the doc and flips it, per
#       docs/REVIEW.md. Multi-line text is quoted line-by-line.
#
#   pw-review-edit.sh add-question  <slug> <review-rel-path> --section <§anchor>
#                                   (--text <q...> | --stdin) [--actor <name>]
#       Agent-side symmetric helper: append the next Qn block ([PENDING] +
#       open marker) at the end of "## Open questions", then reindex.
#
#   pw-review-edit.sh resolve       <slug> <review-rel-path> <Id>
#                                   (--reply <text...> | --stdin)
#       Agent-side: resolve item/question Id IN PLACE — flips the SAME heading
#       ([OPEN]→[RESOLVED] / [PENDING]→[ANSWERED], tag + pw-item-status marker
#       together, never a second heading) and appends the quoted
#       "> ↳ **agent** (<now>): …" reply below the ask/answer. A Qid refuses
#       unless a "↳ **you**" line already exists (never answers on the human's
#       behalf). Human text is never edited or deleted. Then reindexes.
#
# Free-text arguments follow the A-rules (tooling/docs/conventions.md): one
# rest-of-line slot via --text (everything after it is the text, unquoted), or
# --stdin for quote-safe/multi-line handoff. The text is taken VERBATIM.
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

die() { echo "pw-review-edit: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }
now_ts() { date '+%F %H:%M'; }

# review_file <slug> <rel> → absolute path, validated as a review-shaped file
review_file() {
  local d; d="$(proj_dir "$1")"
  local f="$d/$2"
  [ -f "$f" ] || die "no such review file: $2 → fix: create it with: pw-review-edit.sh init-all $1 (or pw-lib.sh review-init $1 $2 <doc-rel-path>)"
  grep -q '^## Sign-off' "$f" || grep -q '^## Items' "$f" \
    || die "$2 has neither '## Items' nor '## Sign-off' — not a valid review file → fix: recreate from template/_REVIEW.template.md via pw-lib.sh review-init"
  printf '%s' "$f"
}

# ---------------------------------------------------------------- init-all
cmd_init_all() {
  [ $# -eq 1 ] || die "usage: init-all <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local doc rel rrel created=0 skipped=0
  local -a docs=()
  if [ -d "$d/analysis" ]; then
    while IFS= read -r doc; do docs+=("$doc"); done < <(
      find "$d/analysis" -maxdepth 1 -name '*.md' ! -name '_TEMPLATE*' ! -name 'README.md' | sort)
  fi
  [ -f "$d/task/PLAN.md" ] && docs+=("$d/task/PLAN.md")
  if [ -d "$d/task" ]; then
    while IFS= read -r doc; do docs+=("$doc"); done < <(
      find "$d/task" -maxdepth 1 -name 'T[0-9]*.md' | sort)
  fi
  if [ ${#docs[@]} -eq 0 ]; then
    echo "$slug: no analysis/task docs yet — nothing to create review files for"
    return 0
  fi
  for doc in "${docs[@]}"; do
    rel="${doc#$d/}"
    case "$rel" in
      analysis/*) rrel="analysis/review/$(basename "$rel" .md).review.md" ;;
      task/*)     rrel="task/review/$(basename "$rel" .md).review.md" ;;
      *) continue ;;
    esac
    if [ -f "$d/$rrel" ]; then
      skipped=$((skipped+1)); continue
    fi
    PW_PROJECTS_DIR="$PROJECTS_DIR" "$LIB" review-init "$slug" "$rrel" "$rel" >/dev/null \
      && { echo "created $rrel (for $rel)"; created=$((created+1)); } \
      || die "review-init failed for $rel → fix: run pw-lib.sh review-init $slug $rrel $rel manually and read its stderr"
  done
  echo "$slug: init-all — $created created, $skipped already present"
}

# ---------------------------------------------------------------- signoff
cmd_signoff() {
  local slug="$1" rel="$2" decision="$3" by="you"
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --by) [ $# -ge 2 ] || die "--by requires an argument"; by="$2"; shift 2 ;;
      --by=*) by="${1#--by=}"; shift ;;
      *) die "signoff: unknown option: $1 (try --help)" ;;
    esac
  done
  case "$decision" in
    approved|changes-requested|in-review) ;;
    *) die "invalid decision '$decision' → fix: use exactly one of: approved | changes-requested | in-review" ;;
  esac
  local f; f="$(review_file "$slug" "$rel")"
  grep -q '^## Sign-off' "$f" || die "$rel has no '## Sign-off' section → fix: not a gate-bearing review file; nothing to sign off"
  local ts row; ts="$(now_ts)"; row="| $ts | $by | $decision |"
  if grep -q '^| | | in-review |$' "$f"; then
    local tmp; tmp="$(mktemp)"
    awk -v row="$row" '{ if ($0 == "| | | in-review |") { print row; next } print }' "$f" > "$tmp"
    cat "$tmp" > "$f"; rm -f "$tmp"
  else
    local lastrow; lastrow="$(_signoff_last_real_row_line "$f")"
    [ "$lastrow" -gt 0 ] || die "no Sign-off table rows found in $rel → fix: the table lost its rows; restore the '| Date-time | By | Decision |' header + separator from template/_REVIEW.template.md"
    local tmp; tmp="$(mktemp)"; printf '%s\n' "$row" > "$tmp"
    md_insert_lines_after "$f" "$lastrow" "$tmp"; rm -f "$tmp"
  fi
  PW_PROJECTS_DIR="$PROJECTS_DIR" "$LIB" log "$slug" "$by" "signed off $rel: $decision (via pw-review-edit.sh)" >/dev/null
  echo "$slug: $rel → Sign-off row appended: $decision (by $by, $ts)"
}

# ------------------------------------------------------- shared block utils

# _next_id <file> <R|Q> → next free numeric id (max of live REAL headings + archived
# markers, +1). Placeholder stubs are excluded via _review_item_headings (same filter the
# gates/counts trust — an unfilled stub must not consume an id). Archived ids only survive
# as <!-- pw-archived:Rn --> pointer rows in the live file — scanning both keeps ids
# monotonic across archives.
_next_id() {
  local f="$1" p="$2" max=0 n
  while IFS= read -r h; do
    n="$(printf '%s' "$h" | sed -n "s/^### ${p}\([0-9][0-9]*\) ·.*/\1/p")"
    [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
  done < <(_review_item_headings "$f")
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ "$n" -gt "$max" ] && max="$n"
  done < <(grep -o "pw-archived:$p[0-9]*" "$f" 2>/dev/null | sed "s/pw-archived:$p//" || true)
  echo $((max+1))
}

# _read_text → TEXT from --text rest-of-line or --stdin (A3 verbatim handoff)
_TEXT="" _TEXT_SET=0
_read_text_opts() { # parses trailing opts of add-item/add-question; sets SECTION ACTOR TEXT
  while [ $# -gt 0 ]; do
    case "$1" in
      --section) [ $# -ge 2 ] || die "--section requires an argument"; SECTION="$2"; shift 2 ;;
      --section=*) SECTION="${1#--section=}"; shift ;;
      --actor) [ $# -ge 2 ] || die "--actor requires an argument"; ACTOR="$2"; shift 2 ;;
      --actor=*) ACTOR="${1#--actor=}"; shift ;;
      --text) shift; TEXT="$*"; _TEXT_SET=1; break ;;
      --stdin) TEXT="$(cat)"; _TEXT_SET=1; shift ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done
  [ "$_TEXT_SET" = 1 ] || die "no text given → fix: pass --text <the ask, rest of line unquoted> or --stdin (heredoc)"
  [ -n "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ] || die "text is empty → fix: --text/--stdin must carry the actual ask/answer"
  printf '%s\n' "$TEXT" | grep -qE '^#{2,3} ' \
    && die "text must not contain lines starting with '## '/'### ' (they would corrupt the heading scan) → fix: indent or quote the line"
  return 0
}

# _section_line <blanked-file> <heading-ERE> → line number (0 = absent)
_section_line() {
  awk -v re="$2" '$0 ~ re {print NR; exit} END{}' "$1" | head -1 | { read -r n; echo "${n:-0}"; }
}

# _write_block <tmpfile> <heading> <body-text> → heading + body + blank + ---
# (NO trailing blank line — insert-before callers append one; stub-replace callers inherit
# the blank line that already follows the stub's own --- in the file).
_write_block() {
  local out="$1" heading="$2" body="$3"
  {
    printf '%s\n' "$heading"
    printf '%s\n' "$body"
    printf '\n---\n'
  } > "$out"
}

# _stub_range <blanked> <R|Q> <sec-start> <sec-end> → "start end" of the template's unfilled
# placeholder stub (heading carrying <YYYY-MM-DD> + everything through its --- rule), or empty.
# Filling the stub in place (instead of appending below it) is the template's intended UX —
# the stub exists so hand-editors get valid syntax by copy-paste; a tool must not leave a
# duplicate phantom R1/Q1 above the first real item.
_stub_range() {
  awk -v p="$2" -v s="$3" -v e="$4" '
    NR>=s && NR<=e && index($0, "### " p) == 1 && index($0, "<YYYY-MM-DD") > 0 {st=NR}
    st && NR>=st && $0=="---" {print st, NR; exit}
  ' "$1"
}

_reindex() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$LIB" review reindex "$1" "$2" >/dev/null; }
_log() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$LIB" log "$1" "$2" "$3" >/dev/null; }

# ---------------------------------------------------------------- add-item
cmd_add_item() {
  local slug="$1" rel="$2"; shift 2
  local SECTION="" ACTOR="you" TEXT=""
  _read_text_opts "$@"
  [ -n "$SECTION" ] || die "add-item: --section <§anchor> is required → fix: anchor the item to a doc section, e.g. --section '§3 Affected repos'"
  local f; f="$(review_file "$slug" "$rel")"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local oq; oq="$(_section_line "$blanked" '^## Open questions')"
  [ "$oq" -gt 0 ] || { rm -f "$blanked"; die "$rel has no '## Open questions' heading — not a valid review file → fix: recreate from template/_REVIEW.template.md"; }
  local n; n="$(_next_id "$f" R)"
  local ts; ts="$(now_ts)"
  local heading="### R$n · $SECTION — [OPEN] ($ACTOR, $ts) <!-- pw-item-status: open -->"
  local block; block="$(mktemp)"; _write_block "$block" "$heading" "$TEXT"
  # Fill the template's unfilled R-stub in place when present; append at the section end otherwise.
  local items_start stub
  items_start="$(_section_line "$blanked" '^## Items')"
  [ "$items_start" -gt 0 ] || { rm -f "$blanked"; die "$rel has no '## Items' heading — not a valid review file → fix: recreate from template/_REVIEW.template.md"; }
  stub="$(_stub_range "$blanked" R "$items_start" "$((oq-1))")"
  if [ -n "$stub" ]; then
    md_replace_range "$f" "${stub% *}" "${stub#* }" "$block"
  else
    printf '\n' >> "$block"
    md_insert_lines_before "$f" "$oq" "$block"
  fi
  rm -f "$block" "$blanked"
  _reindex "$slug" "$rel"
  _log "$slug" "$ACTOR" "added R$n to $rel ($SECTION)"
  echo "$slug: $rel → R$n added ($SECTION, $ACTOR, $ts)"
}

# ---------------------------------------------------------------- answer
# _find_item_line <blanked> <Id> → "LINE<TAB>TAG" of the real heading (empty if none).
# Unfilled template stubs (carrying <YYYY-MM-DD) are NOT real headings — same filter as
# _review_item_headings — so answer/resolve can never operate on a placeholder.
_find_item_line() {
  awk -v id="$2" '
    /^### [RQ][0-9]+ · / && index($0, "<YYYY-MM-DD") == 0 {
      h = $0; sub(/^### /, "", h); sub(/ ·.*/, "", h)
      if (h == id) {
        tag = $0; sub(/^.*— \[/, "", tag); sub(/\].*/, "", tag)
        printf "%d\t%s\n", NR, tag; exit
      }
    }' "$1"
}

# _block_end <blanked> <start-line> → last line of the item's block (next ## /### heading - 1, EOF fallback)
_block_end() {
  awk -v s="$2" 'NR>s && /^(## |### )/ {print NR-1; exit} END{}' "$1" | head -1 | { read -r n; local total; total="$(wc -l < "$1" | tr -d ' ')"; echo "${n:-$total}"; }
}

cmd_answer() {
  local slug="$1" rel="$2" qid="$3"; shift 3
  local TEXT=""
  _read_text_opts "$@"
  case "$qid" in Q[0-9]*) ;; *) die "answer: question id must look like Q2 (got '$qid')" ;; esac
  local f; f="$(review_file "$slug" "$rel")"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local hit hl tag
  hit="$(_find_item_line "$blanked" "$qid")"
  [ -n "$hit" ] || { rm -f "$blanked"; die "no real question heading '$qid' in $rel → fix: check the '## Contents' table or grep '^### Q' for the live ids"; }
  hl="${hit%%$'\t'*}"; tag="${hit#*$'\t'}"
  [ "$tag" = "ANSWERED" ] && { rm -f "$blanked"; die "$qid in $rel is already [ANSWERED] → fix: open a NEW question (pw-review-edit.sh add-question) if this is a fresh ask; never re-answer a settled one"; }
  local bend; bend="$(_block_end "$blanked" "$hl")"
  # insertion point: before the block's trailing --- rule (last one in range), else end of block
  local ins
  ins="$(awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e && $0=="---" {n=NR} END{print n+0}' "$blanked")"
  if [ "$ins" -gt 0 ]; then ins=$((ins-1)); else ins="$bend"; fi
  # trim trailing blank lines from the insert point (we re-add exactly one blank separator)
  while [ "$ins" -gt "$hl" ] && [ -z "$(sed -n "${ins}p" "$blanked" | tr -d '[:space:]')" ]; do ins=$((ins-1)); done
  local quoted; quoted="$(mktemp)"
  {
    # blank quoted separator ('>') if the previous content line is already a ↳ quote block —
    # same quoted block, one blank quoted line between (template rule); a plain blank line otherwise
    local prev; prev="$(sed -n "${ins}p" "$blanked" | sed 's/[[:space:]]*$//')"
    case "$prev" in '>'*) printf '>\n' ;; *) printf '\n' ;; esac
    printf '%s\n' "$TEXT" | sed 's/^/> /; s/^> $/>/' | sed "1s|^> |> ↳ **you** ($(now_ts)): |"
  } > "$quoted"
  md_insert_lines_after "$f" "$ins" "$quoted"
  rm -f "$quoted" "$blanked"
  _log "$slug" you "answered $qid in $rel"
  echo "$slug: $rel → your answer was appended under $qid (agent folds it in + flips to [ANSWERED] on the next pass)"
}

# ---------------------------------------------------------------- add-question
cmd_add_question() {
  local slug="$1" rel="$2"; shift 2
  local SECTION="" ACTOR="agent" TEXT=""
  _read_text_opts "$@"
  [ -n "$SECTION" ] || die "add-question: --section <§anchor> is required"
  local f; f="$(review_file "$slug" "$rel")"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local oq; oq="$(_section_line "$blanked" '^## Open questions')"
  [ "$oq" -gt 0 ] || { rm -f "$blanked"; die "$rel has no '## Open questions' heading → fix: recreate from template/_REVIEW.template.md"; }
  # end of the Open-questions section = line before the next ## heading (Archived items / Sign-off)
  local send
  send="$(awk -v s="$oq" 'NR>s && /^## / {print NR; exit} END{}' "$blanked" | head -1)"
  [ -n "$send" ] || send="$(wc -l < "$blanked" | tr -d ' ')"
  local n; n="$(_next_id "$f" Q)"
  local ts; ts="$(now_ts)"
  local heading="### Q$n · $SECTION — [PENDING] ($ACTOR, $ts) <!-- pw-item-status: open -->"
  local block; block="$(mktemp)"; _write_block "$block" "$heading" "$TEXT"
  # Fill the template's unfilled Q-stub in place when present; append at the section end otherwise.
  local stub
  stub="$(_stub_range "$blanked" Q "$oq" "$((send-1))")"
  if [ -n "$stub" ]; then
    md_replace_range "$f" "${stub% *}" "${stub#* }" "$block"
  else
    printf '\n' >> "$block"
    md_insert_lines_before "$f" "$send" "$block"
  fi
  rm -f "$block" "$blanked"
  _reindex "$slug" "$rel"
  _log "$slug" "$ACTOR" "asked Q$n in $rel ($SECTION)"
  echo "$slug: $rel → Q$n added ($SECTION, $ACTOR, $ts) — awaiting the human's answer"
}

# ---------------------------------------------------------------- resolve
cmd_resolve() {
  local slug="$1" rel="$2" id="$3"; shift 3
  local TEXT=""
  # resolve takes its text via --reply/--stdin
  while [ $# -gt 0 ]; do
    case "$1" in
      --reply) shift; TEXT="$*"; _TEXT_SET=1; break ;;
      --stdin) TEXT="$(cat)"; _TEXT_SET=1; shift ;;
      *) die "resolve: unknown option: $1 (try --help)" ;;
    esac
  done
  [ "${_TEXT_SET:-0}" = 1 ] || die "resolve: no reply given → fix: pass --reply <what changed, rest of line> or --stdin"
  [ -n "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ] || die "resolve: reply is empty → fix: the reply must say what changed (never a bare 'fixed'/'done')"
  case "$id" in R[0-9]*|Q[0-9]*) ;; *) die "resolve: id must look like R3 or Q2 (got '$id')" ;; esac
  local f; f="$(review_file "$slug" "$rel")"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local hit hl tag
  hit="$(_find_item_line "$blanked" "$id")"
  [ -n "$hit" ] || { rm -f "$blanked"; die "no real heading '$id' in $rel → fix: check the '## Contents' table for live ids (archived ones live in the .archive.md sibling)"; }
  hl="${hit%%$'\t'*}"; tag="${hit#*$'\t'}"
  case "$tag" in
    RESOLVED|ANSWERED) rm -f "$blanked"; die "$id in $rel is already [$tag] → fix: resolving edits the SAME heading once, never a second pass — open a new item if this is new work" ;;
  esac
  local bend; bend="$(_block_end "$blanked" "$hl")"
  if [ "${id#Q}" != "$id" ]; then
    # question: a ↳ **you** line MUST already exist — never answer on the human's behalf
    awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e' "$blanked" | grep -q '↳ \*\*you\*\*' \
      || { rm -f "$blanked"; die "$id has no '↳ **you**' answer yet → fix: the human answers first (pw-review-edit.sh answer $slug $rel $id --text …); the agent only folds + flips afterwards"; }
  fi
  # 1) flip the SAME heading line in place (tag + marker together)
  local hline newtag newmark
  hline="$(sed -n "${hl}p" "$f")"
  case "$tag" in
    OPEN)    newtag="RESOLVED"; newmark="resolved" ;;
    PENDING) newtag="ANSWERED"; newmark="resolved" ;;
    *) rm -f "$blanked"; die "$id has unrecognized status tag [$tag] → fix: expected [OPEN] or [PENDING]" ;;
  esac
  printf '%s\n' "$hline" \
    | sed "s/\[$tag\]/[$newtag]/; s/pw-item-status: open/pw-item-status: $newmark/" > "$f.hdr"
  md_replace_line "$f" "$hl" "$f.hdr"; rm -f "$f.hdr"
  # 2) append the agent reply before the block's trailing --- (recompute on the CURRENT file:
  #    the heading flip was a 1-for-1 line replace, so blanked line numbers still hold)
  local ins
  ins="$(awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e && $0=="---" {n=NR} END{print n+0}' "$blanked")"
  if [ "$ins" -gt 0 ]; then ins=$((ins-1)); else ins="$bend"; fi
  while [ "$ins" -gt "$hl" ] && [ -z "$(sed -n "${ins}p" "$blanked" | tr -d '[:space:]')" ]; do ins=$((ins-1)); done
  local reply; reply="$(mktemp)"
  {
    local prev; prev="$(sed -n "${ins}p" "$blanked" | sed 's/[[:space:]]*$//')"
    case "$prev" in '>'*) printf '>\n' ;; *) printf '\n' ;; esac
    printf '%s\n' "$TEXT" | sed 's/^/> /; s/^> $/>/' | sed "1s|^> |> ↳ **agent** ($(now_ts)): |"
  } > "$reply"
  md_insert_lines_after "$f" "$ins" "$reply"
  rm -f "$reply" "$blanked"
  _reindex "$slug" "$rel"
  _log "$slug" agent "resolved $id in $rel"
  echo "$slug: $rel → $id flipped to [$newtag] in place, agent reply appended"
}

# ---------------------------------------------------------------- dispatch
[ $# -ge 1 ] || { pw_usage; }
case "$1" in -h|--help) pw_usage ;; esac
OP="$1"; shift
case "$OP" in
  init-all)     cmd_init_all "$@" ;;
  signoff)
    [ $# -ge 3 ] || die "usage: signoff <slug> <review-rel-path> <approved|changes-requested|in-review> [--by <name>]"
    cmd_signoff "$@" ;;
  add-item)
    [ $# -ge 2 ] || die "usage: add-item <slug> <review-rel-path> --section <§anchor> (--text <ask...> | --stdin) [--actor <name>]"
    cmd_add_item "$@" ;;
  answer)
    [ $# -ge 3 ] || die "usage: answer <slug> <review-rel-path> <Qid> (--text <answer...> | --stdin)"
    cmd_answer "$@" ;;
  add-question)
    [ $# -ge 2 ] || die "usage: add-question <slug> <review-rel-path> --section <§anchor> (--text <q...> | --stdin) [--actor <name>]"
    cmd_add_question "$@" ;;
  resolve)
    [ $# -ge 3 ] || die "usage: resolve <slug> <review-rel-path> <Rid|Qid> (--reply <text...> | --stdin)"
    cmd_resolve "$@" ;;
  -h|--help) pw_usage ;;
  *) die "unknown operator: $OP → fix: expected init-all | signoff | add-item | answer | add-question | resolve (see --help)" ;;
esac
