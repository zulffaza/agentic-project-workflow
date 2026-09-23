#!/usr/bin/env bash
# ============================================================================
# pw-ship.sh — the ship/MR entity: everything /pw-ship and /pw-sync query or mutate.
#
#   pw-ship.sh resolve            <slug>
#   pw-ship.sh exec               <slug> <task-id> <description-file>
#   pw-ship.sh monitor            <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]
#   pw-ship.sh mr-state           <slug> <task-id>
#   pw-ship.sh mr-state-batch     <slug> [task-ids...]
#   pw-ship.sh comment-seen       <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]
#   pw-ship.sh dashboard-mr-state <slug> <task-id> <state>
#
# Facets (S1b): READ  = resolve, mr-state, mr-state-batch, monitor
#               WRITE = exec, comment-seen, dashboard-mr-state
# Merged from pw-ship-resolve.sh, pw-ship-exec.sh, pw-mr-state-batch.sh,
# pw-pipeline-monitor.sh and pw-lib's ship/mr-state block (entity consolidation;
# operator names and output contracts unchanged).
#
# resolve — pre-compute the shippable task set. Before /pw-ship invokes an agent,
#   resolves the exact set of shippable tasks: reads task statuses, checks for real
#   commits, checks for existing MRs, resolves tickets from the task file.
#   Output (one line per shippable task):
#     T01|repo|branch|base|ticket|title|has-commit|has-mr
# exec — mechanical ship execution after the agent confirmed the push list and
#   generated the MR description file: git push origin <branch>, glab/gh MR create
#   with structured args, task-file Result MR upsert, dashboard open-state. Loud
#   non-zero when the push succeeded but the forge returned no URL.
# monitor — poll the MR pipeline until terminal state. Exit 0 success, 1 failed,
#   2 timeout; records "Build check:" into the task Result (never the dashboard —
#   CI green ≠ merged).
# mr-state — query the forge for one task's MR state: prints open|merged|closed|
#   unknown (exit 1 + "unknown" for any lookup failure — never dies on runtime
#   misses, only usage errors).
# mr-state-batch — mr-state for many tasks (all PLAN tasks when no ids given).
#   Output: T01|open  T02|merged  T03|closed  T04|unknown
# comment-seen — upsert ONE row per MR-comment thread into the task review file's
#   "## MR comment tracking" table (keyed hidden marker; idempotent reruns; the
#   local authority for unresolvable threads the forge can never report resolved).
# dashboard-mr-state — set one task's State cell in the dashboard MR table.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
ST="$HERE/pw-status.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-ship: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

# ================= READ facet =================================================

