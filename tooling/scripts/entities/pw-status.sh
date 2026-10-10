#!/usr/bin/env bash
# ============================================================================
# pw-status.sh — deterministic project status report (replaces /pw-status agent)
#
#   pw-status.sh <slug>                  full status report
#   pw-status.sh <slug> --skip-cli-check skip CLI auth status check
#   pw-status.sh --all [--attention] [--phase <phase>] [--json]
#       READ-ONLY cross-project overview across the projects root: one row per
#       discovered project — phase, attention conditions, accepted tasks, last
#       recorded event, and the inspection command. Local records only: no
#       forge/auth/model calls, no writes (never inserts missing dashboard
#       lines). --attention keeps attention rows; --phase filters by dashboard
#       phase token; --json prints one machine-readable object. Exit 0 =
#       complete; 1 = partial (unreadable/malformed records; rows kept);
#       2 = bad arguments or a missing projects root.
#   pw-status.sh --selftest              run isolated self-test
#
#   Project-state setters (the dashboard/LOG.md entity; merged from pw-lib, plan 20):
#   log <slug> <actor> <msg...> · status <slug> <phase> [--rewind] · oneliner <slug> <text...>
#   adopted <slug> <text...> · phase <slug> · dashboard-task-status <slug> <task-id> <status>
#   task-accept <slug> <task-id>   (one call sets all three acceptance holders: task file +
#                                   PLAN row + dashboard row; best-effort dashboard; one LOG line)
#   stack <slug>   read-only stacked-MR topology/health report (parent|target|landed|freshness
#                  per stack task, plus stale/pending counts); "no stacks" for legacy projects.
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
# Reads README.md, PLAN.md, the latest Sign-off row of each review (shared mdlib
# readers — never a whole-file "approved" grep), and real open-item counts, shows
# LOG.md lines, reports blockers, and checks CLI auth status (informational, non-blocking).
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
. "$HERE/../lib/pw-reviewlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
OVTAB="$(printf '\t')"

die() { echo "pw-status: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d) → fix: check the slug under the projects dir (new project? create it with: /pw-new $1)"; printf '%s' "$d"; }

# --- latest-row sign-off readers (report display; shared mdlib primitives — NEVER a
# whole-file "approved" grep: a historical approved row survives a reopen and would hide a
# real blocker; the readers return the LATEST Decision + By cells verbatim, richer
# provider/model By values included, without altering the decision token). RFC staging
# carries no Sign-off gate of its own and is excluded from approval discovery everywhere —
# the same boundary pw-preflight.sh enforces; its open items ride the list above.
_latest_signoff_approved() { # <file> → 0 iff the latest approval is consumable
  _review_approval_valid "$1"
}
_latest_signoff_display() { # <file> → "changes-requested by pw-review (repair)" / "approved ✅" / "none yet"
  local _f="$1" _dec _act
  _dec="$(_signoff_latest_decision "$_f")" || _dec=""
  _act="$(_signoff_latest_actor "$_f")" || _act=""
  [ -n "$_dec" ] || _dec="none yet"
  if [ -n "$_act" ]; then printf '%s by %s' "$_dec" "$_act"; else printf '%s' "$_dec"; fi
  if _decision_is_approved "$_dec" && ! _review_approval_valid "$_f"; then
    printf ' [blocked by unresolved work or an active human rejection]'
  fi
}

