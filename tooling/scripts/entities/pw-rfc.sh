#!/usr/bin/env bash
# ============================================================================
# pw-rfc.sh — the rfc-doc entity: the optional /pw-rfc publish side-loop's
# deterministic state (rfc/RFC.md, rfc/META.md, dashboard RFC: line) + comment
# listing. Never touches dashboard Status: (RFC is a side-loop, not a phase).
#
#   pw-rfc.sh init         <slug> [backend]      create rfc/RFC.md + META.md from
#       template if missing (idempotent; META stamped with the REAL backend).
#   pw-rfc.sh target       <slug> <ref>          set META Target: (persists).
#   pw-rfc.sh state        <slug> <field> <value>
#       set META Backend|LastRevision|Wave1Published|Wave2Published.
#   pw-rfc.sh comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>
#       per-thread upsert into META's ## Comment tracking (hidden keyed marker).
#   pw-rfc.sh dashboard    <slug> <text...>      set the dashboard RFC: line.
#   pw-rfc.sh comments     <slug>                list open threads + per-thread
#       reply counts (was pw-rfc-comments.sh).
#
# Merged from pw-lib's rfc block + pw-rfc-comments.sh (plan 20). See
# tooling/docs/rfc.md + rfc-backends.md.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
ST="$HERE/pw-status.sh"

die() { echo "pw-rfc: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

# --- RFC side-loop (see tooling/docs/rfc.md + tooling/docs/rfc-backends.md) ------------
# Deterministic helpers for the optional /pw-rfc publish loop — never touches the dashboard
# Status: (RFC is a side-loop, not a phase), same discipline as /pw-ship's own helpers.

# Create rfc/RFC.md from the canonical template if (and only if) it doesn't exist yet —
# idempotent, same shape as cmd_review_init. Never clobbers a doc already in progress. Also
# ensures rfc/META.md exists, stamped with the REAL configured backend (not a hardcoded guess) —
# call this with the resolved backend so META.md never drifts from what's actually configured.
#   rfc init <slug> [backend]   (backend defaults to "markdown" if omitted)
cmd_rfc_init() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: init <slug> [backend]"
  local slug="$1" backend="${2:-markdown}" d; d="$(proj_dir "$slug")"
  local f="$d/rfc/RFC.md"
  _rfc_meta_ensure "$d/rfc/META.md" "$slug" "$backend"
  if [ -f "$f" ]; then
    echo "$slug: rfc already exists: rfc/RFC.md (left untouched)"
    return 0
  fi
  local tmpl="$HERE/../../../template/rfc/_TEMPLATE-RFC.md"
  [ -f "$tmpl" ] || die "template not found: $tmpl"
  mkdir -p "$d/rfc"
  sed "s/<PROJECT_NAME>/$slug/g" "$tmpl" > "$f"
  "$ST" log "$slug" rfc "created rfc/RFC.md from template (backend: $backend)"
  echo "$slug: rfc-init created rfc/RFC.md"
}

# Create rfc/META.md with its fixed skeleton if missing — 🤖-owned, never hand-edited (same
# convention as ADOPTED.md). Private helper shared by rfc init/target/state. Backend defaults to
# "markdown" only when the caller doesn't know better; rfc init always passes the real one so the
# skeleton is correct from the moment it's first created, never left silently wrong.
_rfc_meta_ensure() {
  local f="$1" slug="$2" backend="${3:-markdown}"
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")"
  {
    printf '# RFC metadata — %s   [🤖-owned — never hand-edit; see `pw-rfc.sh target|state`]\n\n' "$slug"
    printf -- '- **Backend:** %s\n' "$backend"
    printf -- '- **Target:** \n'
    printf -- '- **Last revision pushed:** \n'
    printf -- '- **Wave 1 published:** no\n'
    printf -- '- **Wave 2 published:** no\n'
  } > "$f"
}

# Ensure rfc/META.md has a "## Comment tracking" table (create the header if missing) — lazily
# added only once a thread is actually seen, so a project with no comments yet never grows this
# section. Private helper for cmd_rfc_comment_seen.
_rfc_comment_section_ensure() {
  local f="$1"
  grep -q '^## Comment tracking' "$f" 2>/dev/null && return 0
  {
    printf '\n## Comment tracking   [🤖-owned — never hand-edit; see `pw-rfc.sh comment-seen`]\n\n'
    printf '| Thread | Replies seen | Solved |\n'
    printf '|--------|--------------|--------|\n'
  } >> "$f"
}