cmd_resolve() {
  [ $# -eq 1 ] || die "usage: resolve <slug>"

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
}

# --- MR state detection (for /pw-sync and /pw-ship comments) -----------------
# Check an MR's current state via the forge CLI. Prints one of "open", "merged", "closed", or
# "unknown" to stdout; exit 0 for the three definitive states, exit 1 + "unknown" for anything it
# can't determine (no MR URL/worktree/origin, or the forge query failed or returned null). Callers
# treat stdout "unknown" as mr-state-unknown and skip — this helper never die()s on a runtime
# lookup failure, only on a usage error. Resolves the forge per repo (same as /pw-ship does) —
# never hardcodes a host.
#   mr-state <slug> <task-id>
# MR URL is taken from the task's "## Result → MR:" line if present, else from the dashboard
# Merge-requests table (Task · MR · Target rows). Requires an existing worktree for the task so
# the forge CLI can be run from inside the repo (glab needs repo context to resolve :id).
# Emit an mr-state lookup failure: diagnostic to stderr, "unknown" to stdout, exit 1. set -e-safe:
# always invoke as `_mr_unknown "…" || return 1` so the failing call sits in an OR-list.
# Resolve the task file's MR URL scoped to `## Result`: the `- **MR:**` / `- MR:` field line first
# (its URL — else its trimmed sentinel value like `(none)`), then the first bare http(s) URL in
# the Result block, else empty (caller falls back to the dashboard table). Section-scoping is the
# point: a whole-file `grep 'https://' | head -1` lets decoy literal URLs in ## Steps beat the real
# field — seen 2026-09, where a stencil placeholder URL left mr-state "found-but-unparseable" and
# the task unknown forever despite a correct `- **MR:**` line. Mirror of pw_task_mr_url in
# pw-common.sh (kept as a private copy so the source stays extractable for the C21 catcher) —
# update both together.
_resolve_task_mr_url() {
  local sec line val url
  [ -f "$1" ] || return 0
  sec="$(awk '/^## Result/{p=1; next} /^## /{p=0} p' "$1" 2>/dev/null)" || return 0
  [ -n "$sec" ] || return 0
  line="$(printf '%s\n' "$sec" | grep -m1 -E '^[[:space:]]*([-*][[:space:]]*)?\*{0,2}MR\*{0,2}[[:space:]]*:' || true)"
  if [ -n "$line" ]; then
    val="$(printf '%s' "$line" | sed -E \
      -e 's/^[[:space:]]*([-*][[:space:]]*)?\*{0,2}MR\*{0,2}[[:space:]]*:[[:space:]]*//' \
      -e 's/^[*_[:space:]]+//' -e 's/[[:space:]]+\*\*.*$//' -e 's/[[:space:]]+$//')"
    if [ -n "$val" ]; then
      url="$(printf '%s' "$val" | grep -oE "https?://[^ )>|\"\`]+" | head -1 || true)"
      [ -n "$url" ] && { printf '%s' "$url"; return 0; }
      printf '%s' "$val"; return 0
    fi
  fi
  printf '%s\n' "$sec" | grep -oE "https?://[^ )>|\"\`]+" | head -1 || true
}

_mr_unknown() {
  echo "mr-state: $*" >&2
  echo "unknown"
  return 1
}

_mr_state_impl() {
  local slug="$1" task="$2"
  local d; d="$(proj_dir "$slug")"
  local taskfile="$d/task/$task.md"

  # MR URL: task file "## Result" block first (field "MR:" or a bare URL), else dashboard table row.
  # Result-scoping — see _resolve_task_mr_url. The dashboard pattern takes the URL from ANY column of
  # the row (`| T02 | repo | [MR 18](url) |` markdown-link cell included); the old one demanded the
  # URL immediately after the task cell and silently never matched real rows.
  local mr_url=""
  mr_url="$(_resolve_task_mr_url "$taskfile")"
  if [ -z "$mr_url" ]; then
    mr_url="$(grep -E "^\|[[:space:]]*\**$task\**[[:space:]]*\|" "$d/README.md" 2>/dev/null \
              | grep -oE "https?://[^ )>|\"\`]+" | head -1 || true)"
  fi
  [ -n "$mr_url" ] || _mr_unknown "no MR URL found for $task (task file or dashboard table)" || return 1

  # Extract MR IID/number from URL (GitLab /-/merge_requests/<n> or GitHub /pull/<n>)
  local mr_iid
  mr_iid="$(printf '%s' "$mr_url" | grep -oE '/-/merge_requests/[0-9]+' | grep -oE '[0-9]+$' || true)"
  [ -z "$mr_iid" ] && mr_iid="$(printf '%s' "$mr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+$' || true)"
  [ -n "$mr_iid" ] || _mr_unknown "could not extract MR IID from URL: $mr_url" || return 1

  # Locate the task's worktree — the task file's own "Branch:" / "Worktree:" fields are
  # authoritative (never pattern-match project-specific branch shapes like PAYMXMP-123/… — a task
  # can live on any branch, and the shape is the project's business, not this tool's). Fall back to
  # scanning worktree/ ONLY when the branch is known, matching the checked-out branch (a worktree's
  # .git is a FILE, not a dir, so find by the checkout marker, never by -type d). With no branch
  # and no Worktree: field, fail loudly with the candidates instead of guessing the first worktree
  # in a multi-repo project.
  local repo_dir="" branch
  if [ -f "$taskfile" ]; then
    branch="$(grep -m1 -E '^- \*\*Branch:\*\*' "$taskfile" | sed -E 's/^- \*\*Branch:\*\* *`?([^`]*)`?$/\1/; s/[[:space:]]*$//' || true)"
    local wt_rel
    wt_rel="$(grep -m1 -E '^- \*\*Worktree:\*\*' "$taskfile" | sed -E 's/^- \*\*Worktree:\*\* *`?([^`]*)`?$/\1/; s/[[:space:]]*$//' || true)"
    [ -n "$wt_rel" ] && [ -d "$d/$wt_rel" ] && repo_dir="$d/$wt_rel"
  fi
  if [ -z "$repo_dir" ] && [ -n "$branch" ]; then
    local g
    for g in $(find "$d/worktree" -maxdepth 4 -name .git 2>/dev/null); do
      local cand; cand="$(dirname "$g")"
      local cb; cb="$(git -C "$cand" branch --show-current 2>/dev/null || true)"
      if [ "$cb" = "$branch" ]; then repo_dir="$cand"; break; fi
    done
  fi
  if [ -z "$repo_dir" ] || [ ! -d "$repo_dir" ]; then
    if [ -z "$branch" ]; then
      find "$d/worktree" -maxdepth 4 -name .git 2>/dev/null | while read -r g; do
        echo "  candidate: $(dirname "$g")" >&2
      done || true
    fi
    _mr_unknown "no worktree found for $task (Branch: ${branch:-unset}, Worktree: field missing or not under $d/worktree)" || return 1
  fi

  local origin_url
  origin_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
  [ -n "$origin_url" ] || _mr_unknown "no origin remote in $repo_dir" || return 1

  # Host extraction handles ssh (git@host:...) and https (https://host/...) forms.
  local host
  host="$(printf '%s' "$origin_url" | sed -E 's|^.*@||; s|^https?://||; s|[:/].*||')"
  [ -n "$host" ] || _mr_unknown "could not resolve host from origin: $origin_url" || return 1

  # Resolve forge: PW_FORGE_HOSTS override, else auto-detect (github.com → github, else gitlab).
  local forge="gitlab"
  case "$host" in
    github.com) forge="github" ;;
  esac
  if [ -n "${PW_FORGE_HOSTS:-}" ]; then
    for entry in "${PW_FORGE_HOSTS[@]}"; do
      local h="${entry%%=*}" f="${entry#*=}"
      [ "$h" = "$host" ] && { forge="$f"; break; }
    done
  fi

  # Query MR state from INSIDE the repo dir (glab resolves the project from cwd; gh from origin).
  local state=""
  case "$forge" in
    github)
      state="$(cd "$repo_dir" && gh pr view "$mr_iid" --json state -q .state 2>/dev/null || true)"
      ;;
    gitlab)
      state="$(cd "$repo_dir" && GITLAB_HOST="$host" glab mr view "$mr_iid" --output json 2>/dev/null | jq -r .state 2>/dev/null || true)"
      ;;
    *) die "unknown forge: $forge" ;;
  esac
  [ -n "$state" ] && [ "$state" != "null" ] \
    || _mr_unknown "failed to query MR $mr_iid state via $forge CLI on $host (is it authenticated?)" || return 1

  # Normalize state
  case "$state" in
    MERGED|merged) echo "merged" ;;
    OPEN|opened) echo "open" ;;
    CLOSED|closed) echo "closed" ;;
    *) _mr_unknown "unexpected MR state: $state (from $forge on $host)" || return 1 ;;
  esac
}

