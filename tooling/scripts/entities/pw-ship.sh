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
#   pw-ship.sh history            <slug> <invocation|pending|init|begin|checkpoint|freeze|deliver> [MR-url] [options]
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
# history — project-owned invocation/MR attempt records and owned description delivery.
#   invocation prints a call ID; pending lists unfinished records without querying a forge.
#   init --file <creation-body> verifies/snapshots a new marked MR; begin --invocation <id>
#   checkpoints its before state.
#   checkpoint --attempt <key> --file <JSON> accepts authored evidence; freeze seals it.
#   deliver --attempt <key> --limit <documented-number> --unit <utf8|chars>
#   --limit-source <reference> performs bounded read/write/readback, oldest-block pruning,
#   and immutable newest-first history. No pushes or thread replies are performed here.
#   init --reviewed is human-triggered only, never on agent initiative: it snapshots an
#   explicitly reviewed current body without rewriting any retained frozen attempt.
#
# Facet: STACK (plan 35) — branch-inheritance lifecycle. The `Stacked on:` field and
# ancestry/target readers live in pw-common.sh; these operators are the ship-owned read/write
# surface the /pw-ship stack selection and the comment/sync cascade call.
# stack-validate — fail-closed topology check (cycle, unknown/self/cross-repo parent,
#   incompatible destinations, shared branch, missing depends_on edge).
# stack — read-only topology + health preview (task|parent|target|branch|base|landed|freshness|debt).
# stack-plan — root-first publication order with effective targets + parent-first readiness.
# stack-record — write the state binding row (fork/consumed SHAs, target, verification tuple).
# stack-fresh / stack-stale — freshness-debt toggle for the current verification tuple.
# stack-land — observe a parent's landing (kind:branch) before promoting children.
# stack-promote — post-landing verdict: promote|<target> / noop / block|<reason>.
# stack-op — pending-operation recovery rows (list|create|set|clear); stack-debt gates outward work.
# stack-adopt — infer stack edges from real MR targets (dry-run; --apply imports).
# stack-inherited — record one descendant's inherited update (never a fabricated reviewer comment).
# stack-cascade — parent-first descendant integration/verify-binding/record/push with persisted stages.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
. "$HERE/../lib/pw-shiplib.sh"
ST="$HERE/pw-status.sh"
# -h/--help before positional parsing: without this, "-h" would be taken as a slug/arg.
case "${1:-}" in -h|--help) pw_usage ;; esac

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
REPOS_DIR="${PW_REPOS:-$(cd "$PROJECTS_DIR/.." && pwd)}"

die() { echo "pw-ship: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: $PW_HOME/tooling/scripts/toolchain/scaffold.sh $1)"; printf '%s' "$d"; }

# ================= READ facet =================================================

cmd_history() {
  [ $# -ge 2 ] || die "usage: history <slug> <operation> [MR-url] [options] → fix: see --help"
  local slug="$1"; shift
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "unsafe project slug → fix: use a project name, not a path"
  local d ts="" mappings="" registered=no taskfile url; d="$(proj_dir "$slug")"
  if [ "$1" = begin ]; then
    ts="$(pw_now_wib)" || die "cannot format history timestamp → fix: check the date command"
  fi
  if [ -n "${PW_FORGE_HOSTS[0]:-}" ]; then mappings="$(printf '%s\n' "${PW_FORGE_HOSTS[@]}")"; fi
  case "$1" in
    init|begin)
      for taskfile in "$d"/task/T*.md; do
        [ -f "$taskfile" ] || continue
        url="$(pw_task_mr_url "$taskfile")"
        [ "$url" != "${2:-}" ] || { registered=yes; break; }
      done
      if [ "$registered" = no ] && [ -f "$d/README.md" ]; then
        # Legacy dashboards can own the URL when a task Result has no MR field.
        while IFS= read -r url; do
          [ "$url" != "${2:-}" ] || { registered=yes; break; }
        done < <(awk -F'|' '
          /^\|/ {
            candidate=0
            for (i=2;i<NF;i++) { c=$i; gsub(/[*`]/,"",c); gsub(/^[[:space:]]+|[[:space:]]+$/,"",c); if(c=="MR") candidate=i }
            if($0 ~ /^\|[-| :]+\|[[:space:]]*$/) {m=header; header=0; next}
            header=candidate
            if(m && $m ~ /https?:/) print $m
          }' "$d/README.md" | grep -oE 'https?://[^ )>|"`]+' || true)
      fi ;;
  esac
  pw_ship_history "$d" "$ts" "$mappings" "$registered" "$@"
}

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
  origin_url="$(git -C "$repo_dir" config --get remote.origin.url 2>/dev/null || true)"
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
    # Bash 3.2 rejects "${arr[@]}" on an EMPTY array under `set -u` — use the guarded form.
    for entry in ${PW_FORGE_HOSTS[@]+"${PW_FORGE_HOSTS[@]}"}; do
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

  # Effective review target (plan 35): a stacked task targets its nearest unmerged ancestor's
  # branch, else its ultimate Base branch. The entity boundary enforces the same gates the
  # preflight does, so a bypassed preflight cannot let stale or mid-cascade work ship.
  STACK_PARENT="$(pw_stack_parent "$TASK_FILE" 2>/dev/null || true)"
  TARGET_BRANCH="$BASE"
  if [ -n "$STACK_PARENT" ]; then
    pw_stack_state_validate "$D" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before shipping $TASK_ID"
    # Fresh remote view before validating the published parent (a stale origin ref must not pass).
    git -C "$REPO_DIR" fetch -q --prune origin \
      || die "git fetch origin failed in $REPO_DIR → fix: check network/auth before shipping $TASK_ID"
    TARGET_BRANCH="$(pw_stack_effective_target "$D" "$TASK_ID" "$BASE")" \
      || die "cannot resolve the stack target for $TASK_ID (unprovable landing destination or missing ancestor Branch) → fix: /pw-doctor --project $SLUG (stack topology)"
    [ -n "$TARGET_BRANCH" ] || die "cannot resolve the stack target for $TASK_ID → fix: /pw-doctor --project $SLUG (stack topology)"
    case "$TARGET_BRANCH" in ''|*[!A-Za-z0-9._/-]*|-*) die "refusing unsafe stack target branch '$TARGET_BRANCH' for $TASK_ID";; esac
    _stack_stale "$D" "$TASK_ID" \
      && die "task $TASK_ID's verification tuple is stale (head/parent/target changed) → fix: re-verify (/pw-execute $SLUG $TASK_ID) before shipping"
    if [ -f "$D/task/stack-ops.tsv" ]; then
      local _opkey _okind _opanc _oev _oexp _ocreated _ostages _ostate _clos
      _clos=" $(_stack_closure_ids "$D" "$TASK_ID" | tr '\n' ' ') "
      while IFS=$'\t' read -r _opkey _okind _opanc _oev _oexp _ocreated _ostages _ostate; do
        [ "$_opkey" = "key" ] && continue
        [ -n "$_opkey" ] || continue
        [ "$_ostate" = "done" ] && continue
        case "$_clos" in *" $_opanc "*) die "pending stack operation '$_opkey' ($_opanc) blocks shipping $TASK_ID → fix: resume the recorded cascade stages before a new ship";; esac
      done < "$D/task/stack-ops.tsv"
    fi
    # Parent-first readiness: while the effective target is an ancestor's BRANCH, the published ref
    # and the local branch must both sit at that ancestor's verified head. Once every ancestor has
    # landed, the effective target IS the ultimate base — there is no ancestor branch to match;
    # require the base itself to be published instead (the fetch above keeps origin fresh). The
    # old unconditional ancestor match wrongly failed a fully-landed stack ("no ancestor matches").
    if [ "$TARGET_BRANCH" = "$BASE" ]; then
      git -C "$REPO_DIR" rev-parse --verify "origin/$BASE" >/dev/null 2>&1 \
        || die "ultimate target '$BASE' is not published on origin for $TASK_ID → fix: publish/finish the stack landing first (/pw-ship $SLUG)"
    else
      local _anc _abr _av _ohead _lhead _matched=0
      while IFS= read -r _anc; do
        [ -n "$_anc" ] || continue
        _abr="$(_stack_branch_of "$D" "$_anc")"
        [ "$_abr" = "$TARGET_BRANCH" ] || continue
        _matched=1
        _av="$(pw_stack_state_get "$D" "$_anc" verified_head)"
        [ -n "$_av" ] \
          || die "parent $_anc has no verified binding for target '$TARGET_BRANCH' → fix: run pw-ship.sh stack-verify $_anc <evidence> after its ## Verify (or re-run /pw-ship $SLUG $_anc)"
        _ohead="$(git -C "$REPO_DIR" rev-parse "origin/$TARGET_BRANCH" 2>/dev/null || true)"
        [ "$_ohead" = "$_av" ] \
          || die "parent target '$TARGET_BRANCH' on origin is not at $_anc's verified head (${_av:0:8}) → fix: push the verified parent first (/pw-ship $SLUG $_anc)"
        _lhead="$(git -C "$REPO_DIR" rev-parse "$TARGET_BRANCH" 2>/dev/null || true)"
        [ "$_lhead" = "$_av" ] \
          || die "local parent branch '$TARGET_BRANCH' is not at $_anc's verified head (${_av:0:8}) → fix: re-run the parent's execution/verify (/pw-execute $SLUG $_anc)"
        break
      done <<EOF
$(pw_stack_chain "$D" "$TASK_ID" 2>/dev/null || true)
EOF
      [ "$_matched" = 1 ] || die "no ancestor task matches the stack target '$TARGET_BRANCH' → fix: /pw-doctor --project $SLUG (stack topology)"
    fi
  fi

  # Push branch
  echo "Pushing $BRANCH to origin..."
  git -C "$REPO_DIR" push origin "$BRANCH" || die "push failed"

  # Check for existing MR — Result-scoped resolution (`**MR:**` field first; a whole-file grep lets
  # decoy URLs in ## Steps win, which once made this call mis-see "existing MR"). See pw_task_mr_url.
  MR_URL="$(pw_task_mr_url "$TASK_FILE")"

  # Determine forge CLI — by the repo's actual origin host (docs/forges.md resolution, simplified:
  # github.com → gh, anything else → glab; self-hosted GitLab needs gitlab in its URL or falls to
  # the availability order below). Prefer correct-over-merely-installed, then fall back.
  ORIGIN_URL="$(git -C "$REPO_DIR" config --get remote.origin.url 2>/dev/null || echo "")"
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
    DESCRIPTION="$(cat "$DESC_FILE" && printf '.')" \
      || die "cannot read MR creation body → fix: restore the generated description file before retrying"
    DESCRIPTION="${DESCRIPTION%.}"

    # Create MR
    # Run from inside the repo so both CLIs resolve their project/host context (see forges.md).
    if [ "$FORGE_CLI" = "glab" ]; then
      MR_OUTPUT="$( cd "$REPO_DIR" && glab mr create \
        --source-branch "$BRANCH" \
        --target-branch "$TARGET_BRANCH" \
        --title "$MR_TITLE" \
        --description "$DESCRIPTION" \
        --no-editor \
        --output json 2>&1 || true)"
      MR_URL="$(echo "$MR_OUTPUT" | grep -o '"web_url":"[^"]*"' | sed 's/"web_url":"//;s/"//' || echo "")"
    elif [ "$FORGE_CLI" = "gh" ]; then
      MR_OUTPUT="$( cd "$REPO_DIR" && gh pr create \
        --head "$BRANCH" \
        --base "$TARGET_BRANCH" \
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
      if grep -q '<!-- pw-mr-summary:start -->' "$DESC_FILE"; then
        cmd_history "$SLUG" init "$MR_URL" --file "$DESC_FILE" \
          || die "MR created but initial ownership snapshot is pending → fix: retain the creation body and retry its history init after fixing readback"
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

  # Persist the effective target for a stacked task so promotion/cascade can compare observed
  # vs recorded targets. Best-effort (a state write failure never fails an otherwise-good ship).
  if [ -n "${STACK_PARENT:-}" ]; then
    pw_stack_state_upsert "$D" "$TASK_ID" target="$TARGET_BRANCH" parent="$STACK_PARENT" >/dev/null 2>&1 || true
  fi

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

# ================= STACK facet (plan 35) ======================================
# The stack record is ship-owned: one minimal state row per affected branch/MR
# (task/stack.tsv) plus pending-operation rows (task/stack-ops.tsv). The `Stacked on:` field and
# ancestry/effective-target readers live in pw-common.sh; these operators are the read/write
# surface the /pw-ship stack selection and the comment/sync cascade call. Everything here is
# branch-local and offline — no live forge call except stack-adopt's target read, which goes
# through the same forge resolver as mr-state.

# Every task id that participates in a stack edge (as child or parent), one per line.
_stack_tasks() {
  local d="$1" f t p
  for f in "$d"/task/T*.md; do
    [ -f "$f" ] || continue
    t="$(basename "$f" .md)"; p="$(pw_stack_parent "$f")"
    if [ -n "$p" ]; then printf '%s\n' "$t"; printf '%s\n' "$p"; fi
  done | sort -u
  return 0
}
_stack_depth() { local c; c="$(pw_stack_chain "$1" "$2" 2>/dev/null || true)"; [ -n "$c" ] && printf '%s\n' "$c" | grep -c . || printf '0\n'; }
_pw_deps_has() { case " $(printf '%s' "$1" | tr ',;' '  ') " in *" $2 "*) return 0 ;; esac; return 1; }

# --- stack runtime helpers (plan 35 hardening) --------------------------------
# _stack_repo_of / _stack_branch_of / _stack_base_of — the task's machine fields, trimmed.
_stack_repo_of()   { pw_field "$1/task/$2.md" Repo 2>/dev/null || true; }
_stack_branch_of() { local b; b="$(pw_field "$1/task/$2.md" Branch 2>/dev/null || true)"; b="${b//\`/}"; printf '%s' "${b%%[[:space:]]*}"; }
_stack_base_of()   { local b; b="$(pw_field "$1/task/$2.md" 'Base branch' 2>/dev/null || true)"; b="${b%%[[:space:]]*}"; [ -n "$b" ] || b="master"; printf '%s' "$b"; }

# _stack_closure_ids <d> <t> — the task itself plus its stack ancestors and descendants (the set a
# pending operation on any member must gate).
_stack_closure_ids() {
  local d="$1" t="$2"
  printf '%s\n' "$t"
  pw_stack_ancestors "$d" "$t" 2>/dev/null || true
  pw_stack_descendants "$d" "$t" 2>/dev/null || true
}

# _stack_resolve_ref <repo-dir> <branch> — a ref that exists for <branch> (origin/<b> preferred).
_stack_resolve_ref() {
  local rd="$1" b="$2"
  git -C "$rd" rev-parse --verify "origin/$b" >/dev/null 2>&1 && { printf '%s' "origin/$b"; return 0; }
  git -C "$rd" rev-parse --verify "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
  return 1
}

# _stack_task_repo_dir <d> <t> — the task's mounted worktree (Worktree: field, else branch match).
_stack_task_repo_dir() {
  local d="$1" t="$2" branch wt_rel cand g cb
  branch="$(_stack_branch_of "$d" "$t")"
  wt_rel="$(pw_field "$d/task/$t.md" Worktree 2>/dev/null || true)"; wt_rel="${wt_rel//\`/}"
  if [ -n "$wt_rel" ] && [ -d "$d/$wt_rel" ]; then printf '%s' "$d/$wt_rel"; return 0; fi
  if [ -n "$branch" ]; then
    for g in $(find "$d/worktree" -maxdepth 4 -name .git 2>/dev/null); do
      cand="$(dirname "$g")"
      cb="$(git -C "$cand" branch --show-current 2>/dev/null || true)"
      [ "$cb" = "$branch" ] && { printf '%s' "$cand"; return 0; }
    done
  fi
  return 1
}

_stack_host_of()  { git -C "$1" config --get remote.origin.url 2>/dev/null | sed -E 's|^.*@||; s|^https?://||; s|[:/].*||'; }
_stack_forge_of() {
  local host="$1" forge="gitlab" entry h ff
  case "$host" in github.com) forge="github" ;; esac
  for entry in ${PW_FORGE_HOSTS[@]+"${PW_FORGE_HOSTS[@]}"}; do h="${entry%%=*}"; ff="${entry#*=}"; [ "$h" = "$host" ] && { forge="$ff"; break; }; done
  printf '%s' "$forge"
}
_stack_mr_iid() {
  local forge="$1" mr="$2"
  if [ "$forge" = github ]; then printf '%s' "$mr" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+$'
  else printf '%s' "$mr" | grep -oE '/-/merge_requests/[0-9]+' | grep -oE '[0-9]+$'; fi
}

# _stack_stale <d> <t> — rc 0 when the recorded verification tuple no longer covers CURRENT reality
# (child head, consumed parent, effective target, CI context) or the task is unverified; rc 1 fresh.
# The comparison is against live Git/state — a manual freshness flag can never certify stale data.
_stack_stale() {
  local d="$1" t="$2" fresh vh parent_task vp_rec vp_exp cps vt_rec vt_cur repo branch cur_head cs ct
  fresh="$(pw_stack_state_get "$d" "$t" freshness)"
  [ "$fresh" = "stale" ] && return 0
  vh="$(pw_stack_state_get "$d" "$t" verified_head)"
  [ -n "$vh" ] || return 0
  # Transitive: a stale ancestor makes every descendant stale (an upstream fix must propagate).
  local _a
  for _a in $(pw_stack_ancestors "$d" "$t" 2>/dev/null || true); do
    _stack_stale "$d" "$_a" && return 0
  done
  repo="$(_stack_repo_of "$d" "$t")"; branch="$(_stack_branch_of "$d" "$t")"
  cur_head=""
  if [ -n "$repo" ] && [ -n "$branch" ] && [ -d "$REPOS_DIR/$repo" ]; then
    cur_head="$(git -C "$REPOS_DIR/$repo" rev-parse "$branch" 2>/dev/null || true)"
    [ -n "$cur_head" ] && [ "$vh" != "$cur_head" ] && return 0
  fi
  parent_task="$(pw_stack_parent_id "$d" "$t")"
  if [ -n "$parent_task" ]; then
    vp_rec="$(pw_stack_state_get "$d" "$t" verified_parent)"
    vp_exp="$(pw_stack_state_get "$d" "$parent_task" verified_head)"
    [ "$vp_rec" = "$vp_exp" ] || return 0
    cps="$(pw_stack_state_get "$d" "$t" consumed_parent_sha)"
    if [ -n "$cps" ] && [ -n "$repo" ] && [ -n "$branch" ] && [ -d "$REPOS_DIR/$repo" ]; then
      git -C "$REPOS_DIR/$repo" merge-base --is-ancestor "$cps" "$branch" 2>/dev/null || return 0
    fi
  fi
  vt_rec="$(pw_stack_state_get "$d" "$t" verified_target)"
  vt_cur="$(pw_stack_effective_target "$d" "$t" "$(_stack_base_of "$d" "$t")" 2>/dev/null || true)"
  [ "$vt_rec" = "$vt_cur" ] || return 0
  # CI tuple (plan 35 rev 2): 'skipped' and 'pending' are explicit dispositions (shipping may
  # proceed; a monitor settles them, so neither is silently read as green); 'failed'/'unknown' block
  # until replaced; a green SHA bound to an OLD head, or any binding whose ci_target is not the live
  # effective target, cannot carry across a retarget.
  cs="$(pw_stack_state_get "$d" "$t" ci_sha)"
  ct="$(pw_stack_state_get "$d" "$t" ci_target)"
  case "$cs" in
    ""|skipped|pending) : ;;
    failed|unknown) return 0 ;;
    *) [ -n "$cur_head" ] && [ "$cs" != "$cur_head" ] && return 0 ;;
  esac
  [ -n "$ct" ] && [ "$ct" != "$vt_cur" ] && return 0
  return 1
}