# _review_gate_relevant <rel> <phase> — 0 when this review file's approval gate is a
# gate of the project's CURRENT phase (the same scoping pw-preflight.sh enforces):
# analysis-topic reviews gate analysis→breakdown→execution; the PLAN review gates
# breakdown→execution. Everything else (context readiness, task-plan/task-exec/ship
# mirrors, RFC content, the close record) is an OPTIONAL lane whose absence is never a
# gate, and RFC comment staging (analysis/review/RFC.review.md) has no approval gate at
# all. Keeping the split here means the overview and the single-project report always
# classify the same file the same way.
_review_gate_relevant() {
  local rel="$1" phase="$2"
  case "$rel" in
    analysis/review/RFC.review.md) return 1 ;;
    analysis/review/*.review.md)
      case "$phase" in analysis|breakdown|executing) return 0 ;; *) return 1 ;; esac ;;
    task/review/PLAN.review.md)
      case "$phase" in breakdown|executing) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

# _review_pending_display <file> — "in-review by <actor>" / "changes-requested by <actor>"
# when the file carries a REAL (attributed) non-approved latest decision. rc 1 when there
# is no real decision: the template's placeholder row ("| | | in-review |") reads as
# in-review with an EMPTY actor and must never nag as pending work, and a valid approval
# is not pending anything.
_review_pending_display() {
  local _f="$1" _dec _act
  _dec="$(_signoff_latest_decision "$_f")" || return 1
  case "$_dec" in ''|"none yet") return 1 ;; esac
  _decision_is_approved "$_dec" && return 1
  _act="$(_signoff_latest_actor "$_f")" || _act=""
  [ -n "$_act" ] || return 1
  printf '%s by %s' "$_dec" "$_act"
}


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
      last_epoch="$(pw_timestamp_epoch "$ltag" 2>/dev/null)" || last_epoch=""
      if [ -n "$last_epoch" ]; then
        local diff_min=$(( (now_epoch - last_epoch) / 60 ))
        if [ "$now_epoch" -ge "$last_epoch" ] && [ "$diff_min" -lt "$window" ]; then
          echo "pw-status: skipped duplicate log entry for $slug (same actor+message ${diff_min}m ago, within ${window}m window)" >&2
          return 0
        fi
      fi
    fi
  fi
  local ts; ts="$(pw_now_wib)" || die "log: cannot format event timestamp → fix: check the date command and retry"
  printf -- '- **%s** · `%s` — %s\n' "$ts" "$actor" "$msg" >> "$f"
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


# Mark a task accepted in ALL THREE acceptance holders in one call (plan 23 / KI-1 — the single
# mechanical propagator of the human accept decision):
#   1. PLAN task-table Status cell ← accepted (the cell `pw-preflight.sh close` reads — the gate)
#   2. task file `- **Status:**` ← accepted
#   3. dashboard README Task-status row ← accepted (BEST-EFFORT: a missing/unfillable row warns
#      but does not fail — task file + PLAN are the gate's truth; with the KI-2 fill rule a
#      still-untouched placeholder table self-heals here)
# Idempotent: when every holder already says accepted → exit 0 with no duplicate LOG entry;
# otherwise ONE log line covers the whole sync. Used when the MR is already merged.
#   task-accept <slug> <task-id>
cmd_task_accept() {
  [ $# -eq 2 ] || die "usage: task-accept <slug> <task-id>"
  local slug="$1" task="$2"
  local d; d="$(proj_dir "$slug")"
  local taskfile="$d/task/$task.md"
  [ -f "$taskfile" ] || die "no task file: task/$task.md"
  local plan="$d/task/PLAN.md"
  [ -f "$plan" ] || die "no task/PLAN.md in project $slug — nothing to accept against (/pw-breakdown $slug owns the PLAN table)"

  # Holder 1 — PLAN row (gate truth). A missing row is a doc-sync problem: die, never silence.
  local plan_status
  plan_status="$(pw_plan_pairs "$plan" | awk -F'|' -v t="$task" '$1 == t { print $2; exit }')"
  [ -n "$plan_status" ] || die "no PLAN task-table row for $task — repair the PLAN doc first (the row must exist; task-accept never creates rows)"
  local changed=0
  if [ "$plan_status" != "accepted" ]; then
    _plan_cell_update "$plan" "$task" status accepted \
      || die "could not set the PLAN Status cell for $task (see above)"
    changed=1
  fi

  # Holder 2 — task file Status field (existing behavior).
  local file_status; file_status="$(pw_field "$taskfile" Status)"
  if [ "$file_status" != "accepted" ]; then
    if grep -q '^- \*\*Status:\*\*' "$taskfile"; then
      sed -i '' -E 's/^- \*\*Status:\*\*.*$/- **Status:** accepted/' "$taskfile"
    else
      # Insert after first line if no Status line exists
      sed -i '' '1a\
- **Status:** accepted
' "$taskfile"
    fi
    changed=1
  fi

  # Holder 3 — dashboard row, best-effort (never fails the accept).
  local readme="$d/README.md"
  if [ -f "$readme" ]; then
    local before; before="$(cat "$readme")"
    if _dashboard_update "$readme" 'ID' 'Status' "$task" accepted 2>/dev/null; then
      [ "$before" = "$(cat "$readme")" ] || changed=1
    else
      echo "pw-status: warning: dashboard row for $task not updated (no row and no fillable placeholder) — task file + PLAN are the gate truth" >&2
    fi
  fi

  if [ "$changed" -eq 1 ]; then
    cmd_log "$slug" sync "$task: MR already merged, marked as accepted (task file + PLAN row + dashboard)"
    echo "$slug: $task marked as accepted (MR already merged)"
  else
    echo "$slug: $task already accepted in every holder — nothing to do"
  fi
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
        used="$(printf '%s' "$lline" | sed -nE "s/.*spawned $id[^(]*\(([^)]*)\).*/\1/p")"
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

