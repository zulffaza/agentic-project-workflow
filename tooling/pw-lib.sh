#!/usr/bin/env bash
# pw-lib.sh — mechanical helpers the /pw-* commands call so the load-bearing, format-sensitive
# steps (dashboard Status, One-liner, LOG.md, phase read) are deterministic instead of hand-edited
# prose. Deterministic + phase-validated so a flaky/cheap executor can't corrupt the dashboard.
#
#   pw-lib.sh status      <slug> <phase> [--rewind]   set dashboard Status: (validated, no accidental
#                                                     backward move) + auto-log the change
#   pw-lib.sh oneliner    <slug> <text...>            set the dashboard One-liner (agent, at analysis)
#   pw-lib.sh adopted     <slug> <text...>            set/insert the dashboard Adopted: pointer (/pw-adopt)
#   pw-lib.sh log         <slug> <actor> <msg...>     append a timestamped LOG.md line (a Markdown
#                                                     bullet — readable in a plain preview view)
#   pw-lib.sh phase       <slug>                       print the current Status value (for scoping/status)
#   pw-lib.sh rfc init      <slug> [backend]            create rfc/RFC.md from the template if missing
#                                                     (+ rfc/META.md stamped with [backend], default markdown)
#   pw-lib.sh rfc target    <slug> <ref>                set/insert rfc/META.md's Target: (external doc ref)
#   pw-lib.sh rfc state     <slug> <field> <value>      set/insert another rfc/META.md field (see --help)
#   pw-lib.sh rfc dashboard <slug> <text...>            set/insert the dashboard RFC: line (/pw-rfc)
#   pw-lib.sh rfc comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>
#                                                     upsert one comment-thread's tracked state
#                                                     (per-thread, not a single scalar cursor)
#   pw-lib.sh ai-review    <slug> [<phase> <mode>]   get (no extra args) or set one phase's AI-review
#                                                     mode on the dashboard (phase: analysis|plan|
#                                                     task-plan|task-exec|ship; mode: off|advisory|auto)
#   pw-lib.sh ai-model     <slug> [<role> <provider:model|—>]
#                                                     get/set one spawn-lane's model row on the
#                                                     dashboard (role: researcher|analyst|
#                                                     writer-task|reviewer|verifier — never the
#                                                     executor, whose pin lives in its task file's
#                                                     `Execute with:`; — = no row = provider default)
#   pw-lib.sh model-check   <provider> <model-id>    pass/refuse a model against
#                                                     PW_MODEL_ALLOWLIST_<PROVIDER> in pw.config.sh
#                                                     — empty/unset = ALL models allowed (the
#                                                     default). Called by /pw-breakdown and
#                                                     /pw-execute; not meant to be run by hand.
#   pw-lib.sh task-accept   <slug> <task-id>         update a task's Status: field to "accepted"
#                                                     (used when an MR is already merged).
#   pw-lib.sh dashboard-task-status <slug> <task-id> <status>
#                                                     update a task's status in the dashboard
#                                                     README.md task status table.
#   pw-lib.sh worktree-remove <slug> <task-id>       safely remove a task's worktree (refuses if
#                                                     the worktree has uncommitted changes or is
#                                                     the current directory). Used when an MR is
#                                                     already merged to clean up the worktree.
#   pw-lib.sh selftest                                 run an isolated round-trip test
#
# Portable across Claude Code and KiloCode executors (plain bash; call by absolute path).
#
# FROZEN (S2, tooling/docs/conventions.md): no NEW subcommands here — add operators to the
# entity's own script instead; shared primitives live in pw-mdlib.sh (sourced below).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # …/agentic-project-workflow/tooling
PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"  # …/projects  (override for tests)
VALID_PHASES="context analysis breakdown executing review done"

# Load pw.config.sh if reachable (same resolution pw-common.sh uses) so forge routing
# (PW_FORGE_HOSTS) and allowlists work when pw-lib.sh is called directly. Never required.
if [ -f "$HERE/../pw.config.sh" ]; then . "$HERE/../pw.config.sh"; fi
if ! declare -p PW_FORGE_HOSTS >/dev/null 2>&1; then PW_FORGE_HOSTS=(); fi

# S5 (tooling/docs/conventions.md): pure markdown-document primitives live in pw-mdlib.sh —
# sourced, never executed. pw-lib.sh is FROZEN for new subcommands (S2): new capability goes
# to a per-entity script (pw-review.sh, pw-context.sh, …), shared code to pw-*lib.sh.
. "$HERE/scripts/lib/pw-mdlib.sh"

die() { echo "pw-lib: $*" >&2; exit 2; }
proj_dir() { local d="$PROJECTS_DIR/$1"; [ -d "$d" ] || die "no such project: $1 ($d)"; printf '%s' "$d"; }

