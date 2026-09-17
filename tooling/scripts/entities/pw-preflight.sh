#!/usr/bin/env bash
# ============================================================================
# pw-preflight.sh — gate validation before expensive agent invocations
#
#   pw-preflight.sh analyze   <slug>         phase legal + context/ inputs exist
#   pw-preflight.sh execute   <slug>         check PLAN review gate, phase, scope
#   pw-preflight.sh breakdown <slug>         check analysis review gates, RFC
#   pw-preflight.sh ship      <slug>         check shippable tasks, verify
#   pw-preflight.sh comments  <slug>         check ≥1 task has a linked MR (comment push)
#   pw-preflight.sh close     <slug>         check all tasks accepted
#   pw-preflight.sh review    <slug> [phase] check review files exist
#
# Every failure names the concrete next action ("→ fix: …"), so a blocked
# command is never a dead end. Exit 0 + silent on success; exit 1 + message else.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-preflight: $*" >&2; exit 1; }
# die_fix <problem> <fix> — one error line plus the concrete recovery action.
die_fix() {
  echo "pw-preflight: $1" >&2
  if [ $# -ge 2 ] && [ -n "$2" ]; then echo "  → fix: $2" >&2; fi
  exit 1
}
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die_fix "no such project: $1 ($d)" "check the slug under $PROJECTS_DIR (scaffold a new one with: scaffold.sh $1)"; printf '%s' "$d"; }

[ $# -ge 2 ] || die "usage: pw-preflight.sh <command> <slug> [args...]"

COMMAND="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"
PHASE_RAW="$("$HERE/../../pw-lib.sh" phase "$SLUG" 2>/dev/null || true)"
PHASE="$(pw_phase_token "${PHASE_RAW:-missing}")"
PHASE_FIX=""
case "$COMMAND" in
  analyze) PHASE_FIX="if you are (re-)analyzing a project that moved on: pw-lib.sh status $SLUG analysis --rewind" ;;
  ship) PHASE_FIX="finish execution first (each task '- **Status:** done'), or if the project IS further along: pw-lib.sh status $SLUG <phase>" ;;
  execute) PHASE_FIX="set the phase with: pw-lib.sh status $SLUG executing (or run /pw-breakdown to create the PLAN)" ;;
  breakdown) PHASE_FIX="get to an analysis/breakdown phase first (/pw-analyze), or pw-lib.sh status $SLUG breakdown" ;;
  close) PHASE_FIX="close runs after acceptance (/pw-ship handles MRs; accepted tasks then pw-lib.sh status $SLUG done)" ;;
  comments) PHASE_FIX="comments push to MRs, which exist only after a ship — run /pw-ship $SLUG (push mode) first" ;;
esac
if ! pw_phase_valid "$PHASE"; then
  die_fix "phase token '${PHASE:-missing}' is not canonical (README says: '- **Status:** ${PHASE_RAW:-none}')" "$(pw_phase_hint | sed "s/<slug>/$SLUG/")"
fi
# Gate: require PHASE (except commands without a phase constraint).
phase_gate() { case " $1 " in *" $PHASE "*) return 0 ;; *) die_fix "cannot $COMMAND in phase '$PHASE' (must be: $1)" "${PHASE_FIX}";; esac; }