# _stack_preview_freshness <d> <t> — the READ-ONLY preview token ("fresh"|"stale"|"unverified")
# for stack rows, preflight ship/close, and status. _stack_stale remains the STRICT execution gate
# and is never weakened: exec/verify still refuse an unbound task. The preview reports "unverified"
# only for a task that has nothing to be stale yet — no record at all, no explicit stale flag, no
# branch anywhere (not started), and a non-shippable status (todo/empty). Everything else
# _stack_stale flags reports "stale": a tuple that no longer covers reality, an explicit stale
# flag, a STARTED task without a tuple, and a done/accepted (shippable) task without its required
# binding — the last case must block, never get a false "unverified" exemption.
_stack_preview_freshness() {
  local d="$1" t="$2" fs vh status repo branch wt_hit
  if ! _stack_stale "$d" "$t"; then printf 'fresh'; return 0; fi
  fs="$(pw_stack_state_get "$d" "$t" freshness)"
  [ "$fs" = "stale" ] && { printf 'stale'; return 0; }
  vh="$(pw_stack_state_get "$d" "$t" verified_head)"
  [ -n "$vh" ] && { printf 'stale'; return 0; }
  status="$(pw_field "$d/task/$t.md" Status 2>/dev/null || true)"
  case "$status" in
    todo|"") : ;;
    *) printf 'stale'; return 0 ;;
  esac
  repo="$(_stack_repo_of "$d" "$t")"; branch="$(_stack_branch_of "$d" "$t")"
  if [ -n "$branch" ] && [ -n "$repo" ] && [ -d "$REPOS_DIR/$repo" ]; then
    { git -C "$REPOS_DIR/$repo" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1 \
      || git -C "$REPOS_DIR/$repo" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1; } \
      && { printf 'stale'; return 0; }
  fi
  if [ -d "$d/worktree" ]; then
    wt_hit="$(find "$d/worktree" -maxdepth 3 -type d -name "$t-*" 2>/dev/null || true)"
    [ -n "$wt_hit" ] && { printf 'stale'; return 0; }
  fi
  printf 'unverified'
}

