#!/usr/bin/env bash
# ============================================================================
# pw-status.sh — deterministic project status report (replaces /pw-status agent)
#
#   pw-status.sh <slug>                  full status report
#   pw-status.sh <slug> --skip-cli-check skip CLI auth status check
#   pw-status.sh --selftest              run isolated self-test
#
#   Project-state setters (the dashboard/LOG.md entity; merged from pw-lib, plan 20):
#   log <slug> <actor> <msg...> · status <slug> <phase> [--rewind] · oneliner <slug> <text...>
#   adopted <slug> <text...> · phase <slug> · dashboard-task-status <slug> <task-id> <status>
#   task-accept <slug> <task-id>
#
#   provider-audit <slug> [task-ids…]
#       REPORT-ONLY consistency audit of `Execute with:` rows vs. what actually ran:
#       per task prints T0n|expected=…|used=…|via=…|route=…|verdict=ok|mismatch|stale-provider|unbound|never-run.
#       "expected" is validated against the live catalog via pw-config.sh model-resolve, so a
#       row pinning a removed provider/api-provider reads stale-provider (the migration case)
#       and a row whose model simply does not exist reads unbound. Exit 0 iff no
#       mismatch/stale-provider/unbound. Mutates nothing (no LOG line — this is a reader).
#
# Produces the same output as /pw-status today, with zero agent invocation.
# Reads README.md, PLAN.md, greps for open items, shows LOG.md lines, reports
# blockers, and checks CLI auth status (informational, non-blocking).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-status: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }


# --- project-state entity (merged from pw-lib, plan 20 Phase 4) ---------------
# Phase rank for the monotonic guard. executing and review share a rank on purpose:
# re-running a task flips executing→review→executing repeatedly — normal, not a rewind.
phase_rank() {
  case "$1" in
    context)   echo 0 ;; analysis) echo 1 ;; breakdown) echo 2 ;;
    executing) echo 3 ;; review)   echo 3 ;; done)      echo 4 ;;
    *) echo -1 ;;
  esac
}