# stack <slug> — read-only stack report (plan 35): the topology/health rows from the ship entity
# plus stale/debt counts. No stacks = legacy independent behavior. Mutates nothing.
cmd_stack() {
  [ $# -eq 1 ] || die "usage: stack <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local rows; rows="$("$HERE/pw-ship.sh" stack "$slug" 2>/dev/null || true)"
  local n; n="$(printf '%s\n' "$rows" | awk -F'|' 'NR>1 && $1 ~ /^T[0-9]/ {c++} END{print c+0}')"
  if [ "${n:-0}" -eq 0 ]; then echo "$slug: no stacks (legacy independent behavior)"; return 0; fi
  printf '%s\n' "$rows"
  local stale unv debt
  stale="$(printf '%s\n' "$rows" | awk -F'|' '$7=="stale" {c++} END{print c+0}')"
  unv="$(printf '%s\n' "$rows" | awk -F'|' '$7=="unverified" {c++} END{print c+0}')"
  debt="$(printf '%s\n' "$rows" | awk -F'|' '$8+0 > 0 {c++} END{print c+0}')"
  echo "stacks: ${n} task(s), ${stale} stale, ${unv} unverified (not started), ${debt} with pending operations"
}

# --- cross-project overview (--all) -----------------------------------------------
# READ-ONLY by contract: derives one row per discovered project from local records
# only. Never writes (notably: never runs the config review-axis getters — they INSERT
# missing dashboard lines as a side effect), never calls a forge/auth/model CLI, never
# spawns workers, and never reads context payloads, worktrees, or secrets. Exit codes:
# 0 = complete scan (including an empty result); 1 = partial scan (unreadable/malformed
# records — every readable row is still emitted with its diagnostics); 2 = invalid
# arguments or an inaccessible projects root.
_overview_line() { # one control-free display line (untrusted file content safety)
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/[[:cntrl:]]/ /g'
}
_overview_json() { # JSON string escape for an already _overview_line-sanitized value
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
_overview_slug_ok() {
  case "$1" in ''|.|..|*/*|*[!a-z0-9-]*|[!a-z0-9]*) return 1 ;; esac
  return 0
}
_overview_slug_clean() { # display-safe slug; never a command fragment for invalid names
  _overview_line "$1" | sed "s/[\"\\\\]/_/g"
}
_overview_is_project() { # the workflow markers discovery recognizes
  local d="$1"
  if [ -d "$d/analysis" ] && [ -d "$d/task" ] && [ -f "$d/context/INDEX.md" ]; then return 0; fi
  if [ -f "$d/task/PLAN.md" ] && { [ -d "$d/task/review" ] || [ -d "$d/analysis/review" ] || [ -d "$d/review" ]; }; then return 0; fi
  return 1
}
_overview_event_display() { # <raw event timestamp> → compact "9 Oct" (raw when unparseable)
  local raw="$1" e d
  if e="$(pw_timestamp_epoch "$raw" 2>/dev/null)"; then
    d="$(TZ=Asia/Jakarta LC_ALL=C date -r "$e" '+%e %b' 2>/dev/null)"
    [ -n "$d" ] || d="$(TZ=Asia/Jakarta LC_ALL=C date -d "@$e" '+%e %b' 2>/dev/null)"
    if [ -n "$d" ]; then printf '%s' "${d# }"; return 0; fi
  fi
  _overview_line "$raw" | sed "s/[\"\\\\]/'/g"
}
_overview_last_event() { # <log> → "json-raw<TAB>display"; rc 1 when there is no entry
  local raw
  [ -f "$1" ] && [ -r "$1" ] || return 1
  raw="$(sed -n 's/^- \*\*\([^*]*\)\*\* ·.*/\1/p' "$1" | tail -n 1)"
  [ -n "$raw" ] || return 1
  raw="$(_overview_line "$raw")"
  printf '%s\t%s' "$(_overview_json "$raw")" "$(_overview_event_display "$raw")"
}
_overview_rel_array() { # stdin: one project-relative path per line → "a","b" (JSON strings)
  local out="" sep="" l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    out="$out$sep\"$(_overview_json "$l")\""; sep=","
  done
  printf '%s' "$out"
}
_overview_list_count() { # stdin: one item per line → count
  local n=0 l
  while IFS= read -r l; do [ -n "$l" ] && n=$((n+1)); done
  printf '%s' "$n"
}

# _overview_collect <dir> <display-slug> — one TAB record on stdout. Field map:
#  1 group(0 unfinished/1 closed) · 2 attn(0 has/1 none) · 3 slug · 4 phase token|unknown
#  5 attention text · 6 accepted ("n/a"|"?"|A/T) · 7 last-event display · 8 inspection cmd
#  9 json phase_raw · 10 json path · 11 json description · 12 json reasons array
#  13 json last-event raw · 14 json tasks object|null · 15 diagnostics text
#  16 json diagnostics array · 17 unreadable flag · 18 malformed flag
_overview_collect() {
  local d="$1" slug="$2"
  local readme="$d/README.md" plan="$d/task/PLAN.md"
  local phase_raw="" phase="unknown" desc="" u=0 m=0
  local diag_text="" diags_json="[" dsep="" diag_n=0
  local meta_n=0 meta_json="" msep=""
  local tasks_json="null" accepted_disp="n/a" tot=0 a_n=0 dn_n=0 vf_n=0 ip_n=0 td_n=0 ot_n=0
  local vf_json="" done_json="" other_json=""
  local id st stn spec idi sti tv dw diff_det seen=" " dash_pairs=""
  local _k _lane _af _rel _oc open_n=0 open_files="" pend_rel="" appr_rel="" scanrec=""
  local last_raw="" last_disp="" _le
  local attn=0 attn_text="" reasons="[" rsep="" grp=0 aflag=1 inspect=""
  _ov_diag() { # diagnostics list + metadata uncertainty (the same finding, two consumers)
    local _t; _t="$(_overview_line "$1")"
    diag_text="${diag_text:+$diag_text; }$_t"; diag_n=$((diag_n+1))
    diags_json="$diags_json$dsep\"$(_overview_json "$_t")\""; dsep=","
    meta_n=$((meta_n+1)); meta_json="$meta_json$msep\"$(_overview_json "$_t")\""; msep=","
  }
  _ov_diag_plain() { # diag only — the phase-token finding carries its own attention code
    local _t; _t="$(_overview_line "$1")"
    diag_text="${diag_text:+$diag_text; }$_t"; diag_n=$((diag_n+1))
    diags_json="$diags_json$dsep\"$(_overview_json "$_t")\""; dsep=","
  }
  _ov_meta() { # metadata uncertainty without a scan-health diagnostic
    local _t; _t="$(_overview_line "$1")"
    meta_n=$((meta_n+1)); meta_json="$meta_json$msep\"$(_overview_json "$_t")\""; msep=","
  }

  # dashboard: phase + description (never a write; pw_field is a pure reader)
  if [ ! -f "$readme" ] || [ ! -r "$readme" ]; then
    u=1; _ov_diag "README.md missing or unreadable — dashboard fields unavailable"
  else
    phase_raw="$(_overview_line "$(pw_field "$readme" Status)")"
    phase="$(pw_phase_token "${phase_raw:-missing}")"
    if ! pw_phase_valid "$phase"; then
      m=1; phase="unknown"
      _ov_diag_plain "README.md Status line carries no valid lifecycle token"
    fi
    desc="$(_overview_line "$(pw_field "$readme" One-liner)")"
    case "$desc" in '<'*'>') desc="" ;; esac   # scaffold placeholder, not a summary
  fi

  # PLAN tasks (+ holder disagreement against task files and the dashboard mirror)
  if [ -f "$plan" ]; then
    if [ ! -r "$plan" ]; then
      u=1; accepted_disp="?"; _ov_diag "task/PLAN.md unreadable"
    else
      spec="$(_pw_plan_map "$plan")"
      idi="${spec%% *}"; sti="$(printf '%s' "$spec" | cut -d' ' -f2)"
      if [ "${idi:-0}" -gt 0 ] 2>/dev/null && [ "${sti:-0}" -gt 0 ] 2>/dev/null; then
        [ -f "$readme" ] && dash_pairs="$(pw_plan_pairs "$readme")"
        while IFS='|' read -r id st; do
          [ -n "$id" ] || continue
          case "$seen" in
            *" $id "*) m=1; _ov_diag "duplicate task id $id in the PLAN task table"; continue ;;
          esac
          seen="$seen$id "
          tot=$((tot+1))
          stn="$(printf '%s' "$st" | sed -e 's/^[`*]*//' -e 's/[`*]*$//')"; stn="${stn%% *}"
          case "$stn" in
            accepted) a_n=$((a_n+1)) ;;
            done) dn_n=$((dn_n+1)); done_json="$done_json${done_json:+,}\"$id\"" ;;
            verify-failed) vf_n=$((vf_n+1)); vf_json="$vf_json${vf_json:+,}\"$id\"" ;;
            in-progress) ip_n=$((ip_n+1)) ;;
            todo) td_n=$((td_n+1)) ;;
            '') m=1; _ov_diag "task $id has an empty PLAN status cell" ;;
            *) ot_n=$((ot_n+1)); other_json="$other_json${other_json:+,}\"$id\""
               _ov_meta "task $id status '$stn' is not a known task state" ;;
          esac
          case "$stn" in
            accepted|done|verify-failed|in-progress|todo)
              diff_det=""; tv=""
              if [ -f "$d/task/$id.md" ] && [ -r "$d/task/$id.md" ]; then
                tv="$(pw_field "$d/task/$id.md" Status | sed -e 's/^[`*]*//' -e 's/[`*]*$//')"; tv="${tv%% *}"
              fi
              case "$tv" in
                accepted|done|verify-failed|in-progress|todo)
                  [ "$tv" = "$stn" ] || diff_det="$id: PLAN=$stn task-file=$tv" ;;
              esac
              if [ -z "$diff_det" ] && [ -n "$dash_pairs" ]; then
                dw="$(printf '%s\n' "$dash_pairs" | awk -F'|' -v id="$id" '$1==id{print $2; exit}')"
                dw="$(printf '%s' "$dw" | sed -e 's/^[`*]*//' -e 's/[`*]*$//')"; dw="${dw%% *}"
                case "$dw" in
                  accepted|done|verify-failed|in-progress|todo)
                    [ "$dw" = "$stn" ] || diff_det="$id: PLAN=$stn dashboard=$dw" ;;
                esac
              fi
              [ -n "$diff_det" ] && _ov_meta "$diff_det"
              ;;
          esac
        done <<EOF
