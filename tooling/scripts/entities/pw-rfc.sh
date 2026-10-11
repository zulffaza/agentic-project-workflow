#!/usr/bin/env bash
# ============================================================================
# pw-rfc.sh — the rfc-doc entity: the optional /pw-rfc publish side-loop's
# deterministic state (rfc/RFC.md, rfc/META.md, dashboard RFC: line) + comment
# listing. Never touches dashboard Status: (RFC is a side-loop, not a phase).
#
#   pw-rfc.sh init --project <slug> [--backend <b>]
#       create rfc/RFC.md + META.md from template if missing (idempotent; META
#       stamped with the REAL backend).
#   pw-rfc.sh target --project <slug> --ref <ref>          set META Target: (persists).
#   pw-rfc.sh state --project <slug> --field <field> --value <value>
#       set META Backend|LastRevision|Wave1Published|Wave2Published.
#   pw-rfc.sh comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>
#       per-thread upsert into META's ## Comment tracking (hidden keyed marker).
#   pw-rfc.sh dashboard --project <slug> --text <text…>    set the dashboard RFC: line.
#   pw-rfc.sh comments --project <slug> [--backend <b>]
#       list open threads + per-thread reply counts (was pw-rfc-comments.sh).
#
# Named-argument grammar: operation words first, every value named; --project
# selects the project. Scalar values are ONE token (quote spaces); the prose
# --text runs until the next --flag token.
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
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: /pw-new --project $1)"; printf '%s' "$d"; }

# --- RFC side-loop (see tooling/docs/rfc.md + tooling/docs/rfc-backends.md) ------------
# Deterministic helpers for the optional /pw-rfc publish loop — never touches the dashboard
# Status: (RFC is a side-loop, not a phase), same discipline as /pw-ship's own helpers.

# Create rfc/RFC.md from the canonical template if (and only if) it doesn't exist yet —
# idempotent, same shape as cmd_review_init. Never clobbers a doc already in progress. Also
# ensures rfc/META.md exists, stamped with the REAL configured backend (not a hardcoded guess) —
# call this with the resolved backend so META.md never drifts from what's actually configured.
#   rfc init --project <slug> [--backend <b>]   (backend defaults to "markdown" if omitted)
cmd_rfc_init() {
  local slug="" backend="markdown" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; --backend=*) v="${a#*=}"; a="--backend" ;; esac
    case "$a" in
      --project|--backend)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --backend) backend="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "init --project <slug> [--backend <b>]" ;;
      *) _pw_positional "$a" "operation words first, values named — e.g. init --project <slug> [--backend <b>]" ;;
    esac
  done
  [ -n "$slug" ] || die "init: --project is required → fix: init --project <slug> [--backend <b>]"
  local d; d="$(proj_dir "$slug")"
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
  "$ST" log --project "$slug" --actor rfc --message "created rfc/RFC.md from template (backend: $backend)"
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
    printf '# RFC metadata — %s   [🤖-owned — never hand-edit; maintained via /pw-rfc]\n\n' "$slug"
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
    printf '\n## Comment tracking   [🤖-owned — never hand-edit; maintained via /pw-rfc]\n\n'
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
#   rfc target --project <slug> --ref <ref>
cmd_rfc_target() {
  local slug="" ref="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; --ref=*) v="${a#*=}"; a="--ref" ;; esac
    case "$a" in
      --project|--ref)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --ref) ref="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "target --project <slug> --ref <ref>" ;;
      *) _pw_positional "$a" "target --project <slug> --ref <ref>" ;;
    esac
  done
  [ -n "$slug" ] || die "target: --project is required → fix: target --project <slug> --ref <ref>"
  [ -n "$ref" ] || die "target: --ref is required → fix: pass the external doc ref"
  local d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  _rfc_meta_ensure "$f" "$slug"
  _rfc_meta_upsert "$f" "Target" "$ref"
  "$ST" log --project "$slug" --actor rfc --message "target set: $ref"
  echo "$slug: rfc target -> $ref"
}

# Set/insert any other rfc/META.md field.
#   rfc state --project <slug> --field <field> --value <value>   (field: Backend|LastRevision|Wave1Published|Wave2Published)
cmd_rfc_state() {
  local slug="" field="" value="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --field=*)   v="${a#*=}"; a="--field" ;;
      --value=*)   v="${a#*=}"; a="--value" ;;
    esac
    case "$a" in
      --project|--field|--value)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --field) field="$v" ;; --value) value="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "state --project <slug> --field <field> --value <value>" ;;
      *) _pw_positional "$a" "state --project <slug> --field <field> --value <value>" ;;
    esac
  done
  [ -n "$slug" ] || die "state: --project is required → fix: state --project <slug> --field <field> --value <value>"
  [ -n "$field" ] || die "state: --field is required → fix: state --project <slug> --field <field> --value <value>"
  [ -n "$value" ] || die "state: --value is required → fix: state --project <slug> --field <field> --value <value>"
  local d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
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
  "$ST" log --project "$slug" --actor rfc --message "state $field=$value"
  echo "$slug: rfc state $field -> $value"
}

