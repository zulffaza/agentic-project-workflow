#!/usr/bin/env bash
# ============================================================================
# pw-preflight.sh — gate validation before expensive agent invocations
#
#   pw-preflight.sh analyze     <slug>
#       phase legal + context/ inputs exist
#   pw-preflight.sh prepare     <slug>
#       phase context (assisted preparation writes context only; empty scaffolded
#       context is accepted — unlike analyze, no input rows are required)
#   pw-preflight.sh execute     <slug>
#       check PLAN review gate (latest approval, no real open items), phase, scope
#   pw-preflight.sh breakdown   <slug>
#       check analysis review gates (latest approval, no real open items; RFC staging
#       excluded from approval discovery — its own open-item gate stays), RFC
#   pw-preflight.sh ship        <slug>
#       check shippable tasks, verify
#   pw-preflight.sh comments    <slug>
#       check ≥1 task has a linked MR (comment push)
#   pw-preflight.sh close       <slug>
#       check all tasks accepted
#   pw-preflight.sh review      <slug> [lane]
#       check review files exist — lane: analysis|plan|task-plan|task-exec|ship
#       (unknown lane words fail closed)
#
# Exit 0 + silent on success; exit 1 + message naming the concrete blocker
# otherwise — the command files carry the recovery actions (every blocked step
# in /pw-* says "→ fix: …" in prose).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
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
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die_fix "no such project: $1 ($d)" "check the slug under $PROJECTS_DIR (scaffold a new one with: /pw-new $1)"; printf '%s' "$d"; }

# _gate_review_approved <review-rel-path> — the approval gate a phase-consuming
# command needs, via the shared mdlib file readers (this script never re-implements a
# detector): `_review_approval_valid` is true ONLY when the LATEST real Sign-off row reads
# approved (legacy "approved ✅" included), NO real unresolved item/question remains
# (template stubs and worked examples never match), and no explicit human rejection is
# still active — feedback applied after an approval, by any route including hand edits,
# invalidates consumption even though the historical row stays in the file. Classification
# for the message: approved-then-open is a STALE approval and needs a different fix than
# "never approved" (an active human rejection reads as 11 — resolve/approve through
# /pw-review, the human's decision to withdraw or re-approve is not this gate's call).
# rc: 0 pass · 10 real open items remain · 11 no consumable approval (latest row not an
# approval, an active human rejection, or no Sign-off rows at all — fail closed).
_gate_review_approved() { # <review-rel-path> (resolved against $D — the caller's project)
  local f="$D/$1"
  _review_approval_valid "$f" && return 0
  _review_has_open_marker "$f" && return 10
  return 11
}

[ $# -ge 2 ] || die "usage: pw-preflight.sh <command> <slug> [args...]"

COMMAND="$1"
SLUG="$2"
shift 2

D="$(proj_dir "$SLUG")"
PHASE_RAW="$("$HERE/pw-status.sh" phase "$SLUG" 2>/dev/null || true)"
PHASE="$(pw_phase_token "${PHASE_RAW:-missing}")"
PHASE_FIX=""
case "$COMMAND" in
  analyze) PHASE_FIX="if you are (re-)analyzing a project that moved on: /pw-status $SLUG rewind analysis" ;;
  prepare) PHASE_FIX="preparation writes context only; if you really mean to redo this project's context: reopen its analysis and PLAN reviews first with /pw-review (their stale approvals must not be consumed), then /pw-status $SLUG rewind context, then re-run preparation" ;;
  ship) PHASE_FIX="finish execution first (each task '- **Status:** done'), or if the project IS further along: /pw-status $SLUG rewind <phase>" ;;
  execute) PHASE_FIX="move to executing via the flow (/pw-breakdown creates the PLAN and the flow advances the phase; /pw-status $SLUG rewind <phase> from a later one)" ;;
  breakdown) PHASE_FIX="get to an analysis/breakdown phase first (/pw-analyze), or /pw-status $SLUG rewind breakdown" ;;
  close) PHASE_FIX="close runs after acceptance (/pw-ship handles MRs; accept each done task — tell the agent to record it)" ;;
  comments) PHASE_FIX="comments push to MRs, which exist only after a ship — run /pw-ship $SLUG (push mode) first" ;;
esac
if ! pw_phase_valid "$PHASE"; then
  die_fix "phase token '${PHASE:-missing}' is not canonical (README says: '- **Status:** ${PHASE_RAW:-none}')" "$(pw_phase_hint | sed "s/<slug>/$SLUG/")"
fi
# Gate: require PHASE (except commands without a phase constraint).
phase_gate() { case " $1 " in *" $PHASE "*) return 0 ;; *) die_fix "cannot $COMMAND in phase '$PHASE' (must be: $1)" "${PHASE_FIX}";; esac; }