$(pw_plan_pairs "$plan")
EOF
        accepted_disp="$a_n/$tot"
        tasks_json="{\"parsable\":true,\"accepted\":$a_n,\"total\":$tot,\"done\":$dn_n,\"verify_failed\":$vf_n,\"in_progress\":$ip_n,\"todo\":$td_n,\"other\":$ot_n}"
      else
        m=1; accepted_disp="?"
        _ov_diag "task/PLAN.md task table unparsable (no ID/Status header row)"
      fi
    fi
  fi

  # review records across the shared five lanes (the same walk the review readers use)
  scanrec="$(pw_review_files "$d" 2>/dev/null)" || true
  while IFS="$OVTAB" read -r _k _lane _af; do
    case "$_k" in
      escape) u=1; _ov_diag "review directory '$_lane' is or climbs through a symlink — not read" ;;
      symlink) u=1; _ov_diag "symlinked review file not read: $_lane/$(basename "$_af")" ;;
      file)
        _rel="$_lane/$(basename "$_af")"
        if [ ! -r "$_af" ]; then u=1; _ov_diag "review file unreadable: $_rel"; continue; fi
        _oc="$(pw_review_item_counts "$_af")"; _oc="${_oc#open=}"; _oc="${_oc%% *}"; _oc="${_oc:-0}"
        if [ "$_oc" -gt 0 ]; then
          open_n=$((open_n+_oc)); open_files="$open_files$_rel
