#!/usr/bin/env bash
# ============================================================================
# pw-review.sh — the review-doc entity: creation, deterministic editing, gate
# reads, and lifecycle (reindex/archive/reopen/auto-signoff) in one script.
#
# Facets (S1b): WRITE = init, init-all, signoff, add-item, answer, add-question,
#                      resolve, note-init, reindex, archive, reopen
#               READ  = gate, has-open, count, scan
#               SPECIAL = auto-signoff (the tool-enforced gate exception, mode=auto only)
#
# Merged from pw-review-edit.sh (plan 17), pw-review-scan.sh, and pw-lib's
# `review *` block (plan 20 entity consolidation). Operator semantics, output
# contracts, and doctrine guards are unchanged; old `pw-lib.sh review-init` is
# now `init`, and `pw-lib.sh review <sub>` callers drop the `review` prefix.
#
#   pw-review.sh init         <slug> <review-rel-path> <doc-rel-path>
#       Create one review file verbatim from the canonical template if missing
#       (idempotent — existing items/replies/Sign-off history never clobbered).
#   pw-review.sh init-all     <slug>
#       Batch version: every analysis doc, PLAN.md, and T0n.md gets its sibling
#       review file. Exit 0 always.
#   pw-review.sh gate         <slug> <review-rel-path>
#       Print the latest Sign-off decision VERBATIM; exit 0 iff approved.
#   pw-review.sh has-open     <slug> <review-rel-path>
#       Print yes/no + exit 0/1 (missing file -> "no" + exit 1, never an error).
#   pw-review.sh count        <slug> <review-rel-path>
#       "open=N resolved=M items=K" — THE single source of truth for any
#       "how many open?" display (same detector the gates trust).
#   pw-review.sh scan         <slug> [--phase <phase>]
#       Read-only project-wide summary, one line per review file.
#   pw-review.sh reindex      <slug> <review-rel-path>
#       (Re)build the heading-anchored "## Contents" table (auto-run by every
#       heading-changing operator here).
#   pw-review.sh archive      <slug> <review-rel-path>
#       Move fully-[RESOLVED]/[ANSWERED] blocks verbatim to the .archive.md
#       sibling with pointer rows; gate mechanisms provably unaffected.
#   pw-review.sh reopen       <slug> <review-rel-path>
#       Append a fresh in-review row when a fix lands AFTER approval (never
#       deletes history); harmless no-op when already open.
#   pw-review.sh note-init    <slug>
#       Create REVIEWER-NOTES.md with its header if missing (idempotent).
#   pw-review.sh auto-signoff <slug> <review-rel-path> <phase>
#       The ONE tool-enforced exception to "only a human clears a gate": refuses
#       unless this project's AI Review mode for <phase> is 'auto' (re-checked
#       here, never taken on the caller's word) AND zero real open items.
#   pw-review.sh signoff      <slug> <review-rel-path> <approved|changes-requested|in-review> [--by <name>]
#       DOCTRINE (C4): human-triggered only — an agent runs this ONLY verbatim
#       on the user's explicit instruction, never on its own initiative.
#   pw-review.sh add-item     <slug> <review-rel-path> --section <§anchor> (--text <ask...> | --stdin) [--actor <name>]
#   pw-review.sh answer       <slug> <review-rel-path> <Qid> (--text <answer...> | --stdin)
#   pw-review.sh add-question <slug> <review-rel-path> --section <§anchor> (--text <q...> | --stdin) [--actor <name>]
#   pw-review.sh resolve      <slug> <review-rel-path> <Rid|Qid> (--reply <text...> | --stdin)
#       Deterministic block editing: next Rn/Qn id, timestamps, pw-item-status
#       markers, --- rules, auto-reindex. Free text per the A-rules (one
#       rest-of-line --text slot or --stdin heredoc, VERBATIM). Human text is
#       never edited or deleted; resolve flips the SAME heading in place.
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
ST="$HERE/pw-status.sh"
CFG="$HERE/pw-config.sh"
# Mirror of the ai-review config phases (owned by pw-config.sh).
AI_REVIEW_PHASES="analysis plan task-plan task-exec ship"