# Operator words are reserved: setters are invoked as `pw-status.sh <operator> <slug> …`;
# a leading arg that is not an operator keeps the report behavior (C1).
# Append one LOG.md entry as a Markdown bullet — `- **<date>** · \`<actor>\` — <message>` — instead
# of a bare pipe-delimited line. A pipe row with no table header just renders as one long,
# hard-to-scan paragraph in a plain markdown preview; a bullet list wraps sanely per entry, bolds
# the timestamp, and tags the actor as inline code, so a growing LOG.md stays skimmable.
#
# Duplicate-guard: a real project's LOG.md was observed with the identical actor+message logged
# twice (once even three times) back-to-back within minutes — a caller re-running its own trailing
# log step, not a deliberate second entry. Dedup key: exact actor+message match against LOG.md's
# LAST line only (not a scan of history — a repeat several entries back is a different, real
# event, not this bug), within PW_LOG_DEDUP_WINDOW_MIN minutes (default 5) of that line's own
# timestamp. On a match: warn to stderr and return 0 WITHOUT appending — never `die`, since
# cmd_log runs as a trailing step inside many other commands and must not abort the caller's real
# work over an audit-trail nicety. A parse failure on the last line (unexpected format, clock
# skew) fails OPEN — always logs — rather than risk silently dropping a genuinely new entry.
cmd_log() {
  [ $# -ge 3 ] || die "usage: log <slug> <actor> <msg...>"
  local slug="$1" actor="$2"; shift 2
  local msg="$*"
  local d; d="$(proj_dir "$slug")"
  local f="$d/LOG.md"
  local window="${PW_LOG_DEDUP_WINDOW_MIN:-5}"
  if [ -f "$f" ] && [ -s "$f" ]; then
    local last; last="$(tail -n 1 "$f")"
    local ltag; ltag="$(printf '%s' "$last" | sed -n 's/^- \*\*\([^*]*\)\*\* · .*/\1/p')"
    local ltail; ltail="$(printf '%s' "$last" | sed 's/^- \*\*[^*]*\*\* · //')"
    local newtail; newtail="$(printf -- '`%s` — %s' "$actor" "$msg")"
    if [ -n "$ltag" ] && [ "$ltail" = "$newtail" ]; then
      local now_epoch last_epoch
      now_epoch="$(date '+%s')"
      last_epoch="$(date -j -f '%Y-%m-%d %H:%M' "$ltag" '+%s' 2>/dev/null || date -d "$ltag" '+%s' 2>/dev/null || echo '')"
      if [ -n "$last_epoch" ]; then
        local diff_min=$(( (now_epoch - last_epoch) / 60 ))
        if [ "$diff_min" -ge 0 ] && [ "$diff_min" -lt "$window" ]; then
          echo "pw-status: skipped duplicate log entry for $slug (same actor+message ${diff_min}m ago, within ${window}m window)" >&2
          return 0
        fi
      fi
    fi
  fi
  printf -- '- **%s** · `%s` — %s\n' "$(date '+%F %H:%M')" "$actor" "$msg" >> "$f"
}

cmd_status() {
  local rewind=0 args=()
  for a in "$@"; do case "$a" in --rewind) rewind=1 ;; *) args+=("$a") ;; esac; done
  set -- "${args[@]}"
  [ $# -eq 2 ] || die "usage: status <slug> <phase> [--rewind]   (phase: $PW_VALID_PHASES)"
  local slug="$1" phase="$2"
  case " $PW_VALID_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $PW_VALID_PHASES)";; esac
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  grep -q '^- \*\*Status:\*\*' "$f" || die "no '- **Status:**' line in $f"
  # Monotonic guard: refuse an accidental backward move (e.g. a stray reset to 'context' after
  # analysis) unless the caller explicitly rewinds. This is the deterministic fix for phases
  # silently sliding backward when a command mis-fires.
  local cur; cur="$(cmd_phase "$slug")"
  local cr tr; cr="$(phase_rank "$cur")"; tr="$(phase_rank "$phase")"
  if [ "$rewind" -eq 0 ] && [ "$tr" -ge 0 ] && [ "$cr" -ge 0 ] && [ "$tr" -lt "$cr" ]; then
    die "refusing to move Status backward: $cur → $phase. If you really mean to rewind a phase, pass --rewind."
  fi
  awk -v p="$phase" '!d && /^- \*\*Status:\*\*/ {print "- **Status:** " p; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" status "Status -> $phase$([ "$rewind" -eq 1 ] && echo ' (rewind)')"
  echo "$slug: Status -> $phase"
}

