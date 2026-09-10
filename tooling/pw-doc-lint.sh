#!/usr/bin/env bash
# ============================================================================
# pw-doc-lint.sh — validate document structure and conventions
#
#   pw-doc-lint.sh analysis <slug> <topic>   validate analysis/<topic>.md
#   pw-doc-lint.sh task <slug> <task-id>     validate task/T0n.md
#   pw-doc-lint.sh plan <slug>               validate task/PLAN.md
#   pw-doc-lint.sh review <slug> <path>      validate review file structure
#   pw-doc-lint.sh dashboard <slug>          validate README.md tables
#   pw-doc-lint.sh all <slug>                lint everything in the project
#
# Exit 0 + silent on pass; exit 1 + human-readable errors on fail.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/.." && pwd)"
. "$HERE/pw-common.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"

die() { echo "pw-doc-lint: $*" >&2; exit 1; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

[ $# -ge 2 ] || die "usage: pw-doc-lint.sh <type> <slug> [args...]"

TYPE="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"
ERRORS=()

add_error() {
  ERRORS+=("$1")
}

lint_analysis() {
  local topic="$1"
  local f="$D/analysis/$topic.md"
  [ -f "$f" ] || die "analysis doc not found: $f"
  
  # Check required sections
  grep -q '^# 1\. Problem' "$f" || add_error "$f: missing §1 (Problem)"
  grep -q '^# 2\. Current state' "$f" || add_error "$f: missing §2 (Current state)"
  grep -q '^# 3\. Affected repos' "$f" || add_error "$f: missing §3 (Affected repos)"
  grep -q '^# 4\. Approach options' "$f" || add_error "$f: missing §4 (Approach options)"
  grep -q '^# 5\. Decisions' "$f" || add_error "$f: missing §5 (Decisions)"
  
  # Check §4 has 2+ options OR explicit justification
  if grep -q '^# 4\. Approach options' "$f"; then
    OPTIONS="$(awk '/^# 4\. Approach options/{p=1; next} /^# /{p=0} p && /^## Option/{count++} END{print count+0}' "$f")"
    if [ "$OPTIONS" -lt 2 ]; then
      if ! grep -q 'only one approach' "$f"; then
        add_error "$f: §4 should have 2+ options or explicit 'only one approach' justification"
      fi
    fi
  fi
  
  # Check §5.1 has decisions log
  if grep -q '^# 5\. Decisions' "$f"; then
    if ! grep -q '## 5\.1 Decisions log' "$f"; then
      add_error "$f: missing §5.1 (Decisions log)"
    fi
  fi
  
  # Check no (Rn)/(Qn) tags in §1-4 prose
  if awk '/^# 1\. Problem/,/^# 5\. Decisions/' "$f" | grep -qE '\([RQ][0-9]+\)' 2>/dev/null; then
    add_error "$f: (Rn)/(Qn) tags belong in §5.1 only, not §1-4"
  fi
  
  # Check chosen approach is filled
  if grep -q '^\*\*Chosen approach:\*\*' "$f"; then
    if grep '^\*\*Chosen approach:\*\*' "$f" | grep -q '_pending'; then
      add_error "$f: 'Chosen approach' is not filled in"
    fi
  fi
}

lint_task() {
  local task_id="$1"
  local f="$D/task/$task_id.md"
  [ -f "$f" ] || die "task file not found: $f"
  
  # Check required fields
  grep -q '^Repo:' "$f" || add_error "$f: missing 'Repo:' field"
  grep -q '^Base branch:' "$f" || add_error "$f: missing 'Base branch:' field"
  grep -q '^Branch:' "$f" || add_error "$f: missing 'Branch:' field"
  grep -q '^Execute with:' "$f" || add_error "$f: missing 'Execute with:' field"
  grep -q '^Story points:' "$f" || add_error "$f: missing 'Story points:' field"
  grep -q '^## Verify' "$f" || add_error "$f: missing '## Verify' section"
  grep -q '^## Steps' "$f" || add_error "$f: missing '## Steps' section"
  grep -q '^## Result' "$f" || add_error "$f: missing '## Result' section"
  
  # Check ## Steps has 3+ items
  if grep -q '^## Steps' "$f"; then
    STEPS="$(awk '/^## Steps/{p=1; next} /^## /{p=0} p && /^[0-9]+\./{count++} END{print count+0}' "$f")"
    if [ "$STEPS" -lt 3 ]; then
      add_error "$f: ## Steps should have 3+ items (has $STEPS)"
    fi
  fi
  
  # Check ## Result is filled if Status is done or accepted
  STATUS="$(grep '^Status:' "$f" | sed 's/^Status: *//' || echo "")"
  if [ "$STATUS" = "done" ] || [ "$STATUS" = "accepted" ]; then
    if grep -q '^## Result' "$f"; then
      RESULT="$(awk '/^## Result/{p=1; next} /^## /{p=0} p' "$f" | wc -l)"
      if [ "$RESULT" -lt 2 ]; then
        add_error "$f: ## Result should be filled when Status is $STATUS"
      fi
    fi
  fi
}

lint_plan() {
  local f="$D/task/PLAN.md"
  [ -f "$f" ] || die "PLAN.md not found: $f"
  
  # Check repo manifest table
  grep -q '^## Repos in scope' "$f" || add_error "$f: missing '## Repos in scope' section"
  
  # Check dependency DAG
  grep -q '^## Dependency' "$f" || add_error "$f: missing '## Dependency' section"
  
  # Check task table
  grep -q '^## Tasks' "$f" || add_error "$f: missing '## Tasks' section"
  
  # Check task table has required columns
  if grep -q '^## Tasks' "$f"; then
    HEADER="$(awk '/^## Tasks/{p=1; next} p && /^\|/{print; exit}' "$f")"
    echo "$HEADER" | grep -q 'Task' || add_error "$f: task table missing 'Task' column"
    echo "$HEADER" | grep -q 'Repo' || add_error "$f: task table missing 'Repo' column"
    echo "$HEADER" | grep -q 'Branch' || add_error "$f: task table missing 'Branch' column"
    echo "$HEADER" | grep -q 'SP' || add_error "$f: task table missing 'SP' column"
    echo "$HEADER" | grep -q 'Execute with' || add_error "$f: task table missing 'Execute with' column"
  fi
  
  # Check Produced by is filled
  if grep -q '^\*\*Produced by:\*\*' "$f"; then
    if grep '^\*\*Produced by:\*\*' "$f" | grep -q '_pending'; then
      add_error "$f: 'Produced by' is not filled in"
    fi
  fi
  
  # Check task count matches actual task files
  if grep -q '^## Tasks' "$f"; then
    PLAN_TASKS="$(awk '/^## Tasks/{p=1; next} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    ACTUAL_TASKS="$(ls -1 "$D/task"/T*.md 2>/dev/null | wc -l | xargs)"
    if [ "$PLAN_TASKS" != "$ACTUAL_TASKS" ]; then
      add_error "$f: task count mismatch (PLAN has $PLAN_TASKS, found $ACTUAL_TASKS task files)"
    fi
  fi
}

lint_review() {
  local rel_path="$1"
  local f="$D/$rel_path"
  [ -f "$f" ] || die "review file not found: $f"
  
  # Check required sections
  grep -q '^## Items' "$f" || add_error "$f: missing '## Items' section"
  grep -q '^## Open questions' "$f" || add_error "$f: missing '## Open questions' section"
  grep -q '^## Sign-off' "$f" || add_error "$f: missing '## Sign-off' section"
  
  # Check items have pw-item-status markers
  if grep -q '^## Items' "$f"; then
    ITEMS="$(awk '/^## Items/{p=1; next} /^## /{p=0} p && /^### /{count++} END{print count+0}' "$f")"
    if [ "$ITEMS" -gt 0 ]; then
      MARKERS="$(grep -c 'pw-item-status:' "$f" || echo 0)"
      if [ "$MARKERS" -lt "$ITEMS" ]; then
        add_error "$f: some items missing pw-item-status markers"
      fi
    fi
  fi
}

lint_dashboard() {
  local f="$D/README.md"
  [ -f "$f" ] || die "README.md not found: $f"
  
  # Check task table rows match task files
  if grep -q '^## Tasks' "$f"; then
    DASHBOARD_TASKS="$(awk '/^## Tasks/{p=1; next} /^## /{p=0} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    ACTUAL_TASKS="$(ls -1 "$D/task"/T*.md 2>/dev/null | wc -l | xargs)"
    if [ "$DASHBOARD_TASKS" != "$ACTUAL_TASKS" ]; then
      add_error "$f: task table row count ($DASHBOARD_TASKS) doesn't match task files ($ACTUAL_TASKS)"
    fi
  fi
}

case "$TYPE" in
  analysis)
    [ $# -ge 1 ] || die "usage: pw-doc-lint.sh analysis <slug> <topic>"
    lint_analysis "$1"
    ;;
  task)
    [ $# -ge 1 ] || die "usage: pw-doc-lint.sh task <slug> <task-id>"
    lint_task "$1"
    ;;
  plan)
    lint_plan
    ;;
  review)
    [ $# -ge 1 ] || die "usage: pw-doc-lint.sh review <slug> <path>"
    lint_review "$1"
    ;;
  dashboard)
    lint_dashboard
    ;;
  all)
    # Lint everything
    if [ -d "$D/analysis" ]; then
      for topic_file in "$D/analysis"/*.md; do
        [ -f "$topic_file" ] || continue
        topic="$(basename "$topic_file" .md)"
        lint_analysis "$topic"
      done
    fi
    if [ -f "$D/task/PLAN.md" ]; then
      lint_plan
    fi
    for task_file in "$D/task"/T*.md; do
      [ -f "$task_file" ] || continue
      task_id="$(basename "$task_file" .md)"
      lint_task "$task_id"
    done
    if [ -d "$D/analysis/review" ]; then
      for review_file in "$D/analysis/review"/*.review.md; do
        [ -f "$review_file" ] || continue
        lint_review "analysis/review/$(basename "$review_file")"
      done
    fi
    if [ -d "$D/task/review" ]; then
      for review_file in "$D/task/review"/*.review.md; do
        [ -f "$review_file" ] || continue
        lint_review "task/review/$(basename "$review_file")"
      done
    fi
    lint_dashboard
    ;;
  *)
    die "unknown type: $TYPE (expected: analysis|task|plan|review|dashboard|all)"
    ;;
esac

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "pw-doc-lint: found ${#ERRORS[@]} error(s):" >&2
  for err in "${ERRORS[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

exit 0