die() { echo "pw-review: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }
now_ts() { date '+%F %H:%M'; }


# review_file <slug> <rel> → absolute path, validated as a review-shaped file
review_file() {
  local d; d="$(proj_dir "$1")"
  local f="$d/$2"
  [ -f "$f" ] || die "no such review file: $2 → fix: create it with: pw-review.sh init-all $1 (or pw-review.sh init $1 $2 <doc-rel-path>)"
  grep -q '^## Sign-off' "$f" || grep -q '^## Items' "$f" \
    || die "$2 has neither '## Items' nor '## Sign-off' — not a valid review file → fix: recreate from template/_REVIEW.template.md via pw-review.sh init"
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
    if cmd_init "$slug" "$rrel" "$rel" >/dev/null; then echo "created $rrel (for $rel)"; created=$((created+1)); else die "init failed for $rel → fix: run pw-review.sh init $slug $rrel $rel manually and read its stderr"; fi
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
  PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" log "$slug" "$by" "signed off $rel: $decision (via pw-review.sh)" >/dev/null
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

_reindex() { cmd_reindex "$1" "$2" >/dev/null; }
_log() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" log "$1" "$2" "$3" >/dev/null; }

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
  [ "$tag" = "ANSWERED" ] && { rm -f "$blanked"; die "$qid in $rel is already [ANSWERED] → fix: open a NEW question (pw-review.sh add-question) if this is a fresh ask; never re-answer a settled one"; }
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
      || { rm -f "$blanked"; die "$id has no '↳ **you**' answer yet → fix: the human answers first (pw-review.sh answer $slug $rel $id --text …); the agent only folds + flips afterwards"; }
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


# --- lifecycle + gate reads (merged from pw-lib's review block, plan 20) ---

# Create a review file from the canonical template if (and only if) it doesn't exist yet —
# idempotent, so calling this on every /pw-analyze or /pw-breakdown run never clobbers a review
# already in progress (your items, replies, Sign-off history). This is the deterministic fix for
# "I had to manually copy the review template myself" and for review files silently missing the
# permanent format hints under ## Items / ## Open questions (this always copies the template
# byte-for-byte, so those hints and the worked examples are never dropped).
#   init <slug> <review-rel-path> <doc-rel-path>
#   e.g. init myproj analysis/review/topic.review.md analysis/topic.md
cmd_init() {
  [ $# -eq 3 ] || die "usage: init <slug> <review-rel-path> <doc-rel-path>"
  local slug="$1" rel="$2" docrel="$3"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  if [ -f "$f" ]; then
    echo "$slug: review already exists: $rel (left untouched)"
    return 0
  fi
  local tmpl="$HERE/../../../template/_REVIEW.template.md"
  [ -f "$tmpl" ] || die "template not found: $tmpl"
  local docname; docname="$(basename "$docrel")"
  mkdir -p "$(dirname "$f")"
  sed "s|<doc\\.md>|$docname|g" "$tmpl" > "$f"
  _log "$slug" review "created $rel (in-review, awaiting your items)"
  echo "$slug: init created $rel (reviewing ../$docname)"
}

# Private: this project's mode for one phase (always "off"/"advisory"/"auto" — never empty, since
# cmd_ai_review ensures the line first). Used by cmd_review_auto_signoff's gate check.
_ai_review_mode_of() {
  local slug="$1" phase="$2" modes kv
  modes="$("$CFG" ai-review "$slug")"   # the config entity owns the modes
  for kv in $modes; do
    [ "${kv%%=*}" = "$phase" ] && { echo "${kv#*=}"; return 0; }
  done
  echo "off"
}

# Create REVIEWER-NOTES.md with its header if (and only if) it doesn't exist yet — idempotent,
# same shape as cmd_review_init/cmd_rfc_init. pw-reviewer appends its own dated section directly
# after this (free-form reasoning prose doesn't fit a CLI-args shape — same precedent as a task's
# ## Result section, which executors already fill by hand rather than through a wrapper).
#   review note-init <slug>
cmd_note_init() {
  [ $# -eq 1 ] || die "usage: note-init <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local f="$d/REVIEWER-NOTES.md"
  if [ -f "$f" ]; then
    echo "$slug: REVIEWER-NOTES.md already exists (left untouched)"
    return 0
  fi
  {
    printf '# Reviewer notes — %s\n\n' "$slug"
    printf 'Append-only journal from `pw-reviewer` AI-review passes (see `docs/REVIEW.md` and the\n'
    printf "\`pw-review\` skill) — NOT the gate itself (that stays in each \`.review.md\`'s Items/\n"
    printf 'Sign-off). This is the *why*: what the reviewer checked, what it decided, and any\n'
    printf 'generalizable takeaway under a `**Lessons:**` line (optional — only when something is\n'
    printf 'genuinely worth carrying forward, not on every pass). A human, a later reviewer pass, the\n'
    printf "orchestrator, and (if configured) /pw-close's memory-seeding step all read this — never\n"
    printf 'hand-edit a past entry; append a new dated section per pass.\n\n'
    printf 'Per-entry shape — keep %s and %s short bullets, never a paragraph, so a scan of this\n' \
      '**Reasoning**' 'each field'
    printf 'file stays fast even after many passes; end every entry with a `---` rule:\n\n'
    printf '## <YYYY-MM-DD HH:MM> · <phase> · <artifact-rel-path> · mode=<advisory|auto>\n'
    printf -- '- **Verdict:** <n items filed | clean pass — auto-approved | clean pass — awaiting\n'
    printf '  human | ESCALATED — §<anchor> recurred twice, needs a human>\n'
    printf -- '- **Reasoning:** 2-4 short bullets, not a paragraph — one line per distinct point\n'
    printf '  - <what you checked>\n'
    printf '  - <what stood out, and why that verdict>\n'
    printf -- '- **Lessons:** <optional — 1-3 bullets, ONLY when genuinely generalizable; omit this\n'
    printf '  field entirely most passes>\n\n'
    printf -- '---\n'
  } > "$f"
  _log "$slug" review "created REVIEWER-NOTES.md"
  echo "$slug: review note-init created REVIEWER-NOTES.md"
}

# Deterministic, unambiguous replacement for prose like "look for an approved row anywhere in this
# file" — the ambiguity that let a stale historical approval keep satisfying a hard gate after a
# later `in-review`/`changes-requested` row superseded it (exactly what /pw-breakdown's analysis
# gate and /pw-execute's PLAN gate must NOT do once a doc is reopened post-approval — see
# docs/RFC.md). Prints the current decision text VERBATIM (so an old file's literal "approved ✅"
# still prints that, not a rewritten "approved") — the exit code is what accepts both forms, via
# _decision_is_approved.
#   review gate <slug> <review-rel-path>
cmd_gate() {
  [ $# -eq 2 ] || die "usage: gate <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local decision; decision="$(_signoff_latest_decision "$f")" \
    || die "no Sign-off table rows found in $rel — not a valid review file"
  echo "$decision"
  _decision_is_approved "$decision"
}

# The other half of the analysis/RFC parity fix (docs/RFC.md): a fix applied to a doc AFTER its
# review file was already approved (e.g. an RFC comment folded back into the analysis post-
# approval) must invalidate that stale approval, or `review gate` above would still wrongly pass.
# Appends a fresh `in-review` row — NEVER deletes the old approval, same append-only-history rule
# as a human's own manual reopen (template's Sign-off section: "Add a new 'in-review' row, don't
# delete the old approval"). Idempotent no-op if the file isn't currently approved (accepts either
# form via _decision_is_approved — nothing stale to invalidate otherwise) — safe for a caller to
# call unconditionally before applying a fix, no extra branching needed. Tagged
# "pw-review (auto-reopen)" so it's never mistaken for a human's own `changes-requested` decision on
# a skim of the file or its git history.
#   review reopen <slug> <review-rel-path>
cmd_reopen() {
  [ $# -eq 2 ] || die "usage: reopen <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local decision; decision="$(_signoff_latest_decision "$f")" \
    || die "no Sign-off table rows found in $rel — not a valid review file"
  if ! _decision_is_approved "$decision"; then
    echo "$slug: $rel already open (current: $decision) — nothing to reopen"
    return 0
  fi
  local lastrow; lastrow="$(_signoff_last_real_row_line "$f")"
  local ts row; ts="$(date '+%F %H:%M')"; row="| $ts | pw-review (auto-reopen) | in-review |"
  { head -n "$lastrow" "$f"; printf '%s\n' "$row"; tail -n "+$((lastrow+1))" "$f"; } \
    > "$f.tmp" && mv "$f.tmp" "$f"
  _log "$slug" pw-review "AUTO-REOPENED $rel — a fix was applied after it was already approved (new row: in-review); re-approve once settled"
  echo "$slug: $rel reopened (was $decision, now in-review)"
}

# Write the Sign-off row on a review file WITHOUT a human — the ONE tool-enforced exception to
# "only a human clears a gate" (template/_REVIEW.template.md's own rule). Refuses unless BOTH:
# (1) this project's AI Review mode for <phase> is genuinely "auto" (checked here, never taken on
# the caller's word), and (2) the file has no real remaining open item/question per
# _review_has_open_marker above. The row is tagged "pw-reviewer (auto)", never blended with a
# human "you" row, so it's never mistaken for a human decision on a skim of the file or its git
# history.
#   review auto-signoff <slug> <review-rel-path> <phase>
cmd_auto_signoff() {
  [ $# -eq 3 ] || die "usage: auto-signoff <slug> <review-rel-path> <phase>   (phase: $AI_REVIEW_PHASES)"
  local slug="$1" rel="$2" phase="$3"
  case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local mode; mode="$(_ai_review_mode_of "$slug" "$phase")"
  [ "$mode" = "auto" ] || die "refusing auto-signoff: this project's AI Review mode for '$phase' is '$mode', not 'auto' (pw-config.sh ai-review $slug $phase auto to enable)"
  _review_has_open_marker "$f" && die "refusing auto-signoff: $rel still has an unresolved [OPEN] item or [PENDING] question"
  local signline; signline="$(grep -n '^## Sign-off' "$f" | head -1 | cut -d: -f1)"
  [ -n "$signline" ] || die "no '## Sign-off' section in $rel — not a valid review file"
  local ts row; ts="$(date '+%F %H:%M')"; row="| $ts | pw-reviewer (auto) | approved |"
  if grep -q '^| | | in-review |$' "$f"; then
    # first sign-off on this file → replace the template's lone placeholder row
    awk -v row="$row" '{ if ($0 == "| | | in-review |") { print row; next } print }' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    # a re-review cycle already replaced/added rows → append ours as the table's new last row
    # (head/tail splice, not awk -v — same portability reasoning as _ship_comment_section_ensure:
    # no shell-quote gymnastics, no awk variable involved). Uses the comment-stripped scanner, not
    # a raw "last | line from ## Sign-off to EOF" — the raw version picks the template's own
    # WORKED-EXAMPLE Sign-off rows (inside a trailing <!-- --> block) since they're the last such
    # lines in the whole file, corrupting a SECOND-or-later signoff. See _signoff_last_real_row_line.
    local lastrow; lastrow="$(_signoff_last_real_row_line "$f")"
    [ "$lastrow" -gt 0 ] || die "no Sign-off table rows found in $rel"
    { head -n "$lastrow" "$f"; printf '%s\n' "$row"; tail -n "+$((lastrow+1))" "$f"; } \
      > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  _log "$slug" pw-reviewer "AUTO-APPROVED $rel (phase=$phase, AI Review mode=auto, zero open items) — no human sign-off"
  echo "$slug: $rel auto-signed-off by pw-reviewer (phase=$phase)"
}

# Generic open-item check — reuses _review_has_open_marker (the same detector `auto-signoff` relies
# on) but exposed standalone, since not every open-item check hangs off a Sign-off gate.
# `analysis/review/RFC.review.md` has no Sign-off table of its own (pulled comments there are
# informational staging, never individually approved as a unit) — so `review gate` doesn't apply to
# it, but /pw-breakdown still needs to know whether any pulled comment is sitting unresolved before
# letting the analysis's own approval unblock breakdown. Missing file → "no" + exit 1 (no RFC
# negotiation in flight, not an error) rather than dying — plenty of projects never touch the RFC
# side-loop at all, and that must never be treated as a failure.
#   review has-open <slug> <review-rel-path>
cmd_has_open() {
  [ $# -eq 2 ] || die "usage: has-open <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  if [ ! -f "$f" ]; then
    echo "no"
    return 1
  fi
  if _review_has_open_marker "$f"; then
    echo "yes"
    return 0
  fi
  echo "no"
  return 1
}

# Machine-count of real item states in one review file — THE single source of truth for any
# "how many open?" display (pw-review.sh scan, pw-status). Reuses the exact _comment_blanked +
# heading-marker detector the gates trust, so a dashboard line can never again disagree with a
# Sign-off decision: the template's guidance blockquote ("Add an item: … <!-- pw-item-status:
# open -->") is prose on a '>' line, matches only `^###` headings, and can never inflate a count.
# Text-tag fallbacks (pre-marker files: [OPEN]/[PENDING]/emoji) counted per heading line, only
# when that heading carries no machine marker at all.
#   review count <slug> <review-rel-path>   -> "open=N resolved=M items=K" (missing file -> all 0, exit 1)
cmd_count() {
  [ $# -eq 2 ] || die "usage: count <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || { echo "open=0 resolved=0"; return 1; }
  local h stripped open=0 fb res=0 fb2
  stripped="$(_comment_blanked "$f")"
  h="$(_review_item_headings "$f")"
  open="$(printf '%s\n' "$h" | grep -cE '^###+ .*pw-item-status: open' || true)"; open="${open:-0}"
  fb="$(printf '%s\n' "$h" | grep -E '^###+ .*(🔴 open|⏳ awaiting answer|\[OPEN\]|\[PENDING\])' | grep -v 'pw-item-status:' | grep -c . || true)"
  res="$(printf '%s\n' "$h" | grep -cE '^###+ .*pw-item-status: resolved' || true)"; res="${res:-0}"
  fb2="$(printf '%s\n' "$h" | grep -E '^###+ .*(\[RESOLVED\]|\[ANSWERED\])' | grep -v 'pw-item-status:' | grep -c . || true)"
  # items: real item HEADINGS under "## Items" (section rule identical to the template) — lets
  # consumers like pw-doc-lint's marker-vs-items check compare like with like in ONE pass,
  # without re-reading the raw file (which would count headings living inside the worked-example
  # comment block — exactly the un-blanked-read half of the C22 phantom).
  local items
  items="$(printf '%s\n' "$stripped" | awk '
    /^## Items/ {p=1; next}
    p && /^## / {p=0}
    p && /^###+ / && !/<YYYY-MM-DD/ && !/<§section/ {n++}
    END {print n+0}')"
  echo "open=$((open + ${fb:-0})) resolved=$((res + ${fb2:-0})) items=${items:-0}"
}

# Idempotently (re)build the heading-text-anchored "## Contents" table — ID / section-anchor /
# status for every real item/question, in file order — so applying ONE review item only requires
# jumping to the section it names instead of reading the whole file to find it. Anchored by
# HEADING TEXT, never a line number (a rewrite shifts lines; heading text doesn't), so re-running
# this after any edit is always safe — never goes stale the way a line-number index would.
#   review reindex <slug> <review-rel-path>
cmd_reindex() {
  [ $# -eq 2 ] || die "usage: reindex <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local rows; rows="$(_review_items_tsv "$f" | cut -f2-)"
  local block; block="$(mktemp)"
  {
    printf '<!-- pw-contents:begin -->\n'
    printf '## Contents   [🤖-owned — regenerated by `pw-review.sh reindex`; never hand-edit]\n\n'
    printf '| ID | Section / anchor | Status |\n|----|-------------------|--------|\n'
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows" | awk -F'\t' '{printf "| %s | %s | [%s] |\n", $1, $2, $3}'
    else
      printf '| _(none yet)_ | | |\n'
    fi
    printf '<!-- pw-contents:end -->\n'
  } > "$block"
  if grep -q '<!-- pw-contents:begin -->' "$f"; then
    local b e
    b="$(grep -n '<!-- pw-contents:begin -->' "$f" | head -1 | cut -d: -f1)"
    e="$(grep -n '<!-- pw-contents:end -->' "$f" | head -1 | cut -d: -f1)"
    { head -n "$((b-1))" "$f"; cat "$block"; tail -n "+$((e+1))" "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
  else
    local anchor; anchor="$(grep -n '^Gate:' "$f" | head -1 | cut -d: -f1)"
    if [ -n "$anchor" ]; then
      { head -n "$anchor" "$f"; printf '\n'; cat "$block"; tail -n "+$((anchor+1))" "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
    else
      { cat "$block"; printf '\n'; cat "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
    fi
  fi
  rm -f "$block"
  local n; n="$(printf '%s\n' "$rows" | grep -c . || true)"; : "${n:=0}"
  _log "$slug" review "reindexed $rel ($n live item(s)/question(s))"
  echo "$slug: reindexed $rel ($n item(s)/question(s))"
}

# Move every fully-resolved ([RESOLVED] item / [ANSWERED] question) heading block out of the live
# review file, VERBATIM, into a sibling "<topic>.archive.md" — replacing it with one pointer row
# in a "## Archived items" table. This is what keeps a long-lived, many-round review file from
# forcing every future round to re-read the whole resolved history just to apply one new item.
#
# Gate-safety (why this can never break a hard gate): cmd_gate/cmd_reopen/
# cmd_auto_signoff only ever read the "## Sign-off" table's latest row
# (_signoff_latest_decision) and the open-marker check (_review_has_open_marker). This function
# NEVER touches [OPEN]/[PENDING] headings and never writes to "## Sign-off" — it only ever moves
# headings whose marker already reads resolved/answered — so both gate mechanisms are provably
# unaffected by any archive run. Never edits or deletes the human's original ask/answer text —
# moved byte-for-byte verbatim.
#   review archive <slug> <review-rel-path>
cmd_archive() {
  [ $# -eq 2 ] || die "usage: archive <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local archrel="${rel%.review.md}.archive.md"
  local af="$d/$archrel"

  # Ensure the section exists FIRST (idempotent, positioned right before ## Sign-off — same splice
  # pattern _ship_comment_section_ensure uses). This always lands strictly AFTER every item/
  # question heading, so it can never shift the line ranges computed below.
  if ! grep -q '^## Archived items' "$f"; then
    local secfile; secfile="$(mktemp)"
    {
      printf '\n## Archived items   [🤖-owned — see `pw-review.sh archive`; never hand-edit]\n\n'
      printf 'Full text preserved verbatim in `%s`.\n\n' "$(basename "$archrel")"
      printf '| ID | Summary | Archived |\n|----|---------|----------|\n'
    } > "$secfile"
    if grep -q '^## Sign-off' "$f"; then
      local signline; signline="$(grep -n '^## Sign-off' "$f" | head -1 | cut -d: -f1)"
      { head -n "$((signline - 1))" "$f"; cat "$secfile"; printf '\n'; tail -n "+${signline}" "$f"; } \
        > "$f.tmp" && mv "$f.tmp" "$f"
    else
      cat "$secfile" >> "$f"
    fi
    rm -f "$secfile"
  fi
  if [ ! -f "$af" ]; then
    {
      printf '# Archived review items — %s\n\n' "$(basename "${rel%.review.md}")"
      printf 'Items/questions moved out of `%s` once fully [RESOLVED]/[ANSWERED], by `pw-review.sh\n' "$rel"
      printf 'archive` — text preserved verbatim, never edited. See that file'"'"'s "## Archived items"\n'
      printf 'table for one pointer row per entry moved here.\n'
    } > "$af"
  fi

  # Compute (start,end,id) for every RESOLVED/ANSWERED heading against the file's CURRENT state —
  # the section-ensure above only ever adds content at/after ## Sign-off (strictly after every
  # item/question), so it can never shift any of these ranges.
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local total; total="$(wc -l < "$blanked" | tr -d ' ')"
  local -a all_heads=()
  while IFS= read -r h; do all_heads+=("$h"); done < <(grep -nE '^(## |### )' "$blanked" | cut -d: -f1)

  local -a rstarts=() rends=() rids=()
  while IFS=$'\t' read -r ln id anchor tag; do
    [ "$tag" = "RESOLVED" ] || [ "$tag" = "ANSWERED" ] || continue
    local end="$total" hh
    for hh in "${all_heads[@]}"; do
      if [ "$hh" -gt "$ln" ]; then end=$((hh-1)); break; fi
    done
    rstarts+=("$ln"); rends+=("$end"); rids+=("$id")
  done < <(_review_items_tsv "$f")
  rm -f "$blanked"

  if [ "${#rstarts[@]}" -eq 0 ]; then
    echo "$slug: $rel — nothing to archive (no [RESOLVED]/[ANSWERED] items)"
    return 0
  fi

  # Append every moved block's text (verbatim) + a pointer row, in file order. Row-insertion
  # rescans the CURRENT file each time for "## Archived items", so it self-corrects regardless of
  # how many rows already landed there — it never relies on a stale line number.
  local i today; today="$(date +%F)"
  for i in "${!rstarts[@]}"; do
    local s="${rstarts[$i]}" e="${rends[$i]}" id="${rids[$i]}"
    local blocktxt; blocktxt="$(sed -n "${s},${e}p" "$f")"
    local summary
    summary="$(printf '%s\n' "$blocktxt" | tail -n +2 | grep -vE '^[[:space:]]*$' | head -1)"
    if [ ${#summary} -gt 80 ]; then summary="${summary:0:80}…"; fi
    summary="$(printf '%s' "$summary" | sed 's/|/\\|/g')"
    [ -n "$summary" ] || summary="(no summary line)"
    { printf '\n---\n\n'; printf '%s\n' "$blocktxt"; } >> "$af"
    local marker="<!-- pw-archived:$id -->"
    local row="| $id | $summary | $today $marker |"
    if grep -Fq "$marker" "$f"; then
      awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    else
      awk -v row="$row" '
        /^## Archived items/ { insec=1 }
        { print }
        insec && !done && /^\|[-| ]+\|[ ]*$/ { print row; done=1 }
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      grep -Fq "$marker" "$f" || printf '%s\n' "$row" >> "$f"
    fi
  done

  # NOW remove the moved ranges from the live file, HIGHEST start-line first, so removing an
  # already-processed (higher-numbered) block never shifts the line numbers of a not-yet-processed
  # (lower-numbered) one still waiting to be removed.
  local order; order="$(for i in "${!rstarts[@]}"; do printf '%s\t%s\n' "${rstarts[$i]}" "$i"; done | sort -rn -k1,1)"
  while IFS=$'\t' read -r _ i; do
    local s="${rstarts[$i]}" e="${rends[$i]}"
    local flen; flen="$(wc -l < "$f" | tr -d ' ')"
    {
      [ "$s" -gt 1 ] && sed -n "1,$((s-1))p" "$f"
      [ "$e" -lt "$flen" ] && sed -n "$((e+1)),\$p" "$f"
      true
    } > "$f.tmp" && mv "$f.tmp" "$f"
  done <<< "$order"

  cmd_reindex "$slug" "$rel" >/dev/null
  _log "$slug" review "archived ${#rstarts[@]} resolved item(s)/question(s) from $rel to $archrel"
  echo "$slug: archived ${#rstarts[@]} item(s)/question(s) from $rel to $archrel"
}


cmd_scan() {
  SLUG=""
  PHASE_FILTER=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) [ $# -ge 2 ] || die "--phase requires an argument"; PHASE_FILTER="$2"; shift 2 ;;
      --phase=*) PHASE_FILTER="${1#--phase=}"; shift ;;
      -h|--help) pw_usage ;;
      -*) die "unknown option: $1 (try --help)" ;;
      *) SLUG="$1"; shift ;;
    esac
  done

  [ -n "$SLUG" ] || die "usage: scan <slug> [--phase <phase>]"

  D="$(proj_dir "$SLUG")"

  # Find all review files
  REVIEW_FILES=()
  if [ -d "$D/analysis/review" ]; then
    while IFS= read -r -d '' f; do
      REVIEW_FILES+=("$f")
    done < <(find "$D/analysis/review" -name '*.review.md' -print0 2>/dev/null)
  fi
  if [ -d "$D/task/review" ]; then
    while IFS= read -r -d '' f; do
      REVIEW_FILES+=("$f")
    done < <(find "$D/task/review" -name '*.review.md' -print0 2>/dev/null)
  fi

  if [ ${#REVIEW_FILES[@]} -eq 0 ]; then
    echo "No review files found"
    exit 0
  fi

  for f in "${REVIEW_FILES[@]}"; do
    REL="${f#$D/}"
  
    # Counts come from the shared heading-level detector — THE same one the approval
    # gates use. A whole-file `grep -c "pw-item-status: open"` previously counted the template's
    # permanent "> Add an item: … <!-- pw-item-status: open -->" guidance line in EVERY review
    # file, so each one phantom-reported "(1 open)" forever, no matter what was approved.
    COUNTS="$(cmd_count "$SLUG" "$REL" 2>/dev/null || true)"
    OPEN="$(printf '%s' "$COUNTS" | sed -n 's/open=\([0-9]*\).*/\1/p')"; OPEN="${OPEN:-0}"
    RESOLVED="$(printf '%s' "$COUNTS" | sed -n 's/.*resolved=\([0-9]*\).*/\1/p')"; RESOLVED="${RESOLVED:-0}"
  
    # Check sign-off status
    SIGNOFF=""
    if grep -q '## Sign-off' "$f"; then
      # Get the last sign-off row
      # last REAL table row only — the template's example rows live in an HTML comment after
      # the table; an unguarded `/^\|/` scan lands on them and inverts gate state.
      LAST_SIGNOFF="$(awk '
        /^## Sign-off/ {p=1; next}
        p && /^[[:space:]]*<!--/ {exit}
        p && /^\|/ {last=$0; next}
        p && last != "" && /^[^|[:space:]]/ {exit}
        END {print last}' "$f")"
      if echo "$LAST_SIGNOFF" | grep -q 'approved'; then
        SIGNOFF="approved"
      elif echo "$LAST_SIGNOFF" | grep -q 'in-review'; then
        SIGNOFF="in-review"
      elif echo "$LAST_SIGNOFF" | grep -q 'changes-requested'; then
        SIGNOFF="changes-requested"
      fi
    fi
  
    # Build summary line: "<rel>[: N open[, M resolved]] (<decision>)" — parts joined without a
    # leading comma when open is zero (an approved 0-open review reads clean, not ", 1 resolved").
    PARTS=""
    _p() { [ -n "$PARTS" ] && PARTS="$PARTS, "; PARTS="$PARTS$1"; }
    [ "$OPEN" -gt 0 ] && _p "$OPEN open"
    [ "$RESOLVED" -gt 0 ] && _p "$RESOLVED resolved"
    SUMMARY="$REL:"
    [ -n "$PARTS" ] && SUMMARY="$SUMMARY $PARTS"
    # (no separate "pending questions" counter: Q-items ride the same pw-item-status markers;
    #  the old grep looked for a vocabulary the templates never emit — always dead, always 0.)
    if [ -n "$SIGNOFF" ]; then
      SUMMARY="$SUMMARY ($SIGNOFF)"
    fi
  
    # Apply phase filter if specified
    if [ -n "$PHASE_FILTER" ]; then
      case "$REL" in
        analysis/review/*)
          [ "$PHASE_FILTER" = "analysis" ] && echo "$SUMMARY"
          ;;
        task/review/PLAN.review.md)
          [ "$PHASE_FILTER" = "plan" ] || [ "$PHASE_FILTER" = "task-plan" ] && echo "$SUMMARY"
          ;;
        task/review/T*.review.md)
          [ "$PHASE_FILTER" = "task-exec" ] && echo "$SUMMARY"
          ;;
      esac
    else
      echo "$SUMMARY"
    fi
  done

  # a filtered run must be a clean report, not the rc of the last test in the loop (docs:
  # only 0/2 exit shapes — 0 report/nothing, 2 usage/missing project).
  exit 0
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
  init)         cmd_init "$@" ;;
  gate)         cmd_gate "$@" ;;
  has-open)     cmd_has_open "$@" ;;
  count)        cmd_count "$@" ;;
  scan)         cmd_scan "$@" ;;
  reindex)      cmd_reindex "$@" ;;
  archive)      cmd_archive "$@" ;;
  reopen)       cmd_reopen "$@" ;;
  note-init)    cmd_note_init "$@" ;;
  auto-signoff) cmd_auto_signoff "$@" ;;
  -h|--help) pw_usage ;;
  *) die "unknown operator: $OP → fix: see --help (init, init-all, gate, has-open, count, scan, reindex, archive, reopen, note-init, auto-signoff, signoff, add-item, answer, add-question, resolve)" ;;
esac
