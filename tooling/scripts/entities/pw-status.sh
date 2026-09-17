#!/usr/bin/env bash
# ============================================================================
# pw-status.sh — deterministic project status report (replaces /pw-status agent)
#
#   pw-status.sh <slug>                  full status report
#   pw-status.sh <slug> --skip-cli-check skip CLI auth status check
#   pw-status.sh --selftest              run isolated self-test
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

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"

die() { echo "pw-status: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

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
  export PW_PROJECTS_DIR="$TMPDIR"   # child pw-lib.sh calls resolve projects from the env
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
PHASE_RAW="$("$HERE/../../pw-lib.sh" phase "$SLUG")"
PHASE="$(pw_phase_token "${PHASE_RAW:-missing}")"
echo "## Phase: $PHASE"
if [ "${PHASE_RAW:-}" != "$PHASE" ] && [ -n "${PHASE_RAW:-}" ]; then
  printf '  ⚠ README phase line has prose around the token:\n    %s — repair with: pw-lib.sh status <slug> %s\n' "$PHASE_RAW" "$PHASE"
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
# Real review files only, counted through pw-lib's heading-level detector (the same one the
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
"$HERE/../../pw-lib.sh" ai-review "$SLUG"
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