"
        fi
        if _review_approval_valid "$_af"; then :
        elif _review_gate_relevant "$_rel" "$phase"; then
          appr_rel="$appr_rel$_rel
"
        elif _review_pending_display "$_af" >/dev/null 2>&1; then
          pend_rel="$pend_rel$_rel
"
        fi
        ;;
    esac
  done <<EOF
$scanrec
EOF

  # last recorded workflow event (never a file-timestamp proxy)
  if _le="$(_overview_last_event "$d/LOG.md")"; then
    last_raw="${_le%%"$OVTAB"*}"; last_disp="${_le#*"$OVTAB"}"
  fi

  # attention assembly (fixed order; counts only where the text carries them)
  if [ "$phase" = unknown ]; then
    attn=1; attn_text="phase-unknown"
    reasons="$reasons$rsep{\"code\":\"phase-unknown\"}"; rsep=","
  fi
  if [ "$vf_n" -gt 0 ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }verification-failed ($vf_n)"
    reasons="$reasons$rsep{\"code\":\"verification-failed\",\"count\":$vf_n,\"tasks\":[$vf_json]}"; rsep=","
  fi
  if [ "$dn_n" -gt 0 ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }acceptance-pending ($dn_n)"
    reasons="$reasons$rsep{\"code\":\"acceptance-pending\",\"count\":$dn_n,\"tasks\":[$done_json]}"; rsep=","
  fi
  if [ -n "$appr_rel" ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }approval-needed"
    _an="$(printf '%s' "$appr_rel" | _overview_list_count)"
    reasons="$reasons$rsep{\"code\":\"approval-needed\",\"count\":$_an,\"files\":[$(printf '%s' "$appr_rel" | _overview_rel_array)]}"; rsep=","
  fi
  if [ "$open_n" -gt 0 ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }review-open ($open_n)"
    reasons="$reasons$rsep{\"code\":\"review-open\",\"count\":$open_n,\"files\":[$(printf '%s' "$open_files" | _overview_rel_array)]}"; rsep=","
  fi
  if [ -n "$pend_rel" ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }review-pending"
    _an="$(printf '%s' "$pend_rel" | _overview_list_count)"
    reasons="$reasons$rsep{\"code\":\"review-pending\",\"count\":$_an,\"files\":[$(printf '%s' "$pend_rel" | _overview_rel_array)]}"; rsep=","
  fi
  if [ "$meta_n" -gt 0 ]; then
    attn=1; attn_text="${attn_text:+$attn_text, }metadata ($meta_n)"
    reasons="$reasons$rsep{\"code\":\"metadata\",\"count\":$meta_n,\"details\":[$meta_json]}"; rsep=","
  fi
  if ! _overview_slug_ok "$slug"; then
    attn=1; attn_text="${attn_text:+$attn_text, }invalid-name"
    reasons="$reasons$rsep{\"code\":\"invalid-name\"}"; rsep=","
  fi

  [ "$phase" = done ] && grp=1 || grp=0
  [ "$attn" = 1 ] && aflag=0 || aflag=1
  if _overview_slug_ok "$slug"; then
    case "$phase" in
      executing|review|done) inspect="/pw-status $slug" ;;
      *) inspect="/pw-help project $slug" ;;
    esac
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$grp" "$aflag" "$(_overview_slug_clean "$slug")" "$phase" "$attn_text" "$accepted_disp" \
    "$last_disp" "$inspect" "$(_overview_json "$phase_raw")" "$(_overview_json "$d")" \
    "$(_overview_json "$desc")" "$reasons]" "$last_raw" "$tasks_json" "$diag_text" "$diags_json]" "$u" "$m"
}