# _stack_verify_landing <slug> <d> <t> <msha> <into> <kind> — deterministic landing evidence.
# The destination must be an ACTUALLY FETCHED origin ref (a local-only branch can hold arbitrary
# ancestry and proves nothing), and when the forge can report the MR its observed target must be
# the claimed destination. merge/ff: the parent's verified_head must be an ancestor of origin/<into>,
# and any given merge sha must be an ancestor too. squash/rebase/closed: the forge MR state must
# corroborate; content ancestry is NOT provable, so promotion stays blocked.
_stack_verify_landing() {
  local slug="$1" d="$2" t="$3" msha="$4" into="$5" kind="$6"
  local repo rd vh ref mstate="" mrurl mview mtgt
  repo="$(_stack_repo_of "$d" "$t")"
  [ -n "$repo" ] || { echo "parent $t has no Repo field" >&2; return 1; }
  rd="$REPOS_DIR/$repo"; [ -d "$rd" ] || { echo "repo not found: $rd" >&2; return 1; }
  git -C "$rd" fetch -q --prune origin 2>/dev/null \
    || { echo "cannot refresh origin refs in $repo before proving the landing → fix: network/auth, then retry" >&2; return 1; }
  vh="$(pw_stack_state_get "$d" "$t" verified_head 2>/dev/null || true)"
  [ -n "$vh" ] || { echo "parent $t has no verified_head binding — cannot prove a landing" >&2; return 1; }
  mstate="$(_mr_state_impl "$slug" "$t" 2>/dev/null || true)"
  # "unknown" from mr-state means no MR / no forge / a failed query — it is NOT a definitive
  # state. Treat it as "no corroboration"; merge/ff still commit to real Git ancestry, while
  # squash/rebase/closed REQUIRE a definitive forge state.
  case "$mstate" in merged|closed|open) : ;; *) mstate="" ;; esac
  # Observed forge target corroboration whenever the MR URL lets the forge answer: a landing claim
  # into branch X while the MR actually targets Y is not provable (never resolve from the claim).
  mrurl="$(pw_task_mr_url "$d/task/$t.md" 2>/dev/null || true)"
  case "$mrurl" in
    http*)
      mview="$(_stack_mr_view "$mrurl" "$rd" 2>/dev/null || true)"
      if [ -n "$mview" ]; then
        mtgt="${mview#*|}"; mtgt="${mtgt%%|*}"
        [ "$mtgt" = "$into" ] \
          || { echo "forge reports parent $t MR target '$mtgt', not the claimed '$into' — landing not corroborated" >&2; return 1; }
      fi
      ;;
  esac
  case "$kind" in
    merge|ff|fast-forward)
      [ -z "$mstate" ] || [ "$mstate" = "merged" ] || { echo "forge reports parent $t MR state '$mstate', not merged" >&2; return 1; }
      git -C "$rd" rev-parse --verify "origin/$into" >/dev/null 2>&1 \
        || { echo "destination branch '$into' is not published on origin (fetched) — a local-only ref cannot prove a landing" >&2; return 1; }
      ref="origin/$into"
      git -C "$rd" merge-base --is-ancestor "$vh" "$ref" 2>/dev/null \
        || { echo "parent $t verified commit ${vh:0:8} is NOT an ancestor of '$ref' — landing not proven" >&2; return 1; }
      if [ -n "$msha" ] && [ "$msha" != "-" ]; then
        git -C "$rd" merge-base --is-ancestor "$msha" "$ref" 2>/dev/null \
          || { echo "merge commit ${msha:0:8} is not an ancestor of '$ref'" >&2; return 1; }
      fi
      ;;
    squash|rebase)
      [ "$mstate" = "merged" ] || { echo "squash/rebase landing needs the forge to report parent $t merged (got '${mstate:-unknown}')" >&2; return 1; }
      git -C "$rd" rev-parse --verify "origin/$into" >/dev/null 2>&1 \
        || { echo "destination branch '$into' is not published on origin (fetched)" >&2; return 1; }
      ;;
    closed)
      [ "$mstate" = "closed" ] || { echo "closed landing needs the forge to report parent $t MR closed (got '${mstate:-unknown}')" >&2; return 1; }
      ;;
    *) echo "cannot verify landing kind '$kind'" >&2; return 1 ;;
  esac
  return 0
}

# _stack_promote_verdict <slug> <d> <t> — promote|<target> / noop|<target> / block|<reason>.
_stack_promote_verdict() {
  local slug="$1" d="$2" t="$3"
  local base; base="$(_stack_base_of "$d" "$t")"
  local cur landed li kind saw_landed=0
  while IFS= read -r cur; do
    [ -n "$cur" ] || continue
    landed="$(pw_stack_state_get "$d" "$cur" landed)"
    [ "$landed" = "yes" ] || continue
    saw_landed=1
    li="$(pw_stack_state_get "$d" "$cur" landed_into)"
    kind="${li%%:*}"
    case "$kind" in
      merge|ff|fast-forward) : ;;
      squash|rebase) echo "block|parent $cur landed via $kind — ancestry/content not provable; explicit restack approval + --force-with-lease required"; return 1 ;;
      closed) echo "block|parent $cur closed without merge — owner decision required before promoting children"; return 1 ;;
      ""|unknown) echo "block|parent $cur landing kind unknown — re-observe the forge merge state before promotion"; return 1 ;;
      *) echo "block|parent $cur landing kind '$kind' unrecognized"; return 1 ;;
    esac
  done <<EOF
$(pw_stack_chain "$d" "$t" 2>/dev/null || true)
EOF
  local target recorded
  target="$(pw_stack_effective_target "$d" "$t" "$base")" \
    || { echo "block|cannot resolve the effective target for $t (unprovable landing destination or missing ancestor Branch) → fix: /pw-doctor --project $slug"; return 1; }
  case "$target" in ''|*[!A-Za-z0-9._/-]*|-*) echo "block|effective target '$target' is not a safe branch name → fix: correct the task Branch/base fields"; return 1 ;; esac
  recorded="$(pw_stack_state_get "$d" "$t" target)"
  if [ "$saw_landed" = 0 ]; then echo "noop|$target"; return 0; fi
  [ -n "$recorded" ] || { echo "block|child $t has no recorded target — ship or adopt it before promotion"; return 1; }
  if [ "$recorded" = "$target" ]; then echo "noop|$target"; return 0; fi
  # Promotion is a forge write: verify the destination against just-fetched refs — never a
  # local-only branch or a stale origin ref (retargeting an MR onto something unpublished would
  # point it at nothing).
  local rrepo rd
  rrepo="$(_stack_repo_of "$d" "$t")"; rd="$REPOS_DIR/$rrepo"
  [ -d "$rd" ] || { echo "block|repo '$rrepo' not found for $t → fix: mount the task repo before promoting"; return 1; }
  git -C "$rd" fetch -q --prune origin 2>/dev/null \
    || { echo "block|cannot refresh origin in $rrepo before promotion → fix: network/auth, then retry"; return 1; }
  git -C "$rd" rev-parse --verify "origin/$target" >/dev/null 2>&1 \
    || { echo "block|promotion target '$target' is not published on origin → fix: settle/publish '$target' first"; return 1; }
  echo "promote|$target"; return 0
}