cmd_mr_state() {
  [ $# -eq 2 ] || die "usage: mr-state <slug> <task-id>"
  _mr_state_impl "$1" "$2"
}

cmd_mr_state_batch() {
  [ $# -ge 1 ] || die "usage: mr-state-batch <slug> [task-ids...]"

  SLUG="$1"
  shift
  TASK_IDS=("$@")

  D="$(proj_dir "$SLUG")"
  PLAN="$D/task/PLAN.md"

  [ -f "$PLAN" ] || die "PLAN.md not found ($PLAN) — run /pw-breakdown <slug> to produce it"

  # If no task IDs specified, use all tasks from PLAN
  if [ ${#TASK_IDS[@]} -eq 0 ]; then
    while IFS='|' read -r task_id _status; do
      [ -n "$task_id" ] && TASK_IDS+=("$task_id")
    done < <(pw_plan_pairs "$PLAN")
  fi

  # Check MR state for each task
  for task_id in ${TASK_IDS[@]+"${TASK_IDS[@]}"}; do
    # _mr_state_impl may itself print "unknown" AND exit non-zero — capture once, default after.
    STATE="$(_mr_state_impl "$SLUG" "$task_id" 2>/dev/null || true)"
    [ -n "$STATE" ] || STATE="unknown"
    echo "$task_id|$STATE"
  done
}

cmd_monitor() {
  TIMEOUT_MIN="${PW_PIPELINE_TIMEOUT:-15}"
  INTERVAL_SEC="${PW_PIPELINE_INTERVAL:-30}"
  SLUG=""
  TASK_ID=""

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) shift; TIMEOUT_MIN="${1:-$TIMEOUT_MIN}"; shift ;;
      --timeout=*) TIMEOUT_MIN="${1#--timeout=}" ;;
      --interval) shift; INTERVAL_SEC="${1:-$INTERVAL_SEC}"; shift ;;
      --interval=*) INTERVAL_SEC="${1#--interval=}" ;;
      -h|--help) pw_usage ;;
      -*) die "unknown option: $1" ;;
      *)
        if [ -z "$SLUG" ]; then
          SLUG="$1"
        elif [ -z "$TASK_ID" ]; then
          TASK_ID="$1"
        fi
        shift
        ;;
    esac
  done

  [ -n "$SLUG" ] && [ -n "$TASK_ID" ] || die "usage: monitor <slug> <task-id> [--timeout <minutes>] [--interval <seconds>]"

  D="$(proj_dir "$SLUG")"
  TASK_FILE="$D/task/$TASK_ID.md"

  [ -f "$TASK_FILE" ] || die "task file not found: $TASK_FILE"

  # Extract MR URL — Result-scoped (`- **MR:**` field first, bare URL second). Deliberately NOT a
  # whole-file grep: decoy literal URLs in a task's own ## Steps beat the field with that method.
  MR_URL=""
  if [ -f "$TASK_FILE" ]; then
    MR_URL="$(pw_task_mr_url "$TASK_FILE")"
  fi

  [ -n "$MR_URL" ] && [ "$MR_URL" != "(none)" ] || die "no MR URL found in task file"

  # Resolve forge per tooling/docs/forges.md: MR-URL host → PW_FORGE_HOSTS override, else
  # auto-detect (github.com → github, else gitlab). Mirrors mr-state. A URL-substring
  # grep cannot identify self-hosted GitLab (e.g. source.golabs.io contains no "gitlab").
  if [ -f "$PW_HOME/pw.config.sh" ]; then . "$PW_HOME/pw.config.sh"; fi
  MR_HOST="$(echo "$MR_URL" | sed -E 's#^https?://([^/:?#]+).*#\1#')"
  FORGE="gitlab"
  case "$MR_HOST" in github.com) FORGE="github" ;; esac
  if declare -p PW_FORGE_HOSTS >/dev/null 2>&1; then
    for entry in "${PW_FORGE_HOSTS[@]}"; do
      h="${entry%%=*}"; f="${entry#*=}"
      [ "$h" = "$MR_HOST" ] && { FORGE="$f"; break; }
    done
  fi
  FORGE_CLI=""
  case "$FORGE" in
    github) FORGE_CLI="gh" ;;
    gitlab) FORGE_CLI="glab" ;;
    *) die "unknown forge '$FORGE' mapped for host $MR_HOST (check PW_FORGE_HOSTS)" ;;
  esac

  command -v "$FORGE_CLI" >/dev/null 2>&1 || die "$FORGE_CLI not found (needed to monitor $MR_URL)"

  # Extract MR IID/number (+ owner/repo so the query has a repository context regardless of CWD)
  MR_IID=""
  GH_REPO=""
  GL_REPO=""
  if [ "$FORGE_CLI" = "glab" ]; then
    MR_IID="$(echo "$MR_URL" | grep -o 'merge_requests/[0-9]*' | sed 's/merge_requests\///')"
    # Full project path between host and /-/merge_requests on ANY host (self-managed included);
    # passed as --repo below so the query has repo context regardless of CWD.
    GL_REPO="$(echo "$MR_URL" | sed -E "s#^https?://[^/]+/##; s#/-/merge_requests(/[0-9]+).*##")"
  elif [ "$FORGE_CLI" = "gh" ]; then
    MR_IID="$(echo "$MR_URL" | grep -o 'pull/[0-9]*' | sed 's/pull\///')"
    GH_REPO="$(echo "$MR_URL" | sed -nE 's#.*github\.com/([^/]+/[^/]+)/pull.*#\1#p')"
  fi

  # Self-managed GitLab must be pinned to the URL's host — glab defaults to gitlab.com otherwise.
  export GITLAB_HOST="${GITLAB_HOST:-$MR_HOST}"

  [ -n "$MR_IID" ] || die "cannot extract MR IID from URL: $MR_URL"

  # Poll pipeline
  TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
  ELAPSED=0
  START_TIME="$(date +%s)"

  UNKNOWN_STREAK=0
  SKIPPED_STREAK=0
  echo "Monitoring pipeline for $TASK_ID (MR !$MR_IID)..."
  echo "  Timeout: ${TIMEOUT_MIN}m, Interval: ${INTERVAL_SEC}s"
  echo

  while true; do
    STATUS=""

    if [ "$FORGE_CLI" = "glab" ]; then
      # GitLab: MR-linked pipelines, newest first. Two races killed here: (1) right after a push
      # the first list entry is often a BRANCH pipeline the repo rules SKIP (the MR pipeline
      # registers moments later) — reading it reported false FAILED; (2) the first non-skipped
      # entry can be a STALE pipeline from the PREVIOUS push — reading it reported false SUCCESS
      # at 0m. Select by the MR's current head sha, prefer a non-skipped status among that sha's
      # pipelines, and only conclude "all skipped" after two consecutive polls (creation grace).
      # "[]" / no match yet (cold-start race) → keep waiting.
      HEAD_SHA="$(glab api "projects/:id/merge_requests/$MR_IID" ${GL_REPO:+-R "$GL_REPO"} 2>/dev/null | grep -o '"sha":"[0-9a-f]*"' | head -1 | sed 's/.*:"//;s/"$//' || true)"
      RAW="$(glab api "projects/:id/merge_requests/$MR_IID/pipelines" ${GL_REPO:+-R "$GL_REPO"} 2>/dev/null || true)"
      if [ -n "$RAW" ]; then
        STATUS=""
        JQ_OK=""
        if command -v jq >/dev/null 2>&1; then
          # jq legitimately answers "" (no pipelines for the head sha yet) — that must stay
          # "keep waiting", NOT fall through to the sha-blind grep fallback.
          if JQ_OUT="$(echo "$RAW" | jq -r --arg s "${HEAD_SHA:-}" '
            (if ($s | length) > 0 and (any(.[]?; has("sha"))) then (map(select(.sha == $s))) else . end) as $sel
            | ($sel | map(.status // "")) as $st
            | if ($st | length) == 0 then ""
              else (($st | map(select(. != "skipped" and . != "")) | .[0]) // "skipped")
              end' 2>/dev/null)"; then JQ_OK=1; STATUS="$JQ_OUT"; fi
        fi
        # no jq (or unparsable list) → old head-1 fallback, sha filtering unavailable
        [ -n "$JQ_OK" ] || STATUS="$(echo "$RAW" | grep -o '"status":"[^"]*"' | head -1 | sed 's/"status":"//;s/"//' || true)"
        [ -n "$STATUS" ] || STATUS="pending"
        # all pipelines for this head are skipped → neutral SKIPPED, but only after the
        # grace of a second consecutive poll (the MR pipeline may still be registering).
        if [ "$STATUS" = "skipped" ]; then
          SKIPPED_STREAK=$((SKIPPED_STREAK + 1))
        else
          SKIPPED_STREAK=0
        fi
      fi
    elif [ "$FORGE_CLI" = "gh" ]; then
      # GitHub: check PR checks status ("no checks reported" cold-start keeps waiting).
      RAW="$(gh pr checks "$MR_IID" ${GH_REPO:+-R "$GH_REPO"} 2>/dev/null || true)"
      if [ -n "$RAW" ]; then
        STATUS="$(echo "$RAW" | awk 'NR>1{print $2}' | sort -u | head -1 || true)"
        [ -n "$STATUS" ] || STATUS="pending"
      fi
    fi
    STATUS="${STATUS:-unknown}"

    NOW="$(date +%s)"
    ELAPSED=$((NOW - START_TIME))
    ELAPSED_MIN=$((ELAPSED / 60))
    ELAPSED_SEC=$((ELAPSED % 60))

    # Check terminal states
    case "$STATUS" in
      success|SUCCESS|passing|passed)
        echo "$TASK_ID: pipeline SUCCESS (${ELAPSED_MIN}m ${ELAPSED_SEC}s)"

        # Update task file (upsert: placeholder or stale record both overwritten)
        _record_build_check "$TASK_FILE" "SUCCESS"

        # The dashboard is NOT touched here: CI green ≠ merged. The State column belongs to
        # actual merged-ness (mr-state via /pw-ship or /pw-sync); the Build result is
        # already recorded in the task file's `- Build check:` line above.

        exit 0
        ;;
      failed|FAILURE|failed|canceled|CANCELLED|failing)
        echo "$TASK_ID: pipeline FAILED (${ELAPSED_MIN}m ${ELAPSED_SEC}s) — status: $STATUS"

        _record_build_check "$TASK_FILE" "FAILED ($STATUS)"

        exit 1
        ;;
      skipped|SKIPPED)
        # Creation grace: one skipped-only reading may be the branch pipeline racing the MR
        # pipeline's registration — keep polling once before concluding.
        if [ "$SKIPPED_STREAK" -lt 2 ]; then
          echo "$TASK_ID: pipeline running (${ELAPSED_MIN}m ${ELAPSED_SEC}s elapsed) — status: skipped (waiting for MR pipeline)"
          sleep "$INTERVAL_SEC"
          continue
        fi
        # Terminal-neutral: repo pipeline rules ran no jobs for this push. Not a failure —
        # reporting it red sends the build-fix loop chasing a build that never existed.
        echo "$TASK_ID: pipeline SKIPPED (${ELAPSED_MIN}m ${ELAPSED_SEC}s) — no CI jobs ran for this push (repo pipeline rules)"

        _record_build_check "$TASK_FILE" "SKIPPED (no jobs — repo pipeline rules)"

        exit 0
        ;;
      unknown)
        # A query that can't resolve state (auth, bad URL, CLI error) must fail fast —
        # waiting for a terminal state that may never arrive is worse than stopping.
        UNKNOWN_STREAK=$((UNKNOWN_STREAK+1))
        if [ "$UNKNOWN_STREAK" -ge 3 ]; then
          die "pipeline state unreadable after ${UNKNOWN_STREAK} polls — check $FORGE_CLI auth and the MR id ($MR_URL)"
        fi
        ;;
      *)
        UNKNOWN_STREAK=0
        ;;
    esac

    # Check timeout
    if [ "$ELAPSED" -ge "$TIMEOUT_SEC" ]; then
      echo "$TASK_ID: pipeline still running after ${TIMEOUT_MIN}m — not yet resolved"
      exit 2
    fi

    # Still running
    echo "$TASK_ID: pipeline running (${ELAPSED_MIN}m ${ELAPSED_SEC}s elapsed) — status: $STATUS"

    # Wait before next poll
    sleep "$INTERVAL_SEC"
  done
}