cmd_all() {
  local attention=0 phase_filter="" json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --attention) attention=1; shift ;;
      --phase) [ $# -ge 2 ] || die "--phase needs a phase value ($PW_VALID_PHASES) → fix: /pw-status --all --phase <phase>"; phase_filter="$2"; shift 2 ;;
      --phase=*) phase_filter="${1#--phase=}"; shift ;;
      --json) json=1; shift ;;
      -h|--help) pw_usage ;;
      -*) die "unknown option for --all: $1 → fix: /pw-status --all [--attention] [--phase <phase>] [--json]" ;;
      *) die "unexpected argument '$1' with --all → fix: --all scans every project; a slug belongs to the single-project form (/pw-status <slug>)" ;;
    esac
  done
  case "$phase_filter" in
    ""|context|analysis|breakdown|executing|review|done) ;;
    *) die "invalid --phase '$phase_filter' ($PW_VALID_PHASES) → fix: the overview filters dashboard phases; review surfaces belong to /pw-help project <slug>" ;;
  esac
  [ -d "$PROJECTS_DIR" ] || die "projects root not accessible: $PROJECTS_DIR → fix: check PW_PROJECTS_DIR (normally the directory holding your projects)"

  local root bundle rec sorted entry name skipped=0
  root="$(cd "$PROJECTS_DIR" && pwd -P)"
  bundle="$(cd "$HERE/../../.." && pwd -P)"
  OV_TMPD="$(mktemp -d)" || die "cannot create a temporary directory → fix: check TMPDIR"
  trap 'rm -rf "$OV_TMPD"' EXIT
  rec="$OV_TMPD/records"; sorted="$OV_TMPD/sorted"
  : > "$rec"

  for entry in "$root"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    [ -d "$entry" ] || continue
    name="${entry##*/}"
    if [ -L "$entry" ]; then skipped=$((skipped+1)); continue; fi
    [ "$entry" = "$bundle" ] && continue
    _overview_is_project "$entry" || continue
    _overview_collect "$entry" "$name" >> "$rec"
  done

  LC_ALL=C sort -t "$OVTAB" -k1,1n -k2,2n -k3,3 "$rec" > "$sorted"

  local discovered unread malformed shown=0 filtered=0
  discovered="$(awk 'END{print NR+0}' "$sorted")"
  unread="$(awk -F"$OVTAB" '$17==1{n++} END{print n+0}' "$sorted")"
  malformed="$(awk -F"$OVTAB" '$18==1{n++} END{print n+0}' "$sorted")"

  if [ "$json" = 1 ]; then
    OV_SCANNED="$(pw_now_wib)" OV_ROOT="$(_overview_json "$root")" OV_SKIPPED="$skipped" \
    awk -F"$OVTAB" -v wantatt="$attention" -v wantphase="$phase_filter" '
      { if ($17==1) U++; if ($18==1) M++
        if (wantatt==1 && $2+0!=0) next
        if (wantphase!="" && $4!=wantphase) next
        shown++; r[shown]=$0 }
      END {
        printf "{\"schema_version\":1,\"scanned_at\":\"%s\",\"root\":\"%s\",\"counts\":{\"discovered\":%d,\"shown\":%d,\"filtered\":%d,\"skipped_symlinks\":%s,\"unreadable\":%d,\"malformed\":%d},\"projects\":[",
          ENVIRON["OV_SCANNED"], ENVIRON["OV_ROOT"], NR, shown, NR-shown, ENVIRON["OV_SKIPPED"], U+0, M+0
        sep=""
        for (i=1;i<=shown;i++) {
          split(r[i], f, "\t")
          printf "%s{\"slug\":\"%s\",\"path\":\"%s\",\"phase\":\"%s\",\"phase_raw\":%s,\"description\":%s,\"tasks\":%s,\"attention\":%s,\"last_event\":%s,\"inspect\":%s,\"diagnostics\":%s,\"unreadable\":%s,\"malformed\":%s}",
            sep, f[3], f[10], f[4],
            (f[9]=="" ? "null" : "\"" f[9] "\""),
            (f[11]=="" ? "null" : "\"" f[11] "\""),
            f[14], f[12],
            (f[13]=="" ? "null" : "{\"raw\":\"" f[13] "\",\"display\":\"" f[7] "\"}"),
            (f[8]=="" ? "null" : "\"" f[8] "\""),
            f[16], (f[17]+0==1 ? "true" : "false"), (f[18]+0==1 ? "true" : "false")
          sep=","
        }
        printf "]}\n"
      }' "$sorted"
    if [ "$unread" -gt 0 ] || [ "$malformed" -gt 0 ]; then
      printf 'pw-status: partial scan — %s unreadable, %s malformed project(s); per-project diagnostics are inside the JSON → fix: repair the flagged records, then re-run.\n' "$unread" "$malformed" >&2
    fi
  else
    printf 'Local project records | scanned: %s\n\n' "$(pw_now_wib)"
    awk -F"$OVTAB" -v wantatt="$attention" -v wantphase="$phase_filter" -v cf="$OV_TMPD/counts" '
      { if ($17==1) U++; if ($18==1) M++
        if (wantatt==1 && $2+0!=0) next
        if (wantphase!="" && $4!=wantphase) next
        shown++; r[shown]=$0
        if (length($3)>w1) w1=length($3)
        if (length($5)>w2) w2=length($5)
        if (length($7)>w3) w3=length($7)
        if (length($4)>w4) w4=length($4)
      }
      END {
        if (w1<7) w1=7; if (w2<9) w2=9; if (w3<6) w3=6; if (w4<5) w4=5
        if (shown>0) {
          printf "%-*s  %-*s  %-*s  %-8s  %-*s  %s\n", w1, "Project", w4, "Phase", w2, "Attention", "Accepted", w3, "Last event", "Inspect"
          for (i=1;i<=shown;i++) {
            split(r[i], f, "\t")
            printf "%-*s  %-*s  %-*s  %-8s  %-*s  %s\n", w1, f[3], w4, f[4], w2, (f[5]=="" ? "none recorded" : f[5]), f[6], w3, (f[7]=="" ? "—" : f[7]), (f[8]=="" ? "—" : f[8])
          }
        }
        printf "%d\t%d\n", shown+0, NR-shown > cf
      }' "$sorted"
    IFS="$OVTAB" read -r shown filtered < "$OV_TMPD/counts" || true
    if [ "${shown:-0}" -eq 0 ]; then
      if [ "${discovered:-0}" -eq 0 ]; then printf '(no projects)\n'; else printf '(no projects match the filter)\n'; fi
    fi
    printf '\n%s discovered | %s shown | %s filtered | %s skipped symlinks | %s unreadable | %s malformed\n' \
      "$discovered" "${shown:-0}" "${filtered:-0}" "$skipped" "$unread" "$malformed"
    printf 'Phase is recorded workflow state. Accepted does not mean merged.\n'
    if [ "$unread" -gt 0 ] || [ "$malformed" -gt 0 ]; then
      printf '\nPartial scan — records that need attention:\n'
      awk -F"$OVTAB" '($17==1 || $18==1) { printf "  - %s: %s\n", $3, ($15=="" ? "(unreadable — inspect with /pw-status <slug>)" : $15) }' "$sorted"
      printf '→ fix: repair the flagged records (detail: /pw-status <slug>), then re-run /pw-status --all.\n'
    fi
  fi

  if [ "$unread" -gt 0 ] || [ "$malformed" -gt 0 ]; then exit 1; fi
  return 0
}