cmd_oneliner() {
  [ $# -ge 2 ] || die "usage: oneliner <slug> <text...>"
  local slug="$1"; shift; local text="$*"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line in $f"
  awk -v t="$text" '!d && /^- \*\*One-liner:\*\*/ {print "- **One-liner:** " t; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" analyze "One-liner set"
  echo "$slug: One-liner set"
}

# Set/insert the dashboard "Adopted:" pointer. Adoption is optional, so a fresh project has no
# Adopted line — insert one right after the One-liner if absent, else replace its text. Idempotent,
# so /pw-adopt can call it after adding each unit (the caller passes the current count/pointer text).
cmd_adopted() {
  [ $# -ge 2 ] || die "usage: adopted <slug> <text...>"
  local slug="$1"; shift; local text="$*"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  if grep -q '^- \*\*Adopted:\*\*' "$f"; then
    awk -v t="$text" '!d && /^- \*\*Adopted:\*\*/ {print "- **Adopted:** " t; d=1; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor Adopted: after in $f"
    awk -v t="$text" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **Adopted:** " t; d=1}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  cmd_log "$slug" adopt "Adopted pointer set: $text"
  echo "$slug: Adopted -> $text"
}

cmd_phase() {
  [ $# -eq 1 ] || die "usage: phase <slug>"
  local f; f="$(proj_dir "$1")/README.md"
  [ -f "$f" ] || die "no README.md in project $1"
  grep -m1 '^- \*\*Status:\*\*' "$f" | sed 's/^- \*\*Status:\*\*[[:space:]]*//'
}


# Update a task's Status field to "accepted" (used when MR is already merged).
#   task-accept <slug> <task-id>
cmd_task_accept() {
  [ $# -eq 2 ] || die "usage: task-accept <slug> <task-id>"
  local slug="$1" task="$2"
  local d; d="$(proj_dir "$slug")"
  local taskfile="$d/task/$task.md"
  [ -f "$taskfile" ] || die "no task file: task/$task.md"
  
  # Update Status: line in task file
  if grep -q '^- \*\*Status:\*\*' "$taskfile"; then
    sed -i '' -E 's/^- \*\*Status:\*\*.*$/- **Status:** accepted/' "$taskfile"
  else
    # Insert after first line if no Status line exists
    sed -i '' '1a\
- **Status:** accepted
' "$taskfile"
  fi
  
  cmd_log "$slug" sync "$task: MR already merged, marked as accepted"
  echo "$slug: $task marked as accepted (MR already merged)"
}

# Update a task's status in the dashboard README.md task status table.
#   dashboard-task-status <slug> <task-id> <status>
cmd_dashboard_task_status() {
  [ $# -eq 3 ] || die "usage: dashboard-task-status <slug> <task-id> <status>"
  local slug="$1" task="$2" status="$3"
  local d; d="$(proj_dir "$slug")"
  local readme="$d/README.md"
  [ -f "$readme" ] || die "no README.md in project $slug"

  _dashboard_update "$readme" 'ID' 'Status' "$task" "$status" \
    || die "dashboard-task-status: could not update $task in the Task status table (see above)"
  cmd_log "$slug" sync "dashboard: $task status -> $status"
}


# --- provider-audit (report-only; plan-22 §3.2) -----------------------------------------
# PLAN row reader: "T0n|Execute-with" pairs, column-NAME driven (same _pw_plan_map spec as
# pw_plan_execs — both PLAN generations, never positional).
_pw_audit_rows() {
  local spec idi sti bei
  spec="$(_pw_plan_map "$1")"
  idi="${spec%% *}"; rest="${spec#* }"; sti="${rest%% *}"; bei="${rest##* }"
  [ "${idi:-0}" -gt 0 ] 2>/dev/null || return 0
  [ "${bei:-0}" -gt 0 ] 2>/dev/null || return 0
  awk -F'|' -v idi="$idi" -v bei="$bei" '
    /^## Task/ { p=1; next }
    p && /^## / { exit }
    p && /^[ \t]*\|/ && !($0 ~ /^[ \t]*\|[ \t:|+-]*\|[ \t]*$/) {
      split($0, c, "|")
      id = c[idi + 0]; gsub(/[ \t`\*]/, "", id)
      if (match(id, /T[0-9]+/)) { id = substr(id, RSTART, RLENGTH) } else { id = "" }
      v = c[bei + 0]; gsub(/^[ \t]+/, "", v); gsub(/[ \t]+$/, "", v)
      if (id ~ /^T[0-9]+/) print id "|" v
    }' "$1"
}

cmd_provider_audit() {
  [ $# -ge 1 ] || die "usage: provider-audit <slug> [task-ids…]   (report-only; exit 0 iff every row is ok/never-run)"
  local slug="$1"; shift
  local d; d="$(proj_dir "$slug")"
  local plan="$d/task/PLAN.md"
  [ -f "$plan" ] || die "no task/PLAN.md in $slug → fix: run /pw-breakdown $slug first"
  local logf="$d/LOG.md"
  local ids="$*"
  local bad=0 rc id exec prov model route expected used via verdict mr_err lline au _seen _p
  while IFS='|' read -r id exec; do
    [ -n "$id" ] || continue
    if [ -n "$ids" ]; then
      case " $ids " in *" $id "*) ;; *) continue ;; esac
    fi
    exec="$(printf '%s' "$exec" | pw_trim)"
    [ -n "$exec" ] && [ "$exec" != "—" ] || continue
    # provider = text before the first ':' (rows without a ':' bind no agent-provider)
    case "$exec" in
      *:*) prov="${exec%%:*}"; model="${exec#*:}" ;;
      *)   prov=""; model="$exec" ;;
    esac
    expected="$exec"
    route="—"
    if [ -f "$d/task/$id.md" ]; then
      au="$(pw_field "$d/task/$id.md" Route || true)"
      [ -n "${au:-}" ] && route="$au"
    fi
    # availability: model-resolve is the shared oracle (exit 1 = not in catalog → unbound;
    # exit 2 = out of configured api-provider scope → stale-provider; it fails open on
    # "can't check", so a non-zero here is a positive determination).
    verdict="ok"
    if [ -n "$prov" ]; then
      rc=0
      mr_err="$("$HERE/pw-config.sh" model-resolve "$prov" "$model" 2>&1 >/dev/null)" || rc=$?
      case "$rc" in
        1) verdict="unbound" ;;
        2) verdict="stale-provider" ;;
      esac
      # provider itself gone from the enabled set (the migration case)
      if [ "$verdict" = "ok" ]; then
        _seen=0
        for _p in "${PW_PROVIDERS[@]}"; do [ "$_p" = "$prov" ] && _seen=1; done
        [ "$_seen" = 1 ] || verdict="stale-provider"
      fi
    fi
    # what actually ran: newest ledger line for this task, else the task's Actually used:
    used="never-run"; via="—"
    if [ -f "$logf" ]; then
      lline="$(grep -E "spawned $id( |\()" "$logf" 2>/dev/null | tail -1 || true)"
      if [ -n "$lline" ]; then
        used="$(printf '%s' "$lline" | sed -nE 's/.*spawned [^ ]+ \(([^)]*)\).*/\1/p')"
        [ -n "$used" ] || used="unknown"
        via="$(printf '%s' "$lline" | sed -nE 's/.*via=([a-z]+).*/\1/p')"
        via="${via:-—}"
        # a recorded degrade is policy-blessed; anything else that differs is a mismatch
        if [ "$verdict" = "ok" ] && [ "$used" != "$exec" ]; then
          printf '%s' "$lline" | grep -q 'model-degraded' || verdict="mismatch"
        fi
      fi
    fi
    if [ "$used" = "never-run" ] && [ -f "$d/task/$id.md" ]; then
      au="$(pw_field "$d/task/$id.md" "Actually used" || true)"
      case "${au:-}" in ""|"—"|"<*") ;; *) used="$au" ;; esac
    fi
    [ "$verdict" = "ok" ] || bad=1
    printf '%s|expected=%s|used=%s|via=%s|route=%s|verdict=%s\n' "$id" "$expected" "$used" "$via" "$route" "$verdict"
  done <<EOF
$(_pw_audit_rows "$plan")
EOF
  [ "$bad" = 0 ]
}

case "${1:-}" in
  log)                   shift; cmd_log "$@"; exit $? ;;
  status)                shift; cmd_status "$@"; exit $? ;;
  oneliner)              shift; cmd_oneliner "$@"; exit $? ;;
  adopted)               shift; cmd_adopted "$@"; exit $? ;;
  phase)                 shift; cmd_phase "$@"; exit $? ;;
  dashboard-task-status) shift; cmd_dashboard_task_status "$@"; exit $? ;;
  task-accept)           shift; cmd_task_accept "$@"; exit $? ;;
  provider-audit)        shift; cmd_provider_audit "$@"; exit $? ;;
esac

SKIP_CLI_CHECK=0
SELFTEST=0
SLUG=""

for arg in "$@"; do
  case "$arg" in
    --skip-cli-check) SKIP_CLI_CHECK=1 ;;
    --selftest) SELFTEST=1 ;;
    -h|--help) pw_usage ;;
    -*) die "unknown option: $arg (try --help)" ;;
    *) SLUG="$arg" ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  echo "pw-status selftest: creating temp project..."
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT
  PROJECTS_DIR="$TMPDIR"
  export PW_PROJECTS_DIR="$TMPDIR"   # child calls resolve projects from the env
  SLUG="test-project"
  mkdir -p "$TMPDIR/$SLUG/context" "$TMPDIR/$SLUG/analysis/review" "$TMPDIR/$SLUG/task/review"
  cat > "$TMPDIR/$SLUG/README.md" <<'EOF'
# test-project

- **Status:** executing
- **One-liner:** Test project for selftest
- **AI Review:** analysis=off plan=off task-plan=off task-exec=off ship=off
- **AI Models:** researcher=— analyst=— writer-task=— reviewer=— verifier=—

## Task status

| Task | Repo | Branch | Status |
|------|------|--------|--------|
| T01 | api-service | agent/test-project/T01-test | done |
| T02 | worker-service | agent/test-project/T02-test | in-progress |

## Merge requests

| Task | MR | State |
|------|----|-------|
| T01 | !123 | open |
EOF
  cat > "$TMPDIR/$SLUG/task/PLAN.md" <<'EOF'
# PLAN — test-project

## Task table

| Task | Repo | Branch | SP | Execute with | Depends on | Status |
|------|------|--------|----|--------------|------------|--------|
| T01 | api-service | agent/test-project/T01-test | 5 | kilo:default | — | done |
| T02 | worker-service | agent/test-project/T02-test | 3 | kilo:default | T01 | in-progress |
EOF
  cat > "$TMPDIR/$SLUG/LOG.md" <<'EOF'
# Activity log — test-project

- **2026-09-10 09:00** · `scaffold` — project created
- **2026-09-10 09:05** · `status` — Status -> executing
EOF
  echo "pw-status selftest: running status report..."
  SKIP_CLI_CHECK=1
fi

[ -n "$SLUG" ] || die "usage: pw-status.sh <slug> [--skip-cli-check] [--selftest]"

D="$(proj_dir "$SLUG")"
README="$D/README.md"
PLAN="$D/task/PLAN.md"
LOG="$D/LOG.md"

[ -f "$README" ] || die "no README.md in project $SLUG"

# Current phase — canonical token only (C19): a drifted README `- **Status:**` line must
# never print as prose as if it were a phase name here.
PHASE_RAW="$(cmd_phase "$SLUG")"
PHASE="$(pw_phase_token "${PHASE_RAW:-missing}")"
echo "## Phase: $PHASE"
if [ "${PHASE_RAW:-}" != "$PHASE" ] && [ -n "${PHASE_RAW:-}" ]; then
  printf '  ⚠ README phase line has prose around the token:\n    %s — repair with: pw-status.sh status <slug> %s\n' "$PHASE_RAW" "$PHASE"
fi
echo

# Task status table from README
echo "## Tasks"
if grep -qE '^## Task( |s)' "$README"; then
  awk '/^## Task( |s)/{p=1; print; next} /^## /{p=0} p' "$README"
else
  echo "(no task table in README.md)"
fi
echo

# PLAN task table with SP/Time/Result
if [ -f "$PLAN" ]; then
  echo "## PLAN"
  if grep -qE '^## Task( |s)' "$PLAN"; then
    awk '/^## Task( |s)/{p=1; print; next} /^## /{p=0} p' "$PLAN"
  else
    echo "(no task table in PLAN.md)"
  fi
  echo
fi

# Unresolved review items
echo "## Unresolved review items"
# Real review files only, counted through the shared heading-level detector (the same one the
# gates use) — never raw greps: a whole-project grep for "pw-item-status: open" lands on the
# template guidance line present in every review file and reports phantoms. Archive files
# (.archive.md) are closed history and are skipped; _REVIEW.template.md is not a review.
OPEN_ITEMS=""
for rf in "$D"/analysis/review/*.review.md "$D"/task/review/*.review.md; do
  [ -f "$rf" ] || continue
  _c="$("$HERE/pw-review.sh" count "$SLUG" "${rf#$D/}" 2>/dev/null || true)"
  _n="$(printf '%s' "$_c" | sed -n 's/open=\([0-9]*\).*/\1/p')"; _n="${_n:-0}"
  [ "$_n" -gt 0 ] && OPEN_ITEMS="$OPEN_ITEMS${rf#$D/}|$_n
"
done
if [ -n "$OPEN_ITEMS" ]; then
  printf '%s' "$OPEN_ITEMS" | while IFS='|' read -r _rel _n; do [ -n "$_rel" ] && echo "  - $_rel ($_n open)"; done
else
  echo "  (none)"
fi
echo

# AI Review modes
echo "## AI Review modes"
"$HERE/pw-config.sh" ai-review "$SLUG"
echo

# Last N LOG.md lines
echo "## Recent activity"
if [ -f "$LOG" ] && [ -s "$LOG" ]; then
  tail -n 5 "$LOG" | grep '^-' || echo "  (no log entries)"
else
  echo "  (no LOG.md)"
fi
echo

# Blocker assessment
echo "## Blockers"
BLOCKERS=()

# Check for unapproved analysis
if [ "$PHASE" = "analysis" ] || [ "$PHASE" = "breakdown" ] || [ "$PHASE" = "executing" ]; then
  ANALYSIS_REVIEW="$D/analysis/review"
  if [ -d "$ANALYSIS_REVIEW" ]; then
    UNAPPROVED="$(find "$ANALYSIS_REVIEW" -name '*.review.md' -exec grep -L 'approved' {} \; 2>/dev/null || true)"
    if [ -n "$UNAPPROVED" ]; then
      BLOCKERS+=("Unapproved analysis review files")
    fi
  fi
fi

# Check for unapproved PLAN
if [ "$PHASE" = "breakdown" ] || [ "$PHASE" = "executing" ]; then
  if [ -f "$D/task/review/PLAN.review.md" ]; then
    if ! grep -q 'approved' "$D/task/review/PLAN.review.md"; then
      BLOCKERS+=("Unapproved PLAN review")
    fi
  fi
fi

# Check for open reviews
if [ -n "$OPEN_ITEMS" ]; then
  BLOCKERS+=("Open review items (see above)")
fi

# Check for verify-failed tasks
if [ -f "$PLAN" ]; then
  VERIFY_FAILED="$(grep -E '\|.*verify-failed.*\|' "$PLAN" || true)"
  if [ -n "$VERIFY_FAILED" ]; then
    BLOCKERS+=("Verify-failed tasks in PLAN")
  fi
fi

if [ ${#BLOCKERS[@]} -eq 0 ]; then
  echo "  (none)"
else
  for b in "${BLOCKERS[@]}"; do
    echo "  - $b"
  done
fi
echo

# Next actionable command
echo "## Next action"
case "$PHASE" in
  context)
    echo "  Run /pw-analyze to start analysis"
    ;;
  analysis)
    if [ -n "$OPEN_ITEMS" ]; then
      echo "  Run /pw-review to address open review items"
    else
      echo "  Run /pw-breakdown to create PLAN"
    fi
    ;;
  breakdown)
    if [ -f "$D/task/review/PLAN.review.md" ] && ! grep -q 'approved' "$D/task/review/PLAN.review.md"; then
      echo "  Get PLAN approved via /pw-review"
    else
      echo "  Run /pw-execute to start execution"
    fi
    ;;
  executing)
    echo "  Run /pw-execute to continue execution, or /pw-ship when ready"
    ;;
  review)
    echo "  Run /pw-ship to ship completed tasks"
    ;;
  done)
    echo "  Run /pw-close to close the project"
    ;;
  *)
    echo "  Unknown phase: $PHASE"
    ;;
esac

# CLI auth status check (informational, non-blocking)
if [ "$SKIP_CLI_CHECK" -eq 0 ]; then
  echo
  echo "## CLI auth status"
  
  # Run checks in parallel
  CLI_RESULTS=()
  
  # Check gh
  if command -v gh >/dev/null 2>&1; then
    if timeout 5 gh auth status >/dev/null 2>&1; then
      CLI_RESULTS+=("✓ gh authenticated")
    else
      CLI_RESULTS+=("✗ gh not authenticated — run \`gh auth login\`")
    fi
  else
    CLI_RESULTS+=("– gh not installed")
  fi
  
  # Check glab
  if command -v glab >/dev/null 2>&1; then
    if timeout 5 glab auth status >/dev/null 2>&1; then
      CLI_RESULTS+=("✓ glab authenticated")
    else
      CLI_RESULTS+=("✗ glab not authenticated — run \`glab auth login\`")
    fi
  else
    CLI_RESULTS+=("– glab not installed")
  fi
  
  # Check jira
  if command -v jira >/dev/null 2>&1; then
    if timeout 5 jira issue list --limit 1 >/dev/null 2>&1; then
      CLI_RESULTS+=("✓ jira authenticated")
    else
      CLI_RESULTS+=("✗ jira not authenticated — run \`jira login\`")
    fi
  else
    CLI_RESULTS+=("– jira not installed")
  fi
  
  # Check lark-cli
  if command -v lark-cli >/dev/null 2>&1; then
    if timeout 5 lark-cli doctor >/dev/null 2>&1; then
      CLI_RESULTS+=("✓ lark-cli authenticated")
    else
      CLI_RESULTS+=("✗ lark-cli not authenticated — run \`lark-cli auth login\`")
    fi
  else
    CLI_RESULTS+=("– lark-cli not installed")
  fi
  
  for result in "${CLI_RESULTS[@]}"; do
    echo "  $result"
  done
fi

if [ "$SELFTEST" -eq 1 ]; then
  echo
  echo "pw-status selftest: ✓ passed"
fi