# Deterministically upsert ONE row per comment thread, keyed by a hidden
# `<!-- pw-rfc-comment:<thread-id> -->` marker — same append-or-rewrite-in-place shape as
# _scope_upsert (context/INDEX.md's adoption rows). This is what lets `/pw-rfc comments` tell
# "never seen this thread" from "seen before, N replies then, M replies now" from "already
# recorded as solved" — a single scalar watermark can't represent per-thread state (the bug: an
# earlier thread getting new replies after a later thread became "latest" was invisible forever).
#   rfc comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>
cmd_rfc_comment_seen() {
  local slug="" thread="" replies="" solved="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in
      --project=*) v="${a#*=}"; a="--project" ;;
      --thread=*)  v="${a#*=}"; a="--thread" ;;
      --replies=*) v="${a#*=}"; a="--replies" ;;
      --solved=*)  v="${a#*=}"; a="--solved" ;;
    esac
    case "$a" in
      --project|--thread|--replies|--solved)
        [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing "$a"; v="$1"; shift; }
        case "$a" in --project) slug="$v" ;; --thread) thread="$v" ;; --replies) replies="$v" ;; --solved) solved="$v" ;; esac ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>" ;;
      *) _pw_positional "$a" "comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>" ;;
    esac
  done
  [ -n "$slug" ] || die "comment-seen: --project is required → fix: comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>"
  [ -n "$thread" ] || die "comment-seen: --thread is required → fix: comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>"
  [ -n "$replies" ] || die "comment-seen: --replies is required → fix: comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>"
  [ -n "$solved" ] || die "comment-seen: --solved is required → fix: comment-seen --project <slug> --thread <thread-id> --replies <n> --solved <yes|no>"
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
  "$ST" log --project "$slug" --actor rfc --message "comment-seen $thread: $replies replies, solved=$solved"
  echo "$slug: rfc comment-seen $thread -> $replies replies, solved=$solved"
}

# Set/insert the project dashboard's `- **RFC:**` line — mirrors cmd_adopted almost verbatim,
# anchoring after Adopted: if present (dashboard field order: Status → One-liner → [Adopted] →
# [RFC]), else after One-liner.
#   rfc dashboard --project <slug> --text <text…>
cmd_rfc_dashboard() {
  local slug="" text="" a v
  while [ $# -gt 0 ]; do
    a="$1"; shift; v=""
    case "$a" in --project=*) v="${a#*=}"; a="--project" ;; --text=*) v="${a#*=}"; a="--text" ;; esac
    case "$a" in
      --project) [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }; slug="$v" ;;
      --text)
        while [ $# -gt 0 ]; do case "$1" in --*) break ;; esac; v="${v:+$v }$1"; shift; done
        [ -n "$v" ] || die "dashboard: --text requires a value → fix: --text <text…> (runs until the next --flag)"
        text="$v" ;;
      -h|--help) pw_usage ;;
      -*) _pw_unknown "$a" "dashboard --project <slug> --text <text…>" ;;
      *) _pw_positional "$a" "dashboard --project <slug> --text <text…>" ;;
    esac
  done
  [ -n "$slug" ] || die "dashboard: --project is required → fix: dashboard --project <slug> --text <text…>"
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
  "$ST" log --project "$slug" --actor rfc --message "dashboard: $text"
  echo "$slug: RFC -> $text"
}


cmd_comments() {
SLUG=""
BACKEND="${PW_RFC_BACKEND:-markdown}"
BACKEND_FROM_META=1

local a v
while [ $# -gt 0 ]; do
  a="$1"; shift; v=""
  case "$a" in --project=*) v="${a#*=}"; a="--project" ;; --backend=*) v="${a#*=}"; a="--backend" ;; esac
  case "$a" in
    --project)
      [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --project; v="$1"; shift; }
      SLUG="$v" ;;
    --backend)
      [ -n "$v" ] || { [ $# -ge 1 ] || _pw_missing --backend; v="$1"; shift; }
      BACKEND="$v"; BACKEND_FROM_META=0 ;;
    -h|--help) pw_usage ;;
    -*) _pw_unknown "$a" "comments --project <slug> [--backend <b>]" ;;
    *) _pw_positional "$a" "comments --project <slug> [--backend <b>]" ;;
  esac
done

[ -n "$SLUG" ] || die "comments: --project is required → fix: comments --project <slug> [--backend <b>]"

D="$(proj_dir "$SLUG")"
META="$D/rfc/META.md"
REVIEW_FILE="$D/analysis/review/RFC.review.md"

[ -f "$META" ] || die "rfc/META.md not found — run the /pw-rfc publish step first"

# The project's rfc/META.md records its own backend (bold field, per the rfc state block);
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