# ================= WRITE facet ================================================

# _record_build_check <taskfile> <text> — upsert the Result "Build check:" record. A bare
# "already contains 'Build check:'" guard once made this a silent no-op on template-derived
# files (the UNFILLED placeholder bullet matches too — the record never landed). Plan 16 harness,
# found by the monitor case.
_record_build_check() {
  local tf="$1" rec="$2"
  if grep -qE '^[*+-] (\*\*)?Build check' "$tf"; then
    awk -v r="$rec" '
      !d && /^[*+-] \*\*Build check:\*\*/ { print "- **Build check:** " r; d=1; next }
      !d && /^[*+-] Build check:/           { print "- Build check: " r;      d=1; next }
      {print}' "$tf" > "$tf.tmp" && mv "$tf.tmp" "$tf"
  elif grep -q '^## Result' "$tf"; then
    awk -v r="$rec" '/^## Result/{p=1; print; print "- Build check: " r; next} p && /^## /{p=0} {print}' \
      "$tf" > "$tf.tmp" && mv "$tf.tmp" "$tf"
  fi
}

cmd_exec() {
  [ $# -eq 3 ] || die "usage: exec <slug> <task-id> <description-file>"

  SLUG="$1"
  TASK_ID="$2"
  DESC_FILE="$3"

  D="$(proj_dir "$SLUG")"
  TASK_FILE="$D/task/$TASK_ID.md"
  PLAN="$D/task/PLAN.md"

  [ -f "$TASK_FILE" ] || die "task file not found: $TASK_FILE"
  [ -f "$DESC_FILE" ] || die "description file not found: $DESC_FILE"
  [ -f "$PLAN" ] || die "PLAN.md not found"

  # Extract task info
  REPO="$(pw_field "$TASK_FILE" Repo)"
  BRANCH="$(pw_field "$TASK_FILE" Branch)"; BRANCH="${BRANCH//\`/}"; BRANCH="${BRANCH%% *}"
  BASE="$(pw_field "$TASK_FILE" 'Base branch')"; BASE="${BASE//\`/}"; BASE="${BASE%% *}"
  TICKET="$(pw_field "$TASK_FILE" Ticket)"   # bold field OR legacy line-start; pw_field awk never trips set -e
  TITLE="$(grep '^# ' "$TASK_FILE" | head -1 | sed 's/^# //' | pw_trim)"

  [ -n "$REPO" ] || die "Repo not set in task file"
  [ -n "$BRANCH" ] || die "Branch not set in task file"
  [ -n "$BASE" ] || BASE="master"

  REPO_DIR="$REPOS_DIR/$REPO"
  [ -d "$REPO_DIR" ] || die "repo not found: $REPO_DIR"

  # Push branch
  echo "Pushing $BRANCH to origin..."
  git -C "$REPO_DIR" push origin "$BRANCH" || die "push failed"

  # Check for existing MR — Result-scoped resolution (`**MR:**` field first; a whole-file grep lets
  # decoy URLs in ## Steps win, which once made this call mis-see "existing MR"). See pw_task_mr_url.
  MR_URL="$(pw_task_mr_url "$TASK_FILE")"

  # Determine forge CLI — by the repo's actual origin host (docs/forges.md resolution, simplified:
  # github.com → gh, anything else → glab; self-hosted GitLab needs gitlab in its URL or falls to
  # the availability order below). Prefer correct-over-merely-installed, then fall back.
  ORIGIN_URL="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")"
  FORGE_CLI=""
  if echo "$ORIGIN_URL" | grep -q github; then
    command -v gh >/dev/null 2>&1 && FORGE_CLI="gh"
  elif echo "$ORIGIN_URL" | grep -q gitlab; then
    command -v glab >/dev/null 2>&1 && FORGE_CLI="glab"
  fi
  if [ -z "$FORGE_CLI" ]; then
    if command -v glab >/dev/null 2>&1; then FORGE_CLI="glab"
    elif command -v gh >/dev/null 2>&1; then FORGE_CLI="gh"
    else die "no forge CLI found (need glab or gh)"
    fi
  fi

  # Create or update MR — only a REAL URL means an MR already exists. The old bare -n test
  # counted placeholder sentinels ("-", "—") as existing MRs and silently skipped creation
  # (found by the plan 16 T1 ship-exec case).
  case "$MR_URL" in http*) _MR_EXISTS=1;; *) _MR_EXISTS=0;; esac
  if [ "$_MR_EXISTS" = 1 ]; then
    echo "MR already exists: $MR_URL"
  else
    echo "Creating MR..."

    # Build MR title with ticket prefix if available
    MR_TITLE="$TITLE"
    if [ -n "$TICKET" ]; then
      MR_TITLE="[$TICKET] $TITLE"
    fi

    # Read description
    DESCRIPTION="$(cat "$DESC_FILE")"

    # Create MR
    # Run from inside the repo so both CLIs resolve their project/host context (see forges.md).
    if [ "$FORGE_CLI" = "glab" ]; then
      MR_OUTPUT="$( cd "$REPO_DIR" && glab mr create \
        --source-branch "$BRANCH" \
        --target-branch "$BASE" \
        --title "$MR_TITLE" \
        --description "$DESCRIPTION" \
        --no-editor \
        --output json 2>&1 || true)"
      MR_URL="$(echo "$MR_OUTPUT" | grep -o '"web_url":"[^"]*"' | sed 's/"web_url":"//;s/"//' || echo "")"
    elif [ "$FORGE_CLI" = "gh" ]; then
      MR_OUTPUT="$( cd "$REPO_DIR" && gh pr create \
        --head "$BRANCH" \
        --base "$BASE" \
        --title "$MR_TITLE" \
        --body "$DESCRIPTION" 2>&1 || true)"
      MR_URL="$(echo "$MR_OUTPUT" | grep -o 'https://github.com/[^ ]*' || echo "")"
    fi

    if [ -n "$MR_URL" ]; then
      echo "MR created: $MR_URL"

      # Record the MR URL in the task file's Result. Upsert the BOLD field line when present
      # (v2 templates carry a "- **MR:** <placeholder>" bullet — appending a second plain line
      # left the resolver reading the placeholder and re-creating the MR every run):
      if grep -qE '^- \*\*MR:\*\*' "$TASK_FILE"; then
        awk -v mr="$MR_URL" '!d && /^- \*\*MR:\*\*/ { print "- **MR:** " mr; d=1; next } {print}' \
          "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
      elif grep -q '^## Result' "$TASK_FILE"; then
        # Append MR line to Result section
        awk -v mr="$MR_URL" '/^## Result/{p=1; print; print "- MR: " mr; next} p && /^## /{p=0} {print}' \
          "$TASK_FILE" > "$TASK_FILE.tmp" && mv "$TASK_FILE.tmp" "$TASK_FILE"
      else
        # Add Result section
        printf '\n## Result\n\n- MR: %s\n' "$MR_URL" >> "$TASK_FILE"
      fi
    else
      # No URL back = no MR exists; do not let a partial ship pass as success, and never mark
      # the dashboard open for an MR that wasn't created.
      echo "pw-ship exec: branch pushed, but $FORGE_CLI returned no MR URL — first line of its output:" >&2
      echo "  $(echo "$MR_OUTPUT" | head -1)" >&2
      die "MR creation failed (push itself succeeded — safe to re-run after fixing auth/context)"
    fi
  fi

  # Update dashboard (only reached on creation-success or existing-MR paths). Subshell: a die()
  # here must not exit the script — the pre-merge subprocess form only ever killed the child.
  ( cmd_dashboard_mr_state "$SLUG" "$TASK_ID" "open" ) 2>/dev/null || true

  echo "Ship execution complete for $TASK_ID"
}