case "${1:-}" in
  --all)                 shift; cmd_all "$@"; exit $? ;;
  log)                   shift; cmd_log "$@"; exit $? ;;
  status)                shift; cmd_status "$@"; exit $? ;;
  oneliner)              shift; cmd_oneliner "$@"; exit $? ;;
  adopted)               shift; cmd_adopted "$@"; exit $? ;;
  phase)                 shift; cmd_phase "$@"; exit $? ;;
  dashboard-task-status) shift; cmd_dashboard_task_status "$@"; exit $? ;;
  task-accept)           shift; cmd_task_accept "$@"; exit $? ;;
  provider-audit)        shift; cmd_provider_audit "$@"; exit $? ;;
  stack)                 shift; cmd_stack "$@"; exit $? ;;
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
# template guidance line present in every review file and reports phantoms. Discovery is the
# shared review-lane walk (pw-reviewlib.sh) — the SAME five lanes the review readers scan, so
# this report can never again cover fewer surfaces than /pw-review; archives (.archive.md)
# never match the *.review.md pattern, _REVIEW.template.md is not a review, and the review/ai/
# handoff packets (immutable snapshot copies) are never scanned.
OPEN_ITEMS=""
PENDING_REVIEWS=""
ESC_LANES=""
_SCAN="$(pw_review_files "$D" 2>/dev/null)" || true
while IFS="$OVTAB" read -r _kind _lane _afile; do
  case "$_kind" in
    escape)
      ESC_LANES="$ESC_LANES$_lane$OVTAB" ;;
    symlink)
      ESC_LANES="$ESC_LANES$_lane/$(basename "$_afile")$OVTAB" ;;
    file)
      _rel="$_lane/$(basename "$_afile")"
      _n="$(pw_review_item_counts "$_afile" | sed -n 's/open=\([0-9]*\).*/\1/p')"; _n="${_n:-0}"
      [ "$_n" -gt 0 ] && OPEN_ITEMS="$OPEN_ITEMS${_rel}|$_n