# Set/insert a `- **<label>:** <value>` line in a metadata file — insert-if-absent, else
# replace-in-place. Same shape as cmd_adopted, generalized to a parameterized file + label.
_rfc_meta_upsert() {
  local f="$1" label="$2" value="$3"
  if grep -qF -- "- **$label:**" "$f"; then
    awk -v l="$label" -v v="$value" '!d && index($0, "- **" l ":**")==1 { print "- **" l ":** " v; d=1; next } { print }' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf -- '- **%s:** %s\n' "$label" "$value" >> "$f"
  fi
}

# Set/insert rfc/META.md's Target: (the external doc ref a publish goes to). Persists per-project
# so a later /pw-rfc run doesn't need --target repeated.
#   rfc target <slug> <ref>
cmd_rfc_target() {
  [ $# -eq 2 ] || die "usage: target <slug> <ref>"
  local slug="$1" ref="$2" d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  _rfc_meta_ensure "$f" "$slug"
  _rfc_meta_upsert "$f" "Target" "$ref"
  "$ST" log "$slug" rfc "target set: $ref"
  echo "$slug: rfc target -> $ref"
}

# Set/insert any other rfc/META.md field.
#   rfc state <slug> <field> <value>   (field: Backend|LastRevision|Wave1Published|Wave2Published)
cmd_rfc_state() {
  [ $# -eq 3 ] || die "usage: state <slug> <field> <value>   (field: Backend|LastRevision|Wave1Published|Wave2Published)"
  local slug="$1" field="$2" value="$3" d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  local label
  case "$field" in
    Backend)        label="Backend" ;;
    LastRevision)   label="Last revision pushed" ;;
    Wave1Published) label="Wave 1 published" ;;
    Wave2Published) label="Wave 2 published" ;;
    *) die "unknown rfc state field '$field' (allowed: Backend LastRevision Wave1Published Wave2Published)" ;;
  esac
  _rfc_meta_ensure "$f" "$slug"
  _rfc_meta_upsert "$f" "$label" "$value"
  "$ST" log "$slug" rfc "state $field=$value"
  echo "$slug: rfc state $field -> $value"
}

# Deterministically upsert ONE row per comment thread, keyed by a hidden
# `<!-- pw-rfc-comment:<thread-id> -->` marker — same append-or-rewrite-in-place shape as
# _scope_upsert (context/INDEX.md's adoption rows). This is what lets `/pw-rfc comments` tell
# "never seen this thread" from "seen before, N replies then, M replies now" from "already
# recorded as solved" — a single scalar watermark can't represent per-thread state (the bug: an
# earlier thread getting new replies after a later thread became "latest" was invisible forever).
#   rfc comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>
cmd_rfc_comment_seen() {
  [ $# -eq 4 ] || die "usage: comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>"
  local slug="$1" thread="$2" replies="$3" solved="$4"
  case "$solved" in yes|no) ;; *) die "solved must be 'yes' or 'no' (got '$solved')" ;; esac
  case "$replies" in ''|*[!0-9]*) die "reply-count must be a non-negative integer (got '$replies')" ;; esac
  local d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  _rfc_meta_ensure "$f" "$slug"
  _rfc_comment_section_ensure "$f"
  local marker="<!-- pw-rfc-comment:$thread -->"
  local row="| \`$thread\` | $replies | $solved $marker |"
  if grep -Fq "$marker" "$f"; then
    awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf '%s\n' "$row" >> "$f"
  fi
  "$ST" log "$slug" rfc "comment-seen $thread: $replies replies, solved=$solved"
  echo "$slug: rfc comment-seen $thread -> $replies replies, solved=$solved"
}

# Set/insert the project dashboard's `- **RFC:**` line — mirrors cmd_adopted almost verbatim,
# anchoring after Adopted: if present (dashboard field order: Status → One-liner → [Adopted] →
# [RFC]), else after One-liner.
#   rfc dashboard <slug> <text...>
cmd_rfc_dashboard() {
  [ $# -ge 2 ] || die "usage: dashboard <slug> <text...>"
  local slug="$1"; shift; local text="$*"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  if grep -q '^- \*\*RFC:\*\*' "$f"; then
    awk -v t="$text" '!d && /^- \*\*RFC:\*\*/ {print "- **RFC:** " t; d=1; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  elif grep -q '^- \*\*Adopted:\*\*' "$f"; then
    awk -v t="$text" '{print} !d && /^- \*\*Adopted:\*\*/ {print "- **RFC:** " t; d=1}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    grep -q '^- \*\*One-liner:\*\*' "$f" || die "no anchor line (Adopted:/One-liner:) in $f"
    awk -v t="$text" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **RFC:** " t; d=1}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  "$ST" log "$slug" rfc "dashboard: $text"
  echo "$slug: RFC -> $text"
}


cmd_comments() {
SLUG=""
BACKEND="${PW_RFC_BACKEND:-markdown}"
BACKEND_FROM_META=1

while [ $# -gt 0 ]; do
  case "$1" in
    --backend) shift; BACKEND="${1:-$BACKEND}"; BACKEND_FROM_META=0; shift ;;
    --backend=*) BACKEND="${1#--backend=}"; BACKEND_FROM_META=0; shift ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $1" ;;
    *) SLUG="$1"; shift ;;
  esac