# stack-validate <slug> — fail-closed topology check: no cycle, known same-repo parent, one
# ultimate destination, distinct branches, parent present in depends_on.
cmd_stack_validate() {
  [ $# -eq 1 ] || die "usage: stack-validate <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local bad=0 f t p pf repo base prepo pbase cycle deps
  cycle="$(pw_stack_cycle "$d" 2>/dev/null || true)"
  if [ -n "$cycle" ]; then
    echo "pw-ship stack-validate: stack cycle involving $cycle → fix: break the 'Stacked on:' loop in the task files" >&2
    bad=1
  fi
  for f in "$d"/task/T*.md; do
    [ -f "$f" ] || continue
    t="$(basename "$f" .md)"; p="$(pw_stack_parent "$f")"
    [ -n "$p" ] || continue
    pf="$d/task/$p.md"
    repo="$(pw_field "$f" Repo 2>/dev/null || true)"
    base="$(pw_field "$f" 'Base branch' 2>/dev/null || true)"; base="${base%%[[:space:]]*}"
    if [ ! -f "$pf" ]; then
      echo "pw-ship stack-validate: $t stacks on unknown task $p → fix: correct the 'Stacked on:' field in task/$t.md" >&2; bad=1; continue
    fi
    prepo="$(pw_field "$pf" Repo 2>/dev/null || true)"
    [ "$prepo" = "$repo" ] || { echo "pw-ship stack-validate: $t (repo $repo) stacks on $p (repo $prepo) — branches do not span repositories → fix: use depends_on for the cross-repo prerequisite" >&2; bad=1; }
    pbase="$(pw_field "$pf" 'Base branch' 2>/dev/null || true)"; pbase="${pbase%%[[:space:]]*}"
    [ "$pbase" = "$base" ] || { echo "pw-ship stack-validate: $t base '$base' and parent $p base '$pbase' differ → fix: stack members need one ultimate destination" >&2; bad=1; }
    [ "$(pw_field "$f" Branch 2>/dev/null || true)" != "$(pw_field "$pf" Branch 2>/dev/null || true)" ] \
      || { echo "pw-ship stack-validate: $t and $p share a branch — one publication unit cannot stack on itself" >&2; bad=1; }
    deps="$(pw_field "$f" depends_on 2>/dev/null || true)"
    _pw_deps_has "$deps" "$p" || { echo "pw-ship stack-validate: $t stacks on $p but $p is not in depends_on → fix: add $p to the task's depends_on field" >&2; bad=1; }
  done
  [ "$bad" = 0 ] && { echo "$slug: stack topology valid"; return 0; }
  return 1
}

# stack <slug> — read-only topology + health preview. One row per stack task:
#   task|parent|target|branch|base|landed|freshness|debt
# plus a root-first line and any warnings. Never writes.
cmd_stack() {
  [ $# -eq 1 ] || die "usage: stack <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before reading the stack"
  local tasks; tasks="$(_stack_tasks "$d")"
  if [ -z "$tasks" ]; then
    echo "$slug: no stacks (every task independent — absence is legacy independent behavior)"
    return 0
  fi
  echo "task|parent|target|branch|base|landed|freshness|debt"
  local t p br base landed fresh debt target stale_n=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    p="$(pw_stack_parent_id "$d" "$t")"
    br="$(pw_field "$d/task/$t.md" Branch 2>/dev/null || true)"; br="${br//\`/}"; br="${br%%[[:space:]]*}"
    base="$(pw_field "$d/task/$t.md" 'Base branch' 2>/dev/null || true)"; base="${base%%[[:space:]]*}"
    [ -n "$base" ] || base="master"
    landed="$(pw_stack_state_get "$d" "$t" landed)"; [ -n "$landed" ] || landed="no"
    # Freshness is derived from CURRENT reality (tuple comparison); a never-started task with no
    # tuple reads "unverified" (it must bind before its own publication) while true freshness debt
    # reads "stale". _stack_stale itself stays the strict execution gate.
    fresh="$(_stack_preview_freshness "$d" "$t")"
    [ "$fresh" = "stale" ] && stale_n=$((stale_n+1))
    debt="$(awk -F'\t' -v t="$t" 'NR>1 && $3==t && $8!="done" {c++} END{print c+0}' "$d/task/stack-ops.tsv" 2>/dev/null || true)"; [ -n "$debt" ] || debt=0
    target="$(pw_stack_effective_target "$d" "$t" "$base" 2>/dev/null || true)"; [ -n "$target" ] || target="BLOCKED"
    echo "$t|$p|$target|$br|$base|$landed|$fresh|$debt"
  done <<EOF
$tasks
EOF
  local cyc; cyc="$(pw_stack_cycle "$d" 2>/dev/null || true)"
  [ -z "$cyc" ] || echo "WARN: stack cycle involving $cyc"
  [ "$stale_n" -le 0 ] || echo "WARN: $stale_n stack task(s) stale — freshness debt blocks execution/ship/close until the tuple is re-verified"
  return 0
}

# stack-plan <slug> [task-ids…] — the root-first publication order with effective targets and
# readiness. One line: task|repo|branch|target|parent|ready|reason. A stacked child is ready only
# when its target branch already exists on origin (parent published first). No ids = every task.
cmd_stack_plan() {
  [ $# -ge 1 ] || die "usage: stack-plan <slug> [task-ids…]"
  local slug="$1"; shift
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before planning"
  local sel=""
  if [ $# -gt 0 ]; then
    local id; for id in "$@"; do pw_task_id_ok "$id" && sel="$sel$id
"; done
  elif [ -f "$d/task/PLAN.md" ]; then
    local t _s; while IFS='|' read -r t _s; do [ -n "$t" ] && sel="$sel$t
"; done < <(pw_plan_pairs "$d/task/PLAN.md")
  else
    local t; while IFS= read -r t; do [ -n "$t" ] && sel="$sel$t
"; done <<EOF
$(_stack_tasks "$d")
EOF
  fi
  [ -n "$sel" ] || { echo "$slug: no tasks to plan"; return 0; }
  # order root-first: depth (stack ancestors) then id
  local tmpo; tmpo="$(mktemp)"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf '%s\t%s\n' "$(_stack_depth "$d" "$t")" "$t"
  done <<EOF > "$tmpo"
$sel
EOF
  local ordered; ordered="$(sort -n -k1,1 -k2,2 "$tmpo")"; rm -f "$tmpo"
  local repo br base target parent ready reason
  while IFS='	' read -r _depth t; do
    [ -n "$t" ] || continue
    repo="$(pw_field "$d/task/$t.md" Repo 2>/dev/null || true)"
    br="$(pw_field "$d/task/$t.md" Branch 2>/dev/null || true)"; br="${br//\`/}"; br="${br%%[[:space:]]*}"
    base="$(pw_field "$d/task/$t.md" 'Base branch' 2>/dev/null || true)"; base="${base%%[[:space:]]*}"
    [ -n "$base" ] || base="master"
    parent="$(pw_stack_parent_id "$d" "$t")"
    target="$(pw_stack_effective_target "$d" "$t" "$base" 2>/dev/null || true)"
    ready="yes"; reason=""
    local _pf; _pf="$(_stack_preview_freshness "$d" "$t")"
    if [ -z "$target" ]; then
      target="BLOCKED"; ready="no"; reason="effective target unresolved (unprovable landing or missing ancestor Branch) — /pw-doctor --project $slug"
    elif [ "$_pf" = "stale" ]; then
      ready="no"; reason="stale verification tuple — re-verify before publishing"
    elif [ "$_pf" = "unverified" ]; then
      ready="no"; reason="not verified yet — execute + verify before publishing its own work"
    elif [ -n "$parent" ] && [ "$target" != "$base" ]; then
      if ! git -C "$REPOS_DIR/$repo" rev-parse --verify "origin/$target" >/dev/null 2>&1; then
        ready="no"; reason="parent '$target' not published on origin — publish the parent first"
      fi
    fi
    echo "$t|$repo|$br|$target|$parent|$ready|$reason"
  done <<EOF
$ordered
EOF
  return 0
}

# stack-record <slug> <task-id> <col=value>… — write the ship-owned binding/state row. Verification
# columns are REFUSED: only stack-verify may bind them (after a real `## Verify`), so no caller can
# certify unverified data through this generic setter.
cmd_stack_record() {
  [ $# -ge 3 ] || die "usage: stack-record <slug> <task-id> <col=value>…"
  local slug="$1" t="$2"; shift 2
  pw_task_id_ok "$t" || die "invalid task id: $t"
  local d; d="$(proj_dir "$slug")"
  local kv c
  for kv in "$@"; do
    c="${kv%%=*}"
    case "$c" in
      verified_head|verified_parent|verified_target|verified_at|verified_evidence|freshness|ci_sha|ci_target|landed|landed_into)
        die "stack-record cannot set '$c' → fix: bind verification with stack-verify (after ## Verify) and observe landing with stack-land (after proof); no unverified/guessed state is accepted";;
    esac
  done
  pw_stack_state_upsert "$d" "$t" "$@" || die "stack-record failed → fix: check the column names (see pw-common.sh PW_STACK_COLS)"
  echo "$slug: stack state recorded for $t"
}

# stack-verify <slug> <task-id> <evidence-path> [--head <sha>] [--ci-sha <sha|pending|skipped|failed|unknown>] [--ci-target <branch>]
# Deterministic verification binding. Run AFTER the task's real `## Verify` passes: binds the current
# child head + consumed parent verified commit + effective target + evidence path/time, so freshness
# is a live tuple comparison, not a manual flag. Refuses when the parent is unverified or its commit
# is absent from the child branch (integration must happen first). The whole tuple — including the
# CI disposition — is written in ONE atomic record write; nothing here is best-effort.
cmd_stack_verify() {
  [ $# -ge 3 ] || die "usage: stack-verify <slug> <task-id> <evidence-path> [--head <sha>] [--ci-sha <sha>] [--ci-target <branch>]"
  local slug="$1" t="$2" ev="$3"; shift 3
  pw_task_id_ok "$t" || die "invalid task id: $t"
  [ -f "$ev" ] || die "evidence path not found: $ev → fix: run the task's ## Verify and pass its captured output file"
  [ -s "$ev" ] || die "evidence path is empty: $ev → fix: capture the real Verify output (an empty file proves nothing)"
  [ -n "$(tr -d '[:space:]' < "$ev" 2>/dev/null || true)" ] \
    || die "evidence file has no content beyond whitespace: $ev → fix: capture the real Verify output"
  local head="" ci_sha="" ci_target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --head) head="${2:-}"; shift 2 ;;
      --ci-sha) ci_sha="${2:-}"; shift 2 ;;
      --ci-target) ci_target="${2:-}"; shift 2 ;;
      *) die "unknown stack-verify arg '$1'" ;;
    esac
  done
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before binding a verification"
  local repo branch base; repo="$(_stack_repo_of "$d" "$t")"; branch="$(_stack_branch_of "$d" "$t")"; base="$(_stack_base_of "$d" "$t")"
  [ -n "$repo" ] && [ -n "$branch" ] || die "task $t needs Repo/Branch fields to bind a verification"
  local rd="$REPOS_DIR/$repo"; [ -d "$rd" ] || die "repo not found: $rd"
  local cur_head; cur_head="$(git -C "$rd" rev-parse "$branch" 2>/dev/null || true)"
  [ -n "$cur_head" ] || die "cannot resolve branch '$branch' in $repo → fix: ensure the task branch exists locally"
  if [ -n "$head" ] && [ "$head" != "$cur_head" ]; then
    die "stack-verify --head $head does not match the current $branch head ${cur_head:0:12} → fix: re-run after the branch is at the verified commit"
  fi
  local parent_task vp=""
  parent_task="$(pw_stack_parent_id "$d" "$t")"
  if [ -n "$parent_task" ]; then
    vp="$(pw_stack_state_get "$d" "$parent_task" verified_head 2>/dev/null || true)"
    [ -n "$vp" ] || die "parent $parent_task has no verification binding → fix: run pw-ship.sh stack-verify for $parent_task after its ## Verify (execute the parent first)"
    git -C "$rd" merge-base --is-ancestor "$vp" "$branch" 2>/dev/null \
      || die "branch $branch does not contain parent $parent_task's verified commit ${vp:0:12} → fix: /pw-sync $slug $t (integrate the updated parent) before binding"
  fi
  local target; target="$(pw_stack_effective_target "$d" "$t" "$base")" \
    || die "cannot resolve the effective target for $t → fix: check the stack topology (/pw-doctor --project $slug)"
  [ -n "$target" ] || die "cannot resolve the effective target for $t"
  local at; at="$(pw_now_wib)" || die "cannot format the WIB timestamp (pw_now_wib failed) → fix: check the shared date formatter before binding a verification"
  # CI disposition: explicit values only. A valid same-tuple result is preserved when no --ci-sha is
  # supplied; anything else becomes the EXPLICIT pending marker — a target/head change must never
  # keep an old green silently, and 'pending' is visibly distinct from success.
  local cs_prev ct_prev
  cs_prev="$(pw_stack_state_get "$d" "$t" ci_sha)"
  ct_prev="$(pw_stack_state_get "$d" "$t" ci_target)"
  if [ -z "$ci_sha" ]; then
    if [ -n "$cs_prev" ] && [ "$ct_prev" = "$target" ] && [ "$cs_prev" = "$cur_head" ]; then
      ci_sha="$cs_prev"
    else
      ci_sha="pending"
    fi
  fi
  case "$ci_sha" in
    pending|skipped|failed|unknown) : ;;
    *) printf '%s' "$ci_sha" | grep -Eq '^[0-9a-fA-F]{7,64}$' || die "invalid --ci-sha '$ci_sha' → fix: a git sha, or pending|skipped|failed|unknown" ;;
  esac
  [ -n "$ci_target" ] || ci_target="$target"
  case "$ci_target" in ''|*[!A-Za-z0-9._/-]*|-*) die "invalid --ci-target '$ci_target'";; esac
  pw_stack_state_upsert "$d" "$t" \
    verified_head="$cur_head" head_sha="$cur_head" \
    verified_parent="$vp" consumed_parent_sha="${vp:-}" \
    verified_target="$target" target="$target" freshness=fresh \
    verified_at="$at" verified_evidence="$ev" \
    ci_sha="$ci_sha" ci_target="$ci_target" \
    || die "stack verification binding failed"
  echo "$slug: $t verified at ${cur_head:0:12} (parent ${vp:0:8}, target $target, ci ${ci_sha}@${ci_target}, evidence $ev)"
}

# stack-fresh / stack-stale <slug> <task-id> — explicit debt toggle (force stale, or clear the flag).
# The flag alone never certifies: _stack_stale still compares the recorded tuple against live Git.
cmd_stack_freshness() {
  [ $# -eq 3 ] || die "usage: stack-fresh|stack-stale <slug> <task-id>"
  local slug="$1" t="$2" val="$3"
  [ -n "$t" ] || die "usage: stack-fresh|stack-stale <slug> <task-id>"
  pw_task_id_ok "$t" || die "invalid task id: $t"
  case "$val" in fresh|stale) : ;; *) die "unknown freshness '$val'" ;; esac
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_upsert "$d" "$t" freshness="$val" || die "stack freshness write failed"
  echo "$slug: $t freshness -> $val"
}

# stack-land <slug> <task-id> <merge_sha|-> <landed_into> [merge|ff|squash|rebase|closed|unknown]
# Observe AND VERIFY a parent's landing before promoting children: merge/ff is proven by real Git
# ancestry into the destination branch; squash/rebase/closed require corroborating forge MR state.
# Stored as "<kind>:<branch>"; an unprovable/unknown landing is refused (landed=yes is never trusted).
cmd_stack_land() {
  [ $# -ge 4 ] || die "usage: stack-land <slug> <task-id> <merge_sha|-> <landed_into> [kind]"
  local slug="$1" t="$2" msha="$3" into="$4" kind="${5:-merge}"
  pw_task_id_ok "$t" || die "invalid task id: $t"
  case "$kind" in merge|ff|fast-forward|squash|rebase|closed|unknown) : ;; *) die "unknown landing kind '$kind' → fix: one of merge|ff|squash|rebase|closed|unknown" ;; esac
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before recording a landing"
  { [ -n "$into" ] && [ "$into" != "-" ]; } || die "stack-land: <landed_into> branch is required → fix: name the branch the MR merged into"
  case "$into" in *[!A-Za-z0-9._/-]*) die "stack-land: invalid destination branch '$into'" ;; esac
  _stack_verify_landing "$slug" "$d" "$t" "$msha" "$into" "$kind" \
    || die "stack-land: landing for $t NOT proven (no record written) → fix: observe the real forge MR state + destination branch before promoting children"
  # Retain the parent's verified tip as a recovery ref BEFORE recording the landing: after the
  # source branch is deleted its commits can become unreachable, and promotion/recovery must still
  # resolve the proof. The ref is never deleted automatically.
  local rrepo rd vh
  rrepo="$(_stack_repo_of "$d" "$t")"; rd="$REPOS_DIR/$rrepo"
  vh="$(pw_stack_state_get "$d" "$t" verified_head 2>/dev/null || true)"
  if [ -n "$rrepo" ] && [ -d "$rd" ] && [ -n "$vh" ]; then
    git -C "$rd" update-ref "refs/pw-stack-landed/$(basename "$d")/$t" "$vh" \
      || die "stack-land: landing proven but the recovery ref could not be retained → fix: check repo permissions for $rd"
  fi
  pw_stack_state_upsert "$d" "$t" landed=yes landed_into="$kind:$into" || die "stack-land failed"
  if [ -n "$msha" ] && [ "$msha" != "-" ]; then
    pw_stack_state_upsert "$d" "$t" head_sha="$msha" \
      || die "stack-land: could not record the merge head (landing already recorded; re-run stack-land to repair)"
  fi
  echo "$slug: $t landed ($kind into $into, verified)"
}

