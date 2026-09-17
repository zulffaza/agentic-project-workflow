#!/usr/bin/env bash
# ============================================================================
# pw-doc-lint.sh — validate document structure and conventions
#
#   pw-doc-lint.sh analysis <slug> <topic|--all>   validate analysis/<topic>.md (or all topics)
#   pw-doc-lint.sh task <slug> <task-id|--all>     validate task/T0n.md (or all task files)
#   pw-doc-lint.sh plan <slug>               validate task/PLAN.md
#   pw-doc-lint.sh review <slug> <path>      validate review file structure
#   pw-doc-lint.sh dashboard <slug>          validate README.md tables
#   pw-doc-lint.sh all <slug>                lint everything in the project
#
# Exit 0 + silent on pass; exit 1 + human-readable errors on fail.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-doc-lint: $*" >&2; exit 2; }   # 2 = usage/missing project (lint *findings* exit 1 via add_error — docs exit table)
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

[ $# -ge 2 ] || die "usage: pw-doc-lint.sh <type> <slug> [args...]"

TYPE="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"
ERRORS=()

add_error() {
  # add_error "problem" [remediation] — remediation, when given, prints as a
  # second line so no gate failure is ever a dead end.
  if [ $# -ge 2 ]; then ERRORS+=("$1"$'\t'"$2"); else ERRORS+=("$1"); fi
}

lint_analysis() {
  local topic="$1"
  local f="$D/analysis/$topic.md"
  [ -f "$f" ] || die "analysis doc not found: $f"
  
  # Check required sections
  _tpl="section shape: $D/analysis/_TEMPLATE.md"
  grep -qE '^#{1,6}[[:space:]]+1\.' "$f" || add_error "$f: missing §1 (Problem/goal)" "$_tpl"
  grep -qE '^#{1,6}[[:space:]]+2\.' "$f" || add_error "$f: missing §2 (Current state)" "$_tpl"
  grep -qE '^#{1,6}[[:space:]]+3\.' "$f" || add_error "$f: missing §3 (Affected repos)" "$_tpl"
  grep -qE '^#{1,6}[[:space:]]+4\.' "$f" || add_error "$f: missing §4 (approach options)" "$_tpl"
  grep -qE '^#{1,6}[[:space:]]+5\.' "$f" || add_error "$f: missing §5 (decisions/risks)" "$_tpl"
  
  # Check §4 has 2+ options OR explicit justification
  if grep -qE '^#{1,6}[[:space:]]+4\.' "$f"; then
    OPTIONS="$(awk '
      /^#{1,2}[ \t]+4\./ { insec = 1; next }
      /^#{1,2}[ \t]/     { insec = 0 }
      insec && /^#{3,}[ \t]/ && ($0 ~ /[Oo]ption|[Ss]olution area|[0-9]+\.[0-9]+ [A-Z]/) { count++ }
      END { print count+0 }' "$f")"
    if [ "$OPTIONS" -lt 2 ]; then
      if ! grep -q 'only one approach' "$f"; then
        add_error "$f: §4 should have 2+ options or explicit 'only one approach' justification" "add '### 4.1 …' / '### 4.2 …' option subsections under §4, or state 'only one approach' with justification"
      fi
    fi
  fi
  
  # Check §5.1 has decisions log
  if grep -qE '^#{1,6}[[:space:]]+5\.' "$f"; then
    if ! grep -qE '^#{2,6}[[:space:]]+5\.1 ' "$f"; then
      add_error "$f: missing §5.1 (Decisions log)" "add '### 5.1 Decisions log' under §5 — (Rn)/(Qn) decision entries live there"
    fi
  fi
  
  # Check no (Rn)/(Qn) tags in §1-4 prose
  if awk '/^#{1,2}[ \t]+1\./, /^#{1,2}[ \t]+5\./' "$f" | grep -qE '\([RQ][0-9]+\)' 2>/dev/null; then
    add_error "$f: (Rn)/(Qn) tags belong in §5.1 only, not §1-4" "move each '(Rn)'/'(Qn)' citation into §5.1; §1–4 prose refers to decisions by name, not tag"
  fi
  
  # Check chosen approach is filled
  if grep -q '^\*\*Chosen approach:\*\*' "$f"; then
    if grep '^\*\*Chosen approach:\*\*' "$f" | grep -q '_pending'; then
      add_error "$f: 'Chosen approach' is not filled in" "fill the '**Chosen approach:**' line with the picked §4 option (human decision)"
    fi
  fi
}

lint_task() {
  local task_id="$1"
  local f="$D/task/$task_id.md"
  [ -f "$f" ] || die "task file not found: $f"
  
  # Check required fields
  for _fl in "Repo" "Base branch" "Branch" "Execute with" "Story points"; do
    pw_has_field "$f" "$_fl" || add_error "$f: missing '$_fl' field (as '- **$_fl:**' bullet or '^$_fl:' line)" "add '- **$_fl:** <value>' in the header bullets — value must agree with the task's PLAN row"
  done
  grep -q '^## Verify' "$f" || add_error "$f: missing '## Verify' section" "see $D/task/_TEMPLATE-task.md for the required sections"
  grep -q '^## Steps' "$f" || add_error "$f: missing '## Steps' section" "see $D/task/_TEMPLATE-task.md for the required sections"
  grep -q '^## Result' "$f" || add_error "$f: missing '## Result' section" "see $D/task/_TEMPLATE-task.md for the required sections"
  
  # Check ## Steps has 3+ items
  if grep -q '^## Steps' "$f"; then
    STEPS="$(awk '/^## Steps/{p=1; next} /^## /{p=0} p && /^[0-9]+\./{count++} END{print count+0}' "$f")"
    if [ "$STEPS" -lt 3 ]; then
      add_error "$f: ## Steps should have 3+ items (has $STEPS)" "expand '## Steps' to 3+ numbered steps (small enough to be one agent turn each)"
    fi
  fi
  
  # Check ## Result is filled if Status is done or accepted
  STATUS="$(pw_field "$f" Status)"
  if [ "$STATUS" = "done" ] || [ "$STATUS" = "accepted" ]; then
    if grep -q '^## Result' "$f"; then
      RESULT="$(awk '/^## Result/{p=1; next} /^## /{p=0} p' "$f" | wc -l)"
      if [ "$RESULT" -lt 2 ]; then
        add_error "$f: ## Result should be filled when Status is $STATUS" "the executor fills '## Result' when it completes — re-run: /pw-execute <slug> $task_id (or fill it by hand if the work is genuinely done)"
      fi
    fi
  fi
}

lint_plan() {
  local f="$D/task/PLAN.md"
  [ -f "$f" ] || die "PLAN.md not found: $f"
  
  # Check repo manifest table
  grep -qE '^## (Repo manifest|Repos in scope)' "$f" || add_error "$f: missing repo-manifest section (template heading '## Repo manifest')" "add '## Repo manifest' with the repo/base-branch table — see $D/task/_TEMPLATE-orchestration-plan.md"
  
  # Check dependency DAG
  grep -q '^## Dependency' "$f" || add_error "$f: missing '## Dependency' section" "add the '## Dependency DAG' mermaid section — see $D/task/_TEMPLATE-orchestration-plan.md"
  
  # Check task table
  grep -qE '^## Task( |s)' "$f" || add_error "$f: missing task-table section (expected '## Task table')" "add '## Task table' (ID|Title|Repo|depends_on|Group|Execute with|SP|Status|Time|Result columns)"
  
  # Check task table has required columns
  if grep -qE '^## Task( |s)' "$f"; then
    HEADER="$(awk '/^## Task( |s)/{p=1; next} p && /^\|/{print; exit}' "$f")"
    _col() { printf '%s\n' "$HEADER" | awk -F'|' -v re="$1" '{ for (i = 1; i <= NF; i++) { v = $i; gsub(/[ \t`*]/, "", v); if (tolower(v) ~ re) found = 1 } } END { exit found ? 0 : 1 }'; }
    _col '^(task|id)$'      || add_error "$f: task table missing an ID/Task column" "rebuild the header row from $D/task/_TEMPLATE-orchestration-plan.md"
    _col '^repo$'           || add_error "$f: task table missing 'Repo' column" "rebuild the header row from $D/task/_TEMPLATE-orchestration-plan.md"
    _col '^sp$'             || add_error "$f: task table missing 'SP' column" "rebuild the header row from $D/task/_TEMPLATE-orchestration-plan.md"
    _col '^executewith$'    || add_error "$f: task table missing 'Execute with' column" "rebuild the header row from $D/task/_TEMPLATE-orchestration-plan.md"
    _col '^status$'         || add_error "$f: task table missing 'Status' column" "rebuild the header row from $D/task/_TEMPLATE-orchestration-plan.md"
  fi
  
  # Check Produced by is filled (line-start bold or '- **Produced by:**' bullet)
  _PB="$(pw_field "$f" 'Produced by')"
  if [ -n "$_PB" ] && printf '%s' "$_PB" | grep -q '_pending'; then
    add_error "$f: 'Produced by' is not filled in" "fill '- **Produced by:**' with the breakdown run's agent/model stamp"
  fi
  
  # Check task count matches actual task files
  if grep -qE '^## Task( |s)' "$f"; then
    PLAN_TASKS="$(awk '/^## Task( |s)/{p=1; next} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    ACTUAL_TASKS="$(find "$D/task" -maxdepth 1 -name 'T*.md' ! -name '_TEMPLATE*' 2>/dev/null | wc -l | pw_trim)"
    if [ "$PLAN_TASKS" != "$ACTUAL_TASKS" ]; then
      add_error "$f: task count mismatch (PLAN has $PLAN_TASKS, found $ACTUAL_TASKS task files)" "align the task table with task/*.md — add missing rows or delete stale ones (then pw-doc-sync.sh <slug> --dashboard-only)"
    fi
  fi
}

lint_review() {
  local rel_path="$1"
  local f="$D/$rel_path"
  [ -f "$f" ] || die "review file not found: $f"
  
  # Check required sections
  grep -q '^## Items' "$f" || add_error "$f: missing '## Items' section" "review files start from $D/_REVIEW.template.md (created via /pw-review)"
  grep -q '^## Open questions' "$f" || add_error "$f: missing '## Open questions' section" "review files start from $D/_REVIEW.template.md (created via /pw-review)"
  grep -q '^## Sign-off' "$f" || add_error "$f: missing '## Sign-off' section" "review files start from $D/_REVIEW.template.md (created via /pw-review)"
  
  # Check items carry machine status markers — via pw-lib's "review count", the ONE detector
  # (comment-blanking, heading-level, unfilled-stub-exempt) every other consumer uses, instead
  # of a fourth grep that could drift (C22). Unfilled template stubs count as neither item nor
  # marker, so a fresh review can't false-fail; a real heading with NO status vocabulary can.
  _st="$("$HERE/../../pw-lib.sh" review count "$SLUG" "$rel_path" 2>/dev/null || true)"
  ITEMS="$(printf '%s' "$_st" | sed -n 's/.*items=\([0-9]*\).*/\1/p')"; ITEMS="${ITEMS:-0}"
  if [ "$ITEMS" -gt 0 ]; then
    _mo="$(printf '%s' "$_st" | sed -n 's/.*open=\([0-9]*\).*/\1/p')"; _mo="${_mo:-0}"
    _mr="$(printf '%s' "$_st" | sed -n 's/.*resolved=\([0-9]*\).*/\1/p')"; _mr="${_mr:-0}"
    if [ $(( _mo + _mr )) -lt "$ITEMS" ]; then
      add_error "$f: $ITEMS item headings but only $((_mo + _mr)) carry a pw-item-status marker" "add '<!-- pw-item-status: open|resolved -->' on each real '###' item heading (vocabulary is open|resolved — see _REVIEW.template.md)"
    fi
  fi
}

lint_dashboard() {
  local f="$D/README.md"
  [ -f "$f" ] || die "README.md not found: $f"
  
  # Check task table rows match task files
  if grep -qE '^## Task( |s)' "$f"; then
    DASHBOARD_TASKS="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    ACTUAL_TASKS="$(find "$D/task" -maxdepth 1 -name 'T*.md' ! -name '_TEMPLATE*' 2>/dev/null | wc -l | pw_trim)"
    if [ "$DASHBOARD_TASKS" != "$ACTUAL_TASKS" ]; then
      add_error "$f: task table row count ($DASHBOARD_TASKS) doesn't match task files ($ACTUAL_TASKS)" "run: $HERE/pw-doc-sync.sh <slug> --dashboard-only (rebuilds the table from task-file truth)"
    fi
  fi
}

case "$TYPE" in
  readme|project) die "user-friendly alias — use 'dashboard' for the README task table or 'all' for the full sweep" ;;
  analysis)
    [ $# -ge 1 ] || die "usage: pw-doc-lint.sh analysis <slug> <topic|--all>"
    if [ "$1" = "--all" ]; then
      found=0
      for topic_file in "$D/analysis"/*.md; do
        [ -f "$topic_file" ] || continue
        case "$(basename "$topic_file")" in _*|README.md) continue ;; esac   # scaffold, not a real doc
        lint_analysis "$(basename "$topic_file" .md)"
        found=1
      done
      [ "$found" = 1 ] || add_error "$D/analysis: no analysis docs to lint (--all matched none)" "run /pw-analyze to produce them from the context/ notes"
    else
      lint_analysis "$1"
    fi
    ;;
  task)
    [ $# -ge 1 ] || die "usage: pw-doc-lint.sh task <slug> <task-id|--all>"
    if [ "$1" = "--all" ]; then
      found=0
      for task_file in "$D/task"/T*.md; do
        [ -f "$task_file" ] || continue
        lint_task "$(basename "$task_file" .md)"
        found=1
      done
      [ "$found" = 1 ] || add_error "$D/task: no task files to lint (--all matched none)" "run /pw-breakdown to produce them from the approved analysis"
    else
      lint_task "$1"
    fi
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
        case "$(basename "$topic_file")" in _*|README.md) continue ;; esac   # scaffold, not a real doc
        lint_analysis "$(basename "$topic_file" .md)"
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
    _msg="${err%%	*}"; _fix="${err#*	}"
    echo "  - $_msg" >&2
    [ "$_fix" != "$_msg" ] && echo "      → fix: $_fix" >&2
  done
  exit 1
fi

exit 0