case "$COMMAND" in
  prepare)
    # Assisted preparation (/pw-context <slug> prepare): reads the dashboard/context, then
    # writes the brief and INDEX rows through the context entity. Empty scaffolded context is
    # the normal starting point — only the phase is gated (analyze keeps its input-row gate).
    phase_gate "context"
    ;;

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

    # Check PLAN review gate — the approval must be the file's LATEST row AND the file
    # must carry no real unresolved item: feedback applied after approval (or a hand
    # reopen) makes a stale historical "approved" row unusable — consumers fail closed
    # until re-approval, they never re-read history.
    if [ -f "$D/task/review/PLAN.review.md" ]; then
      _grc=0
      _gate_review_approved task/review/PLAN.review.md || _grc=$?
      case "$_grc" in
        10) die_fix "PLAN review has unresolved items — its approval no longer stands" "resolve them (/pw-review $SLUG), then have the Sign-off row re-approved" ;;
        11) die_fix "PLAN review gate not approved" "approve it in $D/task/review/PLAN.review.md (## Sign-off row) or run /pw-review $SLUG" ;;
      esac
    else
      die_fix "PLAN review file missing (task/review/PLAN.review.md)" "run /pw-breakdown $SLUG (it drafts the PLAN + its review file), then approve via /pw-review"
    fi

    # Check PLAN exists
    if [ ! -f "$D/task/PLAN.md" ]; then
      die_fix "PLAN.md missing" "run /pw-breakdown $SLUG"
    fi

    # Check provider awareness: validate each task's Execute-with table value
    # (column-name driven — pw_plan_execs; covers both PLAN generations). Two axes:
    # model-check = PERMISSION (allowlist), model-resolve = AVAILABILITY (live catalog +
    # api-provider prefix scope). model-resolve fails open on "can't check" (no catalog /
    # unknown provider), so a refusal here is a positive determination, safe to hard-stop on.
    while IFS= read -r EXEC_WITH; do
      EXEC_WITH="$(printf '%s' "$EXEC_WITH" | pw_trim)"
      if [ -n "$EXEC_WITH" ] && [ "$EXEC_WITH" != "—" ]; then
        PROVIDER="${EXEC_WITH%%:*}"
        MODEL="${EXEC_WITH#*:}"
        if ! "$HERE/pw-config.sh" model-check "$PROVIDER" "$MODEL" >/dev/null 2>&1; then
          die_fix "model check failed for '$EXEC_WITH' (not in allowlist)" "allow it via PW_$(printf '%s' "$PROVIDER" | tr a-z A-Z)_MODELS in pw.config.sh, or change the PLAN 'Execute with' cell"
        fi
        _mr_rc=0
        _mr_err="$("$HERE/pw-config.sh" model-resolve "$PROVIDER" "$MODEL" 2>&1 >/dev/null)" || _mr_rc=$?
        if [ "$_mr_rc" != 0 ]; then
          die_fix "model-resolve refused '$EXEC_WITH' — this row pins a model/provider that is NOT available right now" "$(printf '%s' "$_mr_err" | tr '\n' ' ' | sed -E 's/^(model-resolve| *→ fix:)+ *//')"
        fi
      fi
    done < <(pw_plan_execs "$D/task/PLAN.md")
    ;;

  breakdown)
    phase_gate "analysis breakdown"

    # Check analysis review gates — every analysis review must be approved as its LATEST
    # row AND carry no real open item. RFC comment staging is EXCLUDED from this approval
    # discovery (analysis/review/RFC.review.md has no Sign-off gate of its own — pulled
    # comments are informational staging, never a unit a human approves); its unresolved
    # items still block breakdown through the dedicated open-item check below.
    if [ -d "$D/analysis/review" ]; then
      for review_file in "$D/analysis/review"/*.review.md; do
        [ -f "$review_file" ] || continue
        _rb="$(basename "$review_file")"
        [ "$_rb" = "RFC.review.md" ] && continue
        _grc=0
        _gate_review_approved "analysis/review/$_rb" || _grc=$?
        case "$_grc" in
          10) die_fix "analysis review $_rb has unresolved items — its approval no longer stands" "resolve them (/pw-review $SLUG), then have the Sign-off row re-approved" ;;
          11) die_fix "analysis review gate not approved for $_rb" "approve it (## Sign-off row with 'approved') or run /pw-review $SLUG" ;;
        esac
      done
    fi

    # Check known RFC comments even if metadata is missing after a partial import. It
    # needs no approval, but an unresolved pulled comment still blocks breakdown.
    if [ -f "$D/analysis/review/RFC.review.md" ]; then
      if "$HERE/pw-review-read.sh" has-open "$SLUG" "analysis/review/RFC.review.md" 2>/dev/null; then
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
      die_fix "no shippable tasks (PLAN task table shows no Status 'done')$([ -n "$NOTDONE" ] && printf ' — not yet done:%s' "$NOTDONE")" "complete the tasks (/pw-execute $SLUG) — 'done' means executed+verified; a pushed-comment sweep uses /pw-ship $SLUG comments instead"
    fi

    # Stacked tasks (plan 35): the topology must be valid, every stacked shippable task must be
    # freshness-clean, and its parent target must exist before publishing. No-op for legacy
    # independent projects (no `Stacked on:` edges).
    STACKROWS="$("$HERE/pw-ship.sh" stack "$SLUG" 2>/dev/null | awk -F'|' 'NR>1 && $1 ~ /^T[0-9]/ {n++} END{print n+0}')"
    if [ "${STACKROWS:-0}" -gt 0 ]; then
      "$HERE/pw-ship.sh" stack-validate "$SLUG" >/dev/null 2>&1 \
        || die_fix "stack topology is invalid" "/pw-ship $SLUG stack previews it, then fix the named 'Stacked on:' / depends_on fields (a stack needs a known same-repo parent in depends_on, one ultimate destination, and distinct branches)"
      STALE_STACK="$("$HERE/pw-ship.sh" stack "$SLUG" 2>/dev/null | awk -F'|' 'NR>1 && $7=="stale" {print $1}' | tr '\n' ' ')"
      [ -z "$STALE_STACK" ] \
        || die_fix "stack task(s) carry stale verification:$STALE_STACK" "re-verify each (merge its updated parent, run '## Verify', push) — a fresh green result cannot reuse an older parent/target tuple; then /pw-ship $SLUG <T0n>"
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

    # A half-finished stack cascade must be resumed, never restarted — its pending-operation rows
    # gate the sweep so a resumed run cannot duplicate pushes, replies, or inherited updates.
    [ -f "$D/task/stack-ops.tsv" ] && ! "$HERE/pw-ship.sh" stack-debt "$SLUG" >/dev/null 2>&1 \
      && die_fix "pending stack operation(s) block a new comment sweep" "/pw-ship $SLUG stack shows the debt; resume it (the recorded stages) before starting a new pass — never replay a cascade from the top"
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
      die_fix "not all tasks are accepted:$UNACCEPTED" "acceptance is a human decision — tell your agent to \"accept $SLUG <T0n>\" (one step records the task file + PLAN row + dashboard), then re-run /pw-close"
    fi

    # Close rejects unresolved stack debt: stale verification or a pending promotion/cascade
    # operation means children are still owed an update (plan 35). Accepted open MRs may remain
    # open — this guard is about the stack record, not about merging.
    STALE_CLOSE="$("$HERE/pw-ship.sh" stack "$SLUG" 2>/dev/null | awk -F'|' 'NR>1 && $7=="stale" {print $1}' | tr '\n' ' ')"
    [ -z "$STALE_CLOSE" ] \
      || die_fix "stack task(s) still carry freshness debt:$STALE_CLOSE" "/pw-sync $SLUG <T0n> (merge the updated parent, re-verify, push) clears the debt before close"
    [ -f "$D/task/stack-ops.tsv" ] && ! "$HERE/pw-ship.sh" stack-debt "$SLUG" >/dev/null 2>&1 \
      && die_fix "unresolved stack operation(s) at close" "/pw-ship $SLUG stack shows the pending stages; finish or record the recovery outcome before close (do not delete stack branches/recovery refs automatically)"
    ;;

  review)
    PHASE_FILTER="${1:-}"

    # Check review files exist. The filter is a REVIEW LANE word — the /pw-review scope
    # set (analysis|plan|task-plan|task-exec|ship), NOT a dashboard phase: task-plan and
    # task-exec review the per-task artifacts through task/review/T0n.review.md, and the
    # ship lane reviews the same mirrored task review files the MR comments fold back
    # into. An unknown lane word fails closed instead of silently skipping the check.
    if [ -n "$PHASE_FILTER" ]; then
      case "$PHASE_FILTER" in
        analysis)
          if [ ! -d "$D/analysis/review" ] || [ -z "$(ls -A "$D/analysis/review"/*.review.md 2>/dev/null)" ]; then
            die_fix "no analysis review files found" "run /pw-review $SLUG (analysis phase) to create them"
          fi
          ;;
        plan)
          if [ ! -f "$D/task/review/PLAN.review.md" ]; then
            die_fix "PLAN review file missing" "run /pw-breakdown $SLUG then /pw-review $SLUG (plan)"
          fi
          ;;
        task-plan|task-exec|ship)
          _lane_fix="run /pw-review $SLUG (task-exec phase) for the shipped tasks"
          case "$PHASE_FILTER" in
            task-plan) _lane_fix="review the task plans through their own files: /pw-review $SLUG task-plan (creates task/review/T0n.review.md per task)" ;;
            ship) _lane_fix="ship-lane reviews are the same task/review/T0n.review.md files MR comments mirror back into — push first (/pw-ship $SLUG), then /pw-ship $SLUG comments and /pw-review $SLUG" ;;
          esac
          if [ ! -d "$D/task/review" ] || [ -z "$(ls -A "$D/task/review"/T*.review.md 2>/dev/null)" ]; then
            die_fix "no task review files found" "$_lane_fix"
          fi
          ;;
        *)
          die_fix "unknown review phase-word '$PHASE_FILTER'" "expected one of: analysis|plan|task-plan|task-exec|ship (the /pw-review <slug> scope lanes — see /pw-help project $SLUG pw-review)"
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
    die "unknown command: $COMMAND (expected: analyze|prepare|execute|breakdown|ship|comments|close|review)"
    ;;
esac

exit 0