# stack-promote <slug> <task-id> — post-landing verdict: promote|<target> / noop / block|<reason>.
cmd_stack_promote() {
  [ $# -eq 2 ] || die "usage: stack-promote <slug> <task-id>"
  local slug="$1" t="$2"; pw_task_id_ok "$t" || die "invalid task id: $t"
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before promotion"
  _stack_promote_verdict "$slug" "$d" "$t"
}

# stack-retarget <slug> <task-id> [--apply] — publish a promoted child's MR to its updated effective
# target via the forge. Default is a dry-run preview; --apply is the explicit publication
# authorization. Robust persistence (plan 35 rev 2): the pending recovery row is written FIRST and
# the forge write only happens after a fresh fetch + destination/state/head inspection; the observed
# target and head are read back after the write; local state/dashboard/mirror failures FAIL LOUD and
# keep the row pending, so a remote success with a broken local mirror resumes without a second
# forge write (the observed target already equals the desired one → safe no-op retry).
cmd_stack_retarget() {
  [ $# -ge 2 ] || die "usage: stack-retarget <slug> <task-id> [--apply]"
  local slug="$1" t="$2"; shift 2
  local apply=0
  while [ $# -gt 0 ]; do case "$1" in --apply) apply=1; shift ;; *) die "unknown stack-retarget arg '$1'" ;; esac; done
  pw_task_id_ok "$t" || die "invalid task id: $t"
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before retargeting"
  # Pending-operation recovery FIRST (plan 35): resume a retained row before any noop shortcut, so a
  # remote success with an unfinished local mirror can never be lost behind a suddenly-"noop" verdict.
  local opkey="retarget:$t" opstate="" optarget="" havep=0
  if [ -f "$d/task/stack-ops.tsv" ]; then
    opstate="$(awk -F'\t' -v k="$opkey" '$1==k{print $8; exit}' "$d/task/stack-ops.tsv" 2>/dev/null || true)"
    optarget="$(awk -F'\t' -v k="$opkey" '$1==k{print $5; exit}' "$d/task/stack-ops.tsv" 2>/dev/null || true)"
    if [ -n "$opstate" ] && [ "$opstate" != "done" ]; then havep=1; fi
  fi
  local verdict; verdict="$(_stack_promote_verdict "$slug" "$d" "$t")" || { echo "$verdict"; return 1; }
  local target=""
  case "$verdict" in
    promote\|*) target="${verdict#promote|}" ;;
    noop\|*)
      if [ "$havep" = 1 ]; then
        target="$optarget"; [ -n "$target" ] && [ "$target" != "-" ] || target="$(pw_stack_state_get "$d" "$t" target)"
        [ -n "$target" ] || die "stack-retarget: pending recovery row has no expected target → fix: inspect task/stack-ops.tsv"
        echo "stack-retarget: resuming the pending retarget for $t (desired target $target)" >&2
      else
        echo "$verdict"; return 0
      fi ;;
    *) echo "$verdict"; return 1 ;;
  esac
  [ -n "$target" ] || die "stack-retarget: empty target"
  case "$target" in ''|*[!A-Za-z0-9._/-]*|-*) die "stack-retarget: unsafe target branch '$target'";; esac
  if [ "$apply" != 1 ]; then
    if [ "$havep" = 1 ]; then
      echo "retarget-recovery-pending|$target (an earlier attempt is unfinished; re-run with --apply to finish the local mirror — the forge write is not repeated)"
      return 1
    fi
    echo "retarget-preview|$target (re-run with --apply to publish the retarget)"
    return 0
  fi
  local mr; mr="$(pw_task_mr_url "$d/task/$t.md" 2>/dev/null || true)"
  case "$mr" in http*) : ;; *) die "stack-retarget: no MR URL for $t → fix: /pw-ship $slug $t first" ;; esac
  local repo_dir; repo_dir="$(_stack_task_repo_dir "$d" "$t")"
  [ -n "$repo_dir" ] || die "stack-retarget: no worktree for $t → fix: /pw-execute $slug $t"
  local host forge iid; host="$(_stack_host_of "$repo_dir")"; forge="$(_stack_forge_of "$host")"; iid="$(_stack_mr_iid "$forge" "$mr")"
  [ -n "$iid" ] || die "stack-retarget: cannot parse the MR id from $mr"
  # Fresh refs + published destination BEFORE any forge write: retargeting onto a branch origin does
  # not have (or onto a stale view of it) is how an MR ends up pointing at nothing.
  git -C "$repo_dir" fetch -q --prune origin \
    || die "stack-retarget: git fetch origin failed in $repo_dir → fix: network/auth before retargeting"
  git -C "$repo_dir" rev-parse --verify "origin/$target" >/dev/null 2>&1 \
    || die "stack-retarget: destination '$target' is not published on origin → fix: settle/publish the promotion target before retargeting children"
  if [ "$havep" = 0 ]; then
    cmd_stack_op "$slug" create "$opkey" promote "$t" "retarget" "retarget=pending" "$target" >/dev/null \
      || die "stack-retarget: could not record the pending recovery row → fix: repair task/stack-ops.tsv (nothing was written to the forge)"
  fi
  local view st_before tg_before head_before
  view="$(_stack_mr_view "$mr" "$repo_dir")" \
    || die "stack-retarget: cannot read the current MR state from the forge (recovery row retained pending) → fix: forge auth/connectivity, then re-run --apply"
  st_before="${view%%|*}"; tg_before="${view#*|}"; tg_before="${tg_before%%|*}"; head_before="${view##*|}"
  case "$st_before" in
    open) : ;;
    *) die "stack-retarget: the MR for $t is '$st_before', not open → fix: reconcile the MR state first (recovery row retained pending)";;
  esac
  if [ "$tg_before" != "$target" ]; then
    local ok=0 out=""
    if [ "$forge" = github ]; then
      out="$( cd "$repo_dir" && gh pr edit "$iid" --base "$target" 2>&1 )" && ok=1 || ok=0
    else
      out="$( cd "$repo_dir" && GITLAB_HOST="$host" glab mr update "$iid" --target-branch "$target" 2>&1 )" && ok=1 || ok=0
    fi
    [ "$ok" = 1 ] || die "stack-retarget: forge retarget failed for $t (recovery row retained pending) → $(printf '%s' "$out" | head -1)"
  fi
  # Read back target AND head: the MR's head must not move underneath the retarget (an external push
  # during the write invalidates the plan — re-preview instead of claiming success).
  local view2 st_after tg_after head_after
  view2="$(_stack_mr_view "$mr" "$repo_dir")" \
    || die "stack-retarget: forge retarget write happened but the readback failed (recovery row retained pending) → fix: forge auth/connectivity, then re-run --apply (no duplicate write)"
  st_after="${view2%%|*}"; tg_after="${view2#*|}"; tg_after="${tg_after%%|*}"; head_after="${view2##*|}"
  [ "$tg_after" = "$target" ] \
    || die "stack-retarget: forge did not report the new target (want $target, got ${tg_after:-none}) — an external change raced the write (recovery row retained pending)"
  [ "$head_after" = "$head_before" ] \
    || die "stack-retarget: MR head moved during the retarget ($head_before → $head_after) — external update; re-preview before continuing (recovery row retained pending)"
  case "$st_after" in
    open|merged) : ;;
    *) die "stack-retarget: MR state changed during the retarget ($st_before → $st_after) — reconcile before continuing (recovery row retained pending)";;
  esac
  # Local state + mirrors: no suppression — a remote success with a local failure stays visible
  # pending debt and re-running completes it WITHOUT another forge write.
  pw_stack_state_upsert "$d" "$t" target="$target" \
    || die "stack-retarget: published on the forge but the local state write failed → fix: re-run /pw-ship $slug stack-retarget $t --apply to finish the local mirror (no duplicate forge write)"
  _dashboard_update "$d/README.md" 'Task' 'Target branch' "$t" "$target" >/dev/null 2>&1 \
    || die "stack-retarget: published on the forge but the dashboard mirror failed → fix: re-run stack-retarget --apply (idempotent; no duplicate forge write)"
  cmd_stack_op "$slug" set "$opkey" "retarget=done" >/dev/null \
    || die "stack-retarget: completed but the recovery row could not be marked done → fix: re-run stack-retarget --apply (idempotent)"
  echo "promote|$target"
  echo "$slug: $t MR retargeted to $target (head ${head_after:0:8}${tg_before:+; was $tg_before})"
}

# --- pending operations (recovery) --------------------------------------------
# task/stack-ops.tsv: key kind ancestor event expected created stages state. `stages` is
# "<stage>=<done|pending|skipped>;…"; state = pending while any stage is pending, else done.
_command_stack_op_file() { printf '%s/task/stack-ops.tsv' "$1"; }
_op_state_of() {  # <stages> -> pending|done|blocked
  local s="$1"
  case "$s" in *blocked*) printf 'blocked'; return 0 ;; esac
  case "$s" in *pending*) printf 'pending' ;; *) printf 'done' ;; esac
}
_stack_op_validate() { awk -F'\t' 'NR>1 && NF>0 && NF!=8{bad=1} END{exit bad}' "$1"; }

# _stack_ops_validate <file> — header/schema gate for task/stack-ops.tsv before recovery state is
# read or rewritten (a drifted row would shift the stages/state columns the gates depend on).
_STACK_OPS_HDR="key${_pw_stack_tab}kind${_pw_stack_tab}ancestor${_pw_stack_tab}event${_pw_stack_tab}expected${_pw_stack_tab}created${_pw_stack_tab}stages${_pw_stack_tab}state"
_stack_ops_validate() {
  local f="$1"
  [ -e "$f" ] || return 0
  [ -L "$f" ] && { echo "stack-op: refusing to read through a symlink $f" >&2; return 1; }
  [ -f "$f" ] || { echo "stack-op: not a regular file: $f → fix: repair task/stack-ops.tsv (machine-owned)" >&2; return 1; }
  [ "$(sed -n '1p' "$f" 2>/dev/null || true)" = "$_STACK_OPS_HDR" ] \
    || { echo "stack-op: unsupported header in $f → fix: restore task/stack-ops.tsv (never hand-edit the columns)" >&2; return 1; }
  _stack_op_validate "$f" || { echo "stack-op: malformed row(s) in $f (field count) → fix: repair the record before resuming recovery" >&2; return 1; }
  return 0
}

