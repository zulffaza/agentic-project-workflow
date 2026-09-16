# shellcheck shell=bash
# ============================================================================
# pw-mdlib.sh — SOURCE-ONLY shared library of pure markdown-document primitives
# (plan 17, S5 of tooling/docs/conventions.md). No CLI, no dispatch, no project
# resolution — every function takes explicit file paths and is safe to source
# from any pw-* script. Extracted VERBATIM from pw-lib.sh (behavior-identical,
# harness-proven) so pw-review-edit.sh / pw-context.sh reuse the exact detectors
# the gates trust instead of forking near-copies.
#
# Functions (review-file detectors — the ONE source of truth, see docs/REVIEW.md):
#   _comment_blanked <file>              file with multi-line HTML comments blanked
#                                        (line numbers preserved; same-line comments kept)
#   _review_item_headings <file>         real, filled ### item/question headings only
#   _review_has_open_marker <file>       0 iff a real heading is still open/pending
#   _decision_is_approved <text>         0 iff a Sign-off Decision cell reads approved
#                                        (accepts the legacy "approved ✅" form)
#   _signoff_last_real_row_line <file>   line no. of the Sign-off table's last REAL row (0=none)
#   _signoff_latest_decision <file>      current (latest-row) Decision cell text; exit 1 if none
#   _review_items_tsv <file>             "LINE\tID\tanchor\tSTATUS" per real Rn/Qn heading
#
# Generic table/splice helpers (used by pw-context.sh / pw-review-edit.sh):
#   md_table_last_row_line <file> <section-ERE>   line no. of the last "|" row of the first
#                                        table under a heading matching the ERE (stops at the
#                                        next "## " heading; 0 = no rows)
#   md_insert_lines_after <file> <lineno> <lines-file>   splice lines-file in AFTER lineno
#   md_replace_line <file> <lineno> <lines-file>         replace exactly one line with the
#                                        lines-file content
#
# Rules: append-or-splice only — never rewrite content in place; callers keep the
# doctrine (human text is never edited). bash 3.2 compatible (macOS default).
# ============================================================================

# Private: true if <file> has a REAL unresolved item/question — a genuine "### ..." heading
# that's still open — OUTSIDE any HTML comment. This is NOT a plain whole-file grep:
# template/_REVIEW.template.md's permanent format-hint blockquotes (kept forever, by design,
# "even once items exist or the section is emptied") and its deletable WORKED EXAMPLE block both
# contain open-item syntax verbatim as demonstrations — a naive grep would treat every review file
# ever created as permanently, unfixably "open".
#
# Comment-stripping is an explicit line-by-line state machine (awk), NOT `sed '/<!--/,/-->/d'`:
# that one-liner checks the CLOSING pattern starting from the line AFTER the one that matched the
# opening pattern — never the same line (verified empirically — a real, reproducible sed gotcha,
# not a hypothetical). A same-line self-contained comment (`<!-- foo -->`, which every real
# item/question heading now carries, see below) would falsely open a multi-line range that then
# swallows everything up to the NEXT `-->` anywhere later in the file. The state machine instead:
# a line with BOTH `<!--` and `-->` is a self-contained one-liner — kept, unstripped, exactly as
# written; a line with only `<!--` opens a genuine multi-line comment (skipped along with every
# line up to and including the next line containing `-->`). template/_REVIEW.template.md's own
# WORKED EXAMPLE blocks deliberately use bracket notation (`[marker: pw-item-status open]`), not
# real `<!-- -->` syntax, for exactly this reason — HTML comments cannot nest, so a real same-line
# comment inside an already-open multi-line one would prematurely close the outer one and leak the
# rest of the worked example into "real" content. Never put real `<!-- -->` syntax inside a
# multi-line comment block in this template.
#
# Primary signal: a real heading carrying `<!-- pw-item-status: open -->` — a dedicated machine
# marker (template/_REVIEW.template.md), immune to a future reword of the human-facing status text
# breaking this check. Fallback: text-match on the CURRENT bracket tags (`[OPEN]`/`[PENDING]`) AND
# the legacy emoji tags (`🔴 open`/`⏳ awaiting answer`), for a review file created before the
# bracket-tag migration — never drop real open items in an older file just because it predates the
# switch; when in doubt, this errs toward "still open," matching auto-signoff's own refuse-by-default
# stance. Never remove the emoji branch even though new files never write it again.
# Shared comment-blanking state machine (see the long rationale above) — factored out so
# _review_has_open_marker, _signoff_last_real_row_line, cmd_review_reindex, and cmd_review_archive
# all read real headings the same way instead of four near-identical copies drifting apart. Blanks
# (never deletes) every line inside a real multi-line comment, so output line numbers always match
# the ORIGINAL file — callers that splice content back in at an exact original line (head/tail)
# depend on this. A same-line, self-contained `<!-- ... -->` comment is left fully unstripped,
# since every real live heading carries exactly one of those.
_comment_blanked() {
  awk '
    BEGIN { in_comment = 0 }
    {
      line = $0
      if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; print ""; next }
      if (line ~ /<!--/ && line ~ /-->/) { print line; next }
      if (line ~ /<!--/) { in_comment = 1; print ""; next }
      print line
    }
  ' "$1"
}

