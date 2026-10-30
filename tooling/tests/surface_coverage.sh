#!/usr/bin/env bash
# ============================================================================
# surface_coverage.sh — validate the prompt-surface coverage ledger.
#
#   tests/surface_coverage.sh check [--ledger FILE] [--root DIR]
#
# Test support, not a user command. The ledger is the maintained map from every
# prompt surface to the instruction text it must keep and the harness entries
# that exercise it. Format: "# surface-coverage v1 gaps=<n>", then TAB rows:
#
#   kind  owner  required  harness  note
#
#   kind      entry | worker | model-skill | reference (derived from the path)
#   owner     tooling-relative file (skills/human/<n>/SKILL.md, agents/pw-*.md,
#             skills/model/<n>/SKILL.md, skills/model/<n>/references/*.md)
#   required  -  or  literals separated by ";;" that must remain in the owner
#   harness   selectors separated by ";;" — T1:<case> (tests/cases/<case>.t.sh
#             must exist), T4:<literal> (must appear in tests/static.sh, i.e. a
#             live canary), or gap (no executable coverage; explain in note)
#   note      free text; a gap row must explain the residual risk
#
# The header gap count must equal the number of gap rows: adding a surface
# without coverage, or losing a canary phrase, fails the check instead of
# silently widening the unverified area. This proves structure only — it cannot
# prove that a mapped case actually asserts the behavior, and it cannot detect a
# paraphrase. Human reconciliation decides.
# ============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$HERE/../.." && pwd)"

usage() {
  cat <<'EOF'
usage: surface_coverage.sh check [--ledger FILE] [--root DIR]

  --ledger FILE  coverage ledger TSV (default: tooling/tests/expectations/coverage.tsv)
  --root DIR     bundle root the tooling-relative paths resolve against
EOF
}