# Ensure task/review/T0n.review.md has a "## MR comment tracking" table (create the header +
# explainer if missing) — lazily added only once a thread is actually seen. Private helper for
# cmd_comment_seen.
#
# Unlike rfc/META.md (pure machine metadata, nothing ever follows the Comment-tracking section),
# a review file's LAST section is "## Sign-off" — human-owned, and meant to read as the closing
# gate. A blind end-of-file append lands this section AFTER Sign-off, visually orphaned below the
# gate a human just signed. So: insert it right BEFORE "## Sign-off" if that heading exists yet
# (review-init always creates one, so in practice it always does); fall back to a plain append only
# if some non-standard file genuinely lacks one.
_ship_comment_section_ensure() {
  local f="$1"
  grep -q '^## MR comment tracking' "$f" 2>/dev/null && return 0
  # Written to a temp file with plain printf, then spliced in with head/tail/cat — NOT awk -v and
  # NOT a heredoc. Two real, confirmed-here portability traps ruled those out: (1) a heredoc body
  # with an odd count of literal apostrophes confuses bash's own parser once nested inside a
  # $(...) substitution; (2) macOS's /usr/bin/awk (the BWK "one true awk", not gawk) rejects a
  # `-v var=…` assignment whose value contains embedded newlines ("awk: newline in string").
  # head/tail/cat sidestep both — no shell-quote gymnastics, no awk variable involved at all.
  local sectionfile; sectionfile="$(mktemp)"
  {
    printf '\n## MR comment tracking   [🤖-owned — never hand-edit; see `pw-ship.sh comment-seen`]\n\n'
    printf "A discussion's \`resolvable\` flag (NOT whether it's diff-anchored vs general — see\n"
    printf "tooling/docs/forges.md) decides whether the forge can ever report it resolved. A \`resolvable: false\`\n"
    printf 'thread (a plain one-off comment) can never report resolved=true via the forge API, no matter how\n'
    printf "many replies it gets — so the forge can never tell a later \`/pw-ship … comments\` run \"this one's\n"
    printf '%s\n' 'already handled". This table is the LOCAL authority for that instead, keyed by thread/comment ID'
    printf "(shown truncated below; the full ID lives in each row's hidden marker, which is what matching\n"
    printf "actually keys on — don't reformat/shorten a row by hand, add a \`note\` argument instead).\n"
    printf '\n| Thread | Kind | Replied | Notes |\n|--------|------|---------|-------|\n'
  } > "$sectionfile"
  if grep -q '^## Sign-off' "$f"; then
    local signline; signline="$(grep -n '^## Sign-off' "$f" | head -1 | cut -d: -f1)"
    { head -n "$((signline - 1))" "$f"; cat "$sectionfile"; printf '\n'; tail -n "+${signline}" "$f"; } \
      > "$f.tmp" && mv "$f.tmp" "$f"
  else
    cat "$sectionfile" >> "$f"
  fi
  rm -f "$sectionfile"
}