cmd_stack_op() {
  [ $# -ge 2 ] || die "usage: stack-op <slug> <list|create|set|clear> [args…]"
  local slug="$1" sub="$2"; shift 2
  local d; d="$(proj_dir "$slug")"; local f; f="$(_command_stack_op_file "$d")"
  _stack_ops_validate "$f" || die "stack ops record invalid (see the reason above) → fix: repair task/stack-ops.tsv before list/create/set/clear"
  local hdr='key	kind	ancestor	event	expected	created	stages	state'
  case "$sub" in
    list)
      local key="${1:-}"
      [ -f "$f" ] || { echo "no pending stack operations"; return 0; }
      if [ -n "$key" ]; then awk -F'\t' -v k="$key" 'NR>1 && $1==k' "$f"; else awk 'NR>1' "$f"; fi
      ;;
    create)
      [ $# -ge 5 ] || die "usage: stack-op <slug> create <key> <kind> <ancestor> <event> <stages> [expected]"
      local key="$1" kind="$2" anc="$3" ev="$4" stages="$5" expected="${6:--}"
      case "$kind" in cascade|sync|promote|adopt) : ;; *) die "unknown op kind '$kind' → fix: cascade|sync|promote|adopt" ;; esac
      pw_task_id_ok "$anc" || die "invalid ancestor task id: $anc"
      _stack_val_bad "$key" && die "stack-op create: key has a reserved character (pipe/TAB/newline)"
      case "$key" in *[!A-Za-z0-9._:-]*) die "stack-op create: key '$key' has unsupported characters → fix: letters/digits/._:- only";; esac
      _stack_val_bad "$ev" && die "stack-op create: event has a reserved character (pipe/TAB/newline)"
      _stack_val_bad "$stages" && die "stack-op create: stages have a reserved character (pipe/TAB/newline)"
      _stack_val_bad "$expected" && die "stack-op create: expected has a reserved character (pipe/TAB/newline)"
      mkdir -p "$d/task"
      pw_path_within "$d" "$f" || die "stack-op: refusing to write outside $d"
      [ -L "$f" ] && die "stack-op: refusing to write through symlink $f"
      local ld="$f.lock" tmp
      pw_lock "$ld" || die "stack-op: could not acquire $ld (another writer active)"
      [ -f "$f" ] || printf '%s\n' "$hdr" > "$f"
      local ts st; ts="$(pw_now_wib 2>/dev/null || date '+%Y-%m-%d %H:%M')"; st="$(_op_state_of "$stages")"
      tmp="$(pw_tmpfile "$d/task")"
      # Every field is non-empty (`-` placeholder for expected): shell `read` treats a TAB as
      # IFS whitespace and drops empty fields, which would shift the stages/state columns.
      awk -F'\t' -v k="$key" -v kind="$kind" -v anc="$anc" -v ev="$ev" -v expv="$expected" -v ts="$ts" -v stages="$stages" -v st="$st" '
        BEGIN{ w = k "\t" kind "\t" anc "\t" ev "\t" expv "\t" ts "\t" stages "\t" st }
        NR==1{print; if ($1==k) { print w; found=1 } ; next}
        $1==k { if (!found) { print w; found=1 } ; next }
        { print }
        END{ if (!found) print w }' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op create: rewrite failed"; }
      _stack_op_validate "$tmp" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op create: refusing a malformed row (field-count mismatch)"; }
      mv "$tmp" "$f" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op create: install failed"; }
      pw_unlock "$ld"
      echo "$slug: stack op $key ($st)"
      ;;
    set)
      [ $# -ge 2 ] || die "usage: stack-op <slug> set <key> <stage=state>[,…]"
      local key="$1" add="$2"
      [ -f "$f" ] || die "no stack ops recorded → fix: stack-op $slug create … first"
      _stack_val_bad "$key" && die "stack-op set: key has a reserved character (pipe/TAB/newline)"
      _stack_val_bad "$add" && die "stack-op set: stages have a reserved character (pipe/TAB/newline)"
      [ -L "$f" ] && die "stack-op: refusing to write through symlink $f"
      local ld="$f.lock" tmp
      pw_lock "$ld" || die "stack-op: could not acquire $ld (another writer active)"
      tmp="$(pw_tmpfile "$d/task")"
      awk -F'\t' -v k="$key" -v add="$add" '
        function newstages(s, a,   n, i, t, sep) {
          n = split(a, arr, ";")
          for (i = 1; i <= n; i++) {
            if (arr[i] == "") continue
            stage = arr[i]; sub(/=.*/, "", stage)
            sub(/^[^=]*=/, "", arr[i])
            sep = (s == "") ? "" : ";"
            if (index(s, stage "=") > 0) { sub(stage "=[^;]*", stage "=" arr[i], s) }
            else { s = s sep stage "=" arr[i] }
          }
          return s
        }
        BEGIN{ OFS="\t"; found=0 }
        NR==1{print; next}
        $1==k { ns = newstages($7, add); st = (ns ~ /blocked/) ? "blocked" : ((ns ~ /pending/) ? "pending" : "done");
                $7 = ns; $8 = st; print; found=1; next }
        { print }
        END{ if (!found) print "ERR: no stack op " k > "/dev/stderr" }' "$f" > "$tmp" 2>"$tmp.err" || true
      if [ -s "$tmp.err" ]; then cat "$tmp.err" >&2; rm -f "$tmp" "$tmp.err"; pw_unlock "$ld"; die "stack-op set: no op '$key' → fix: list the recorded ops first"; fi
      rm -f "$tmp.err"
      _stack_op_validate "$tmp" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op set: refusing a malformed row (field-count mismatch)"; }
      mv "$tmp" "$f" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op set: install failed"; }
      pw_unlock "$ld"
      echo "$slug: stack op $key stages updated"
      ;;
    clear)
      [ $# -ge 1 ] || die "usage: stack-op <slug> clear <key>"
      local key="$1"
      [ -f "$f" ] || { echo "no stack ops recorded"; return 0; }
      _stack_val_bad "$key" && die "stack-op clear: key has a reserved character (pipe/TAB/newline)"
      [ -L "$f" ] && die "stack-op: refusing to write through symlink $f"
      local ld="$f.lock" tmp
      pw_lock "$ld" || die "stack-op: could not acquire $ld (another writer active)"
      tmp="$(pw_tmpfile "$d/task")"
      awk -F'\t' -v k="$key" 'NR==1{print; next} $1!=k{print}' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op clear: rewrite failed"; }
      _stack_op_validate "$tmp" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op clear: refusing a malformed row (field-count mismatch)"; }
      mv "$tmp" "$f" || { rm -f "$tmp"; pw_unlock "$ld"; die "stack-op clear: install failed"; }
      pw_unlock "$ld"
      echo "$slug: stack op $key cleared"
      ;;
    *) die "unknown stack-op subcommand '$sub' → fix: list|create|set|clear" ;;
  esac
}

# stack-debt <slug> [task-ids…] — rc 1 + the pending ops when any operation touching the selected
# set (or its stack closure) is not done. The gate ship/comment/sync/close call before outward
# work, so a resumed run never duplicates a half-finished cascade.
cmd_stack_debt() {
  [ $# -ge 1 ] || die "usage: stack-debt <slug> [task-ids…]"
  local slug="$1"; shift
  local d; d="$(proj_dir "$slug")"; local f; f="$(_command_stack_op_file "$d")"
  [ -f "$f" ] || return 0
  _stack_ops_validate "$f" || die "stack ops record invalid (see the reason above) → fix: repair task/stack-ops.tsv before a debt check"
  local hits="" id matched
  local key kind anc event expected created stages state
  while IFS='	' read -r key kind anc event expected created stages state; do
    [ "$key" = "key" ] && continue
    [ -n "$key" ] || continue
    [ "$state" = "done" ] && continue
    if [ $# -gt 0 ]; then
      matched=0
      for id in "$@"; do [ "$id" = "$anc" ] && matched=1; done
      [ "$matched" = 1 ] || continue
    fi
    hits="$hits$key|$kind|$anc|$state|$stages
"
  done < "$f"
  if [ -n "$hits" ]; then
    printf 'pending stack operation(s) block outward work:\n%s' "$hits" >&2
    return 1
  fi
  return 0
}

# stack-adopt <slug> [--apply] [task-ids…] — read each open MR's actual target and infer the
# stack edge (target == another task's branch). Default is a DRY RUN (no writes); --apply imports
# only proven edges and normalizes the task's Base branch to the ultimate destination.
cmd_stack_adopt() {
  [ $# -ge 1 ] || die "usage: stack-adopt <slug> [--apply] [task-ids…]"
  local slug="$1"; shift
  local apply=0 id; local ids=""
  for id in "$@"; do case "$id" in --apply) apply=1 ;; T[0-9]*) ids="$ids $id" ;; *) die "unknown stack-adopt arg '$id'" ;; esac; done
  local d; d="$(proj_dir "$slug")"
  local sel
  if [ -n "$ids" ]; then
    sel="$(printf '%s\n' $ids)"
  elif [ -f "$d/task/PLAN.md" ]; then
    sel="$(while IFS='|' read -r t _s; do [ -n "$t" ] && printf '%s\n' "$t"; done < <(pw_plan_pairs "$d/task/PLAN.md"))"
  else
    sel="$(cd "$d/task" && ls T*.md 2>/dev/null | sed 's/\.md$//')"
  fi
  local t mr target parent branch base
  local changed=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    t="$(printf '%s' "$t" | pw_trim)"
    mr="$(pw_task_mr_url "$d/task/$t.md" 2>/dev/null || true)"; case "$mr" in http*) : ;; *) continue ;; esac
    target="$(_stack_mr_target "$slug" "$t" "$mr")" || continue
    [ -n "$target" ] || continue
    parent=""
    for branch in "$d"/task/T*.md; do
      [ -f "$branch" ] || continue
      b="$(pw_field "$branch" Branch 2>/dev/null || true)"; b="${b//\`/}"; b="${b%%[[:space:]]*}"
      [ "$b" = "$target" ] && { parent="$(basename "$branch" .md)"; break; }
    done
    [ -n "$parent" ] || continue
    [ "$parent" = "$t" ] && continue
    base="$(pw_field "$d/task/$t.md" 'Base branch' 2>/dev/null || true)"; base="${base%%[[:space:]]*}"
    echo "$t <- $parent (observed target $target; ultimate base ${base:-master})"
    changed=$((changed+1))
    if [ "$apply" = 1 ]; then
      if _stack_task_field_put "$d/task/$t.md" "Stacked on" "$parent"; then
        if [ -f "$d/task/PLAN.md" ]; then _plan_cell_update "$d/task/PLAN.md" "$t" stackedon "$parent" >/dev/null 2>&1 || true; fi
        # Import the edge only. Verification is NEVER fabricated by adoption: no verified_* or
        # freshness is written, so the task stays unverified until stack-verify runs after a real
        # `## Verify`. This blocks an adopted stack from shipping on a guessed binding (H2).
        pw_stack_state_upsert "$d" "$t" parent="$parent" branch="$(_stack_branch_of "$d" "$t")" base="${base:-master}" target="$target" >/dev/null 2>&1 || true
      else
        echo "pw-ship stack-adopt: could not write the Stacked on field for $t (no safe anchor) — edge not imported; PLAN mirror untouched" >&2
      fi
    fi
  done <<EOF
$sel
EOF
  if [ "$changed" = 0 ]; then echo "$slug: no adoptable MR targets (nothing to import)"; fi
  [ "$apply" = 0 ] && [ "$changed" -gt 0 ] && echo "$slug: preview only — re-run with --apply after confirming the inferred edges"
  return 0
}

# _stack_mr_view <mr-url> <repo-dir> — the forge's CURRENT view of one MR as state|target|head, or
# empty (rc 1) when the forge cannot report it. Host/forge resolution reuses the shipped registry
# rule (MR-URL host → PW_FORGE_HOSTS override, github.com default) exactly like mr-state/history, so
# every forge write is checked against the same identity the rest of ship uses.
_stack_mr_view() {
  local mrurl="$1" repo_dir="$2" host forge iid out st tg hd
  { [ -n "$mrurl" ] && [ -n "$repo_dir" ] && [ -d "$repo_dir" ]; } || return 1
  host="$(printf '%s' "$mrurl" | sed -E 's|^.*@||; s|^https?://||; s|[:/].*||')"
  [ -n "$host" ] || return 1
  forge="$(_stack_forge_of "$host")"
  if [ "$forge" = github ]; then
    iid="$(printf '%s' "$mrurl" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+$' || true)"
    [ -n "$iid" ] || return 1
    out="$( cd "$repo_dir" && gh pr view "$iid" --json state,baseRefName,headRefOid 2>/dev/null )" || return 1
    st="$(printf '%s' "$out" | sed -n 's/.*"state":"\([A-Za-z]*\)".*/\1/p' | head -1)"
    tg="$(printf '%s' "$out" | sed -n 's/.*"baseRefName":"\([^"]*\)".*/\1/p' | head -1)"
    hd="$(printf '%s' "$out" | sed -n 's/.*"headRefOid":"\([^"]*\)".*/\1/p' | head -1)"
    case "$st" in OPEN|open) st=open ;; MERGED|merged) st=merged ;; CLOSED|closed) st=closed ;; esac
  else
    iid="$(printf '%s' "$mrurl" | grep -oE '/-/merge_requests/[0-9]+' | grep -oE '[0-9]+$' || true)"
    [ -n "$iid" ] || return 1
    out="$( cd "$repo_dir" && GITLAB_HOST="$host" glab mr view "$iid" --output json 2>/dev/null )" || return 1
    st="$(printf '%s' "$out" | sed -n 's/.*"state":"\([A-Za-z]*\)".*/\1/p' | head -1)"
    tg="$(printf '%s' "$out" | sed -n 's/.*"target_branch":"\([^"]*\)".*/\1/p' | head -1)"
    hd="$(printf '%s' "$out" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p' | head -1)"
    case "$st" in opened|open) st=open ;; merged) st=merged ;; closed) st=closed ;; esac
  fi
  { [ -n "$st" ] && [ -n "$tg" ] && [ -n "$hd" ]; } || return 1
  printf '%s|%s|%s\n' "$st" "$tg" "$hd"
}