# Phase rank for the monotonic guard. executing and review share a rank on purpose: re-running a
# task flips executing→review→executing repeatedly, which is normal, not a rewind.
phase_rank() {
  case "$1" in
    context)   echo 0 ;; analysis) echo 1 ;; breakdown) echo 2 ;;
    executing) echo 3 ;; review)   echo 3 ;; done)      echo 4 ;;
    *) echo -1 ;;
  esac
}

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
          echo "pw-lib: skipped duplicate log entry for $slug (same actor+message ${diff_min}m ago, within ${window}m window)" >&2
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
  [ $# -eq 2 ] || die "usage: status <slug> <phase> [--rewind]   (phase: $VALID_PHASES)"
  local slug="$1" phase="$2"
  case " $VALID_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $VALID_PHASES)";; esac
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

# --- RFC side-loop (see tooling/docs/rfc.md + tooling/docs/rfc-backends.md) ------------
# Deterministic helpers for the optional /pw-rfc publish loop — never touches the dashboard
# Status: (RFC is a side-loop, not a phase), same discipline as /pw-ship's own helpers.

# Create rfc/RFC.md from the canonical template if (and only if) it doesn't exist yet —
# idempotent, same shape as cmd_review_init. Never clobbers a doc already in progress. Also
# ensures rfc/META.md exists, stamped with the REAL configured backend (not a hardcoded guess) —
# call this with the resolved backend so META.md never drifts from what's actually configured.
#   rfc init <slug> [backend]   (backend defaults to "markdown" if omitted)
cmd_rfc_init() {
  [ $# -ge 1 ] && [ $# -le 2 ] || die "usage: rfc init <slug> [backend]"
  local slug="$1" backend="${2:-markdown}" d; d="$(proj_dir "$slug")"
  local f="$d/rfc/RFC.md"
  _rfc_meta_ensure "$d/rfc/META.md" "$slug" "$backend"
  if [ -f "$f" ]; then
    echo "$slug: rfc already exists: rfc/RFC.md (left untouched)"
    return 0
  fi
  local tmpl="$HERE/../template/rfc/_TEMPLATE-RFC.md"
  [ -f "$tmpl" ] || die "template not found: $tmpl"
  mkdir -p "$d/rfc"
  sed "s/<PROJECT_NAME>/$slug/g" "$tmpl" > "$f"
  cmd_log "$slug" rfc "created rfc/RFC.md from template (backend: $backend)"
  echo "$slug: rfc-init created rfc/RFC.md"
}

# Create rfc/META.md with its fixed skeleton if missing — 🤖-owned, never hand-edited (same
# convention as ADOPTED.md). Private helper shared by rfc init/target/state. Backend defaults to
# "markdown" only when the caller doesn't know better; rfc init always passes the real one so the
# skeleton is correct from the moment it's first created, never left silently wrong.
_rfc_meta_ensure() {
  local f="$1" slug="$2" backend="${3:-markdown}"
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")"
  {
    printf '# RFC metadata — %s   [🤖-owned — never hand-edit; see `pw-lib.sh rfc target|state`]\n\n' "$slug"
    printf -- '- **Backend:** %s\n' "$backend"
    printf -- '- **Target:** \n'
    printf -- '- **Last revision pushed:** \n'
    printf -- '- **Wave 1 published:** no\n'
    printf -- '- **Wave 2 published:** no\n'
  } > "$f"
}

# Ensure rfc/META.md has a "## Comment tracking" table (create the header if missing) — lazily
# added only once a thread is actually seen, so a project with no comments yet never grows this
# section. Private helper for cmd_rfc_comment_seen.
_rfc_comment_section_ensure() {
  local f="$1"
  grep -q '^## Comment tracking' "$f" 2>/dev/null && return 0
  {
    printf '\n## Comment tracking   [🤖-owned — never hand-edit; see `pw-lib.sh rfc comment-seen`]\n\n'
    printf '| Thread | Replies seen | Solved |\n'
    printf '|--------|--------------|--------|\n'
  } >> "$f"
}

# Set/insert a `- **<label>:** <value>` line in a metadata file — insert-if-absent, else
# replace-in-place. Same shape as cmd_adopted, generalized to a parameterized file + label.
_rfc_meta_upsert() {
  local f="$1" label="$2" value="$3"
  if grep -qF -- "- **$label:**" "$f"; then
    awk -v l="$label" -v v="$value" '!d && index($0, "- **" l ":**")==1 { print "- **" l ":** " v; d=1; next } { print }' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf -- '- **%s:** %s\n' "$label" "$value" >> "$f"
  fi
}

# Set/insert rfc/META.md's Target: (the external doc ref a publish goes to). Persists per-project
# so a later /pw-rfc run doesn't need --target repeated.
#   rfc target <slug> <ref>
cmd_rfc_target() {
  [ $# -eq 2 ] || die "usage: rfc target <slug> <ref>"
  local slug="$1" ref="$2" d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  _rfc_meta_ensure "$f" "$slug"
  _rfc_meta_upsert "$f" "Target" "$ref"
  cmd_log "$slug" rfc "target set: $ref"
  echo "$slug: rfc target -> $ref"
}

# Set/insert any other rfc/META.md field.
#   rfc state <slug> <field> <value>   (field: Backend|LastRevision|Wave1Published|Wave2Published)
cmd_rfc_state() {
  [ $# -eq 3 ] || die "usage: rfc state <slug> <field> <value>   (field: Backend|LastRevision|Wave1Published|Wave2Published)"
  local slug="$1" field="$2" value="$3" d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  local label
  case "$field" in
    Backend)        label="Backend" ;;
    LastRevision)   label="Last revision pushed" ;;
    Wave1Published) label="Wave 1 published" ;;
    Wave2Published) label="Wave 2 published" ;;
    *) die "unknown rfc state field '$field' (allowed: Backend LastRevision Wave1Published Wave2Published)" ;;
  esac
  _rfc_meta_ensure "$f" "$slug"
  _rfc_meta_upsert "$f" "$label" "$value"
  cmd_log "$slug" rfc "state $field=$value"
  echo "$slug: rfc state $field -> $value"
}

# Deterministically upsert ONE row per comment thread, keyed by a hidden
# `<!-- pw-rfc-comment:<thread-id> -->` marker — same append-or-rewrite-in-place shape as
# _scope_upsert (context/INDEX.md's adoption rows). This is what lets `/pw-rfc comments` tell
# "never seen this thread" from "seen before, N replies then, M replies now" from "already
# recorded as solved" — a single scalar watermark can't represent per-thread state (the bug: an
# earlier thread getting new replies after a later thread became "latest" was invisible forever).
#   rfc comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>
cmd_rfc_comment_seen() {
  [ $# -eq 4 ] || die "usage: rfc comment-seen <slug> <thread-id> <reply-count> <solved:yes|no>"
  local slug="$1" thread="$2" replies="$3" solved="$4"
  case "$solved" in yes|no) ;; *) die "solved must be 'yes' or 'no' (got '$solved')" ;; esac
  case "$replies" in ''|*[!0-9]*) die "reply-count must be a non-negative integer (got '$replies')" ;; esac
  local d; d="$(proj_dir "$slug")"; local f="$d/rfc/META.md"
  _rfc_meta_ensure "$f" "$slug"
  _rfc_comment_section_ensure "$f"
  local marker="<!-- pw-rfc-comment:$thread -->"
  local row="| \`$thread\` | $replies | $solved $marker |"
  if grep -Fq "$marker" "$f"; then
    awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    printf '%s\n' "$row" >> "$f"
  fi
  cmd_log "$slug" rfc "comment-seen $thread: $replies replies, solved=$solved"
  echo "$slug: rfc comment-seen $thread -> $replies replies, solved=$solved"
}