"
      if ! _review_approval_valid "$_afile" && ! _review_gate_relevant "$_rel" "$PHASE"; then
        _pdisp="$(_review_pending_display "$_afile" || true)"
        [ -n "$_pdisp" ] && PENDING_REVIEWS="$PENDING_REVIEWS${_rel}|$_pdisp
"
      fi
      ;;
  esac
done <<EOF
$_SCAN
EOF
if [ -n "$OPEN_ITEMS" ]; then
  printf '%s' "$OPEN_ITEMS" | while IFS='|' read -r _rel _n; do [ -n "$_rel" ] && echo "  - $_rel ($_n open)"; done
else
  echo "  (none)"
fi
if [ -n "$ESC_LANES" ]; then
  printf '  (skipped — never read through a symlink: %s)\n' "$(printf '%s' "$ESC_LANES" | tr "$OVTAB" ' ' )"
fi
echo

# AI Review modes + scheduling/repair axes. READ-ONLY by contract: the config getters
# INSERT missing dashboard lines as a side effect — a status report must never write.
# Values are read straight from the dashboard through the shared field reader; legacy
# `off` reads as effective advisory (marked, never migrated here — persisting it is
# /pw-config … ensure's job), and absent lines show their effective defaults.
echo "## AI Review modes"
_axis="$(pw_field "$README" "AI Review")"
if [ -n "$_axis" ]; then
  _norm=""
  _legacy_off=0
  for _kv in $_axis; do
    case "${_kv#*=}" in
      off) _norm="$_norm ${_kv%%=*}=advisory"; _legacy_off=1 ;;
      *)   _norm="$_norm $_kv" ;;
    esac
  done
  echo "outcome:${_norm}"
  if [ "$_legacy_off" = 1 ]; then
    echo "  (stored legacy off reads as effective advisory — persist with: /pw-config $SLUG project ensure)"
  fi
else
  echo "outcome: — (line absent; effective default: advisory per surface)"
fi
_axis="$(pw_field "$README" "Review Trigger")"
if [ -n "$_axis" ]; then echo "trigger: $_axis"; else echo "trigger: — (line absent; effective default: manual per surface)"; fi
_axis="$(pw_field "$README" "Review Repair")"
if [ -n "$_axis" ]; then echo "repair:  $_axis"; else echo "repair:  — (line absent; effective default: manual per surface)"; fi
_axis="$(pw_field "$README" "Review Budget")"
if [ -n "$_axis" ]; then echo "budget:  $_axis"; else echo "budget:  — (line absent; effective default: rounds=3)"; fi
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

# Check for unapproved analysis (latest Sign-off row only — historical approvals never
# clear a reopened review; RFC staging is excluded from approval discovery since it has no
# Sign-off gate of its own, its open items already ride the list above).
if [ "$PHASE" = "analysis" ] || [ "$PHASE" = "breakdown" ] || [ "$PHASE" = "executing" ]; then
  ANALYSIS_REVIEW="$D/analysis/review"
  if [ -d "$ANALYSIS_REVIEW" ]; then
    _unapproved=""
    for _rf in "$ANALYSIS_REVIEW"/*.review.md; do
      [ -f "$_rf" ] || continue
      case "${_rf##*/}" in RFC.review.md) continue ;; esac
      _latest_signoff_approved "$_rf" && continue
      _unapproved="$_unapproved ${_rf#$D/}"
    done
    if [ -n "$_unapproved" ]; then
      for _rf in $_unapproved; do
        BLOCKERS+=("Unapproved analysis review: $_rf ($(_latest_signoff_display "$D/$_rf"))")
      done
    fi
  fi
fi

# Check for unapproved PLAN (latest Sign-off row only, not a whole-file "approved" grep)
if [ "$PHASE" = "breakdown" ] || [ "$PHASE" = "executing" ]; then
  if [ -f "$D/task/review/PLAN.review.md" ] && ! _latest_signoff_approved "$D/task/review/PLAN.review.md"; then
    BLOCKERS+=("Unapproved PLAN review ($(_latest_signoff_display "$D/task/review/PLAN.review.md"))")
  fi
fi

# Check for pending review decisions on OPTIONAL lanes (attributed in-review /
# changes-requested latest rows). Gate-relevant files are already named by the Unapproved
# blockers above; placeholder rows (empty actor) are not a decision and never appear here.
if [ -n "$PENDING_REVIEWS" ]; then
  while IFS='|' read -r _rel _disp; do
    [ -n "$_rel" ] && BLOCKERS+=("Pending review decision: $_rel ($_disp)")
  done <<EOF
$PENDING_REVIEWS
EOF
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
    if [ -f "$D/task/review/PLAN.review.md" ] && ! _latest_signoff_approved "$D/task/review/PLAN.review.md"; then
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
