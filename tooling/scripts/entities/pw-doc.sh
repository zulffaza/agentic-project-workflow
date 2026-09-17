#!/usr/bin/env bash
# ============================================================================
# pw-doc.sh — the docs entity: structure validation, summary extraction, and
# dashboard reconciliation for pipeline documents (one operator per verb-family,
# S1a; the three former scripts' semantics and exit codes are unchanged).
#
#   pw-doc.sh lint     <analysis|task|plan|review|dashboard|all> <slug> [<path>]
#       Validate required sections/fields; exit 1 with findings, 0 clean,
#       2 usage/missing project.
#   pw-doc.sh summary  <analysis|task|plan|project> <slug> [<path>]
#       Extract the structured summary an agent would otherwise re-read for.
#   pw-doc.sh sync     <slug> [--dashboard-only|--plan-only|--tasks-only]
#       Reconcile dashboard/task docs from the authoritative files (idempotent).
#
# Merged from pw-doc-lint.sh / pw-doc-summary.sh / pw-doc-sync.sh (plan 20).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-doc: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }



cmd_lint() {
[ $# -ge 2 ] || die "usage: pw-doc.sh lint <type> <slug> [args...]"

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
      add_error "$f: task count mismatch (PLAN has $PLAN_TASKS, found $ACTUAL_TASKS task files)" "align the task table with task/*.md — add missing rows or delete stale ones (then pw-doc.sh sync <slug> --dashboard-only)"
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
  
  # Check items carry machine status markers — via the shared heading-level detector, the ONE
  # (comment-blanking, heading-level, unfilled-stub-exempt) every other consumer uses, instead
  # of a fourth grep that could drift (C22). Unfilled template stubs count as neither item nor
  # marker, so a fresh review can't false-fail; a real heading with NO status vocabulary can.
  _st="$("$HERE/pw-review.sh" count "$SLUG" "$rel_path" 2>/dev/null || true)"
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
      add_error "$f: task table row count ($DASHBOARD_TASKS) doesn't match task files ($ACTUAL_TASKS)" "run: $HERE/pw-doc.sh sync <slug> --dashboard-only (rebuilds the table from task-file truth)"
    fi
  fi
}

case "$TYPE" in
  readme|project) die "user-friendly alias — use 'dashboard' for the README task table or 'all' for the full sweep" ;;
  analysis)
    [ $# -ge 1 ] || die "usage: pw-doc.sh lint analysis <slug> <topic|--all>"
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
    [ $# -ge 1 ] || die "usage: pw-doc.sh lint task <slug> <task-id|--all>"
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
    [ $# -ge 1 ] || die "usage: pw-doc.sh lint review <slug> <path>"
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
  echo "pw-doc lint: found ${#ERRORS[@]} error(s):" >&2
  for err in "${ERRORS[@]}"; do
    _msg="${err%%	*}"; _fix="${err#*	}"
    echo "  - $_msg" >&2
    [ "$_fix" != "$_msg" ] && echo "      → fix: $_fix" >&2
  done
  exit 1
fi

exit 0

}

cmd_summary() {
[ $# -ge 2 ] || die "usage: pw-doc.sh summary <type> <slug> [args...]"

TYPE="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"

case "$TYPE" in
  analysis)
    [ $# -ge 1 ] || die "usage: pw-doc.sh summary analysis <slug> <topic>"
    TOPIC="$1"
    f="$D/analysis/$TOPIC.md"
    [ -f "$f" ] || die "analysis doc not found: $f — /pw-analyze produces analysis docs (ls $D/analysis)"
    
    # Extract §1 problem (first paragraph after §1 heading)
    PROBLEM="$(awk '/^#{1,6}[ \t]+1\./{p=1; next} /^#{1,2}[ \t]/{p=0} p && /^$/{if(got_para) exit; next} p{got_para=1; print; exit}' "$f")"
    [ -n "$PROBLEM" ] || PROBLEM="(summary unavailable — read the doc)"
    echo "Problem: $PROBLEM"
    
    # Extract §4 chosen approach
    CHOSEN="$(grep '^\*\*Chosen approach:\*\*' "$f" | sed 's/^\*\*Chosen approach:\*\* *//' || echo "")"
    [ -n "$CHOSEN" ] || CHOSEN="(not yet chosen)"
    echo "Chosen approach: $CHOSEN"
    
    # Extract affected repos
    REPOS="$(awk '/^#{1,6}[ \t]+3\./{p=1; next} /^#{1,2}[ \t]/{p=0} p && /^- /{gsub(/^- `?/, ""); gsub(/`?.*/, ""); print}' "$f" | tr '\n' ',' | sed 's/,$//')"
    [ -n "$REPOS" ] || REPOS="(none listed)"
    echo "Affected repos: $REPOS"
    ;;
    
  task)
    [ $# -ge 1 ] || die "usage: pw-doc.sh summary task <slug> <task-id>"
    TASK_ID="$1"
    f="$D/task/$TASK_ID.md"
    [ -f "$f" ] || die "task file not found: $f — check the task id against $D/task/T*.md"
    
    REPO="$(pw_field "$f" Repo)"
    echo "Repo: ${REPO:-(not set)}"
    
    BRANCH="$(pw_field "$f" Branch)"; BRANCH="${BRANCH//\`/}"; BRANCH="${BRANCH%% *}"
    echo "Branch: ${BRANCH:-(not set)}"
    
    # Goal: current template has a ## Goal section; legacy tasks carry it in step 1
    GOAL="$(awk '/^## Goal/{p=1; next} /^#/{p=0} p && NF {print; exit}' "$f")"
    [ -n "$GOAL" ] || GOAL="$(awk '/^## Steps/{p=1; next} /^#/{p=0} p && /^[0-9]+\./{gsub(/^[0-9]+\. */, ""); print; exit}' "$f")"
    [ -n "$GOAL" ] || GOAL="(no steps defined)"
    echo "Goal: $GOAL"
    
    SP="$(pw_field "$f" 'Story points')"
    echo "SP: ${SP:-?}"
    ;;
    
  plan)
    f="$D/task/PLAN.md"
    [ -f "$f" ] || die "PLAN.md not found: $f — run /pw-breakdown first"
    
    # Count tasks
    TASK_COUNT="$(awk '/^## Task( |s)/{p=1; next} p && /^\|.*T[0-9]/{count++} END{print count+0}' "$f")"
    
    # Sum SP
    TOTAL_SP="$(awk '/^## Task( |s)/{p=1; next} p && /^\|.*T[0-9]/{split($0,a,"|"); for(i in a){gsub(/ /,"",a[i]); if(a[i] ~ /^[0-9]+$/){sum+=a[i]}}} END{print sum+0}' "$f")"
    
    # Extract repos
    REPOS="$(awk -F'|' '/^## Repo( manifest|s in scope)/{p=1; next} /^## /{p=0} p && /^[ \t]*\|/ && !(/^[ \t]*\|[ \t:|-]+\|[ \t]*$/) { v = $2; gsub(/[ \t`*]/, "", v); if (v != "" && tolower(v) != "repo") print v }' "$f" | paste -sd, -)"
    [ -n "$REPOS" ] || REPOS="(none listed)"
    
    # Extract produced by
    PRODUCED_BY="$(pw_field "$f" 'Produced by')"; PRODUCED_BY="${PRODUCED_BY//\`/}"
    PRODUCED_BY="${PRODUCED_BY%%—*}"
    [ -n "$PRODUCED_BY" ] || PRODUCED_BY="(not set)"
    
    echo "Tasks: $TASK_COUNT (ΣSP=$TOTAL_SP)"
    echo "Repos: $REPOS"
    echo "Produced by: $PRODUCED_BY"
    ;;
    
  project)
    f="$D/README.md"
    [ -f "$f" ] || die "README.md not found: $f"
    
    # Extract One-liner
    ONELINER="$(grep '^- \*\*One-liner:\*\*' "$f" | sed 's/^- \*\*One-liner:\*\* *//' || echo "(not set)")"
    echo "One-liner: $ONELINER"
    
    # Extract phase
    PHASE="$("$HERE/pw-status.sh" phase "$SLUG")"
    echo "Phase: $PHASE"
    
    # Count tasks by status
    TODO="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*todo.*\|/{count++} END{print count+0}' "$f")"
    IN_PROGRESS="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*in-progress.*\|/{count++} END{print count+0}' "$f")"
    DONE="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*done.*\|/{count++} END{print count+0}' "$f")"
    ACCEPTED="$(awk '/^## Task( |s)/{p=1; next} /^## /{p=0} p && /\|.*accepted.*\|/{count++} END{print count+0}' "$f")"
    
    echo "Tasks: $TODO todo, $IN_PROGRESS in-progress, $DONE done, $ACCEPTED accepted"
    ;;
    
  *)
    die "unknown type: $TYPE (expected: analysis|task|plan|project)"
    ;;
esac

}