# Set/insert the project dashboard's `- **RFC:**` line — mirrors cmd_adopted almost verbatim,
# anchoring after Adopted: if present (dashboard field order: Status → One-liner → [Adopted] →
# [RFC]), else after One-liner.
#   rfc dashboard <slug> <text...>
cmd_rfc_dashboard() {
  [ $# -ge 2 ] || die "usage: rfc dashboard <slug> <text...>"
  local slug="$1"; shift; local text="$*"
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  if grep -q '^- \*\*RFC:\*\*' "$f"; then
    awk -v t="$text" '!d && /^- \*\*RFC:\*\*/ {print "- **RFC:** " t; d=1; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  elif grep -q '^- \*\*Adopted:\*\*' "$f"; then
    awk -v t="$text" '{print} !d && /^- \*\*Adopted:\*\*/ {print "- **RFC:** " t; d=1}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    grep -q '^- \*\*One-liner:\*\*' "$f" || die "no anchor line (Adopted:/One-liner:) in $f"
    awk -v t="$text" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **RFC:** " t; d=1}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  cmd_log "$slug" rfc "dashboard: $text"
  echo "$slug: RFC -> $text"
}

cmd_rfc() {
  case "${1:-}" in
    init)         shift; cmd_rfc_init "$@" ;;
    target)       shift; cmd_rfc_target "$@" ;;
    state)        shift; cmd_rfc_state "$@" ;;
    dashboard)    shift; cmd_rfc_dashboard "$@" ;;
    comment-seen) shift; cmd_rfc_comment_seen "$@" ;;
    *) die "usage: rfc <init|target|state|dashboard|comment-seen> ..." ;;
  esac
}

# --- AI Models (per-lane model row for the spawned sub-agent lanes — plan 01 §5.1) -----------
# The model sibling of the AI Review config block below: which model a *lane* should run on when a
# phase spawns it, per project. Roles = spawn lanes (researcher / analyst / writer-task / reviewer /
# verifier). The **executor is never a row** — a task's `Execute with:` already pins its per-unit
# model (a dashboard copy would only drift from it) — and clean-execution choices (`Results
# acceptance`, `- AI execution limit`) live in PLAN's Execution strategy, not the dashboard.
# `—` = no row = provider/session default (the kilo `small_model`/`subagent_model` floor, or
# claude's session/def model). Values are `<provider>:<model>`-shaped — the same syntax as
# `Execute with:` (tooling/docs/providers.md). Where a provider can't bind the row at spawn time
# (kilo's Task-tool spawn has no model arg), the driver runs the row as a **headless session** of
# that model over the same work order, and records what actually ran — a pin that can't fire says
# so in the result, instead of silently running the floor model while the row claims a pin.
AI_MODEL_ROLES="researcher analyst writer-task reviewer verifier"

# Idempotent: insert the dashboard line, all-—, if it doesn't exist yet (covers projects scaffolded
# before this feature existed — same ensure-if-missing idiom as _ai_review_line_ensure).
_ai_models_line_ensure() {
  local f="$1"
  grep -q '^- \*\*AI Models:\*\*' "$f" && return 0
  local default="" r
  for r in $AI_MODEL_ROLES; do default="$default $r=—"; done
  default="${default# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor AI Models: after in $f"
  awk -v t="$default" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **AI Models:** " t; d=1}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Get (no extra args) or set (role + value; — clears to no-row).
#   ai-model <slug>                                -> "researcher=— analyst=— writer-task=— reviewer=— verifier=—"
#   ai-model <slug> <role> <provider:model|—>      -> sets just that lane, leaves the other four untouched
cmd_ai_model() {
  [ $# -ge 1 ] || die "usage: ai-model <slug> [<role> <provider:model|—>]   (role: $AI_MODEL_ROLES)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_models_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -eq 2 ] || die "usage: ai-model <slug> <role> <provider:model|—>   (role: $AI_MODEL_ROLES)"
  local role="$1" value="$2"
  case " $AI_MODEL_ROLES " in *" $role "*) ;; *) die "invalid role '$role' (allowed: $AI_MODEL_ROLES)" ;; esac
  case "$value" in
    —|-) ;;  # clearing to no-row is always valid
    *:*) ;;
    *) die "invalid value '$value' — write <provider>:<model> (e.g. kilo:command_code/<m>, claude:sonnet) or — for no row" ;;
  esac
  local cur; cur="$(grep '^- \*\*AI Models:\*\*' "$f" | sed 's/^- \*\*AI Models:\*\*[[:space:]]*//')"
  local new="" found=0 kv k
  for kv in $cur; do
    k="${kv%%=*}"
    if [ "$k" = "$role" ]; then new="$new $role=$value"; found=1
    else new="$new $kv"; fi
  done
  [ "$found" -eq 1 ] || new="$new $role=$value"
  new="${new# }"
  awk -v t="$new" '!d && /^- \*\*AI Models:\*\*/ {print "- **AI Models:** " t; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" ai-model "$role -> $value"
  echo "$slug: AI Model $role -> $value"
}

# --- AI-assisted review (optional delegated review pass — see docs/REVIEW.md + the pw-review
# skill) -----------------------------------------------------------------------------------------
# One config axis per (project, phase): off (default, no change to today's behavior) | advisory
# (pw-reviewer files items, a human still signs off) | auto (pw-reviewer may ALSO sign off itself,
# but ONLY through cmd_review_auto_signoff below, and ONLY when this mode is genuinely "auto").
AI_REVIEW_PHASES="analysis plan task-plan task-exec ship"