# Real, FILLED item headings of one review file: blank-commented, `^### `, and with the
# template's unfilled PLACEHOLDER copies (R1/Q1 shipped live-marked so copy-paste yields valid
# syntax — see "Live headings below use the real syntax" in template/_REVIEW.template.md)
# excluded by their literal `<YYYY-MM-DD HH:MM>` token, which no filled item heading can
# contain. Without this filter a fresh or item-free review can never read as 0-open anywhere —
# the display-phantom that made pw-status report approved gates as unresolved (C22). Excluding
# it is correct for the gate consumers too: auto-signoff must not stay blocked forever on a
# placeholder nobody was ever asked to fill.
_review_item_headings() {
  # stub signatures: the template's two unfilled heading tokens. The timestamp one alone is not
  # enough — a half-cleaned stub can lose `(agent, <YYYY…>)` but still carry `<§section>`.
  _comment_blanked "$1" | awk '/^###+ / && !/<YYYY-MM-DD/ && !/<§section/'
}

_review_has_open_marker() {
  local f="$1" h
  h="$(_review_item_headings "$f")"
  printf '%s\n' "$h" | grep -qE '^### .*pw-item-status: open' && return 0
  printf '%s\n' "$h" | grep -qE '^### .*(🔴 open|⏳ awaiting answer|\[OPEN\]|\[PENDING\])'
}

# True iff a Sign-off Decision cell reads as "approved" — accepts both the CURRENT plain form
# (`approved`, no emoji) and the LEGACY form with a trailing checkmark (`approved ✅`), so an
# already-approved real project file written before the keyboard-typable-symbols migration keeps
# gating correctly. Read-side backward compatibility only — cmd_review_auto_signoff below never
# writes the legacy form again.
_decision_is_approved() {
  case "$1" in
    "approved"|"approved ✅") return 0 ;;
    *) return 1 ;;
  esac
}

# Line number (in the ORIGINAL file) of the ## Sign-off table's real last data row — never a
# WORKED-EXAMPLE row sitting inside the template's own trailing <!-- --> comment block. That block
# contains two lines that look exactly like real table rows ("| 2026-08-06 11:30 | you | approved
# ✅ |" and the pw-reviewer-auto variant) — a naive "last line starting with |, from ## Sign-off to
# EOF" scan (what a first cut of this helper did) picks THOSE, since they're the last such lines in
# the whole file, silently corrupting where a real row gets inserted on any RE-review cycle (a
# fresh file's very first sign-off is unaffected — it replaces the literal placeholder line by
# exact text match instead, a different code path). Fix: blank out (never delete — callers need
# original line numbers for a head/tail splice) every comment line first, reusing the same
# same-line-vs-multi-line state machine as _review_has_open_marker, THEN scan for the last `|` line
# from ## Sign-off onward. Returns 0 if the table has no real rows yet (malformed file).
_signoff_last_real_row_line() {
  local f="$1"
  _comment_blanked "$f" | awk '/^## Sign-off/{s=1} s && /^\|/{n=NR} END{print n+0}'
}

# The Sign-off table's CURRENT (latest) Decision cell only — "approved ✅" / "in-review" /
# "changes-requested" — never "was this ever approved anywhere in the file's history". Empty
# output (+ non-zero exit) if the file has no real Sign-off rows at all.
_signoff_latest_decision() {
  local f="$1" lastrow
  lastrow="$(_signoff_last_real_row_line "$f")"
  [ "$lastrow" -gt 0 ] || return 1
  sed -n "${lastrow}p" "$f" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }'
}
# Extract "LINE<TAB>ID<TAB>anchor text<TAB>STATUS" for every REAL ### Rn/Qn heading in $1, in file
# order — comment-blanked first (see _comment_blanked) so template worked-examples/format-hints
# never appear, same reasoning as _review_has_open_marker. Shared by cmd_review_reindex and
# cmd_review_archive so both agree on exactly what counts as a "real" item/question.
_review_items_tsv() {
  _comment_blanked "$1" | awk '
    /^### [RQ][0-9]+ · / {
      id = $0; sub(/^### /, "", id); sub(/ ·.*/, "", id)
      rest = $0; sub(/^### [RQ][0-9]+ · /, "", rest)
      anchor = rest; sub(/ — \[[A-Z]+\].*/, "", anchor)
      tag = rest; sub(/^.*— \[/, "", tag); sub(/\].*/, "", tag)
      printf "%d\t%s\t%s\t%s\n", NR, id, anchor, tag
    }
  '
}

# --- generic markdown table/splice helpers (plan 17) -------------------------

# Line number of the last "|" row of the first markdown table under a section heading
# matching <section-ERE> — scans from the heading, stops at the next "## " heading.
# Prints 0 when the section (or any table row) is absent. Comment-blanked first so
# worked-example rows inside <!-- --> blocks are never picked (same reasoning as
# _signoff_last_real_row_line, generalized to any section).
md_table_last_row_line() {
  local f="$1" sec="$2"
  _comment_blanked "$f" | awk -v sec="$sec" '
    !s && $0 ~ sec {s=1; next}
    s && /^## / {exit}
    s && /^\|/ {n=NR}
    END {print n+0}
  '
}

# Splice the contents of <lines-file> into <file> AFTER line <lineno> (original-file
# numbering). head/tail splice, not awk -v — no shell-quote gymnastics, portable.
md_insert_lines_after() {
  local f="$1" n="$2" src="$3"
  { head -n "$n" "$f"; cat "$src"; tail -n "+$((n+1))" "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
}

# Replace exactly line <lineno> of <file> with the contents of <lines-file>.
md_replace_line() {
  local f="$1" n="$2" src="$3"
  { head -n "$((n-1))" "$f"; cat "$src"; tail -n "+$((n+1))" "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
}