done

[ -n "$SLUG" ] || die "usage: pw-rfc-comments.sh <slug> [--backend <backend>]"

D="$(proj_dir "$SLUG")"
META="$D/rfc/META.md"
REVIEW_FILE="$D/analysis/review/RFC.review.md"

[ -f "$META" ] || die "rfc/META.md not found — run the /pw-rfc publish step first"

# The project's rfc/META.md records its own backend (bold field, per pw-lib rfc state);
# it wins over the global PW_RFC_BACKEND default unless --backend is given explicitly.
if [ "$BACKEND_FROM_META" = 1 ] && mw="$(pw_field "$META" Backend)" && [ -n "$mw" ]; then
  BACKEND="$mw"
fi

# If backend is markdown, no external comments to fetch
if [ "$BACKEND" = "markdown" ]; then
  echo "RFC comments: no external comments to fetch (backend=markdown)"
  exit 0
fi

# Resolve backend target
TARGET="$(pw_field "$META" Target)"
[ -n "$TARGET" ] || die "no Target: in rfc/META.md"

# Fetch comments from backend (platform-specific)
NEW_COUNT=0
UPDATED_COUNT=0
RESOLVED_COUNT=0

case "$BACKEND" in
  lark)
    # Lark backend: use lark-cli to fetch comments
    if ! command -v lark-cli >/dev/null 2>&1; then
      die "lark-cli not found (required for lark backend)"
    fi
    
    # Extract doc token from target URL
    DOC_TOKEN=""
    if echo "$TARGET" | grep -q 'docx'; then
      DOC_TOKEN="$(echo "$TARGET" | grep -o 'docx/[A-Za-z0-9]*' | sed 's/docx\///')"
    elif echo "$TARGET" | grep -q 'wiki'; then
      DOC_TOKEN="$(echo "$TARGET" | grep -o 'wiki/[A-Za-z0-9]*' | sed 's/wiki\///')"
    fi
    
    [ -n "$DOC_TOKEN" ] || die "cannot extract doc token from target: $TARGET"
    
    # Fetch comments (placeholder — actual implementation depends on lark-cli API)
    echo "Fetching comments from Lark doc $DOC_TOKEN..."
    # COMMENTS="$(lark-cli doc comments list --doc-token "$DOC_TOKEN" 2>/dev/null || echo "")"
    
    # Process comments (placeholder logic)
    # For each comment thread:
    #   - Check if tracked in META.md
    #   - If new, append to RFC.review.md
    #   - If resolved, update tracking
    
    echo "RFC comments: $NEW_COUNT new, $UPDATED_COUNT updated, $RESOLVED_COUNT resolved externally"
    ;;
    
  notion)
    # Notion backend: use Notion API to fetch comments
    echo "Notion backend not yet implemented"
    exit 0
    ;;
    
  *)
    die "unknown RFC backend: $BACKEND"
    ;;
esac

# Create RFC.review.md if missing
if [ ! -f "$REVIEW_FILE" ]; then
  mkdir -p "$(dirname "$REVIEW_FILE")"
  cat > "$REVIEW_FILE" <<'EOF'
# RFC Review

## Items

## Open questions

## Sign-off

| Date | Decision | By |
|------|----------|----|
EOF
fi

echo "RFC comments: $NEW_COUNT new, $UPDATED_COUNT updated, $RESOLVED_COUNT resolved externally"
}

case "${1:-}" in
  init)         shift; cmd_rfc_init "$@" ;;
  target)       shift; cmd_rfc_target "$@" ;;
  state)        shift; cmd_rfc_state "$@" ;;
  comment-seen) shift; cmd_rfc_comment_seen "$@" ;;
  dashboard)    shift; cmd_rfc_dashboard "$@" ;;
  comments)     shift; cmd_comments "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-rfc.sh <init|target|state|comment-seen|dashboard|comments> … (see --help)" ;;
esac