# _stack_mr_target <slug> <task> <mr-url> — the forge-reported target branch (offline shims
# included). Prints nothing (rc 1) when the forge can't report it, so adoption never invents an
# edge. Uses the same per-repo forge resolution as mr-state.
_stack_mr_target() {
  local slug="$1" t="$2" mrurl="$3" d; d="$(proj_dir "$slug")"
  local repo_dir view
  repo_dir="$(_stack_task_repo_dir "$d" "$t")" || return 1
  view="$(_stack_mr_view "$mrurl" "$repo_dir" 2>/dev/null || true)"
  [ -n "$view" ] || return 1
  view="${view#*|}"
  printf '%s\n' "${view%%|*}"
}

# _stack_task_field_put <taskfile> <field> <value> — upsert one bold machine bullet in place
# (deterministic entity-writer style; never hand-edit).
_stack_task_field_put() {
  local f="$1" field="$2" val="$3" tmp
  case "$val" in
    *"$_pw_stack_tab"*|*"$IFS_NL"*|*"|"*) echo "_stack_task_field_put: value has a reserved character (pipe/TAB/newline)" >&2; return 2 ;;
  esac
  [ -f "$f" ] || { echo "_stack_task_field_put: no such file $f" >&2; return 2; }
  tmp="$(mktemp "$(dirname "$f")/.pwtmp.XXXXXX" 2>/dev/null || printf '%s' "$f.pwtmp.$$")"
  if grep -qE "^- \*\*$field:\*\*" "$f"; then
    awk -v fld="$field" -v v="$val" '!d && $0 ~ ("^- \\*\\*" fld ":\\*\\*") { print "- **" fld ":** " v; d=1; next } {print}' "$f" > "$tmp" || { rm -f "$tmp"; return 2; }
  elif grep -qE "^- \*\*depends_on:\*\*" "$f"; then
    awk -v fld="$field" -v v="$val" '{print} /^- \*\*depends_on:\*\*/ && !d { print "- **" fld ":** " v; d=1 }' "$f" > "$tmp" || { rm -f "$tmp"; return 2; }
  elif grep -qE "^- \*\*Repo:\*\*" "$f"; then
    awk -v fld="$field" -v v="$val" '{print} /^- \*\*Repo:\*\*/ && !d { print "- **" fld ":** " v; d=1 }' "$f" > "$tmp" || { rm -f "$tmp"; return 2; }
  else
    rm -f "$tmp"; echo "_stack_task_field_put: no depends_on/Repo anchor in $f to insert '$field' safely" >&2; return 2
  fi
  mv "$tmp" "$f" || { rm -f "$tmp"; return 2; }
  return 0
}

# stack-inherited <slug> <task-id> <parent-id> <parent-sha> — deterministic inherited-update writer.
# Records that <task> absorbed <parent>'s upstream fix during a cascade: one keyed
# `- **Inherited:**` bullet in the task's ## Result plus a LOG line. It NEVER writes reviewer-comment
# text or replies — inherited evidence stays distinct from comment rounds (plan 33 history interop),
# so a descendant that received only an inherited update never shows a fabricated reviewer request.
cmd_stack_inherited() {
  [ $# -eq 4 ] || die "usage: stack-inherited <slug> <task-id> <parent-id> <parent-sha>"
  local slug="$1" t="$2" p="$3" sha="$4"
  pw_task_id_ok "$t" || die "invalid task id: $t"
  pw_task_id_ok "$p" || die "invalid parent task id: $p"
  printf '%s' "$sha" | grep -Eq '^[0-9a-fA-F]{7,64}$' || die "invalid parent sha '$sha' → fix: pass the parent's recorded verified head"
  local d; d="$(proj_dir "$slug")"
  local tf="$d/task/$t.md"; [ -f "$tf" ] || die "no task file: $tf"
  # Membership check on a captured chain (never a live `grep -q` pipe: under pipefail the early
  # exit can SIGPIPE the writer and fail a match that succeeded).
  local chain; chain="$(pw_stack_chain "$d" "$t" 2>/dev/null || true)"
  printf '%s\n' "$chain" | awk -v p="$p" '$0==p{found=1} END{exit !found}' \
    || die "$p is not a stack ancestor of $t → fix: pass an actual 'Stacked on:' ancestor (never invent an edge)"
  local short; short="$(printf '%s' "$sha" | cut -c1-12)"
  local bullet key; bullet="- **Inherited:** $p @ $short (upstream fix — inherited update, no reviewer request)"
  key="- **Inherited:** $p @"
  local tmp; tmp="$(mktemp "$(dirname "$tf")/.pwtmp.XXXXXX" 2>/dev/null || printf '%s' "$tf.pwtmp.$$")"
  if grep -qF -- "$key" "$tf"; then
    awk -v key="$key" -v line="$bullet" 'index($0, key) == 1 { print line; next } { print }' "$tf" > "$tmp" \
      || { rm -f "$tmp"; die "stack-inherited: rewrite failed for $tf"; }
  elif grep -q '^## Result' "$tf"; then
    awk -v line="$bullet" '{ print } /^## Result/ && !done { print line; done=1 }' "$tf" > "$tmp" \
      || { rm -f "$tmp"; die "stack-inherited: rewrite failed for $tf"; }
  else
    { cat "$tf"; printf '\n## Result\n\n%s\n' "$bullet"; } > "$tmp" \
      || { rm -f "$tmp"; die "stack-inherited: rewrite failed for $tf"; }
  fi
  mv "$tmp" "$tf" || { rm -f "$tmp"; die "stack-inherited: install failed for $tf"; }
  "$ST" log "$slug" ship "stack-inherited $t <- $p @ $short (inherited update; no reviewer request)" >/dev/null 2>&1 || true
  echo "$slug: $t inherited update from $p @ $short recorded"
}

# _op_stages_of <slug> <key> — the persisted stage list for one pending-operation row.
_op_stages_of() {
  local f; f="$(_command_stack_op_file "$(proj_dir "$1")")"
  awk -F'\t' -v k="$2" '$1==k{print $7; exit}' "$f" 2>/dev/null || true
}
# _stage_state <stages> <token> — "done" | "pending" | "blocked" | "skipped" | "" (absent).
_stage_state() {
  local s="$1"
  case "$s" in *"$2="*) s="${s#*"$2="}"; printf '%s' "${s%%;*}" ;; *) printf '' ;; esac
}
# _stage_done <stages> <token> — done or skipped are both terminal (an unstarted descendant's
# skipped stages must never be re-attempted on resume).
_stage_done() {
  case "$(_stage_state "$1" "$2")" in done|skipped) return 0 ;; *) return 1 ;; esac
}