# Deterministically upsert ONE row per MR-comment thread — same keyed-marker upsert shape as
# rfc comment-seen (append-or-rewrite-in-place), applied to /pw-ship … comments instead of
# /pw-rfc comments. This is what makes a rerun able to tell "already replied to this unresolvable
# comment" from "new one, never seen" — without it, an unresolvable thread either gets silently
# skipped forever (looks perpetually "not resolved" on the forge, so a naive resolved-filter treats
# it as not-actionable) or gets re-processed/re-replied-to every single run (no forge-side flag
# ever flips to stop it recurring).
#   comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]
cmd_comment_seen() {
  [ $# -ge 5 ] || die "usage: comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]"
  local slug="$1" task="$2" thread="$3" kind="$4" replied="$5"; shift 5; local note="$*"
  case "$kind" in resolvable|unresolvable) ;; *) die "kind must be 'resolvable' or 'unresolvable' (got '$kind')" ;; esac
  case "$replied" in yes|no) ;; *) die "replied must be 'yes' or 'no' (got '$replied')" ;; esac
  local d; d="$(proj_dir "$slug")"
  local f="$d/task/review/$task.review.md"
  [ -f "$f" ] || die "no review file: task/review/$task.review.md (run 'pw-review.sh init $slug task/review/$task.review.md task/$task.md' first)"
  _ship_comment_section_ensure "$f"
  local marker="<!-- pw-mr-comment:$thread -->"
  local shortid="${thread:0:8}"
  local row="| \`$shortid\` | $kind | $replied | $note $marker |"
  if grep -Fq "$marker" "$f"; then
    awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    # Insert right after this section's table separator, so a brand-new row lands INSIDE the
    # table (immediately below the header) instead of at the true end of the file — where it
    # would land after ## Sign-off and read as an orphaned, disconnected block. Falls back to a
    # plain append only if the separator can't be found (defensive; should not normally happen).
    awk -v row="$row" '
      /^## MR comment tracking/ { insec=1 }
      { print }
      insec && !done && /^\|[-| ]+\|[ ]*$/ { print row; done=1 }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    grep -Fq "$marker" "$f" || printf '%s\n' "$row" >> "$f"
  fi
  "$ST" log "$slug" ship "comment-seen $task/$thread ($kind): replied=$replied"
  echo "$slug: ship comment-seen $task/$thread ($kind) -> replied=$replied"
}