# Idempotent: insert the dashboard line, all-off, if it doesn't exist yet (covers projects
# scaffolded before this feature existed — same "never assume, always ensure" idiom as
# _rfc_meta_ensure). Anchored after One-liner, same convention as cmd_adopted.
_ai_review_line_ensure() {
  local f="$1"
  grep -q '^- \*\*AI Review:\*\*' "$f" && return 0
  local default="" p
  for p in $AI_REVIEW_PHASES; do default="$default $p=off"; done
  default="${default# }"
  grep -q '^- \*\*One-liner:\*\*' "$f" || die "no '- **One-liner:**' line to anchor AI Review: after in $f"
  awk -v t="$default" '{print} !d && /^- \*\*One-liner:\*\*/ {print "- **AI Review:** " t; d=1}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Get (no extra args) or set (phase + mode) this project's per-phase AI-review mode.
#   ai-review <slug>                 -> prints "analysis=off plan=off task-plan=off task-exec=off ship=off"
#   ai-review <slug> <phase> <mode>  -> sets just that phase's mode, leaves the other four untouched
cmd_ai_review() {
  [ $# -ge 1 ] || die "usage: ai-review <slug> [<phase> <mode>]   (phase: $AI_REVIEW_PHASES; mode: off|advisory|auto)"
  local slug="$1"; shift
  local f; f="$(proj_dir "$slug")/README.md"
  [ -f "$f" ] || die "no README.md in project $slug"
  _ai_review_line_ensure "$f"
  if [ $# -eq 0 ]; then
    grep '^- \*\*AI Review:\*\*' "$f" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//'
    return 0
  fi
  [ $# -eq 2 ] || die "usage: ai-review <slug> <phase> <mode>   (phase: $AI_REVIEW_PHASES; mode: off|advisory|auto)"
  local phase="$1" mode="$2"
  case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
  case "$mode" in off|advisory|auto) ;; *) die "invalid mode '$mode' (allowed: off advisory auto)" ;; esac
  local cur; cur="$(grep '^- \*\*AI Review:\*\*' "$f" | sed 's/^- \*\*AI Review:\*\*[[:space:]]*//')"
  local new="" found=0 kv k
  for kv in $cur; do
    k="${kv%%=*}"
    if [ "$k" = "$phase" ]; then new="$new $phase=$mode"; found=1
    else new="$new $kv"; fi
  done
  [ "$found" -eq 1 ] || new="$new $phase=$mode"
  new="${new# }"
  awk -v t="$new" '!d && /^- \*\*AI Review:\*\*/ {print "- **AI Review:** " t; d=1; next} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" ai-review "$phase -> $mode"
  echo "$slug: AI Review $phase -> $mode"
}



# Guard against an agent picking an unexpectedly expensive model. Reads PW_MODEL_ALLOWLIST_<PROVIDER>
# (uppercased) from pw.config.sh — a comma-separated list of glob patterns matched against the
# model id (the part after the provider prefix, e.g. "opus" or "command_code/deepseek/*").
# THE RULE: empty or unset = ALL models allowed for that provider — this is the default, and it's
# deliberate: nothing is restricted unless you explicitly configure a pattern. Never taken on the
# caller's word — this re-reads the config itself, same spirit as auto-signoff re-checking its own
# gate rather than trusting the reviewer. Called by /pw-breakdown (while filling a task's `Execute
# with:`) and /pw-execute (again, right before invoking — catches a hand-edited PLAN.md too); not
# meant to be run directly by a human — see docs/EXECUTION.md's "Model allowlist" section.
#   model-check <provider> <model-id>
cmd_model_check() {
  [ $# -eq 2 ] || die "usage: model-check <provider> <model-id>   (empty PW_MODEL_ALLOWLIST_<PROVIDER> = all models allowed)"
  local prov="$1" model="$2" upper var allow pats pat matched=0
  upper="$(printf '%s' "$prov" | tr '[:lower:]' '[:upper:]')"
  var="PW_MODEL_ALLOWLIST_${upper}"
  allow="${!var:-}"
  if [ -z "$allow" ]; then
    echo "model-check: $prov:$model — allowed (PW_MODEL_ALLOWLIST_${upper} is empty = all models allowed, the default)"
    return 0
  fi
  IFS=',' read -ra pats <<< "$allow"
  for pat in "${pats[@]}"; do
    pat="$(printf '%s' "$pat" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$model" in
      $pat) matched=1; break ;;
    esac
  done
  if [ "$matched" -eq 1 ]; then
    echo "model-check: $prov:$model — allowed (matched allowlist pattern \"$pat\")"
    return 0
  fi
  die "model-check: $prov:$model — refused. Not in PW_MODEL_ALLOWLIST_${upper} (\"$allow\"). Add a matching pattern to pw.config.sh, or choose an allowed model."
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

# Safely remove a task's worktree (used when MR is already merged).
#   worktree-remove <slug> <task-id>
cmd_worktree_remove() {
  [ $# -eq 2 ] || die "usage: worktree-remove <slug> <task-id>"
  local slug="$1" task="$2"
  local d; d="$(proj_dir "$slug")"
  local wt="$d/worktree"

  # Find the worktree directory for this task
  local task_wt
  task_wt="$(find "$wt" -maxdepth 3 -type d -name "$task-*" 2>/dev/null | head -1)"
  [ -n "$task_wt" ] && [ -d "$task_wt" ] || { echo "no worktree found for $task"; return 1; }

  # Delegate to pw-teardown.sh — the single owner of the safety guards (refuses the worktree
  # you're standing in, refuses one with uncommitted changes). Never passes --yes: a dirty worktree
  # must be committed/stashed first, exactly as /pw-close requires. Exit 1 from teardown means it
  # skipped the worktree (reason already printed) — don't log "removed".
  "$HERE/scripts/entities/pw-teardown.sh" "$d" "" "$task_wt" || return 1
  cmd_log "$slug" sync "$task: worktree removed (MR already merged)"
  echo "$slug: $task worktree removed"
}

cmd_selftest() {
  local SELF_LIB="$HERE/pw-lib.sh"   # re-spawn by resolved path — bare "$0" can't exec without a slash
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n  <!-- comment stays -->\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo analysis >/dev/null
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" phase demo)"
  [ "$got" = "analysis" ] || die "selftest FAIL: phase='$got' (expected analysis)"
  grep -q '<!-- comment stays -->' "$tmp/demo/README.md" || die "selftest FAIL: clobbered trailing comment"
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `status` — Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing/wrong format"
  # One-liner setter
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" oneliner demo "toggle kafka usage safely" >/dev/null
  grep -q '^- \*\*One-liner:\*\* toggle kafka usage safely$' "$tmp/demo/README.md" || die "selftest FAIL: one-liner not set"
  # Monotonic guard: a backward move without --rewind must fail…
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo context >/dev/null 2>&1; then
    die "selftest FAIL: backward status move was NOT blocked"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" phase demo)" = "analysis" ] || die "selftest FAIL: blocked move still mutated Status"
  # …but --rewind is allowed, and executing↔review (same rank) is never treated as backward.
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo executing >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo review >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo executing >/dev/null   # re-run a task: not a rewind
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" phase demo)" = "executing" ] || die "selftest FAIL: executing↔review blocked"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" status demo analysis --rewind >/dev/null
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" phase demo)" = "analysis" ] || die "selftest FAIL: --rewind did not apply"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" log demo analyze "wrote analysis/x.md" >/dev/null
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `analyze` — wrote analysis/x\.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing/wrong format"
  # Adopted pointer: inserted after One-liner when absent, then replaced in place (idempotent).
  grep -q '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" && die "selftest FAIL: Adopted line present before adopt"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" adopted demo "1 unit — see context/ADOPTED.md" >/dev/null
  grep -q '^- \*\*Adopted:\*\* 1 unit — see context/ADOPTED.md$' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not inserted"
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*Adopted:\*\*' || die "selftest FAIL: Adopted not anchored after One-liner"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" adopted demo "2 units — see context/ADOPTED.md" >/dev/null
  [ "$(grep -c '^- \*\*Adopted:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: Adopted duplicated instead of replaced"
  grep -q '^- \*\*Adopted:\*\* 2 units' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not updated"
  # adopt: multi-unit append MUST NOT clobber (the reported bug). Two branches, same repo.
  mkdir -p "$tmp/demo/context"
  # An INDEX.md with a provenance table (empty placeholder) AND a "Repos in scope" table (empty
  # placeholder) so we can assert both the one-time provenance row and the no-clobber scope rows.
  printf '# Context index\n\n| File / link | What it is | Source | Date added | Trust notes |\n|---|---|---|---|---|\n| | | | | |\n\n## Repos in scope\n| Repo | Base branch | Why |\n|------|-------------|-----|\n| | | |\n' \
    > "$tmp/demo/context/INDEX.md"
  local IX="$tmp/demo/context/INDEX.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-context.sh" adopt demo repoX feat-a master "http://mr/1" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-context.sh" adopt demo repoX feat-b spring3 "http://mr/2" >/dev/null
  local A; A="$tmp/demo/context/ADOPTED.md"
  grep -q '^## A1 · repoX @ feat-a' "$A" || die "selftest FAIL: unit A1 clobbered by 2nd adopt"
  grep -q '^## A2 · repoX @ feat-b' "$A" || die "selftest FAIL: unit A2 not appended"
  [ "$(grep -c '^## A[0-9]* · ' "$A")" = "2" ] || die "selftest FAIL: expected 2 adoption units"
  grep -q '^- \*\*Adopted:\*\* 2 unit(s)' "$tmp/demo/README.md" || die "selftest FAIL: unit count not 2"
  # re-adopt A1 with a corrected base/MR → updates in place, still 2 units, prose untouched
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-context.sh" adopt demo repoX feat-a develop "http://mr/1b" >/dev/null
  [ "$(grep -c '^## A[0-9]* · ' "$A")" = "2" ] || die "selftest FAIL: re-adopt duplicated a unit"
  awk '/^## A1 · /{u=1} u&&/^- Base: /{print;exit}' "$A" | grep -q 'develop' || die "selftest FAIL: A1 base not updated in place"
  awk '/^## A2 · /{u=1} u&&/^- Base: /{print;exit}' "$A" | grep -q 'spring3' || die "selftest FAIL: A2 base wrongly changed"
  # scope table (INDEX.md): both units got a row, empty placeholder dropped, no clobber…
  grep -q 'pw-adopt-scope:repoX@feat-a' "$IX" || die "selftest FAIL: scope row for feat-a missing"
  grep -q 'pw-adopt-scope:repoX@feat-b' "$IX" || die "selftest FAIL: scope row for feat-b clobbered/missing"
  [ "$(grep -c 'pw-adopt-scope:' "$IX")" = "2" ] || die "selftest FAIL: expected 2 scope rows"
  grep -qE '^\| +\| +\|' "$IX" && die "selftest FAIL: empty placeholder scope row not dropped"
  # …and the re-adopt of A1 (base develop, above) rewrote ONLY feat-a's scope row in place.
  grep 'pw-adopt-scope:repoX@feat-a' "$IX" | grep -q 'origin/develop' || die "selftest FAIL: feat-a scope row base not updated"
  grep 'pw-adopt-scope:repoX@feat-b' "$IX" | grep -q 'origin/spring3'  || die "selftest FAIL: feat-b scope row wrongly changed"
  [ "$(grep -c 'pw-adopt-scope:' "$IX")" = "2" ] || die "selftest FAIL: re-adopt duplicated a scope row"
  # provenance row: inserted exactly once, generic (not per-unit enumerated), never rewritten/duped
  # across the multiple adopts above.
  [ "$(grep -cE '^\|[^|]*ADOPTED\.md' "$IX")" = "1" ] || die "selftest FAIL: expected exactly one ADOPTED.md provenance row"
  grep -qE '^\|[^|]*ADOPTED\.md.*all continuation units' "$IX" || die "selftest FAIL: provenance row not generic"
  grep -qE '^\|[^|]*ADOPTED\.md.*feat-a' "$IX" && die "selftest FAIL: provenance row enumerated a unit (should stay generic)"

  # --- rfc side-loop -----------------------------------------------------
  # rfc init: creates rfc/RFC.md verbatim from the template (placeholder stamped), idempotent —
  # a 2nd call never clobbers a manual edit. Also ensures rfc/META.md, stamped with the REAL
  # backend passed in (not a hardcoded guess) — the bug a live fresh-context test caught.
  local RFC="$tmp/demo/rfc/RFC.md" META="$tmp/demo/rfc/META.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc init demo >/dev/null
  [ -f "$RFC" ] || die "selftest FAIL: rfc init did not create rfc/RFC.md"
  grep -q '^# RFC: demo$' "$RFC" || die "selftest FAIL: rfc init did not stamp the project slug"
  [ -f "$META" ] || die "selftest FAIL: rfc init did not also create rfc/META.md"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc init (no backend arg) did not default META.md's Backend to markdown"
  printf '\nmanual edit\n' >> "$RFC"                          # simulate a human/agent edit
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc init demo >/dev/null
  grep -q '^manual edit$' "$RFC" || die "selftest FAIL: rfc init clobbered an existing RFC.md"

  # rfc init <slug> <backend>: on a FRESH project (no rfc/ yet), stamps the REAL backend into
  # META.md from the start — this is the actual regression test for the bug above.
  mkdir -p "$tmp/backend-check"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/backend-check/README.md"
  : > "$tmp/backend-check/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc init backend-check lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$tmp/backend-check/rfc/META.md" || die "selftest FAIL: rfc init <slug> lark did not stamp the real backend"

  # rfc target: upserts Target on the ALREADY-EXISTING META.md (from rfc init above), sets Target;
  # a 2nd call with a different ref replaces in place (still exactly one Target: line) without
  # touching Backend.
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc target demo "https://example.com/doc/1" >/dev/null
  grep -q '^- \*\*Target:\*\* https://example.com/doc/1$' "$META" || die "selftest FAIL: rfc target not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc target demo "https://example.com/doc/2" >/dev/null
  [ "$(grep -c '^- \*\*Target:\*\*' "$META")" = "1" ] || die "selftest FAIL: rfc target duplicated instead of replaced"
  grep -q '^- \*\*Target:\*\* https://example.com/doc/2$' "$META" || die "selftest FAIL: rfc target not updated"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc target touched an unrelated field"

  # rfc state: round-trips for each allowed field; an unknown field is rejected and leaves the
  # file untouched (same idiom as the backward-status-move guard above).
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo Backend lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$META" || die "selftest FAIL: rfc state Backend not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo Wave1Published yes >/dev/null
  grep -q '^- \*\*Wave 1 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave1Published not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo Wave2Published yes >/dev/null
  grep -q '^- \*\*Wave 2 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave2Published not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo LastRevision 42 >/dev/null
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rfc state LastRevision not set"
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo Bogus x >/dev/null 2>&1; then
    die "selftest FAIL: rfc state accepted an unknown field"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc state demo CommentCursor thread-9 >/dev/null 2>&1; then
    die "selftest FAIL: rfc state still accepts the retired CommentCursor field"
  fi
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rejected rfc state call mutated the file"

  # rfc comment-seen: per-thread tracking (replaces the old single-scalar Comment cursor, which
  # couldn't tell "an earlier thread got new replies" from "already handled" once a later thread
  # became the recorded 'latest'). New thread → new row; re-seeing the SAME thread with a higher
  # reply count updates that row in place (no duplicate); flipping solved does the same.
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-A 1 no >/dev/null
  grep -q '^## Comment tracking' "$META" || die "selftest FAIL: comment-seen did not create the tracking section"
  grep -qF '<!-- pw-rfc-comment:thread-A -->' "$META" || die "selftest FAIL: thread-A row not created"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 1 | no ' || die "selftest FAIL: thread-A row has wrong reply-count/solved"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-B 1 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: expected 2 tracked threads after thread-B"
  # thread-A gets a 2nd reply later (the exact scenario the scalar cursor got wrong) → same row,
  # updated in place, still only 2 tracked threads total (no duplicate for thread-A).
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-A 2 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: re-seeing thread-A duplicated a row instead of updating in place"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 2 | no ' || die "selftest FAIL: thread-A reply-count not updated"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | no ' || die "selftest FAIL: thread-B wrongly changed by thread-A's update"
  # thread-B gets resolved externally → solved flips in place, still no duplicate.
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-B 1 yes >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: flipping solved duplicated thread-B's row"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | yes ' || die "selftest FAIL: thread-B solved flag not updated"
  # validation: reply-count must be a non-negative integer, solved must be yes/no; a bad call is
  # rejected and doesn't touch existing rows.
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-C -1 no >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a negative reply-count"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc comment-seen demo thread-C 1 maybe >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a non yes/no solved value"
  fi
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: rejected comment-seen calls still mutated the tracking table"

# (ship comment-seen asserts moved to scripts/entities/pw-ship.sh + tests/cases/pw-ship.t.sh — plan 20)

  # rfc dashboard: inserted after Adopted: when one exists (demo already has one from the adopt
  # tests above); inserted after One-liner when no Adopted: line exists (a fresh project); a 2nd
  # call replaces in place (still exactly one RFC: line either way).
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc dashboard demo "wave 1 published — https://example.com/doc/2" >/dev/null
  grep -q '^- \*\*RFC:\*\* wave 1 published' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not inserted"
  grep -A1 '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after Adopted:"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc dashboard demo "wave 2 published" >/dev/null
  [ "$(grep -c '^- \*\*RFC:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: RFC line duplicated instead of replaced"
  grep -q '^- \*\*RFC:\*\* wave 2 published$' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not updated"

  mkdir -p "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" rfc dashboard demo2 "wave 1 published" >/dev/null
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo2/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after One-liner when no Adopted: exists"

  # --- AI-assisted review -------------------------------------------------
  # ai-review: get on a project with no AI Review line yet auto-creates it, all-off; set updates
  # exactly one phase, leaving the other four untouched; invalid phase/mode rejected.
  local got_ai; got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=off task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review default line wrong: '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2 plan auto >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review set did not update only 'plan': '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2 analysis advisory >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review 2nd set clobbered the 1st: '$got_ai'"
  [ "$(grep -c '^- \*\*AI Review:\*\*' "$tmp/demo2/README.md")" = "1" ] || die "selftest FAIL: AI Review line duplicated"
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2 bogus-phase auto >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid phase"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2 plan bogus-mode >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid mode"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-review demo2)" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: rejected ai-review calls still mutated the line"


  # --- model-check: empty/unset allowlist = all models allowed (the default rule) ---
  local mc
  mc="$(PW_MODEL_ALLOWLIST_CLAUDE="" "$SELF_LIB" model-check claude some-random-model-nobody-configured)" \
    || die "selftest FAIL: model-check refused with an empty allowlist (should always pass)"
  echo "$mc" | grep -q "all models allowed" || die "selftest FAIL: model-check's empty-allowlist message didn't state the 'all models allowed' rule"
  # a configured allowlist passes a matching model...
  PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$SELF_LIB" model-check claude sonnet >/dev/null \
    || die "selftest FAIL: model-check refused a model matching its configured allowlist"
  # ...glob patterns match...
  PW_MODEL_ALLOWLIST_KILO="command_code/deepseek/*" "$SELF_LIB" model-check kilo command_code/deepseek/deepseek-v4-flash >/dev/null \
    || die "selftest FAIL: model-check refused a model matching a glob pattern in its allowlist"
  # ...and refuses one that doesn't, without silently passing.
  if PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$SELF_LIB" model-check claude opus >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a model NOT in its configured allowlist"
  fi
  # ...cursor provider (2026-09): the rules are provider-generic, but the bracket-param quirk is
  # cursor-specific and worth locking: catalog ids carry 'gpt-5.6-sol-high[effort=high]' style
  # suffixes; model-check's shell `case` GLOB treats a bracket literal-ish (char class), so docs
  # steer allowlist patterns to the suffix-free id part with '*' — here we assert the plain, glob,
  # and refuse paths so a future refactor can't silently change that contract.
  mc="$(PW_MODEL_ALLOWLIST_CURSOR="" "$SELF_LIB" model-check cursor cursor-grok-4.6-low)" \
    || die "selftest FAIL: model-check refused cursor with an empty allowlist (should always pass)"
  PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*,gpt-5*" "$SELF_LIB" model-check cursor gpt-5.6-sol >/dev/null \
    || die "selftest FAIL: model-check refused cursor model matching an allowlist glob"
  if PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*" "$SELF_LIB" model-check cursor gpt-5.6-everything >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a cursor model NOT in its configured allowlist"
  fi

  # --- cmd_log duplicate-guard ---------------------------------------------------------
  # The real, observed bug: a live project's LOG.md had the identical actor+message logged twice
  # (once even three times) back-to-back within minutes. Calling log twice with the exact same
  # actor+message must not double-append; a genuinely different message right after must NOT be
  # deduped; the SAME message again, but outside the dedup window, must append (not be dropped).
  mkdir -p "$tmp/logtest"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/logtest/README.md"
  : > "$tmp/logtest/LOG.md"
  local LT="$tmp/logtest/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "1" ] || die "selftest FAIL: duplicate log entry was not deduped"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "2" ] || die "selftest FAIL: a distinct message was wrongly deduped"
  sed -i '' -e 's/^- \*\*[^*]*\*\*/- **2020-01-01 00:00**/' "$LT"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "3" ] || die "selftest FAIL: an identical message outside the dedup window was wrongly skipped"

  # --- review reindex / review archive -------------------------------------------------
  mkdir -p "$tmp/reviewtest/analysis"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/reviewtest/README.md"
  : > "$tmp/reviewtest/LOG.md"
  printf '# Analysis: rt\n' > "$tmp/reviewtest/analysis/rt.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" init reviewtest analysis/review/rt.review.md analysis/rt.md >/dev/null
  local RTV="$tmp/reviewtest/analysis/review/rt.review.md"
  # Add a 2nd OPEN item and a RESOLVED item into ## Items, BEFORE ## Open questions — realistic
  # placement (never a blind end-of-file append, which would land after ## Sign-off and prove
  # nothing). Written to a temp file with plain printf, then head/tail/cat-spliced in — NOT
  # `awk -v` with this multi-line block: macOS's stock awk rejects a `-v` value containing embedded
  # newlines ("awk: newline in string") — the exact portability trap _ship_comment_section_ensure's
  # own comment already documents; sidestep it here the same way that function does.
  local newitems; newitems="$(mktemp)"
  {
    printf '### R2 · §3 second item — [OPEN] (you, 2026-08-19 10:00) <!-- pw-item-status: open -->\n'
    printf 'Second ask, still open.\n\n---\n\n'
    printf '### R3 · §4 third item — [RESOLVED] (you, 2026-08-19 09:00) <!-- pw-item-status: resolved -->\n'
    printf 'Third ask, already fixed.\n\n'
    printf '> ↳ **agent** (2026-08-19 09:30): §4 — fixed as asked.\n\n---\n\n'
  } > "$newitems"
  local oqline; oqline="$(grep -n '^## Open questions' "$RTV" | head -1 | cut -d: -f1)"
  { head -n "$((oqline-1))" "$RTV"; cat "$newitems"; tail -n "+${oqline}" "$RTV"; } > "$RTV.tmp" && mv "$RTV.tmp" "$RTV"
  rm -f "$newitems"
  # Clear the template's own live R1/Q1 stubs (same convention as the auto-signoff test above —
  # never a real "fix", just clearing a never-filled-in placeholder) so this test is isolated to
  # R2/R3.
  sed -i '' -e '/^### R1 · <§section or anchor> — \[OPEN\]/,+1d' \
            -e '/^### Q1 · <§section> — \[PENDING\]/,+1d' "$RTV"

  # reindex: builds a Contents table with exactly R2 (open) and R3 (resolved) — ignoring the
  # template's own commented-out worked-example headings (R1/Q1, still present verbatim above the
  # live section) — and is idempotent (a 2nd run replaces the block in place, never duplicates it).
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" reindex reviewtest analysis/review/rt.review.md >/dev/null
  grep -q '<!-- pw-contents:begin -->' "$RTV" || die "selftest FAIL: review reindex did not insert a Contents block"
  local CT1; CT1="$(sed -n '/pw-contents:begin/,/pw-contents:end/p' "$RTV")"
  printf '%s\n' "$CT1" | grep -qF '| R2 | §3 second item | [OPEN] |' || die "selftest FAIL: reindex Contents missing/wrong R2 row"
  printf '%s\n' "$CT1" | grep -qF '| R3 | §4 third item | [RESOLVED] |' || die "selftest FAIL: reindex Contents missing/wrong R3 row"
  printf '%s\n' "$CT1" | grep -q '| R1 |' && die "selftest FAIL: reindex Contents picked up a commented-out worked-example heading"
  [ "$(grep -c '<!-- pw-contents:begin -->' "$RTV")" = "1" ] || die "selftest FAIL: reindex duplicated the Contents begin-marker"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" reindex reviewtest analysis/review/rt.review.md >/dev/null
  [ "$(grep -c '<!-- pw-contents:begin -->' "$RTV")" = "1" ] || die "selftest FAIL: re-running reindex duplicated the Contents block instead of replacing it in place"
  [ "$(grep -c '^## Contents' "$RTV")" = "1" ] || die "selftest FAIL: re-running reindex duplicated the Contents heading"

  # archive: gate-safety proof — capture the Sign-off section + has-open verdict BEFORE, run
  # archive, assert both are UNCHANGED after, R3's heading is gone from the live file, R2's is
  # untouched, the archive file has R3's text verbatim (including its reply), and a pointer row
  # with the right marker landed in a new "## Archived items" section.
  local before_signoff before_hasopen
  before_signoff="$(sed -n '/^## Sign-off/,$p' "$RTV")"
  before_hasopen="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" has-open reviewtest analysis/review/rt.review.md)"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" archive reviewtest analysis/review/rt.review.md >/dev/null
  local after_signoff after_hasopen
  after_signoff="$(sed -n '/^## Sign-off/,$p' "$RTV")"
  after_hasopen="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" has-open reviewtest analysis/review/rt.review.md)"
  [ "$before_signoff" = "$after_signoff" ] || die "selftest FAIL: review archive changed the Sign-off table/section — gate-safety broken"
  [ "$before_hasopen" = "$after_hasopen" ] || die "selftest FAIL: review archive changed has-open's verdict ($before_hasopen -> $after_hasopen)"
  [ "$after_hasopen" = "yes" ] || die "selftest FAIL: R2 should still be open after archiving R3 (test assumption invalid)"
  grep -q '^### R3 · §4 third item' "$RTV" && die "selftest FAIL: R3's heading is still in the live file after archiving"
  grep -q '^### R2 · §3 second item' "$RTV" || die "selftest FAIL: R2's heading was removed by archive (should be untouched — still [OPEN])"
  local RTA="$tmp/reviewtest/analysis/review/rt.archive.md"
  [ -f "$RTA" ] || die "selftest FAIL: review archive did not create rt.archive.md"
  grep -q '^### R3 · §4 third item — \[RESOLVED\]' "$RTA" || die "selftest FAIL: R3's heading not moved verbatim into the archive file"
  grep -qF '> ↳ **agent** (2026-08-19 09:30): §4 — fixed as asked.' "$RTA" || die "selftest FAIL: R3's reply text not preserved verbatim in the archive file"
  grep -q '^## Archived items' "$RTV" || die "selftest FAIL: review archive did not add an Archived items section"
  grep -qF '<!-- pw-archived:R3 -->' "$RTV" || die "selftest FAIL: no pointer row/marker for R3 in Archived items"

  # a 2nd archive run with nothing newly resolved must be a harmless no-op (no duplicate rows).
  local archived_rows_before; archived_rows_before="$(grep -c 'pw-archived:' "$RTV")"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-review.sh" archive reviewtest analysis/review/rt.review.md >/dev/null
  [ "$(grep -c 'pw-archived:' "$RTV")" = "$archived_rows_before" ] \
    || die "selftest FAIL: re-running archive with nothing newly resolved was not a no-op"

  # --- dashboard table edits (MR-state flow) --------------------------------
  # Task status table + MR table with realistic rows; the MR table's State is column 5, so a
  # fixed-position "column 4" write (the original implementation) would clobber the MR URL.
  printf '\n## Task status\n\n| ID | Title | Repo | Status | Notes |\n|----|-------|------|--------|-------|\n| T01 | fix x | repo-a | done | |\n\n## Merge requests\n\n| Task | Repo | MR | Target branch | State | Build |\n|------|------|----|--------------|-------|-------|\n| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |\n' >> "$tmp/demo/README.md"

  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" dashboard-task-status demo T01 "accepted (MR merged)" >/dev/null
  grep -q '^| T01 | fix x | repo-a | accepted (MR merged) | |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status did not update the Status column"
  grep -q '^| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status leaked into the MR table"

  # (dashboard-mr-state asserts moved to scripts/entities/pw-ship.sh — plan 20)

  # failure path: a task with no row must fail loudly and leave the file untouched.
  local readme_before; readme_before="$(cat "$tmp/demo/README.md")"
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" dashboard-task-status demo T99 done >/dev/null 2>&1; then
    die "selftest FAIL: dashboard-task-status accepted a task with no row"
  fi
  [ "$(cat "$tmp/demo/README.md")" = "$readme_before" ] \
    || die "selftest FAIL: failed dashboard-task-status still mutated the file"

  # (_resolve_task_mr_url regression family moved to scripts/entities/pw-ship.sh + tests/cases/pw-ship.t.sh — plan 20)

  # ai-model: the lane row exists, defaults to all-—, updates one lane only, clears back, refuses
  # the executor lane and a bare model name. Regression guard behind the row: a model line that
  # duplicated a task's `Execute with:` would silently drift from it — the executor is pinned in
  # its task file, never here (§5.1). The row IS advisory on kilo at Task-spawn time (a headless
  # session carries it instead, §8c) — recorded in the result, never silently ignored.
  local got_m; got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model default line wrong: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2 researcher kilo:command_code/x >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2)"
  [ "$got_m" = "researcher=kilo:command_code/x analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model set not isolated to researcher: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2 researcher — >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model clear-to-default failed: '$got_m'"
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2 executor claude:sonnet >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted the executor lane (the task file binds the executor)"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/pw-lib.sh" ai-model demo2 analyst sonnet-no-provider >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted a row without <provider>:<model> form"
  fi
  grep -q '^- \*\*AI Models:\*\*' "$tmp/demo2/README.md" \
    || die "selftest FAIL: ai-model line vanished after clears"

  echo "selftest OK"
}

case "${1:-}" in
  status)      shift; cmd_status "$@" ;;
  oneliner)    shift; cmd_oneliner "$@" ;;
  adopted)     shift; cmd_adopted "$@" ;;
  log)         shift; cmd_log "$@" ;;
  phase)       shift; cmd_phase "$@" ;;
  rfc)         shift; cmd_rfc "$@" ;;
  ai-review)   shift; cmd_ai_review "$@" ;;
  ai-model)    shift; cmd_ai_model "$@" ;;
  model-check) shift; cmd_model_check "$@" ;;
  task-accept) shift; cmd_task_accept "$@" ;;
  dashboard-task-status) shift; cmd_dashboard_task_status "$@" ;;
  worktree-remove)       shift; cmd_worktree_remove "$@" ;;
  selftest)    cmd_selftest ;;
  -h|--help|"") awk 'NR>1{ if ($0 ~ /^#/) { sub(/^# ?/, "", $0); print } else exit }' "$0" ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