CMD=""
ROOT="$DEFAULT_ROOT"
LEDGER="$DEFAULT_ROOT/tooling/tests/expectations/coverage.tsv"
while [ $# -gt 0 ]; do
  case "$1" in
    check) CMD="check"; shift ;;
    --ledger) [ $# -ge 2 ] || { echo "surface-coverage: --ledger needs a value" >&2; exit 2; }; LEDGER="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || { echo "surface-coverage: --root needs a value" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "surface-coverage: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "$CMD" = check ] || { echo "surface-coverage: the check command is required" >&2; usage >&2; exit 2; }
[ -d "$ROOT" ] || { echo "surface-coverage: root not found: $ROOT" >&2; exit 2; }
[ -f "$LEDGER" ] || { echo "surface-coverage: ledger not found: $LEDGER" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pwcov.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# discover every prompt surface this ledger governs (tooling-relative, sorted)
{
  for f in "$ROOT"/tooling/skills/human/*/SKILL.md; do
    [ -f "$f" ] && printf 'entry\t%s\n' "${f#"$ROOT"/tooling/}"
  done
  for f in "$ROOT"/tooling/agents/pw-*.md; do
    [ -f "$f" ] && printf 'worker\t%s\n' "${f#"$ROOT"/tooling/}"
  done
  for f in "$ROOT"/tooling/skills/model/*/SKILL.md; do
    [ -f "$f" ] && printf 'model-skill\t%s\n' "${f#"$ROOT"/tooling/}"
  done
  for f in "$ROOT"/tooling/skills/model/*/references/*.md; do
    [ -f "$f" ] && printf 'reference\t%s\n' "${f#"$ROOT"/tooling/}"
  done
} | LC_ALL=C sort > "$WORK/discovered"

grep -v '^#' "$LEDGER" | grep . > "$WORK/rows" || true

declared_header=""
declared_gaps=""
first=1
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$first" = 1 ]; then
    first=0
    case "$line" in
      "# surface-coverage v1 gaps="*) declared_header=1; declared_gaps="${line##*gaps=}" ;;
      *) echo "surface-coverage: missing header \"# surface-coverage v1 gaps=<n>\"" >&2; exit 1 ;;
    esac
  fi
done < "$LEDGER"
[ -n "$declared_header" ] || { echo "surface-coverage: missing header \"# surface-coverage v1 gaps=<n>\"" >&2; exit 1; }
case "$declared_gaps" in ''|*[!0-9]*) echo "surface-coverage: header gaps= must be a number" >&2; exit 1 ;; esac

bad=0
err() { printf 'surface-coverage: %s\n' "$*" >&2; bad=1; }

# parse rows, validate fields and selectors
: > "$WORK/declared"
: > "$WORK/ids"
gaps=0
lineno=0
while IFS= read -r line; do
  lineno=$((lineno+1))
  [ "$lineno" = 1 ] && continue   # header handled above
  case "$line" in ''|'#'*) continue ;; esac
  IFS=$'\t' read -r kind owner required harness note <<EOF
$line
EOF
  if [ -z "${owner:-}" ] || [ -z "${harness:-}" ]; then
    err "ledger line $((lineno)): expected 5 tab-separated fields (kind, owner, required, harness, note)"
    continue
  fi
  case "$kind" in entry|worker|model-skill|reference) ;; *) err "$owner: unknown kind '$kind'"; continue ;; esac

  case "$owner" in
    skills/human/*/SKILL.md) derived=entry ;;
    agents/pw-*.md) derived=worker ;;
    skills/model/*/SKILL.md) derived=model-skill ;;
    skills/model/*/references/*.md) derived=reference ;;
    *) err "$owner: not a governed prompt surface path"; continue ;;
  esac
  [ "$kind" = "$derived" ] || err "$owner: kind '$kind' does not match its path (expected '$derived')"

  printf '%s\t%s\n' "$kind" "$owner" >> "$WORK/declared"
  if grep -qxF "$kind	$owner" "$WORK/ids"; then err "$owner: duplicate ledger row"; fi
  printf '%s\t%s\n' "$kind" "$owner" >> "$WORK/ids"

  if [ ! -f "$ROOT/tooling/$owner" ]; then err "$owner: ledger row points at a missing file"; continue; fi

  # required literals (split on ;;) must survive in the owner
  if [ "${required:-'-'}" != "-" ]; then
    rest="$required"
    while [ -n "$rest" ]; do
      case "$rest" in
        *';;'*) lit="${rest%%;;*}"; rest="${rest#*;;}" ;;
        *) lit="$rest"; rest="" ;;
      esac
      [ -z "$lit" ] && continue
      grep -qF -- "$lit" "$ROOT/tooling/$owner" || err "$owner: required text missing: $lit"
    done
  fi

  # harness selectors must resolve; 'gap' is allowed but counted
  row_gap=0
  rest="$harness"
  while [ -n "$rest" ]; do
    case "$rest" in
      *';;'*) sel="${rest%%;;*}"; rest="${rest#*;;}" ;;
      *) sel="$rest"; rest="" ;;
    esac
    [ -z "$sel" ] && continue
    case "$sel" in
      gap) row_gap=1 ;;
      T1:*)
        case_name="${sel#T1:}"
        [ -f "$ROOT/tooling/tests/cases/$case_name.t.sh" ] \
          || err "$owner: harness case not found: $case_name"
        ;;
      T4:*)
        phrase="${sel#T4:}"
        grep -qF -- "$phrase" "$ROOT/tooling/tests/static.sh" \
          || err "$owner: T4 canary phrase not found in tests/static.sh: $phrase"
        ;;
      *) err "$owner: unknown harness selector '$sel' (T1:<case>, T4:<literal>, gap)" ;;
    esac
  done
  if [ "$row_gap" = 1 ]; then
    gaps=$((gaps+1))
    if [ "${note:-'-'}" = "-" ] || [ -z "${note:-}" ]; then
      err "$owner: a gap row must explain the residual risk in note"
    fi
  fi
done < "$LEDGER"

LC_ALL=C sort -o "$WORK/declared" "$WORK/declared"

while IFS=$'\t' read -r kind owner; do
  grep -qxF "$kind	$owner" "$WORK/declared" || err "$owner: discovered surface has no ledger row"
done < "$WORK/discovered"

while IFS=$'\t' read -r kind owner; do
  grep -qxF "$kind	$owner" "$WORK/discovered" || err "$owner: ledger row has no matching surface"
done < "$WORK/declared"

[ "$gaps" = "$declared_gaps" ] \
  || err "unverified (gap) surface count changed: ledger header declares gaps=$declared_gaps, found $gaps — cover the new surface or record an explicit owner decision"

surfaces="$(wc -l < "$WORK/discovered" | tr -d ' ')"
if [ "$bad" = 1 ]; then
  echo "surface-coverage: FAILED" >&2
  exit 1
fi
printf 'surface-coverage: ok (%s surfaces, %s gap)\n' "$surfaces" "$gaps"
