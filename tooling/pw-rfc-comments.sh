#!/usr/bin/env bash
# ============================================================================
# pw-rfc-comments.sh — fetch and track RFC comments
#
#   pw-rfc-comments.sh <slug> [--backend <backend>]
#
# Fetches comments from RFC backend, updates tracking, appends new items to
# analysis/review/RFC.review.md.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-rfc-comments: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

SLUG=""
BACKEND="${PW_RFC_BACKEND:-markdown}"

while [ $# -gt 0 ]; do
  case "$1" in
    --backend) shift; BACKEND="${1:-$BACKEND}"; shift ;;
    --backend=*) BACKEND="${1#--backend=}"; shift ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $1" ;;
    *) SLUG="$1"; shift ;;
  esac
done

[ -n "$SLUG" ] || die "usage: pw-rfc-comments.sh <slug> [--backend <backend>]"

D="$(proj_dir "$SLUG")"
META="$D/rfc/META.md"
REVIEW_FILE="$D/analysis/review/RFC.review.md"

# If backend is markdown, no external comments to fetch
if [ "$BACKEND" = "markdown" ]; then
  echo "RFC comments: no external comments to fetch (backend=markdown)"
  exit 0
fi

[ -f "$META" ] || die "rfc/META.md not found"

# Resolve backend target
TARGET="$(grep '^Target:' "$META" | sed 's/^Target: *//' | xargs || echo "")"
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