# Update an MR's state in the dashboard README.md MR table.
#   dashboard-mr-state <slug> <task-id> <state>
cmd_dashboard_mr_state() {
  [ $# -eq 3 ] || die "usage: dashboard-mr-state <slug> <task-id> <state>"
  local slug="$1" task="$2" state="$3"
  local d; d="$(proj_dir "$slug")"
  local readme="$d/README.md"
  [ -f "$readme" ] || die "no README.md in project $slug"

  _dashboard_update "$readme" 'Task' 'State' "$task" "$state" \
    || die "dashboard-mr-state: could not update $task in the Merge requests table (see above)"
  "$ST" log "$slug" sync "dashboard: $task MR state -> $state"
}

case "${1:-}" in
  resolve)            shift; cmd_resolve "$@" ;;
  exec)               shift; cmd_exec "$@" ;;
  monitor)            shift; cmd_monitor "$@" ;;
  mr-state)           shift; cmd_mr_state "$@" ;;
  mr-state-batch)     shift; cmd_mr_state_batch "$@" ;;
  comment-seen)       shift; cmd_comment_seen "$@" ;;
  dashboard-mr-state) shift; cmd_dashboard_mr_state "$@" ;;
  *) die "usage: pw-ship.sh <resolve|exec|monitor|mr-state|mr-state-batch|comment-seen|dashboard-mr-state> … (see --help)" ;;
esac