# stack-cascade <slug> <task-id> [--push] [--verify-cmd <cmd>] [--evidence-dir <dir>]
# Deterministic descendant propagation after an upstream fix: for each transitive stack descendant,
# parent-first, it drives the mechanical stages — integrate (merge the immediate parent's recorded
# verified head), verify (bind through stack-verify after the caller-supplied verification command
# passes), record (stack-inherited), and, for already-shipped descendants only, push (normal push,
# no force) once --push authorizes publication. Semantics stay with the command layer: the fixer,
# the ## Verify command and the publication approval are supplied by the caller. Stages are
# persisted BEFORE side effects and resumed idempotently (already-contained parents and already-
# pushed heads never duplicate); an UNSTARTED descendant (branch nowhere) gets its new prerequisite
# head recorded and all stages skipped (terminal), with no branch/worktree/push/Verify; existing
# branches are integrated in a rehydrated worktree at the approved location, never by checking out
# the shared clone. The describe stage exists only for shipped descendants and is completed by the
# command layer after the history delivery, so a description update cannot vanish.
cmd_stack_cascade() {
  [ $# -ge 2 ] || die "usage: stack-cascade <slug> <task-id> [--push] [--verify-cmd <cmd>] [--evidence-dir <dir>]"
  local slug="$1" root="$2"; shift 2
  local push=0 vcmd="" evdir=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --push) push=1; shift ;;
      --verify-cmd) vcmd="${2:-}"; shift 2 ;;
      --evidence-dir) evdir="${2:-}"; shift 2 ;;
      *) die "unknown stack-cascade arg '$1'" ;;
    esac
  done
  pw_task_id_ok "$root" || die "invalid task id: $root"
  local d; d="$(proj_dir "$slug")"
  pw_stack_state_validate "$d" || die "stack state invalid (see the reason above) → fix: repair task/stack.tsv before a cascade"
  _stack_ops_validate "$(_command_stack_op_file "$d")" || die "stack ops record invalid (see the reason above) → fix: repair task/stack-ops.tsv before a cascade"
  _stack_stale "$d" "$root" && die "$root is not freshly verified → fix: run its ## Verify + stack-verify before cascading"
  local rsha; rsha="$(pw_stack_state_get "$d" "$root" verified_head)"
  [ -n "$rsha" ] || die "$root has no verified_head binding → fix: stack-verify $root after its ## Verify"
  local desc; desc="$(pw_stack_descendants "$d" "$root" 2>/dev/null || true)"
  [ -n "$desc" ] || { echo "$slug: $root has no stack descendants (nothing to cascade)"; return 0; }
  local rrepo rd; rrepo="$(_stack_repo_of "$d" "$root")"; rd="$REPOS_DIR/$rrepo"
  [ -d "$rd" ] || die "repo not found: $rd"
  local opkey; opkey="cascade:$root:$(printf '%s' "$rsha" | cut -c1-7)"
  local t stages=""
  # Build the stage set (persisted before any side effect). Already-shipped descendants (an MR URL)
  # get push+describe stages; push needs the explicit --push authorization and describe stays
  # pending until the plan-33 history delivery is completed by the command layer.
  for t in $desc; do
    stages="$stages$t:integrate=pending;$t:verify=pending;$t:record=pending"
    case "$(pw_task_mr_url "$d/task/$t.md" 2>/dev/null || true)" in
      http*) stages="$stages;$t:push=pending;$t:describe=pending" ;;
    esac
    stages="$stages;"
  done
  if [ -f "$d/task/stack-ops.tsv" ] && awk -F'\t' -v k="$opkey" '$1==k{p=1} END{exit !p}' "$d/task/stack-ops.tsv"; then
    stages="$(_op_stages_of "$slug" "$opkey")"   # RESUME: never reset persisted stages
  else
    cmd_stack_op "$slug" create "$opkey" cascade "$root" "cascade" "$stages" "$rsha" >/dev/null \
      || die "stack-cascade: could not record the pending recovery row (nothing was changed)"
  fi
  local evbase; evbase="${evdir:-$d/task/.cascade-evidence}"; mkdir -p "$evbase"
  # Component lock (one cascade writer per project); the shared clone is NEVER checked out into
  # (worktrees are rehydrated at the approved location instead), so no checkout restore is needed.
  PW_CASCADE_LOCK="$d/task/.stack-cascade.lock"
  pw_lock "$PW_CASCADE_LOCK" 20 || die "stack-cascade: another cascade writer holds $PW_CASCADE_LOCK → fix: wait for it to finish (remove the lock by hand only after confirming no writer is active)"
  _cascade_cleanup() {
    { [ -n "${PW_CASCADE_LOCK:-}" ] && pw_unlock "$PW_CASCADE_LOCK"; } || true
  }
  trap _cascade_cleanup EXIT
  git -C "$rd" fetch -q --prune origin 2>/dev/null \
    || die "stack-cascade: cannot refresh origin in $rrepo → fix: network/auth, then retry (nothing was pushed)"
  local blocked=" " pending_any=0 failed=0
  local D pd psha pbranch dbranch workdir wt ps lex rex wtpath st sk
  for D in $desc; do
    pd="$(pw_stack_parent_id "$d" "$D")"
    [ -n "$pd" ] || continue
    case "$blocked" in *" $D "*) continue ;; esac
    # A descendant of a blocked task is blocked with no further write (subtree rule).
    if [ "$pd" != "$root" ]; then
      case "$blocked" in
        *" $pd "*) cmd_stack_op "$slug" set "$opkey" "$D:integrate=blocked" >/dev/null || die "stack-cascade: stage write failed"; blocked="$blocked$D "; failed=1; continue ;;
      esac
    fi
    psha="$(pw_stack_state_get "$d" "$pd" verified_head)"
    pbranch="$(_stack_branch_of "$d" "$pd")"
    [ -n "$psha" ] || die "stack-cascade: parent $pd has no verified_head (cascade order broken) → fix: verify the parent first"
    dbranch="$(_stack_branch_of "$d" "$D")"
    [ -n "$dbranch" ] || die "stack-cascade: $D has no Branch field"
    # Resolve a working tree WITHOUT ever touching the shared clone's checkout: prefer the mounted
    # worktree, else rehydrate one at the approved task-worktree location. A branch that exists
    # NOWHERE means the task is UNSTARTED: record the new prerequisite head for spawn-time
    # consumption, mark every stage terminal (skipped), and continue — never create a branch,
    # worktree, push, or Verify for an unstarted task.
    workdir=""
    wt="$(_stack_task_repo_dir "$d" "$D" 2>/dev/null || true)"
    lex=0; rex=0
    git -C "$rd" rev-parse --verify --quiet "refs/heads/$dbranch" >/dev/null 2>&1 && lex=1
    git -C "$rd" rev-parse --verify --quiet "refs/remotes/origin/$dbranch" >/dev/null 2>&1 && rex=1
    if [ -z "$wt" ] && [ "$lex" = 0 ] && [ "$rex" = 0 ]; then
      pw_stack_state_upsert "$d" "$D" parent="$pd" consumed_parent_sha="$psha" consumed_parent_branch="$pbranch" \
        || die "stack-cascade: could not record the prerequisite head for unstarted $D (stages retained)"
      sk=""
      for st in integrate verify record push describe; do
        case "$stages" in *"$D:$st="*) sk="$sk$D:$st=skipped;" ;; esac
      done
      if [ -n "$sk" ]; then
        cmd_stack_op "$slug" set "$opkey" "${sk%;}" >/dev/null || die "stack-cascade: stage write failed"
        stages="$(_op_stages_of "$slug" "$opkey")"
      fi
      echo "stack-cascade: $D is unstarted (no branch) — recorded prerequisite $pd @ $(printf '%s' "$psha" | cut -c1-12); it consumes that head at spawn" >&2
      continue
    fi
    if [ -n "$wt" ]; then
      [ "$(git -C "$wt" branch --show-current 2>/dev/null || true)" = "$dbranch" ] \
        || die "stack-cascade: mounted worktree $wt is not on $dbranch → fix: re-attach the task worktree"
      [ -z "$(git -C "$wt" status --porcelain 2>/dev/null || true)" ] \
        || die "stack-cascade: worktree $wt has uncommitted changes → fix: settle them before cascading (never auto-stash)"
      workdir="$wt"
    else
      # Rehydrate at the approved task-worktree location; the shared clone's checkout stays untouched
      # (never `git checkout` in the user's repo root during a cascade).
      wtpath="$d/worktree/$rrepo/$D-$slug"
      mkdir -p "$(dirname "$wtpath")" || die "stack-cascade: cannot create $wtpath"
      if [ "$lex" = 1 ]; then
        git -C "$rd" worktree add "$wtpath" "$dbranch" >/dev/null 2>&1 \
          || die "stack-cascade: cannot rehydrate the $D worktree at $wtpath → fix: /pw-execute $slug $D (is branch $dbranch checked out elsewhere?)"
      else
        git -C "$rd" worktree add --track -b "$dbranch" "$wtpath" "origin/$dbranch" >/dev/null 2>&1 \
          || die "stack-cascade: cannot rehydrate the $D worktree from origin/$dbranch → fix: check the published branch state"
      fi
      workdir="$wtpath"
      echo "stack-cascade: rehydrated the $D worktree at $wtpath (shared clone checkout untouched)" >&2
    fi
    # --- integrate: merge the parent's recorded verified head (no merge when already contained) ---
    if ! _stage_done "$stages" "$D:integrate"; then
      if ! git -C "$workdir" merge-base --is-ancestor "$psha" HEAD 2>/dev/null; then
        if ! git -C "$workdir" -c user.email=stack@pw -c user.name=stack merge -q --no-edit -m "stack cascade: merge $pd @ $(printf '%s' "$psha" | cut -c1-12) into $D" "$psha"; then
          git -C "$workdir" merge --abort >/dev/null 2>&1 || true
          cmd_stack_op "$slug" set "$opkey" "$D:integrate=blocked" >/dev/null || die "stack-cascade: stage write failed"
          blocked="$blocked$D "; failed=1
          echo "stack-cascade: $D integration conflicted with $pd — local state kept, subtree blocked (resolve per /pw-sync, then re-run to resume)" >&2
          continue
        fi
      fi
      cmd_stack_op "$slug" set "$opkey" "$D:integrate=done" >/dev/null || die "stack-cascade: stage write failed"
      stages="$(_op_stages_of "$slug" "$opkey")"
    fi
    # --- verify: the caller's Verify command must pass; binding goes through stack-verify ---
    if ! _stage_done "$stages" "$D:verify"; then
      local dh; dh="$(git -C "$workdir" rev-parse HEAD)"
      if [ -z "$vcmd" ]; then
        echo "stack-cascade: $D integrated; no --verify-cmd supplied → run its ## Verify, bind with 'stack-verify $slug $D <evidence>', then re-run this cascade to resume (stages retained)" >&2
        pending_any=1
        break
      fi
      local evf; evf="$evbase/$D-verify-$(printf '%s' "$dh" | cut -c1-7).log"
      if ( cd "$workdir" && bash -c "$vcmd" ) >"$evf" 2>&1 \
         && "$HERE/pw-ship.sh" stack-verify "$slug" "$D" "$evf" --head "$dh" >/dev/null 2>>"$evf"; then
        cmd_stack_op "$slug" set "$opkey" "$D:verify=done" >/dev/null || die "stack-cascade: stage write failed"
        stages="$(_op_stages_of "$slug" "$opkey")"
      else
        cmd_stack_op "$slug" set "$opkey" "$D:verify=blocked" >/dev/null || die "stack-cascade: stage write failed"
        blocked="$blocked$D "; failed=1
        echo "stack-cascade: $D failed verification — local commit kept, nothing pushed, subtree blocked (see $evf)" >&2
        continue
      fi
    fi
    # --- record: inherited-update evidence (never a reviewer comment) ---
    if ! _stage_done "$stages" "$D:record"; then
      "$HERE/pw-ship.sh" stack-inherited "$slug" "$D" "$pd" "$psha" >/dev/null \
        || die "stack-cascade: could not record the inherited update for $D (stages retained)"
      cmd_stack_op "$slug" set "$opkey" "$D:record=done" >/dev/null || die "stack-cascade: stage write failed"
      stages="$(_op_stages_of "$slug" "$opkey")"
    fi
    # --- push: already-shipped descendants only, and only under explicit --push authorization ---
    ps="$(_stage_state "$stages" "$D:push")"
    if [ "$ps" = "pending" ]; then
      if [ "$push" != 1 ]; then
        pending_any=1
        echo "stack-cascade: $D integrated+verified; publication not authorized (add --push) — push/describe stages retained pending" >&2
      else
        local db remote_head
        db="$(git -C "$workdir" rev-parse HEAD)"
        remote_head="$(git -C "$workdir" ls-remote origin "refs/heads/$dbranch" 2>/dev/null | awk '{print $1}' || true)"
        if [ "$remote_head" != "$db" ]; then
          if ! git -C "$workdir" push -q origin "$dbranch"; then
            cmd_stack_op "$slug" set "$opkey" "$D:push=blocked" >/dev/null || true
            blocked="$blocked$D "; failed=1
            echo "stack-cascade: $D push failed (normal push, no force) — subtree blocked; re-preview before retrying" >&2
            continue
          fi
        fi
        cmd_stack_op "$slug" set "$opkey" "$D:push=done" >/dev/null || die "stack-cascade: stage write failed"
        stages="$(_op_stages_of "$slug" "$opkey")"
      fi
    fi
    # describe (shipped descendants): completed by the command layer after the history delivery.
    [ "$(_stage_state "$stages" "$D:describe")" = "pending" ] && pending_any=1
  done
  stages="$(_op_stages_of "$slug" "$opkey")"
  local st; st="$(_op_state_of "$stages")"
  if [ "$failed" = 1 ] || [ "$st" = "blocked" ]; then
    echo "$slug: cascade incomplete — blocked: ${blocked:-none}; stages: $stages" >&2
    return 2
  fi
  if [ "$pending_any" = 1 ] || [ "$st" = "pending" ]; then
    echo "$slug: cascade propagation incomplete (pending stages — authorization or description delivery): $stages" >&2
    return 1
  fi
  echo "$slug: cascade complete for $root (sha $(printf '%s' "$rsha" | cut -c1-7))"
  return 0
}

case "${1:-}" in
  history)            shift; cmd_history "$@" ;;
  resolve)            shift; cmd_resolve "$@" ;;
  exec)               shift; cmd_exec "$@" ;;
  monitor)            shift; cmd_monitor "$@" ;;
  mr-state)           shift; cmd_mr_state "$@" ;;
  mr-state-batch)     shift; cmd_mr_state_batch "$@" ;;
  comment-seen)       shift; cmd_comment_seen "$@" ;;
  dashboard-mr-state) shift; cmd_dashboard_mr_state "$@" ;;
  stack)              shift; cmd_stack "$@" ;;
  stack-validate)     shift; cmd_stack_validate "$@" ;;
  stack-plan)         shift; cmd_stack_plan "$@" ;;
  stack-record)       shift; cmd_stack_record "$@" ;;
  stack-fresh)        shift; [ $# -eq 2 ] || die "usage: stack-fresh <slug> <task-id>"; cmd_stack_freshness "$1" "$2" fresh ;;
  stack-stale)        shift; [ $# -eq 2 ] || die "usage: stack-stale <slug> <task-id>"; cmd_stack_freshness "$1" "$2" stale ;;
  stack-land)         shift; cmd_stack_land "$@" ;;
  stack-promote)      shift; cmd_stack_promote "$@" ;;
  stack-verify)       shift; cmd_stack_verify "$@" ;;
  stack-retarget)     shift; cmd_stack_retarget "$@" ;;
  stack-op)           shift; cmd_stack_op "$@" ;;
  stack-debt)         shift; cmd_stack_debt "$@" ;;
  stack-adopt)        shift; cmd_stack_adopt "$@" ;;
  stack-inherited)    shift; cmd_stack_inherited "$@" ;;
  stack-cascade)      shift; cmd_stack_cascade "$@" ;;
  *) die "usage: pw-ship.sh <resolve|exec|monitor|mr-state|mr-state-batch|comment-seen|dashboard-mr-state|history|stack|stack-validate|stack-plan|stack-record|stack-verify|stack-fresh|stack-stale|stack-land|stack-promote|stack-retarget|stack-op|stack-debt|stack-adopt|stack-inherited|stack-cascade> … (see --help)" ;;
esac
