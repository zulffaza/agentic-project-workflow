#!/usr/bin/env bash
# ============================================================================
# pw-ship-resolve.sh — pre-compute shippable task set
#
#   pw-ship-resolve.sh <slug>
#
# Before /pw-ship invokes an agent, this script resolves the exact set of
# shippable tasks. Reads task statuses, checks for real commits, checks for
# existing MRs, resolves ticket numbers from context/INDEX.md.
#
# Output format (one line per shippable task):
#   T01|repo|branch|base|ticket|title|has-commit|has-mr
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-ship-resolve: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scaffold.sh $1)"; printf '%s' "$d"; }

[ $# -eq 1 ] || die "usage: pw-ship-resolve.sh <slug>"

SLUG="$1"
D="$(proj_dir "$SLUG")"
PLAN="$D/task/PLAN.md"
INDEX="$D/context/INDEX.md"

[ -f "$PLAN" ] || die "PLAN.md not found ($PLAN) — run /pw-breakdown <slug> to produce it"

# (ticket resolution is per-task from the task file's `Ticket:` field — below)

# Process each task in PLAN — column-NAME driven rows (works with both PLAN
# generations); repo/branch/base/ticket/title read from the task file itself
# in bold-bullet or legacy line-start shape via pw_field().
while IFS='|' read -r task_id status; do
  task_id="$(echo "$task_id" | pw_trim)"
  status="$(echo "$status" | pw_trim)"
  [[ "$task_id" =~ ^T[0-9]+ ]] || continue
  [ "$status" = "done" ] || continue
  
  TASK_FILE="$D/task/$task_id.md"
  repo=""; branch=""
  BASE="$(pw_field "$TASK_FILE" 'Base branch' 2>/dev/null || true)"
  BASE="${BASE//\`/}"; BASE="${BASE%% *}"; BASE="${BASE:-master}"
  if [ -f "$TASK_FILE" ]; then
    repo="$(pw_field "$TASK_FILE" Repo)"
    branch="$(pw_field "$TASK_FILE" Branch)"; branch="${branch//\`/}"; branch="${branch%% *}"
  fi
  
  # Check for real commits
  HAS_COMMIT="no"
  REPO_DIR="$REPOS_DIR/$repo"
  if [ -n "$repo" ] && [ -d "$REPO_DIR" ] && [ -n "$branch" ]; then
    if git -C "$REPO_DIR" rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
      COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..origin/$branch" 2>/dev/null | wc -l | pw_trim)"
      if [ "${COMMIT_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        HAS_COMMIT="yes"
      fi
    fi
  fi
  
  # Check for existing MR — Result-scoped `**MR:**` field first, then a bare URL in the block
  # (pw_task_mr_url). Only a genuine http(s) URL counts as shipped; `(none)`/odd text does not.
  HAS_MR="no"
  if [ -f "$TASK_FILE" ]; then
    MR_URL="$(pw_task_mr_url "$TASK_FILE")"
    case "$MR_URL" in http*) HAS_MR="yes" ;; esac
  fi
  
  # Resolve ticket
  TICKET="$(pw_field "$TASK_FILE" Ticket 2>/dev/null || true)"
  
  # Extract title from task file
  TITLE="$(grep '^# ' "$TASK_FILE" 2>/dev/null | head -1 | sed 's/^# //; s/^T[0-9]*[: ]*//' | pw_trim)"
  [ -n "$TITLE" ] || TITLE="$task_id"
  
  echo "$task_id|$repo|$branch|$BASE|$TICKET|$TITLE|$HAS_COMMIT|$HAS_MR"
  
done < <(pw_plan_pairs "$PLAN")