cmd_sync() {
SYNC_MODE="all"
for arg in "$@"; do
  case "$arg" in
    --dashboard-only) SYNC_MODE="dashboard" ;;
    --plan-only) SYNC_MODE="plan" ;;
    --tasks-only) SYNC_MODE="tasks" ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $arg" ;;
  esac
done

# Extract slug (first non-flag argument)
SLUG=""
for arg in "$@"; do
  [[ "$arg" =~ ^-- ]] && continue
  SLUG="$arg"
  break
done

[ -n "$SLUG" ] || die "usage: pw-doc.sh sync <slug> [--dashboard-only | --plan-only | --tasks-only]"

D="$(proj_dir "$SLUG")"
README="$D/README.md"
PLAN="$D/task/PLAN.md"

[ -f "$README" ] || die "README.md not found"

sync_dashboard() {
  echo "Syncing dashboard (README.md)..."
  [ -f "$PLAN" ] || { echo "PLAN.md not found, skipping"; return 0; }
  
  local WORK; WORK="$(mktemp -d)"; trap 'rm -rf "${WORK:-}"' RETURN   # :- guard: bash 3.2 keeps a RETURN trap in the
  # dynamic scope — it re-fires at the enclosing call's return, after WORK is popped (nesting made this
  # visible when pw-doc.sh merged the three scripts; unguarded it tripped set -u on every sync).
  
  # ---- ground truth per task (from the task file; PLAN status is the tie-break) ----
  local plan_st="$WORK/plan-status" TASKROWS="$WORK/task-rows" MRROWS="$WORK/mr-rows"
  pw_plan_pairs "$PLAN" | tr '|' '\t' > "$plan_st"
  : > "$TASKROWS"; : > "$MRROWS"
  local tf id st repo branch base title line mr
  for tf in "$D/task"/T*.md; do
    [ -f "$tf" ] || continue
    id="$(basename "$tf" .md)"; [[ "$id" =~ ^T[0-9]+ ]] || continue
    st="$(pw_field "$tf" Status)"; [ -n "$st" ] || st="$(awk -F'\t' -v i="$id" '$1==i{print $2; exit}' "$plan_st")"; st="${st:-todo}"
    repo="$(pw_field "$tf" Repo)"; repo="${repo//\`/}"
    branch="$(pw_field "$tf" Branch)"; branch="${branch//\`/}"; branch="${branch%% *}"
    base="$(pw_field "$tf" 'Base branch')"; base="${base//\`/}"; base="${base%% *}"; [ -n "$base" ] || base="—"
    title="$(grep '^# ' "$tf" | head -1 | sed 's/^# //; s/^T[0-9]*[: ]*//' | pw_trim)"; [ -n "$title" ] || title="—"
    mr="$(pw_task_mr_url "$tf")"  # Result-scoped: **MR:** field -> its URL/sentinel, else bare URL
    [ "$mr" = "(none)" ] && mr="—"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$repo" "$branch" "$base" "$title" "$mr" >> "$TASKROWS"
  done
  
  # ---- table rebuilder: keeps the existing header+separator, regenerates data rows;
  #      cells we can derive are taken from TASKROWS, everything else (Notes/State/Build/…)
  #      is preserved per-task-id from the old rows; unknown-to-either cells get —.
  _rebuild_table() {
    local hre="$1" bounds hdrno dstart dend HDR CELLS n i name line id v
    bounds="$(awk -v hre="$hre" '
      BEGIN { want=0; state=0 }
      /^## / { if (!want && $0 ~ hre) { want=1; sec=NR; next } else if (want && state>=1) { print sec, hdr, (dstartNR ? dstartNR : hdr+2), NR-1; exit } else if (want && state==0) { want=0 } }
      want && state==0 && /^[ \t]*\|/ { hdr=NR; state=1; next }
      want && state==1 { # separator expected on hdr+1; data after
        if (NR <= hdr+1) { dstartNR = NR+1 }
        if ($0 !~ /^[ \t]*\|/ && $0 !~ /^[ \t]*$/) { if (!dendFound) { print sec, hdr, dstartNR, NR-1; dendFound=1 } }
      }
      END { if (want && state==1 && !dendFound) print sec, hdr, (dstartNR ? dstartNR : hdr+2), NR }' "$README")"
    [ -n "$bounds" ] || { echo "  (no table under /$hre/ — left untouched)"; return 0; }
    set -- $bounds; hdrno="$2"; dstart="$3"; dend="$4"
    HDR="$(sed -n "${hdrno}p" "$README")"
    
    # header cell names (lowercased, non-code stripped); positional fields after IFS split on |
    CELLS="$(printf '%s' "$HDR" | awk -F'|' '{ for (i = 2; i < NF; i++) { v = $i; gsub(/[ \t`*]/, "", v); print tolower(v) } }')"
    
    # preserved values from existing data rows: "<id>\t<name>\t<value>"
    local PRES="$WORK/pres.${hre//[^A-Za-z]/}"
    : > "$PRES"
    if [ "$dend" -ge "$dstart" ]; then
      printf '%s\n' "$CELLS" > "$WORK/names"
      sed -n "${dstart},${dend}p" "$README" | awk -F'|' -v namesf="$WORK/names" '
        BEGIN { n = 0; while ((getline x < namesf) > 0) NAME[++n] = x }
        { id = $2; gsub(/[ \t]/, "", id); if (id !~ /^T[0-9]+/) next
          for (i = 0; i < n; i++) { v = $(i + 2); gsub(/^[ \t]+/, "", v); gsub(/[ \t|]+$/, "", v); print id "\t" NAME[i + 1] "\t" v } }' > "$PRES"
    fi
    
    # emit new data rows
    local OUT="$WORK/newrows.${hre//[^A-Za-z]/}"
    : > "$OUT"
    while IFS=$'\t' read -r id st repo branch base title mr; do
      local row ln col val
      row=""
      while IFS= read -r col; do
        case "$col" in
          id|task) val="$id" ;;
          status) val="$st" ;;
          repo) val="$repo" ;;
          branch) val="$branch" ;;
          title) val="$title" ;;
          mr) val="$mr" ;;
          "target branch"|"target"|"base branch") val="$base" ;;
          *) val="$(awk -F'\t' -v i="$id" -v c="$col" '$1==i && $2==c { found=1; print $3 } END { if (!found) print "" }' "$PRES")"
             [ -n "$val" ] || val="—" ;;
        esac
        row="$row| $val "
      done <<< "$CELLS"
      echo "${row}|" >> "$OUT"
    done < "$TASKROWS"
    
    # splice: [1..dstart-1] + newrows + [dend+1..]
    local TMP="$WORK/README"
    { sed -n "1,$((dstart-1))p" "$README"; cat "$OUT"; sed -n "$((dend+1)),\$p" "$README"; } > "$TMP"
    mv "$TMP" "$README"
  }
  
  _rebuild_table '^## Task( status|s| table)' 
  
  
  # ---- MR table: append-only rows for tasks with a Result MR (preserves State/Build) ----
  while IFS=$'\t' read -r id st repo branch base title mr; do
    [ "$mr" != "—" ] && [ -n "$mr" ] || continue
    if ! grep -qE "^\|[ \t]*$id[ \t]*\|" "$README"; then
      local mline hdr_cells c col row val
      mline=""
      hdr_cells="$(awk -F'|' '/^## Merge requests/{p=1;next} p && /^## /{exit} p && /^[ \t]*\|/ && NF>2 { for (i=2;i<NF;i++){ v=$i; gsub(/[ \t`*]/,"",v); print tolower(v) } exit }' "$README")"
      row=""
      while IFS= read -r col; do
        case "$col" in
          task|id) val="$id" ;;
          repo) val="$repo" ;;
          mr) val="$mr" ;;
          "target branch") val="$base" ;;
          state) val="open" ;;
          build) val="—" ;;
          *) val="—" ;;
        esac
        row="$row| $val "
      done <<< "$hdr_cells"
      # insert after the separator row of the MR table
      awk -v ins="${row}|" '/^## Merge requests/{p=1} p && /^[ \t]*\|[-: |]+\|$/ { print; print INS; p=0; next } { print }' INS="${row}|" "$README" > "$WORK/re" && mv "$WORK/re" "$README"
    fi
  done < "$TASKROWS"
  
  # refresh State for MR rows from PRESERVED old values is automatic; URL changes:
  while IFS=$'\t' read -r id st repo branch base title mr; do
    [ "$mr" != "—" ] && [ -n "$mr" ] || continue
    grep -qE "^\|[ \t]*$id[ \t]*\|" "$README" || continue
    case "$mr" in *://*) awk -v url="$mr" '
        /^## Merge requests/{ p=1; print; next } p && /^## /{ p=0; print; next }
        p && /^[ \t]*\|[ \t]*'"$id"'[ \t]*\|/ {
          n = split($0, c, "|")
          for (i = 2; i < n; i++) { h = c[i]; gsub(/[ \t`*]/, "", h); if (tolower(h) == "mr") c[i] = " " url " " }
          out = ""; for (i = 1; i <= n; i++) out = out c[i] (i < n ? "|" : ""); print out; next
        }
        { print }' "$README" > "$WORK/re" && mv "$WORK/re" "$README" ;; esac
  done < "$TASKROWS"
  
  echo "Dashboard sync complete"
}

sync_plan() {
  echo "Syncing PLAN.md..."
  
  [ -f "$PLAN" ] || { echo "PLAN.md not found, skipping"; return 0; }
  
  # Sync task count and SP totals
  TASK_COUNT="$(ls -1 "$D/task"/T*.md 2>/dev/null | wc -l | pw_trim)"
  TOTAL_SP=0
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    SP="$(pw_field "$task_file" 'Story points')"; SP="${SP%% *}"
    [[ "$SP" =~ ^[0-9]+$ ]] && TOTAL_SP=$((TOTAL_SP + SP))
  done
  
  # Update PLAN header if needed
  if grep -q '^\*\*Task count:\*\*' "$PLAN"; then
    awk -v count="$TASK_COUNT" -v sp="$TOTAL_SP" '
      /^\*\*Task count:\*\*/ { print "- **Task count:** " count " (ΣSP=" sp ")"; next }
      { print }
    ' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  fi
  
  echo "PLAN sync complete"
}

sync_tasks() {
  echo "Syncing task files..."
  
  for task_file in "$D/task"/T*.md; do
    [ -f "$task_file" ] || continue
    task_id="$(basename "$task_file" .md)"
    
    REPO="$(pw_field "$task_file" Repo)"
    BRANCH="$(pw_field "$task_file" Branch)"; BRANCH="${BRANCH//\`/}"
    BASE="$(pw_field "$task_file" 'Base branch')"; BASE="${BASE//\`/}"; BASE="${BASE%% *}"; BASE="${BASE:-master}"
    
    [ -n "$REPO" ] && [ -n "$BRANCH" ] || continue
    
    REPO_DIR="$REPOS_DIR/$REPO"
    [ -d "$REPO_DIR" ] || continue
    
    # Check for commits
    COMMIT_COUNT=0
    if git -C "$REPO_DIR" rev-parse --verify "origin/$BRANCH" >/dev/null 2>&1; then
      COMMIT_COUNT="$(git -C "$REPO_DIR" log --oneline "origin/$BASE..origin/$BRANCH" 2>/dev/null | wc -l | pw_trim)"
    fi
    
    # Update Result section if needed
    if [ "$COMMIT_COUNT" -gt 0 ]; then
      if ! grep -q 'commits' "$task_file" 2>/dev/null; then
        # Append commit count to Result section
        if grep -q '^## Result' "$task_file"; then
          awk -v count="$COMMIT_COUNT" '/^## Result/{p=1; print; print "- " count " commit(s)"; next} p && /^## /{p=0} {print}' \
            "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
        fi
      fi
    fi
  done
  
  echo "Task file sync complete"
}

case "$SYNC_MODE" in
  dashboard) sync_dashboard ;;
  plan) sync_plan ;;
  tasks) sync_tasks ;;
  all)
    sync_dashboard
    sync_plan
    sync_tasks
    ;;
esac

echo "Document sync complete"

}

case "${1:-}" in
  lint)    shift; cmd_lint "$@" ;;
  summary) shift; cmd_summary "$@" ;;
  sync)    shift; cmd_sync "$@" ;;
  -h|--help) pw_usage ;;
  *) die "usage: pw-doc.sh <lint|summary|sync> … (see --help)" ;;
esac