case "$COMMAND" in
  analyze)
    phase_gate "context analysis"

    # The analysis agent reasons ONLY from context/ — fail early if it's empty,
    # with the concrete fill step, instead of a vague "insufficient context" mid-run.
    [ -f "$D/context/INDEX.md" ] || die_fix "context/INDEX.md missing" "the 🧑 context index is the analysis input — create it (shape in context/README.md) or run /pw-research $SLUG to gather inputs first"
    _inrows="$(awk '
      /^\|/ {
        if ($0 ~ /---/) next
        if (index($0, "_e.g._")) next   # scaffold example row = not real input (legend-token class)
        n = split($0, cells, "|")
        first = cells[2]; gsub(/[ \t`*-]/, "", first)
        if (first == "") next
        low = tolower(first)
        if (low ~ /^file.?link$/ || low ~ /^repo/) next
        count++
      } END { print count+0 }' "$D/context/INDEX.md")"
    if [ "$_inrows" -lt 1 ]; then
      die_fix "context/INDEX.md has no input rows yet" "fill 'File / link' rows (tickets, REQUIREMENTS.md, code refs — one per input) before analyzing, or run /pw-research $SLUG to gather them"
    fi
    ;;

  execute)
    phase_gate "breakdown executing review"

    # Check PLAN review gate
    if [ -f "$D/task/review/PLAN.review.md" ]; then
      if ! "$HERE/../../pw-lib.sh" review gate "$SLUG" task/review/PLAN.review.md >/dev/null 2>&1; then
        die_fix "PLAN review gate not approved" "approve it in $D/task/review/PLAN.review.md (## Sign-off row) or run /pw-review $SLUG"
      fi
    else
      die_fix "PLAN review file missing (task/review/PLAN.review.md)" "run /pw-breakdown $SLUG (it drafts the PLAN + its review file), then approve via /pw-review"
    fi

    # Check PLAN exists
    if [ ! -f "$D/task/PLAN.md" ]; then
      die_fix "PLAN.md missing" "run /pw-breakdown $SLUG"
    fi

    # Check provider awareness: validate each task's Execute-with table value
    # (column-name driven — pw_plan_execs; covers both PLAN generations).
    while IFS= read -r EXEC_WITH; do
      EXEC_WITH="$(printf '%s' "$EXEC_WITH" | pw_trim)"
      if [ -n "$EXEC_WITH" ] && [ "$EXEC_WITH" != "—" ]; then
        PROVIDER="${EXEC_WITH%%:*}"
        MODEL="${EXEC_WITH#*:}"
        if ! "$HERE/../../pw-lib.sh" model-check "$PROVIDER" "$MODEL" >/dev/null 2>&1; then
          die_fix "model check failed for '$EXEC_WITH' (not in allowlist)" "allow it via PW_$(printf '%s' "$PROVIDER" | tr a-z A-Z)_MODELS in pw.config.sh, or change the PLAN 'Execute with' cell"
        fi
      fi
    done < <(pw_plan_execs "$D/task/PLAN.md")
    ;;

  breakdown)
    phase_gate "analysis breakdown"

    # Check analysis review gates
    if [ -d "$D/analysis/review" ]; then
      for review_file in "$D/analysis/review"/*.review.md; do
        [ -f "$review_file" ] || continue
        if ! "$HERE/../../pw-lib.sh" review gate "$SLUG" "analysis/review/$(basename "$review_file")" >/dev/null 2>&1; then
          die_fix "analysis review gate not approved for $(basename "$review_file")" "approve it (## Sign-off row with 'approved') or run /pw-review $SLUG"
        fi
      done
    fi

    # Check RFC open items (if RFC exists)
    if [ -f "$D/rfc/META.md" ]; then
      if "$HERE/../../pw-lib.sh" review has-open "$SLUG" "analysis/review/RFC.review.md" 2>/dev/null; then
        die_fix "RFC has open items" "resolve/close them in analysis/review/RFC.review.md (pw-item-status markers) before breakdown"
      fi
    fi
    ;;

  ship)
    phase_gate "executing review"

    # Shippable = at least one task with PLAN Status 'done' (verify-failed is
    # 'verify-failed', accepted has moved on). Column/ID-driven: works on both
    # PLAN generations including markdown-linked ids — never positional.
    [ -f "$D/task/PLAN.md" ] || die_fix "PLAN.md missing" "run /pw-breakdown $SLUG"
    SHIPPABLE=""
    NOTDONE=""
    while IFS='|' read -r task_id status; do
      [ -n "$task_id" ] || continue
      if [ "$status" = "done" ]; then
        SHIPPABLE="$SHIPPABLE $task_id"
        TASK_FILE="$D/task/$task_id.md"
        # Status FIELD only — never a whole-file grep: the template legend mentions
        # "verify-failed" in a comment and would match every fresh task file.
        if [ -f "$TASK_FILE" ] && [ "$(pw_field "$TASK_FILE" Status)" = "verify-failed" ]; then
          die_fix "task $task_id is verify-failed" "fix and re-verify it (/pw-execute $SLUG $task_id) before shipping"
        fi
      elif [ "$status" != "accepted" ]; then
        NOTDONE="$NOTDONE $task_id"
      fi
    done < <(pw_plan_pairs "$D/task/PLAN.md")
    if [ -z "$SHIPPABLE" ]; then
      die_fix "no shippable tasks (PLAN task table shows no Status 'done')$([ -n "$NOTDONE" ] && printf ' — not yet done:%s' "$NOTDONE")" "complete the tasks (/pw-execute $SLUG) — 'done' means executed+verified; a pushed-comment sweep uses 'pw-preflight.sh comments $SLUG' instead"
    fi
    ;;

  comments)
    # /pw-ship <slug> comments posts to ALREADY-pushed MRs — no 'done' requirement
    # (tasks may be accepted, or done-pending-second-round), only an existing MR.
    phase_gate "executing review done"
    LINKED=0
    for tf in "$D"/task/T*.md; do
      [ -e "$tf" ] || continue
      MR="$(pw_task_mr_url "$tf")"  # Result-scoped MR field (see pw_task_mr_url)
      case "${MR:-}" in http*) LINKED=$((LINKED + 1)) ;; esac
    done
    if [ "$LINKED" -eq 0 ]; then
      die_fix "no task has a linked MR to comment on" "push first: /pw-ship $SLUG (push mode) creates the MRs and records '- **MR:**' in each task file"
    fi
    ;;

  close)
    phase_gate "review done"

    # All tasks accepted? (name-driven, both PLAN generations).
    [ -f "$D/task/PLAN.md" ] || die_fix "PLAN.md missing" "nothing to close — /pw-breakdown $SLUG first"
    UNACCEPTED=""
    while IFS='|' read -r task_id status; do
      [ -n "$task_id" ] || continue
      [ "$status" = "accepted" ] || UNACCEPTED="$UNACCEPTED $task_id($status)"
    done < <(pw_plan_pairs "$D/task/PLAN.md")
    if [ -n "$UNACCEPTED" ]; then
      die_fix "not all tasks are accepted:$UNACCEPTED" "a human accepts each shipped task (set '- **Status:** accepted' in the task file + PLAN row), then sync the dashboard: pw-doc-sync.sh $SLUG --dashboard-only"
    fi
    ;;

  review)
    PHASE_FILTER="${1:-}"

    # Check review files exist
    if [ -n "$PHASE_FILTER" ]; then
      case "$PHASE_FILTER" in
        analysis)
          if [ ! -d "$D/analysis/review" ] || [ -z "$(ls -A "$D/analysis/review"/*.review.md 2>/dev/null)" ]; then
            die_fix "no analysis review files found" "run /pw-review $SLUG (analysis phase) to create them"
          fi
          ;;
        plan|task-plan)
          if [ ! -f "$D/task/review/PLAN.review.md" ]; then
            die_fix "PLAN review file missing" "run /pw-breakdown $SLUG then /pw-review $SLUG (plan)"
          fi
          ;;
        task-exec)
          if [ ! -d "$D/task/review" ] || [ -z "$(ls -A "$D/task/review"/T*.review.md 2>/dev/null)" ]; then
            die_fix "no task review files found" "run /pw-review $SLUG (task-exec phase) for the shipped tasks"
          fi
          ;;
      esac
    else
      # Check any review files exist
      if [ ! -d "$D/analysis/review" ] && [ ! -d "$D/task/review" ]; then
        die_fix "no review directories found" "run /pw-review $SLUG to open the first review"
      fi
    fi
    ;;

  *)
    die "unknown command: $COMMAND (expected: analyze|execute|breakdown|ship|comments|close|review)"
    ;;
esac

exit 0
