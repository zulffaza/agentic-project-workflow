#!/usr/bin/env bash
# ============================================================================
# pw-review.sh — the review-doc entity: creation, deterministic editing, gate
# reads, and lifecycle (reindex/archive/reopen/auto-signoff/pass entry) in one
# script.
#
# Facets (S1b): WRITE = init, init-docs, init-all, signoff, start, add-item,
#                      answer, add-question, resolve, note-init, reindex,
#                      archive, reopen, auto-signoff, prepare, import
#               READ  = gate, has-open, count, eligible, scan, passes (read facet),
#                      eligible
#               SPECIAL = auto-signoff (the tool-enforced gate exception, mode=auto only)
#
# Phase-scoped initialization and agent-managed operational states: agents record
# in-review/changes-requested bookkeeping rows with distinct actors; `approved`
# stays human by default, with the guarded auto mode preserved.
#
#   pw-review.sh init         <slug> <review-rel-path> <doc-rel-path>
#       Legacy internal per-file contract (unchanged shape): create one review
#       file verbatim from the canonical template if missing (idempotent —
#       existing items/replies/Sign-off history never clobbered). Publication is
#       lock-guarded, symlink-checked, and no-clobber; the title substitution
#       escapes sed replacement metacharacters.
#   pw-review.sh init-docs    <slug> <artifact-rel-path> [<artifact-rel-path> ...]
#       Selected-document initialization: validate the FULL list first (missing,
#       README/template/RFC targets, unsupported families, path/symlink escapes
#       all reject the whole list with nothing created), normalize + deduplicate,
#       then reuse the internal init contract per target. Duplicate paths and
#       reruns finish only the missing files; a per-file write failure reports
#       created/skipped/failed separately and exits 2.
#   pw-review.sh init-all     <slug>
#       Current-phase-only batch: reads the dashboard phase at invocation time
#       (context/done create nothing; analysis → analysis topics only, RFC
#       excluded; breakdown → PLAN + T0n; executing/review → current T0n
#       results; missing/unknown phase fails closed — never a project-wide scan).
#       Idempotent, never overwrites or deletes existing reviews. Exit 0 on a
#       complete run, 2 when a creation failed (per-file results reported).
#   pw-review.sh gate         <slug> <review-rel-path>
#       Print the latest Sign-off decision VERBATIM; exit 0 iff the approval is
#       CONSUMABLE: latest row approved AND zero real open items AND no active
#       human rejection. Unknown/malformed tables fail closed.
#   pw-review.sh has-open     <slug> <review-rel-path>
#       Print yes/no + exit 0/1 (missing file -> "no" + exit 1, never an error).
#   pw-review.sh count        <slug> <review-rel-path>
#       "open=N resolved=M items=K" — THE single source of truth for any
#       "how many open?" display (same detector the gates trust).
#   pw-review.sh eligible     <slug> <review-rel-path>
#       Read-only pass-eligibility report: "eligible=N open=A foldin=B
#       awaiting=C unactionable=D" — real actionable work only (stubs, resolved,
#       archived, malformed, and waiting-human-only rows are not eligible);
#       exit 0 iff N>0.
#   pw-review.sh prepare      <slug> <scope> [--refresh] [--repair] [--pass-id <id>] [--print]
#       Freeze ONE review unit into review/ai/<pass-id>/ (manifest + snapshot/ +
#       request.md) WITHOUT launching a model. Scope: T0n | context|analysis|plan|
#       task-plan|task-exec|ship|rfc|close | artifact path. An existing packet for the
#       same unit shows instead of overwriting; --refresh = another paid identity,
#       --repair = bounded-cycle round (refused past review-rounds).
#   pw-review.sh import       <slug> --report <report.json> [--pass <id>]
#       Validate an external reviewer report against its prepared manifest (schema,
#       pass/project binding, freshness fingerprint) and import findings/questions
#       once per pass (replay-safe; stale reports are retained but change nothing).
#       Imports are ADVISORY only: no approval row, no repair, no publication.
#   pw-review.sh passes       <slug> [--json]
#       Read-only: one line per review/ai/ pass (surface, state, artifact, verdict).
#   pw-review.sh scan         <slug> [--phase <phase>]
#       Read-only project-wide summary, one line per review file, showing the
#       latest decision AND its actor from the shared readers. Lanes: analysis
#       (topic reviews, RFC staging excluded), plan (PLAN), task-plan /
#       task-exec / ship (the task review artifacts).
#   pw-review.sh reindex      <slug> <review-rel-path>
#       (Re)build the heading-anchored "## Contents" table (auto-run by every
#       heading-changing operator here).
#   pw-review.sh archive      <slug> <review-rel-path>
#       Move fully-[RESOLVED]/[ANSWERED] blocks verbatim to the .archive.md
#       sibling with pointer rows; gate mechanisms provably unaffected. The empty
#       resolved set creates NO sibling/header and changes NO bytes (pure no-op).
#       The sibling path gets the same containment + symlink guard as the review
#       file; blocks are fenced with pw-archived-block markers so a failed-publish
#       retry re-appends nothing and duplicates nothing.
#   pw-review.sh start        <slug> <review-rel-path> [--phase <analysis|plan|task-plan|task-exec|ship>]
#                                 [--provider <actual-id>] [--model <actual-id>] [--confirm-earlier]
#       Pass entry. Without --phase this is the normal repair pass, attributed
#       "pw-review (repair)". With --phase it is an independent AI pass; the
#       configured mode must be advisory/auto and the row names the ACTUAL
#       reviewer: "pw-reviewer (<mode>; provider=<p>; model=<m>)" (unknown when
#       the runtime cannot confirm). Appends changes-requested ONLY when the
#       file has real actionable work (eligible>0); an empty/stub/resolved-only/
#       malformed-only/waiting-human-only set adds no row. Same attempt on the
#       same actor stays idempotent; a distinct actor may log a new attempt.
#       Repairing an artifact whose phase was already consumed (dashboard phase
#       ahead of the artifact lane) requires --confirm-earlier; unknown/missing
#       dashboard phase and malformed Sign-off tables fail closed before writes.
#   pw-review.sh reopen       <slug> <review-rel-path> [--confirm-earlier]
#       Append a fresh in-review row when a fix lands AFTER approval (never
#       deletes history); harmless no-op when already open. An approval from an
#       earlier, already-consumed phase requires --confirm-earlier.
#   pw-review.sh note-init    <slug>
#       Create REVIEWER-NOTES.md with its header if missing (idempotent).
#   pw-review.sh auto-signoff <slug> <review-rel-path> <phase> [--provider <actual-id>]
#                                 [--model <actual-id>] [--confirm-earlier]
#       The ONE tool-enforced exception to "only a human clears a gate": refuses
#       unless this project's AI Review mode for <phase> is 'auto' (re-checked
#       here, never taken on the caller's word) AND the review file belongs to
#       that phase's lane (RFC staging never) AND zero real open items AND no
#       explicit human changes-requested is still active. The row names the
#       actual reviewer (identity defaults to unknown).
#   pw-review.sh signoff      <slug> <review-rel-path> <approved|changes-requested|in-review> [--by <name>]
#       DOCTRINE (C4): human-triggered only — an agent runs this ONLY verbatim
#       on the user's explicit instruction, never on its own initiative. --by
#       must name a HUMAN: reserved machine actors (pw-reviewer (…), pw-review
#       (repair/feedback/auto-reopen)) are written only by their guarded code
#       paths and rejected here; legacy rows with those labels stay readable.
#   pw-review.sh add-item     <slug> <review-rel-path> --section <§anchor> (--text <ask...> | --stdin) [--actor <name>]
#   pw-review.sh answer       <slug> <review-rel-path> <Qid> (--text <answer...> | --stdin)
#   pw-review.sh add-question <slug> <review-rel-path> --section <§anchor> (--text <q...> | --stdin) [--actor <name>]
#   pw-review.sh resolve      <slug> <review-rel-path> <Rid|Qid> (--reply <text...> | --stdin)
#       Deterministic block editing: next Rn/Qn id, timestamps, pw-item-status
#       markers, --- rules, auto-reindex. Free text per the A-rules (one
#       rest-of-line --text slot or --stdin heredoc, VERBATIM). Human text is
#       never edited or deleted; resolve flips the SAME heading in place.
#       add-item and answer are the human-feedback cycle: the first one after a
#       stale 'approved' (or after an explicit HUMAN changes-requested) queues
#       exactly one agent-attributed "pw-review (feedback) | in-review" row;
#       repeats inside an active agent pass change no history. Every mutation
#       here is one serialized, staged, atomic replacement — feedback and state
#       land together, never with a visible stale-approval interval.
#
# Timestamps: review writers stamp "D MMMM YYYY HH.mm WIB" (explicit UTC+7,
# English locale). Readers keep accepting legacy "YYYY-MM-DD HH:MM" rows, the
# legacy "approved ✅" decoration, and the template's unfilled placeholder —
# historical text is never rewritten. Unrelated writers (LOG, scaffold,
# context) keep their formats (review-local scope).
#
# Exit codes: 0 success · 1 read-side "not approved / no eligible work" (gate,
# has-open, eligible, count-on-missing) · 2 usage/state error (stderr carries a
# → fix: hint).
# Portable bash 3.2+. Project slug resolves under $PW_PROJECTS_DIR.
# ============================================================================
set -euo pipefail

if [ "${1:-}" = "--selftest" ]; then exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/selftest_entry.sh" "$(basename "${BASH_SOURCE[0]}" .sh)"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_HOME="$(cd "$HERE/../../.." && pwd)"
. "$HERE/../lib/pw-common.sh"
. "$HERE/../lib/pw-mdlib.sh"
. "$HERE/../lib/pw-reviewlib.sh"

PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../../../.." && pwd)}"
ST="$HERE/pw-status.sh"
CFG="$HERE/pw-config.sh"
# Mirror of the ai-review config surfaces (owned by pw-config.sh).
AI_REVIEW_PHASES="context analysis plan task-plan task-exec ship rfc close"

die() { echo "pw-review: $*" >&2; exit 2; }
# proj_dir — one directory component only: the same slug contract the read facet applies.
# The old raw "$PROJECTS_DIR/$1" concatenation let `../evil` (and nested paths) select a
# project OUTSIDE the projects root for every writer here, even though artifact-relative
# containment was checked afterwards — the base must be pinned first. Comparison is
# physical (pwd -P both sides, macOS /var symlink included): a canonical project directory
# must remain inside the projects root, symlinked slugs that resolve outward are refused.
proj_dir() {
  local slug="$1" base d
  case "$slug" in
    ''|.|..|*/*|*$'\n'*|*$'\r'*|*$'\t'*)
      die "invalid project slug: '$slug' → fix: use exactly one project directory name (no paths, no traversal)" ;;
  esac
  [ -d "$PROJECTS_DIR/$slug" ] || die "no such project: $1 ($PROJECTS_DIR/$slug) → fix: check the slug under the projects dir (new project? create it with: /pw-new $1)"
  base="$(cd "$PROJECTS_DIR" 2>/dev/null && pwd -P)" || die "cannot resolve the projects directory: $PROJECTS_DIR → fix: check PW_PROJECTS_DIR exists"
  d="$(cd "$PROJECTS_DIR/$slug" && pwd -P)" || die "cannot resolve project directory: $slug"
  case "$d/" in
    "$base/"*) printf '%s' "$d" ;;
    *) die "project '$slug' resolves outside the projects directory → fix: select a project under $base (real symlink escape? remove it)" ;;
  esac
}
now_ts() { pw_now_wib; }

# staged-or-die — the entity's serialization gate: pw_review_staged <file> <fn> [args…],
# routed so a busy lock or a failed worker exits 2 (the worker already wrote its reason to
# stderr) and the ORIGINAL file stays untouched with no leftover temps or lock.
staged_or_die() {
  local f="$1" rc=0
  pw_review_staged "$@" || rc=$?
  [ "$rc" = 0 ] && return 0
  [ "$rc" = 3 ] && die "$f is locked by another writer → fix: retry in a moment; if no writer is running, remove the stale lock directory $f.pwlock"
  exit 2
}

# _dash_lane_state <slug> <rel> → prints "ok" (current lane), "earlier" (the
# dashboard has moved past this artifact's lane — reopen/repair needs explicit
# confirmation), or "unknown" (missing/non-canonical dashboard phase).
# The rfccontent lane is exempt: the RFC side-loop runs across phases and its
# published-content gate is the RFC flow's own, so no dashboard phase "consumes" it.
_dash_lane_state() {
  local slug="$1" rel="$2" lane
  lane="$(pw_review_lane "$rel")"
  [ "$lane" = rfccontent ] && { echo ok; return 0; }
  local raw tok; raw="$("$ST" phase "$slug" 2>/dev/null || true)"; tok="$(pw_phase_token "${raw:-missing}")"
  pw_phase_valid "$tok" || { echo unknown; return 0; }
  local dr lr
  dr="$(pw_dash_rank "$tok")"; lr="$(pw_review_lane_rank "$lane")"
  [ "$dr" -gt "$lr" ] && echo earlier || echo ok
}

# _ai_identity <provider> <model> — fill unconfirmed parts with "unknown" (never
# a config guess) and reject table-breaking characters.
_ai_identity() {
  local prov="${1:-unknown}" model="${2:-unknown}"
  [ -n "$prov" ]  || prov="unknown"
  [ -n "$model" ] || model="unknown"
  pw_meta_check "provider" "$prov"  || die "invalid --provider value → fix: pass the provider id as reported by the reviewer run (no pipes, tabs, or newlines)"
  pw_meta_check "model" "$model"    || die "invalid --model value → fix: pass the exact model identifier the provider reported (no pipes, tabs, or newlines)"
  printf '%s\t%s\n' "$prov" "$model"
}

# review_file <slug> <rel> → absolute path, validated as a review-shaped file
review_file() {
  local d; d="$(proj_dir "$1")" || return 2
  pw_review_contain "$d" "$2" >/dev/null || die "invalid review path: $2 → fix: use a project-relative path inside the project"
  local f="$d/$2"
  [ -L "$f" ] && die "refusing symlinked review file: $2 → fix: operate on the real file (symlinks can silently redirect writes outside the project)"
  [ -f "$f" ] || die "no such review file: $2 → fix: create it with: /pw-review $1 init-all (or /pw-review $1 init <artifact-path>)"
  grep -q '^## Sign-off' "$f" || grep -q '^## Items' "$f" \
    || die "$2 has neither '## Items' nor '## Sign-off' — not a valid review file → fix: move the invalid copy aside, then recreate it with /pw-review $1 init"
  printf '%s' "$f"
}

# ---------------------------------------------------------------- init (legacy per-file contract)
cmd_init() {
  [ $# -eq 3 ] || die "usage: init <slug> <review-rel-path> <doc-rel-path>"
  local slug="$1" rel="$2" docrel="$3"
  local d; d="$(proj_dir "$slug")" || return 2
  pw_review_contain "$d" "$rel" >/dev/null || die "invalid review path: $rel → fix: keep it project-relative (review files live under analysis/review/ or task/review/)"
  _init_one "$slug" "$d" "$rel" "$docrel" || die "init failed for $rel (see stderr) → fix: re-run /pw-review $slug init $docrel after checking the project dir"
}

# _init_one <slug> <projdir> <reviewrel> <docrel> → rc-only worker shared by
# init/init-docs/init-all so partial results can be reported per file. Publication is
# lock-guarded and no-clobber: render to a temp beside the target, RE-verify the target
# still does not exist (regular check + symlink check — a dangling `.pwlock`-free window
# between the first -f test and the write used to redirect the redirection through a
# planted symlink), then one atomic same-directory mv. The title substitution escapes
# sed replacement metacharacters (&, backslash, and the | delimiter) — a docname like
# `weird&name.md` used to expand `&` to the matched `<doc.md>` token inside the title.
_init_one() {
  local slug="$1" d="$2" rel="$3" docrel="$4"
  local f="$d/$rel"
  if [ -f "$f" ]; then
    echo "$slug: review already exists: $rel (left untouched)"
    return 0
  fi
  [ -e "$f" ] && { echo "pw-review: refusing to write over a non-regular file: $rel" >&2; return 1; }
  [ -L "$f" ] && { echo "pw-review: refusing symlinked review target: $rel" >&2; return 1; }
  local tmpl="$HERE/../../../template/_REVIEW.template.md"
  [ -f "$tmpl" ] || { echo "pw-review: template not found: $tmpl" >&2; return 1; }
  local docname; docname="$(basename "$docrel")"
  local docc; docc="$(printf '%s' "$docname" | sed -e 's/[\\&|]/\\&/g')"
  mkdir -p "$(dirname "$f")" 2>/dev/null || { echo "pw-review: cannot create directory for $rel → fix: check the review/ subdir permissions under $d" >&2; return 1; }
  [ -w "$(dirname "$f")" ] || { echo "pw-review: write failed for $rel (review dir not writable → fix: check the review/ subdir permissions under $d)" >&2; return 1; }
  pw_review_lock "$f" || { echo "pw-review: $rel is locked by another writer → fix: retry in a moment; if no writer is running, remove the stale lock directory $f.pwlock" >&2; return 1; }
  local tmpf="$f.init.$$" rc=1
  if sed "s|<doc\\.md>|$docc|g" "$tmpl" > "$tmpf" 2>/dev/null \
     && [ ! -e "$f" ] && [ ! -L "$f" ] && mv "$tmpf" "$f" 2>/dev/null; then
    rc=0
  fi
  [ "$rc" = 0 ] || rm -f "$tmpf"
  pw_review_unlock "$f"
  [ "$rc" = 0 ] || { echo "pw-review: write failed for $rel" >&2; return 1; }
  _log "$slug" review "created $rel (in-review, awaiting your items)"
  echo "$slug: init created $rel (reviewing ../$docname)"
}

# ---------------------------------------------------------------- init-docs (selected-document list)
cmd_init_docs() {
  [ $# -ge 2 ] || die "usage: init-docs <slug> <artifact-rel-path> [<artifact-rel-path> ...] → fix: pass project-relative paths of the documents to review (analysis/<topic>.md, task/PLAN.md, task/T0n.md)"
  local slug="$1"; shift
  local d; d="$(proj_dir "$slug")" || return 2
  # Pass 1: validate the FULL list before creating anything; normalize + dedupe on the
  # derived review path. Every rejection is collected so one bad entry reports alongside
  # the rest, and NOTHING is written when the list is invalid.
  local -a plan=() seen=() errs=()
  local p line s dup bad=0
  for p in "$@"; do
    if line="$(pw_review_reviewrel "$d" "$p" 2>&1)"; then
      :
    else
      errs+=("$line"); bad=1; continue
    fi
    dup=0
    for s in "${seen[@]:-}"; do [ "$s" = "${line#*$'\t'}" ] && { dup=1; break; }; done
    [ "$dup" = 1 ] && continue
    seen+=("${line#*$'\t'}")
    plan+=("$line")
  done
  [ "$bad" = 0 ] || { for s in "${errs[@]}"; do echo "pw-review: selected list rejected — nothing created → fix: $s" >&2; done; exit 2; }
  [ "${#plan[@]}" -gt 0 ] || die "init-docs: empty selection after normalization"
  # Pass 2: per-target init with separated outcome reporting.
  local created=0 present=0 failed=0 entry docrel rrel
  for entry in "${plan[@]}"; do
    docrel="${entry%%$'\t'*}"; rrel="${entry#*$'\t'}"
    if [ -f "$d/$rrel" ]; then
      present=$((present+1)); continue
    fi
    if _init_one "$slug" "$d" "$rrel" "$docrel" >/dev/null; then
      echo "created $rrel (for $docrel)"; created=$((created+1))
    else
      echo "FAILED $rrel (for $docrel)"; failed=$((failed+1))
    fi
  done
  echo "$slug: init-docs — $created created, $present already present, $failed failed"
  [ "$failed" -eq 0 ] || die "init-docs: $failed target(s) failed (existing content untouched) → fix: re-run the list; see the per-file FAILED lines above"
}

# ---------------------------------------------------------------- init-all (current phase only)
cmd_init_all() {
  [ $# -eq 1 ] || die "usage: init-all <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")" || return 2
  local raw tok; raw="$("$ST" phase "$slug" 2>/dev/null || true)"; tok="$(pw_phase_token "${raw:-missing}")"
  pw_phase_valid "$tok" || die "dashboard phase is '$tok' — cannot scope init-all → fix: $(pw_phase_hint | sed "s/<slug>/$slug/")"
  case "$tok" in
    context)
      echo "$slug: phase 'context' — no review files to initialize yet (/pw-analyze $slug produces the first reviewable analysis)"
      return 0 ;;
    done)
        echo "$slug: phase 'done' — init-all creates nothing here → fix: select explicitly (/pw-review $slug init <artifact-path>) or rewind the dashboard first (/pw-status $slug rewind <phase>)"
      return 0 ;;
  esac
  local -a docs=()
  local doc
  case "$tok" in
    analysis)
      if [ -d "$d/analysis" ]; then
        while IFS= read -r doc; do docs+=("$doc"); done < <(
          find "$d/analysis" -maxdepth 1 -name '*.md' ! -name '_TEMPLATE*' ! -name 'README.md' ! -name 'RFC.md' | sort)
      fi ;;
    breakdown)
      [ -f "$d/task/PLAN.md" ] && docs+=("$d/task/PLAN.md")
      if [ -d "$d/task" ]; then
        while IFS= read -r doc; do docs+=("$doc"); done < <(
          find "$d/task" -maxdepth 1 -name 'T[0-9]*.md' | sort)
      fi ;;
    executing|review)
      if [ -d "$d/task" ]; then
        while IFS= read -r doc; do docs+=("$doc"); done < <(
          find "$d/task" -maxdepth 1 -name 'T[0-9]*.md' | sort)
      fi ;;
  esac
  if [ "${#docs[@]}" -eq 0 ]; then
    echo "$slug: phase '$tok' has no reviewable artifacts yet — nothing to create (earlier/later-phase reviews are never created here; existing ones are preserved)"
    return 0
  fi
  local created=0 present=0 failed=0 line rrel
  for doc in "${docs[@]}"; do
    line="$(pw_review_reviewrel "$d" "${doc#$d/}" 2>/dev/null)" || continue
    rrel="${line#*$'\t'}"
    if [ -f "$d/$rrel" ]; then
      present=$((present+1)); continue
    fi
    if _init_one "$slug" "$d" "$rrel" "${line%%$'\t'*}" >/dev/null; then
      echo "created $rrel (for ${line%%$'\t'*})"; created=$((created+1))
    else
      echo "FAILED $rrel (for ${line%%$'\t'*})"; failed=$((failed+1))
    fi
  done
  echo "$slug: init-all (phase $tok) — $created created, $present already present, $failed failed"
  [ "$failed" -eq 0 ] || die "init-all: $failed target(s) failed → fix: re-run /pw-review $slug init-all or init the file directly and read the FAILED lines above"
}

# ---------------------------------------------------------------- signoff (human-triggered, C4)
SIGNOFF_BY="" SIGNOFF_DECISION="" SIGNOFF_REL=""
_signoff_body() {
  local f="$1"
  local ts; ts="$(now_ts)" || return 1
  # the shared row placer appends after the current latest DATA row (a placeholder left
  # unreplaced above real rows never becomes the anchor) and propagates every splice or
  # publish failure — a signoff that did not land must abort the staged write, not pass.
  pw_signoff_row_put "$f" "$ts" "$SIGNOFF_BY" "$SIGNOFF_DECISION" \
    || { echo "pw-review: no Sign-off table rows found in $SIGNOFF_REL → fix: the table lost its rows; restore the '| Date-time | By | Decision |' header + separator from template/_REVIEW.template.md" >&2; return 1; }
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header in $SIGNOFF_REL — sign-off aborted, nothing published → fix: check the file is writable and retry" >&2; return 1; }
}

cmd_signoff() {
  local slug="$1" rel="$2" decision="$3" by="you"
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --by) [ $# -ge 2 ] || die "--by requires an argument"; by="$2"; shift 2 ;;
      --by=*) by="${1#--by=}"; shift ;;
      *) die "signoff: unknown option: $1 (try --help)" ;;
    esac
  done
  case "$decision" in
    approved|changes-requested|in-review) ;;
    *) die "invalid decision '$decision' → fix: use exactly one of: approved | changes-requested | in-review" ;;
  esac
  pw_meta_check "decision-by (--by)" "$by" || die "--by must be a single-line name without tabs or pipes → fix: pass the human's display name only"
  # --by names the HUMAN author. Reserved machine actors are written only by their guarded
  # code paths (auto-signoff, pass entry, feedback, reopen); letting a human-signoff row
  # carry one would impersonate a machine role — and _decision_actor_kind readers weigh
  # those labels (reviewer rows never count as human rejections; agent rows never grant
  # approval). Legacy rows with these actors stay READABLE; they can no longer be written
  # through this door.
  local by_kind; by_kind="$(_decision_actor_kind "$by")"
  [ "$by_kind" = human ] || die "--by '$by' is a reserved machine actor ($by_kind) — human sign-off must attribute to a human → fix: pass the person's own name (pw-review (…) and pw-reviewer (…) rows are written only by their guarded transitions)"
  local f; f="$(review_file "$slug" "$rel")" || return 2
  grep -q '^## Sign-off' "$f" || die "$rel has no '## Sign-off' section → fix: not a gate-bearing review file; nothing to sign off"
  SIGNOFF_BY="$by" SIGNOFF_DECISION="$decision" SIGNOFF_REL="$rel"
  staged_or_die "$f" _signoff_body
  PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" log "$slug" "$by" "signed off $rel: $decision (via pw-review.sh)" >/dev/null
  echo "$slug: $rel → Sign-off row appended: $decision (by $by)"
  if [ "$decision" = "approved" ] && _review_has_open_marker "$f"; then
    echo "$slug: NOTE — approval recorded, but $rel still has unresolved items/questions: every approval-consuming gate stays BLOCKED (_review_approval_valid) until they are resolved or archived."
  fi
}

# ------------------------------------------------------- shared block utils

# _next_id <file> <R|Q> → next free numeric id (max of live REAL headings + archived
# markers, +1). Placeholder stubs are excluded via _review_item_headings (same filter the
# gates/counts trust — an unfilled stub must not consume an id). Archived ids only survive
# as <!-- pw-archived:Rn --> pointer rows in the live file — scanning both keeps ids
# monotonic across archives.
_next_id() {
  local f="$1" p="$2" max=0 n
  while IFS= read -r h; do
    n="$(printf '%s' "$h" | sed -n "s/^### ${p}\([0-9][0-9]*\) ·.*/\1/p")"
    [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
  done < <(_review_item_headings "$f")
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    [ "$n" -gt "$max" ] && max="$n"
  done < <(grep -o "pw-archived:$p[0-9]*" "$f" 2>/dev/null | sed "s/pw-archived:$p//" || true)
  echo $((max+1))
}

# _read_text → TEXT from --text rest-of-line or --stdin (A3 verbatim handoff)
_TEXT="" _TEXT_SET=0
_read_text_opts() { # parses trailing opts of add-item/add-question; sets SECTION ACTOR TEXT
  while [ $# -gt 0 ]; do
    case "$1" in
      --section) [ $# -ge 2 ] || die "--section requires an argument"; SECTION="$2"; shift 2 ;;
      --section=*) SECTION="${1#--section=}"; shift ;;
      --actor) [ $# -ge 2 ] || die "--actor requires an argument"; ACTOR="$2"; shift 2 ;;
      --actor=*) ACTOR="${1#--actor=}"; shift ;;
      --text) shift; TEXT="$*"; _TEXT_SET=1; break ;;
      --stdin) TEXT="$(cat)"; _TEXT_SET=1; shift ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done
  [ "$_TEXT_SET" = 1 ] || die "no text given → fix: pass --text <the ask, rest of line unquoted> or --stdin (heredoc)"
  [ -n "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ] || die "text is empty → fix: --text/--stdin must carry the actual ask/answer"
  # Any line starting as a 2+ level markdown heading is injected structure: item bodies are
  # written verbatim, so a `#### R9 … [OPEN] … pw-item-status: open` line would plant a real
  # approval blocker (the gate fails closed on heading levels 3+ — it blocks; only canonical
  # `### ` items are work). The old guard covered only levels 2-3 and let level 4+ through.
  printf '%s\n' "$TEXT" | grep -qE '^#{2,} ' \
    && die "text must not contain lines starting with a markdown heading (## or deeper would corrupt the heading scan) → fix: indent or quote the line"
  return 0
}

# _section_line <blanked-file> <heading-ERE> → line number (0 = absent)
_section_line() {
  awk -v re="$2" '$0 ~ re {print NR; exit} END{}' "$1" | head -1 | { read -r n; echo "${n:-0}"; }
}

# _write_block <tmpfile> <heading> <body-text> → heading + body + blank + ---
# (NO trailing blank line — insert-before callers append one; stub-replace callers inherit
# the blank line that already follows the stub's own --- rule).
_write_block() {
  local out="$1" heading="$2" body="$3"
  {
    printf '%s\n' "$heading"
    printf '%s\n' "$body"
    printf '\n---\n'
  } > "$out"
}

# _stub_range <blanked> <R|Q> <sec-start> <sec-end> → "start end" of the template's unfilled
# placeholder stub (heading carrying <YYYY-MM-DD> + everything through its --- rule), or empty.
# Filling the stub in place (instead of appending below it) is the template's intended UX —
# the stub exists so hand-editors get valid syntax by copy-paste; a tool must not leave a
# duplicate phantom R1/Q1 above the first real item. The legacy placeholder token stays
# recognizable forever (readers accept BOTH placeholder generations).
_stub_range() {
  awk -v p="$2" -v s="$3" -v e="$4" '
    NR>=s && NR<=e && index($0, "### " p) == 1 && (index($0, "<YYYY-MM-DD") > 0 || index($0, "<DD MMMM YYYY") > 0) {st=NR}
    st && NR>=st && $0=="---" {print st, NR; exit}
  ' "$1"
}

# ------------------------------------------------------- feedback-cycle transition
# Globals set by the calling feedback writer before staged():
#   _FT_REL      display path        _FT_HUMAN   1 = human-origin write
#   _FT_EARLIER  1 = lane already consumed by a later dashboard phase
#   _FT_UNKNOWN  1 = dashboard phase missing/non-canonical (fail closed on state)
# One agent-attributed "pw-review (feedback) | in-review" row goes in ONLY when the
# previous decision was a STALE approval, a first attributed cycle on a blank
# placeholder, or a still-queued HUMAN changes-requested answered by new human
# feedback. Repeats inside an active agent pass (latest changes-requested written
# by an automated actor) never toggle — that is the reviewer/fixer anti-churn rule.
# rc 1 propagates a failed row splice/publish: feedback and state land together or
# not at all (the staged operation aborts, the original stays untouched).
_FT_REL=""; _FT_HUMAN=0; _FT_EARLIER=0; _FT_UNKNOWN=0; _FT_QUEUED=0; _FT_PENDING=0
_feedback_transition() {
  local f="$1" d a kind
  _FT_QUEUED=0; _FT_PENDING=0
  if ! d="$(_signoff_latest_decision "$f")"; then
    echo "pw-review: NOTE: $_FT_REL has no Sign-off table rows — the feedback itself is recorded; the approval table must be repaired before any gate reads it → fix: restore the '| Date-time | By | Decision |' header + placeholder row from template/_REVIEW.template.md" >&2
    return 0
  fi
  a="$(_signoff_latest_actor "$f")" || a=""
  kind="$(_decision_actor_kind "$a")"
  case "$d" in
    in-review)
      [ "$kind" = blank ] || return 0 ;;
    changes-requested)
      { [ "$_FT_HUMAN" = 1 ] && [ "$kind" = human ]; } || return 0 ;;
    approved|approved✅|approved\ ✅)
      if [ "$_FT_EARLIER" = 1 ]; then
        _FT_PENDING=1
        echo "pw-review: NOTE: $_FT_REL is approved and its phase was already consumed by a later dashboard phase — the feedback is recorded, the approval row is preserved, and every approval consumer stays blocked while this item is open → fix: this reopen needs the human's explicit confirmation — ask, then re-run with --confirm-earlier" >&2
        return 0
      fi ;;
    *)
      echo "pw-review: NOTE: unrecognized latest decision '$d' in $_FT_REL — sign-off state untouched (never treated as blank) → fix: repair the Sign-off table (approved | changes-requested | in-review) from template/_REVIEW.template.md" >&2
      return 0 ;;
  esac
  if [ "$_FT_UNKNOWN" = 1 ]; then
    echo "pw-review: NOTE: dashboard phase is missing or non-canonical — feedback recorded, state transition skipped fail-closed → fix: repair the dashboard Status line (/pw-status $slug shows the current phase)" >&2
    return 0
  fi
  local ts; ts="$(pw_now_wib)" || return 1
  pw_signoff_row_put "$f" "$ts" "pw-review (feedback)" "in-review" \
    || { echo "pw-review: FAILED to place the feedback-cycle row in $_FT_REL (table lost its rows or the splice failed) — the whole staged write is aborted, nothing published → fix: repair the table from template/_REVIEW.template.md and retry" >&2; return 1; }
  _FT_QUEUED=1
}

# ---------------------------------------------------------------- add-item
AI_SECTION=""; AI_ACTOR=""; AI_TEXT=""; AI_REL=""; _AI_IDFILE=""
_add_item_body() {
  local f="$1"
  # aliases keep the historical heading-line bytes (mutation register anchor C26)
  local SECTION="$AI_SECTION" ACTOR="$AI_ACTOR"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local oq; oq="$(_section_line "$blanked" '^## Open questions')"
  [ "$oq" -gt 0 ] || { rm -f "$blanked"; echo "pw-review: $AI_REL has no '## Open questions' heading — not a valid review file → fix: recreate from template/_REVIEW.template.md" >&2; return 1; }
  local n; n="$(_next_id "$f" R)"
  local ts; ts="$(now_ts)" || return 1
  local heading="### R$n · $SECTION — [OPEN] ($ACTOR, $ts) <!-- pw-item-status: open -->"
  local block; block="$(mktemp)"; _write_block "$block" "$heading" "$AI_TEXT"
  local items_start stub
  items_start="$(_section_line "$blanked" '^## Items')"
  [ "$items_start" -gt 0 ] || { rm -f "$blanked" "$block"; echo "pw-review: $AI_REL has no '## Items' heading — not a valid review file → fix: recreate from template/_REVIEW.template.md" >&2; return 1; }
  stub="$(_stub_range "$blanked" R "$items_start" "$((oq-1))")"
  if [ -n "$stub" ]; then
    md_replace_range "$f" "${stub% *}" "${stub#* }" "$block" \
      || { rm -f "$block" "$blanked"; echo "pw-review: FAILED to fill the item stub in $AI_REL — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  else
    printf '\n' >> "$block"
    md_insert_lines_before "$f" "$oq" "$block" \
      || { rm -f "$block" "$blanked"; echo "pw-review: FAILED to splice the new item into $AI_REL — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  fi
  rm -f "$block" "$blanked"
  pw_review_contents_rebuild "$f" \
    || { echo "pw-review: FAILED to rebuild the Contents block in $AI_REL — whole staged write aborted → fix: repair the paired <!-- pw-contents:begin/end --> markers (see docs/REVIEW.md)" >&2; return 1; }
  _feedback_transition "$f" || return 1
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header in $AI_REL — whole staged write aborted → fix: check the file is writable and retry" >&2; return 1; }
  printf '%s\n' "$n" > "$_AI_IDFILE"
}

cmd_add_item() {
  local slug="$1" rel="$2"; shift 2
  local SECTION="" ACTOR="you" TEXT=""
  _read_text_opts "$@"
  [ -n "$SECTION" ] || die "add-item: --section <§anchor> is required → fix: anchor the item to a doc section, e.g. --section '§3 Affected repos'"
  pw_meta_check "--section" "$SECTION" || die "--section must be a single-line anchor without tabs or pipes → fix: e.g. --section '§3 Affected repos'"
  pw_meta_check "--actor" "$ACTOR"     || die "--actor must be a single-line name without tabs or pipes → fix: name the human or the agent role only"
  pw_heading_meta_check "--section" "$SECTION" || die "add-item: --section carries reserved review syntax → fix: keep status tags, HTML comments, machine markers, reply arrows, and <stub> tokens out of the anchor — the tool writes them into the heading itself"
  pw_heading_meta_check "--actor" "$ACTOR"     || die "add-item: --actor carries reserved review syntax → fix: pass a plain name (the heading tag and marker are written by the tool, never injected)"
  local f; f="$(review_file "$slug" "$rel")" || return 2
  AI_SECTION="$SECTION" AI_ACTOR="$ACTOR" AI_TEXT="$TEXT" AI_REL="$rel"
  _FT_REL="$rel"
  if [ "$(_decision_actor_kind "$ACTOR")" = human ]; then _FT_HUMAN=1; else _FT_HUMAN=0; fi
  _set_lane_flags "$slug" "$rel"
  _AI_IDFILE="$(mktemp)"
  staged_or_die "$f" _add_item_body
  local n; n="$(cat "$_AI_IDFILE")"; rm -f "$_AI_IDFILE"
  _log "$slug" "$ACTOR" "added R$n to $rel ($SECTION) via add-item (feedback-cycle queued: $_FT_QUEUED)"
  echo "$slug: $rel → R$n added ($SECTION, $ACTOR)"
  if [ "$_FT_QUEUED" = 1 ]; then
    echo "$slug: $rel → queued one 'pw-review (feedback) | in-review' row (the stale approval is now invalidated)"
  fi
  return 0
}

# _set_lane_flags — compute the feedback transition's environment globals.
_set_lane_flags() {
  local slug="$1" rel="$2" st
  st="$(_dash_lane_state "$slug" "$rel")"
  _FT_UNKNOWN=0; _FT_EARLIER=0
  case "$st" in earlier) _FT_EARLIER=1 ;; unknown) _FT_UNKNOWN=1 ;; esac
}

# ---------------------------------------------------------------- answer
ANS_REL="" ANS_TEXT=""
# _find_item_line → "<line>\t<STATUS>" with STATUS from the shared sttag classifier
# (marker-first, leftmost canonical bracket, CONFLICT when the two disagree) — never the
# old greedy last-`— [`-bracket, which a crafted `) — [RESOLVED] (you` actor suffix
# exploited to make a live [OPEN] item read as settled (archive then "resolved" it away
# and the gate auto-approved). CONFLICT: answer/resolve refuse it; the gate blocks it.
_find_item_line() {
  awk -v id="$2" "$_MD_STTAG"'
    /^### [RQ][0-9]+ · / && index($0, "<YYYY-MM-DD") == 0 && index($0, "<DD MMMM YYYY") == 0 {
      h = $0; sub(/^### /, "", h); sub(/ ·.*/, "", h)
      if (h == id) { printf "%d\t%s\n", NR, sttag($0, h); exit }
    }' "$1"
}

_block_end() {
  awk -v s="$2" 'NR>s && /^(## |### )/ {print NR-1; exit} END{}' "$1" | head -1 | { read -r n; local total; total="$(wc -l < "$1" | tr -d ' ')"; echo "${n:-$total}"; }
}

_answer_body() {
  local f="$1" qid="$2"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local hit hl tag
  hit="$(_find_item_line "$blanked" "$qid")"
  [ -n "$hit" ] || { rm -f "$blanked"; echo "pw-review: no real question heading '$qid' in $ANS_REL → fix: check the '## Contents' table or grep '^### Q' for the live ids" >&2; return 1; }
  hl="${hit%%$'\t'*}"; tag="${hit#*$'\t'}"
  [ "$tag" = "ANSWERED" ] && { rm -f "$blanked"; echo "pw-review: $qid in $ANS_REL is already [ANSWERED] → fix: open a NEW question instead if this is a fresh ask; never re-answer a settled one" >&2; return 1; }
  [ "$tag" = "CONFLICT" ] && { rm -f "$blanked"; echo "pw-review: $qid in $ANS_REL carries disagreeing status marker/tag — answer refused until the heading is repaired → fix: make the [PENDING]/[ANSWERED] tag and the pw-item-status marker agree (see docs/REVIEW.md)" >&2; return 1; }
  local bend; bend="$(_block_end "$blanked" "$hl")"
  local ins
  ins="$(awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e && $0=="---" {n=NR} END{print n+0}' "$blanked")"
  if [ "$ins" -gt 0 ]; then ins=$((ins-1)); else ins="$bend"; fi
  while [ "$ins" -gt "$hl" ] && [ -z "$(sed -n "${ins}p" "$blanked" | tr -d '[:space:]')" ]; do ins=$((ins-1)); done
  local ts; ts="$(now_ts)" || { rm -f "$blanked"; return 1; }
  local quoted; quoted="$(mktemp)"
  {
    local prev; prev="$(sed -n "${ins}p" "$blanked" | sed 's/[[:space:]]*$//')"
    case "$prev" in '>'*) printf '>\n' ;; *) printf '\n' ;; esac
    printf '%s\n' "$ANS_TEXT" | sed 's/^/> /; s/^> $/>/' | sed "1s|^> |> ↳ **you** ($ts): |"
  } > "$quoted"
  md_insert_lines_after "$f" "$ins" "$quoted" \
    || { rm -f "$quoted" "$blanked"; echo "pw-review: FAILED to splice the answer into $ANS_REL — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  rm -f "$quoted" "$blanked"
  pw_review_contents_rebuild "$f" \
    || { echo "pw-review: FAILED to rebuild the Contents block in $ANS_REL — whole staged write aborted → fix: repair the paired <!-- pw-contents:begin/end --> markers (see docs/REVIEW.md)" >&2; return 1; }
  _feedback_transition "$f" || return 1
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header in $ANS_REL — whole staged write aborted → fix: check the file is writable and retry" >&2; return 1; }
}

cmd_answer() {
  local slug="$1" rel="$2" qid="$3"; shift 3
  local TEXT=""
  _read_text_opts "$@"
  case "$qid" in Q[0-9]*) ;; *) die "answer: question id must look like Q2 (got '$qid')" ;; esac
  local f; f="$(review_file "$slug" "$rel")" || return 2
  ANS_REL="$rel" ANS_TEXT="$TEXT"
  _FT_REL="$rel" _FT_HUMAN=1
  _set_lane_flags "$slug" "$rel"
  staged_or_die "$f" _answer_body "$qid"
  _log "$slug" you "answered $qid in $rel"
  echo "$slug: $rel → your answer was appended under $qid (agent folds it in + flips to [ANSWERED] on the next pass)"
  [ "$_FT_QUEUED" = 1 ] && echo "$slug: $rel → queued one 'pw-review (feedback) | in-review' row (the stale approval is now invalidated)"
  return 0
}

# ---------------------------------------------------------------- add-question
AQ_SECTION=""; AQ_ACTOR=""; AQ_TEXT=""
_add_question_body() {
  local f="$1"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local oq; oq="$(_section_line "$blanked" '^## Open questions')"
  [ "$oq" -gt 0 ] || { rm -f "$blanked"; echo "pw-review: no '## Open questions' heading — not a valid review file → fix: recreate from template/_REVIEW.template.md" >&2; return 1; }
  local send
  send="$(awk -v s="$oq" 'NR>s && /^## / {print NR; exit} END{}' "$blanked" | head -1)"
  [ -n "$send" ] || send="$(wc -l < "$blanked" | tr -d ' ')"
  local n; n="$(_next_id "$f" Q)"
  local ts; ts="$(now_ts)" || return 1
  local heading="### Q$n · $AQ_SECTION — [PENDING] ($AQ_ACTOR, $ts) <!-- pw-item-status: open -->"
  local block; block="$(mktemp)"; _write_block "$block" "$heading" "$AQ_TEXT"
  local stub
  stub="$(_stub_range "$blanked" Q "$oq" "$((send-1))")"
  if [ -n "$stub" ]; then
    md_replace_range "$f" "${stub% *}" "${stub#* }" "$block" \
      || { rm -f "$block" "$blanked"; echo "pw-review: FAILED to fill the question stub — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  else
    printf '\n' >> "$block"
    md_insert_lines_before "$f" "$send" "$block" \
      || { rm -f "$block" "$blanked"; echo "pw-review: FAILED to splice the new question — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  fi
  rm -f "$block" "$blanked"
  pw_review_contents_rebuild "$f" \
    || { echo "pw-review: FAILED to rebuild the Contents block — whole staged write aborted → fix: repair the paired <!-- pw-contents:begin/end --> markers (see docs/REVIEW.md)" >&2; return 1; }
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header — whole staged write aborted → fix: check the file is writable and retry" >&2; return 1; }
  printf '%s\n' "$n" > "$_AQ_IDFILE"
}

cmd_add_question() {
  local slug="$1" rel="$2"; shift 2
  local SECTION="" ACTOR="agent" TEXT=""
  _read_text_opts "$@"
  [ -n "$SECTION" ] || die "add-question: --section <§anchor> is required"
  pw_meta_check "--section" "$SECTION" || die "--section must be a single-line anchor without tabs or pipes → fix: e.g. --section '§4 Approach'"
  pw_meta_check "--actor" "$ACTOR"     || die "--actor must be a single-line name without tabs or pipes"
  pw_heading_meta_check "--section" "$SECTION" || die "add-question: --section carries reserved review syntax → fix: keep status tags, HTML comments, machine markers, reply arrows, and <stub> tokens out of the anchor"
  pw_heading_meta_check "--actor" "$ACTOR"     || die "add-question: --actor carries reserved review syntax → fix: pass a plain name (the heading tag and marker are written by the tool, never injected)"
  local f; f="$(review_file "$slug" "$rel")" || return 2
  AQ_SECTION="$SECTION" AQ_ACTOR="$ACTOR" AQ_TEXT="$TEXT"
  _AQ_IDFILE="$(mktemp)"
  staged_or_die "$f" _add_question_body
  local n; n="$(cat "$_AQ_IDFILE")"; rm -f "$_AQ_IDFILE"
  _reindex "$slug" "$rel"
  _log "$slug" "$ACTOR" "asked Q$n in $rel ($SECTION)"
  echo "$slug: $rel → Q$n added ($SECTION, $ACTOR) — awaiting the human's answer"
}

# ---------------------------------------------------------------- resolve
RS_TEXT="" RS_REL=""
_resolve_body() {
  local f="$1" id="$2"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local hit hl tag
  hit="$(_find_item_line "$blanked" "$id")"
  [ -n "$hit" ] || { rm -f "$blanked"; echo "pw-review: no real heading '$id' in $RS_REL → fix: check the '## Contents' table for live ids (archived ones live in the .archive.md sibling)" >&2; return 1; }
  hl="${hit%%$'\t'*}"; tag="${hit#*$'\t'}"
  case "$tag" in
    RESOLVED|ANSWERED) rm -f "$blanked"; echo "pw-review: $id in $RS_REL is already [$tag] → fix: resolving edits the SAME heading once, never a second pass — open a new item if this is new work" >&2; return 1 ;;
  esac
  local bend; bend="$(_block_end "$blanked" "$hl")"
  if [ "${id#Q}" != "$id" ]; then
    awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e' "$blanked" | grep -q '↳ \*\*you\*\*' \
      || { rm -f "$blanked"; echo "pw-review: $id has no '↳ **you**' answer yet → fix: the human answers first (/pw-review <slug> answer <review-path> <Qid> <answer>); the agent only folds + flips afterwards" >&2; return 1; }
  fi
  local ts; ts="$(now_ts)" || { rm -f "$blanked"; return 1; }
  local hline newtag newmark
  hline="$(sed -n "${hl}p" "$f")"
  case "$tag" in
    OPEN)    newtag="RESOLVED"; newmark="resolved" ;;
    PENDING) newtag="ANSWERED"; newmark="resolved" ;;
    *) rm -f "$blanked"; echo "pw-review: $id has unrecognized status tag [$tag] → fix: expected [OPEN] or [PENDING]" >&2; return 1 ;;
  esac
  printf '%s\n' "$hline" \
    | sed "s/\\[$tag\\]/[$newtag]/; s/pw-item-status: open/pw-item-status: $newmark/" > "$f.hdr" \
    || { rm -f "$f.hdr" "$blanked"; echo "pw-review: FAILED to render the flipped heading for $id — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  if md_replace_line "$f" "$hl" "$f.hdr"; then rm -f "$f.hdr"
  else rm -f "$f.hdr" "$blanked"; echo "pw-review: FAILED to flip the $id heading in place — nothing published → fix: check the file is writable and retry" >&2; return 1; fi
  local ins
  ins="$(awk -v s="$hl" -v e="$bend" 'NR>=s && NR<=e && $0=="---" {n=NR} END{print n+0}' "$blanked")"
  if [ "$ins" -gt 0 ]; then ins=$((ins-1)); else ins="$bend"; fi
  while [ "$ins" -gt "$hl" ] && [ -z "$(sed -n "${ins}p" "$blanked" | tr -d '[:space:]')" ]; do ins=$((ins-1)); done
  local reply; reply="$(mktemp)"
  {
    local prev; prev="$(sed -n "${ins}p" "$blanked" | sed 's/[[:space:]]*$//')"
    case "$prev" in '>'*) printf '>\n' ;; *) printf '\n' ;; esac
    printf '%s\n' "$RS_TEXT" | sed 's/^/> /; s/^> $/>/' | sed "1s|^> |> ↳ **agent** ($ts): |"
  } > "$reply"
  md_insert_lines_after "$f" "$ins" "$reply" \
    || { rm -f "$reply" "$blanked"; echo "pw-review: FAILED to splice the agent reply for $id — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  rm -f "$reply" "$blanked"
  pw_review_contents_rebuild "$f" \
    || { echo "pw-review: FAILED to rebuild the Contents block after resolving $id — whole staged write aborted → fix: repair the paired <!-- pw-contents:begin/end --> markers (see docs/REVIEW.md)" >&2; return 1; }
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header after resolving $id — whole staged write aborted → fix: check the file is writable and retry" >&2; return 1; }
}

cmd_resolve() {
  local slug="$1" rel="$2" id="$3"; shift 3
  local TEXT=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reply) shift; TEXT="$*"; _TEXT_SET=1; break ;;
      --stdin) TEXT="$(cat)"; _TEXT_SET=1; shift ;;
      *) die "resolve: unknown option: $1 (try --help)" ;;
    esac
  done
  [ "${_TEXT_SET:-0}" = 1 ] || die "resolve: no reply given → fix: pass --reply <what changed, rest of line> or --stdin"
  [ -n "$(printf '%s' "$TEXT" | tr -d '[:space:]')" ] || die "resolve: reply is empty → fix: the reply must say what changed (never a bare 'fixed'/'done')"
  case "$id" in R[0-9]*|Q[0-9]*) ;; *) die "resolve: id must look like R3 or Q2 (got '$id')" ;; esac
  local f; f="$(review_file "$slug" "$rel")" || return 2
  RS_TEXT="$TEXT" RS_REL="$rel"
  # a fixer reply inside a pass is NOT a human-feedback cycle: no state transition here
  staged_or_die "$f" _resolve_body "$id"
  _reindex "$slug" "$rel"
  _log "$slug" agent "resolved $id in $rel"
  echo "$slug: $rel → $id flipped to [$([ "${id#Q}" != "$id" ] && echo ANSWERED || echo RESOLVED)] in place, agent reply appended"
}

# --- lifecycle + gate reads ----------------------------------------------------

# Deterministic, unambiguous replacement for prose like "look for an approved row anywhere in this
# file": gate consumption requires the LATEST row approved AND zero real open items AND no active
# human rejection (_review_approval_valid — feedback added after an approval by ANY route,
# including hand edits, invalidates consumption; an unknown/malformed table fails closed).
# Prints the current decision text VERBATIM (so an old file's literal "approved ✅" still prints
# that); the exit code is the consumability verdict.
#   gate <slug> <review-rel-path>

# The other half of the analysis/RFC-parity mechanism (docs/RFC.md): a fix applied to a doc AFTER
# its review was already approved must invalidate that stale approval. Appends a fresh `in-review`
# row — NEVER deletes the old approval (append-only history). Idempotent no-op when the file isn't
# currently approved. Tagged "pw-review (auto-reopen)" (legacy attribution kept for history
# compatibility). Reopening an approval whose phase was already consumed by a later dashboard
# phase requires --confirm-earlier: a later phase may depend on the approval being rewound.
#   reopen <slug> <review-rel-path> [--confirm-earlier]
REOPEN_REL=""
_reopen_body() {
  local f="$1"
  local ts; ts="$(pw_now_wib)" || return 1
  pw_signoff_row_put "$f" "$ts" "pw-review (auto-reopen)" "in-review" \
    || { echo "pw-review: no Sign-off table rows found in $REOPEN_REL → fix: the table lost its rows; restore them from template/_REVIEW.template.md" >&2; return 1; }
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header in $REOPEN_REL — reopen aborted, nothing published → fix: check the file is writable and retry" >&2; return 1; }
}

cmd_reopen() {
  local slug="$1" rel="$2" confirm=0
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --confirm-earlier) confirm=1; shift ;;
      *) die "reopen: unknown option: $1 (try --help)" ;;
    esac
  done
  local d; d="$(proj_dir "$slug")" || return 2
  pw_review_contain "$d" "$rel" >/dev/null || die "invalid review path: $rel → fix: keep it project-relative"
  local f="$d/$rel"
  [ -L "$f" ] && die "refusing symlinked review file: $rel → fix: operate on the real file (symlinks can silently redirect writes outside the project)"
  [ -f "$f" ] || die "no such review file: $rel → fix: create it with: /pw-review $slug init <artifact-path>"
  local decision; decision="$(_signoff_latest_decision "$f")" \
    || die "no Sign-off table rows found in $rel — not a valid review file → fix: restore the table from template/_REVIEW.template.md"
  if ! _decision_is_approved "$decision"; then
    echo "$slug: $rel already open (current: $decision) — nothing to reopen"
    return 0
  fi
  local st; st="$(_dash_lane_state "$slug" "$rel")"
  [ "$st" = unknown ] && die "dashboard phase is missing or non-canonical — cannot judge whether this approval was already consumed → fix: repair the dashboard Status line (/pw-status $slug shows the current phase)"
  [ "$st" = earlier ] && [ "$confirm" != 1 ] && die "$rel is approved and its phase was consumed by a LATER dashboard phase — reopening it rewinds a gate work already depends on → fix: get the human's explicit confirmation, then re-run with --confirm-earlier"
  REOPEN_REL="$rel"
  staged_or_die "$f" _reopen_body
  _log "$slug" pw-review "AUTO-REOPENED $rel — a fix was applied after it was already approved (new row: in-review); re-approve once settled"
  echo "$slug: $rel reopened (was $decision, now in-review)"
}

# Write the Sign-off row on a review file WITHOUT a human — the ONE tool-enforced exception to
# "only a human clears a gate". Refuses unless ALL of: (1) AI Review mode for <phase> is genuinely
# "auto" (re-checked here), (2) the review file belongs to <phase>'s lane (artifact/lane binding —
# RFC staging NEVER gets an approval row), (3) zero real open items/questions, (4) no explicit
# human changes-requested still active (the conservative rejection policy: only a human row
# withdraws it), and (5) the phase was not already consumed by a later dashboard phase — that
# needs --confirm-earlier. The row names the ACTUAL reviewer: pw-reviewer (auto;
# provider=<p>; model=<m>), "unknown" for anything the runtime cannot confirm — identity labels
# never grant authority the guards above don't.
#   auto-signoff <slug> <review-rel-path> <phase> [--provider <id>] [--model <id>] [--confirm-earlier]
AS_BY=""; AS_REL=""
_auto_signoff_body() {
  local f="$1"
  _review_has_open_marker "$f" && { echo "pw-review: refusing auto-signoff: $AS_REL still has an unresolved [OPEN] item or [PENDING] question" >&2; return 1; }
  _signoff_human_rejection_active "$f" && { echo "pw-review: refusing auto-signoff: an explicit human changes-requested is still active in $AS_REL → fix: only the human withdraws it (/pw-review <slug> signoff <review-path> in-review --by <name>, on explicit instruction)" >&2; return 1; }
  local ts; ts="$(pw_now_wib)" || return 1
  pw_signoff_row_put "$f" "$ts" "$AS_BY" approved \
    || { echo "pw-review: no Sign-off table rows found in $AS_REL → fix: restore the table from template/_REVIEW.template.md" >&2; return 1; }
  pw_review_gate_refresh "$f" \
    || { echo "pw-review: FAILED to refresh the Gate header in $AS_REL — auto-signoff aborted, nothing published → fix: check the file is writable and retry" >&2; return 1; }
}

cmd_auto_signoff() {
  [ $# -ge 3 ] || die "usage: auto-signoff <slug> <review-rel-path> <phase> [--provider <id>] [--model <id>] [--confirm-earlier]   (phase: $AI_REVIEW_PHASES)"
  local slug="$1" rel="$2" phase="$3"; shift 3
  local provider="" model="" confirm=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --provider) [ $# -ge 2 ] || die "--provider requires an argument"; provider="$2"; shift 2 ;;
      --provider=*) provider="${1#--provider=}"; shift ;;
      --model) [ $# -ge 2 ] || die "--model requires an argument"; model="$2"; shift 2 ;;
      --model=*) model="${1#--model=}"; shift ;;
      --confirm-earlier) confirm=1; shift ;;
      *) die "auto-signoff: unknown option: $1 (try --help)" ;;
    esac
  done
  case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
  local d; d="$(proj_dir "$slug")" || return 2
  pw_review_contain "$d" "$rel" >/dev/null || die "invalid review path: $rel → fix: keep it project-relative"
  local f="$d/$rel"
  [ -L "$f" ] && die "refusing symlinked review file: $rel → fix: operate on the real file (symlinks can silently redirect writes outside the project)"
  [ -f "$f" ] || die "no such review file: $rel"
  local lane; lane="$(pw_review_lane "$rel")"
  [ "$lane" = rfc ] && die "RFC comment staging never receives an approval row — its unresolved comments keep their own has-open check (see docs/RFC.md)"
  pw_review_phase_lane_ok "$phase" "$lane" \
    || die "lane mismatch: $rel belongs to the '$lane' lane, not '$phase' → fix: pass the surface that owns this artifact (context↔context readiness, analysis↔analysis topics, plan↔PLAN, task-plan/task-exec/ship↔task docs+results, rfc↔rfc/RFC.md content, close↔the CLOSE record)"
  local mode; mode="$(_ai_review_mode_of "$slug" "$phase")"
  [ "$mode" = "auto" ] || die "refusing auto-signoff: this project's AI Review mode for '$phase' is '$mode', not 'auto' (pw-config.sh project set $slug ai-review $phase=auto to enable)"
  local st; st="$(_dash_lane_state "$slug" "$rel")"
  [ "$st" = unknown ] && die "dashboard phase is missing or non-canonical → fix: repair the dashboard Status line (/pw-status $slug shows the current phase)"
  [ "$st" = earlier ] && [ "$confirm" != 1 ] && die "$rel's phase was already consumed by a later dashboard phase — an auto approval here would silently rewind a used gate → fix: get the human's confirmation, then rerun with --confirm-earlier"
  local ident prov mdl; ident="$(_ai_identity "$provider" "$model")"
  prov="${ident%%$'\t'*}"; mdl="${ident#*$'\t'}"
  AS_BY="pw-reviewer (auto; provider=$prov; model=$mdl)" AS_REL="$rel"
  staged_or_die "$f" _auto_signoff_body
  _log "$slug" pw-reviewer "AUTO-APPROVED $rel (phase=$phase, AI Review mode=auto, provider=$prov, model=$mdl, zero open items, no active human rejection) — no human sign-off"
  echo "$slug: $rel auto-signed-off by $AS_BY (phase=$phase)"
}

# Read-only generic open-item check (RFC staging's side-loop check rides this; missing file →
# "no" + exit 1, never an error).

# Read-only eligible-work report — the same detector `start` uses, so a caller can see the REAL
# actionable work set before deciding to enter a pass (stubs/resolved/archived/malformed-only/
# waiting-human-only → eligible=0, exit 1: nothing to repair, no transition justified).


cmd_reindex() {
  [ $# -eq 2 ] || die "usage: reindex <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local f; f="$(review_file "$slug" "$rel")" || return 2
  staged_or_die "$f" pw_review_contents_rebuild
  local rows n
  rows="$(_review_items_tsv "$f" | cut -f2-)"
  n="$(printf '%s\n' "$rows" | grep -c . || true)"; : "${n:=0}"
  _log "$slug" review "reindexed $rel ($n live item(s)/question(s))"
  echo "$slug: reindexed $rel ($n item(s)/question(s))"
}

cmd_archive() {
  [ $# -eq 2 ] || die "usage: archive <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  case "$rel" in
    *.review.md) ;;
    *) die "archive expects a .review.md file (got '$rel') → fix: archive the live review file, never its .archive.md sibling" ;;
  esac
  local d; d="$(proj_dir "$slug")" || return 2
  pw_review_contain "$d" "$rel" >/dev/null || die "invalid review path: $rel → fix: keep it project-relative"
  local f="$d/$rel"
  [ -L "$f" ] && die "refusing symlinked review file: $rel → fix: operate on the real file (symlinks can silently redirect writes outside the project)"
  [ -f "$f" ] || die "no such review file: $rel"
  # The .archive.md sibling is a real file the worker appends OUTSIDE the staged copy —
  # it gets the same containment + symlink guard as the review file itself, or a planted
  # (or dangling) symlink at the derived sibling path would silently redirect the public
  # redirection through it. Derived name replaces the suffix only, so containment of the
  # review path bounds the sibling directory; the check makes that explicit.
  local archrel="${rel%.review.md}.archive.md"
  pw_review_contain "$d" "$archrel" >/dev/null \
    || die "invalid archive sibling path: $archrel → fix: keep the review path project-relative"
  local af="$d/$archrel"
  [ -L "$af" ] && die "refusing symlinked archive sibling: $archrel → fix: remove the symlink (archive appends real payload; it must never write through a public path redirect)"
  local rc=0 _AR_N=0
  pw_review_staged "$f" _archive_body "$slug" "$rel" "$archrel" "$af" || rc=$?
  [ "$rc" = 3 ] && die "$rel is locked by another writer → fix: retry in a moment; if no writer is running, remove the stale lock directory $f.pwlock"
  [ "$rc" = 0 ] || exit 2
  # an empty resolved set published nothing and created nothing (see _archive_body order);
  # report no-op only — never an "archive completed" claim, never a LOG line, for zero items.
  [ "${_AR_N:-0}" -gt 0 ] || return 0
  _log "$slug" review "archived ${_AR_N:-0} resolved item(s)/question(s) from $rel to $archrel"
  echo "$slug: archive completed for $rel → $archrel"
}

# Archive worker — runs against the STAGED COPY ($1 = work file). Gate-safety: this only ever
# moves resolved/answered headings (sttag-classifier canonical: a CONFLICT heading is NEVER
# movable, so archiving can never strip a real OPEN blocker out of the gate's view) and never
# touches "## Sign-off" — see _review_approval_valid's readers, which keep working on the
# latest row + open markers + human rejection only.
# Ordering (no-op purity): the real resolved set is computed FIRST; an empty set returns with
# zero writes — no "## Archived items" header, no sibling file, bytes untouched. Section and
# sibling creation happen only when there is something to move.
# Sibling atomicity + retry idempotence: each block is appended through a temp + same-directory
# mv, and every payload block is fenced with `<!-- pw-archived-block:<id> -->` markers. If the
# review-file publish later fails, the already-landed block is detected on retry (begin marker
# present → skip append), so a repeated archive run can neither duplicate payload nor lose a
# partially written one; historical blocks and pointer rows are preserved verbatim and the old
# archive is never deleted. Every splice/publish failure propagates rc 1 so the staged review
# publish aborts and the command never reports success.
_archive_body() {
  local f="$1" slug="$2" rel="$3" archrel="$4" af="$5"
  local blanked; blanked="$(mktemp)"; _comment_blanked "$f" > "$blanked"
  local total; total="$(wc -l < "$blanked" | tr -d ' ')"
  local -a all_heads=()
  while IFS= read -r h; do all_heads+=("$h"); done < <(grep -nE '^(## |### )' "$blanked" | cut -d: -f1)

  local -a rstarts=() rends=() rids=()
  while IFS=$'\t' read -r ln id anchor tag; do
    [ "$tag" = "RESOLVED" ] || [ "$tag" = "ANSWERED" ] || continue
    local end="$total" hh
    for hh in "${all_heads[@]}"; do
      if [ "$hh" -gt "$ln" ]; then end=$((hh-1)); break; fi
    done
    rstarts+=("$ln"); rends+=("$end"); rids+=("$id")
  done < <(_review_items_tsv "$f")
  rm -f "$blanked"

  if [ "${#rstarts[@]}" -eq 0 ]; then
    _AR_N=0
    echo "$slug: $rel — nothing to archive (no [RESOLVED]/[ANSWERED] items); no sibling or header was created"
    return 0
  fi
  [ -L "$af" ] && { echo "pw-review: refusing to append through a symlinked archive sibling: $archrel → fix: remove the symlink" >&2; return 1; }
  local i today; today="$(pw_now_wib)" || return 1

  if ! grep -q '^## Archived items' "$f"; then
    local secfile; secfile="$(mktemp)"
    {
      printf '\n## Archived items   [agent-owned; refreshed automatically; do not edit]\n\n'
      printf 'Full text preserved verbatim in `%s`.\n\n' "$(basename "$archrel")"
      printf '| ID | Summary | Archived |\n|----|---------|----------|\n'
    } > "$secfile" || { rm -f "$secfile"; echo "pw-review: FAILED to render the Archived items section — nothing published → fix: check the file is writable and retry" >&2; return 1; }
    if grep -q '^## Sign-off' "$f"; then
      local signline; signline="$(grep -n '^## Sign-off' "$f" | head -1 | cut -d: -f1)"
      if ! { head -n "$((signline - 1))" "$f"; cat "$secfile"; printf '\n'; tail -n "+${signline}" "$f"; } > "$f.tmp"; then
        rm -f "$secfile" "$f.tmp"; echo "pw-review: FAILED to add the Archived items section to $rel — nothing published → fix: check the file is writable and retry" >&2; return 1
      fi
      if ! mv "$f.tmp" "$f"; then
        rm -f "$secfile" "$f.tmp"; echo "pw-review: FAILED to publish the Archived items section in $rel — nothing published → fix: check the file is writable and retry" >&2; return 1
      fi
    else
      if ! cat "$secfile" >> "$f"; then
        rm -f "$secfile"; echo "pw-review: FAILED to append the Archived items section to $rel — nothing published → fix: check the file is writable and retry" >&2; return 1
      fi
    fi
    rm -f "$secfile"
  fi
  if [ ! -f "$af" ]; then
    local htmp="$af.tmp"
    {
      printf '# Archived review items — %s\n\n' "$(basename "${rel%.review.md}")"
      printf 'Items/questions moved out of `%s` once fully [RESOLVED]/[ANSWERED] — text preserved verbatim, never edited. See that file'"'"'s "## Archived items"\n' "$rel"
      printf 'table for one pointer row per entry moved here.\n'
    } > "$htmp" || { rm -f "$htmp"; echo "pw-review: FAILED to render the archive sibling header for $archrel → fix: check the review dir is writable and retry" >&2; return 1; }
    if ! mv "$htmp" "$af"; then
      rm -f "$htmp"; echo "pw-review: FAILED to create the archive sibling $archrel → fix: check the review dir is writable and retry" >&2; return 1
    fi
  fi

  for i in "${!rstarts[@]}"; do
    local s="${rstarts[$i]}" e="${rends[$i]}" id="${rids[$i]}"
    local blocktxt; blocktxt="$(sed -n "${s},${e}p" "$f")"
    local summary
    summary="$(printf '%s\n' "$blocktxt" | tail -n +2 | grep -vE '^[[:space:]]*$' | head -1)"
    if [ ${#summary} -gt 80 ]; then summary="${summary:0:80}…"; fi
    summary="$(printf '%s' "$summary" | sed 's/|/\\|/g')"
    [ -n "$summary" ] || summary="(no summary line)"
    local bmark="<!-- pw-archived-block:$id -->"
    if ! grep -Fq "$bmark" "$af"; then
      local atmp="$af.tmp"
      if cp "$af" "$atmp" 2>/dev/null \
         && { printf '\n---\n\n'; printf '%s\n' "$bmark"; printf '%s\n' "$blocktxt"; printf '<!-- end pw-archived-block:%s -->\n' "$id"; } >> "$atmp" \
         && mv "$atmp" "$af" 2>/dev/null; then
        :
      else
        rm -f "$atmp"; echo "pw-review: FAILED to append the $id block to $archrel — whole archive aborted, nothing published → fix: check the review dir is writable and retry" >&2; return 1
      fi
    fi
    local marker="<!-- pw-archived:$id -->"
    local row="| $id | $summary | $today $marker |"
    if grep -Fq "$marker" "$f"; then
      if ! awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' "$f" > "$f.tmp"; then
        rm -f "$f.tmp"; echo "pw-review: FAILED to rewrite the $id pointer row — whole archive aborted, nothing published → fix: check the file is writable and retry" >&2; return 1
      fi
      mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "pw-review: FAILED to publish the $id pointer row — whole archive aborted → fix: check the file is writable and retry" >&2; return 1; }
    else
      if ! awk -v row="$row" '
        /^## Archived items/ { insec=1 }
        { print }
        insec && !done && /^\|[-| ]+\|[ ]*$/ { print row; done=1 }
      ' "$f" > "$f.tmp"; then
        rm -f "$f.tmp"; echo "pw-review: FAILED to insert the $id pointer row — whole archive aborted, nothing published → fix: check the file is writable and retry" >&2; return 1
      fi
      mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "pw-review: FAILED to publish the $id pointer row — whole archive aborted → fix: check the file is writable and retry" >&2; return 1; }
      grep -Fq "$marker" "$f" || { echo "pw-review: FAILED to place the $id pointer row in $rel (Archived items table not found) — whole archive aborted, nothing published → fix: restore the '## Archived items' table and retry" >&2; return 1; }
    fi
  done

  local order; order="$(for i in "${!rstarts[@]}"; do printf '%s\t%s\n' "${rstarts[$i]}" "$i"; done | sort -rn -k1,1)"
  while IFS=$'\t' read -r _ i; do
    local s="${rstarts[$i]}" e="${rends[$i]}"
    local flen; flen="$(wc -l < "$f" | tr -d ' ')"
    if ! {
      [ "$s" -gt 1 ] && sed -n "1,$((s-1))p" "$f"
      [ "$e" -lt "$flen" ] && sed -n "$((e+1)),\$p" "$f"
      true
    } > "$f.tmp"; then
      rm -f "$f.tmp"; echo "pw-review: FAILED to remove the archived $((i+1))-th block from $rel — whole archive aborted, nothing published → fix: check the file is writable and retry" >&2; return 1
    fi
    mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "pw-review: FAILED to publish block removals for $rel — nothing published → fix: check the file is writable and retry" >&2; return 1; }
  done <<< "$order"

  pw_review_contents_rebuild "$f" \
    || { echo "pw-review: FAILED to rebuild the Contents block during archive of $rel — whole archive aborted, nothing published → fix: repair the paired <!-- pw-contents:begin/end --> markers (see docs/REVIEW.md)" >&2; return 1; }
  _AR_N="${#rstarts[@]}"
  echo "$slug: archived ${#rstarts[@]} item(s)/question(s) from $rel to $archrel"
}

# ---------------------------------------------------------------- start (pass entry)
ST_BY=""; ST_REL=""
# Worker decision (under the per-file lock, so the work set is RE-checked before publishing —
# recheck the work set before publication): append changes-requested only for real eligible work;
# never approved; never toggle inside the same active attempt. The latest-decision ENUM is
# validated FIRST: a file whose current decision is unrecognized/malformed must fail closed
# even when the work set happens to be empty — reporting such a file "clean" would tell the
# caller the gate state is trustworthy when it is not (the empty-set short-circuit previously
# ran before the enum check).
_start_body() {
  local f="$1"
  local d a
  if ! d="$(_signoff_latest_decision "$f")"; then
    echo "pw-review: no Sign-off table rows found in $ST_REL — not a valid review file → fix: restore the table from template/_REVIEW.template.md" >&2
    return 1
  fi
  case "$d" in
    approved|approved\ ✅) ;;
    in-review|changes-requested) ;;
    *) echo "pw-review: unrecognized latest decision '$d' in $ST_REL — pass entry stopped, no state mutation → fix: repair the Sign-off table (approved | changes-requested | in-review) from template/_REVIEW.template.md" >&2; return 1 ;;
  esac
  local counts; counts="$(_review_eligible_counts "$f")"
  local e="${counts#eligible=}"; e="${e%% *}"
  if [ "${e:-0}" -eq 0 ]; then
    printf '__clean__ %s\n' "$counts" > "$_START_REPORT"
    return 0
  fi
  a="$(_signoff_latest_actor "$f")" || a=""
  if [ "$d" = "changes-requested" ] && [ "$a" = "$ST_BY" ]; then
    printf '__resume__ %s\n' "$counts" > "$_START_REPORT"
    return 0
  fi
  local ts; ts="$(pw_now_wib)" || return 1
  pw_signoff_row_put "$f" "$ts" "$ST_BY" changes-requested \
    || { echo "pw-review: no Sign-off table rows found in $ST_REL mid-write — nothing published → fix: restore the table from template/_REVIEW.template.md" >&2; return 1; }
  pw_review_gate_refresh "$f" || return 1
  printf '__entered__ %s\n' "$counts" > "$_START_REPORT"
}

cmd_start() {
  [ $# -ge 2 ] || die "usage: start <slug> <review-rel-path> [--phase <analysis|plan|task-plan|task-exec|ship>] [--provider <id>] [--model <id>] [--confirm-earlier]"
  local slug="$1" rel="$2"; shift 2
  local phase="" provider="" model="" confirm=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --phase) [ $# -ge 2 ] || die "--phase requires an argument"; phase="$2"; shift 2 ;;
      --phase=*) phase="${1#--phase=}"; shift ;;
      --provider) [ $# -ge 2 ] || die "--provider requires an argument"; provider="$2"; shift 2 ;;
      --provider=*) provider="${1#--provider=}"; shift ;;
      --model) [ $# -ge 2 ] || die "--model requires an argument"; model="$2"; shift 2 ;;
      --model=*) model="${1#--model=}"; shift ;;
      --confirm-earlier) confirm=1; shift ;;
      *) die "start: unknown option: $1 (try --help)" ;;
    esac
  done
  local f; f="$(review_file "$slug" "$rel")" || return 2
  grep -q '^## Sign-off' "$f" || die "$rel has no '## Sign-off' section — pass entry needs the gate table (task reviews created from the template always have one)"
  local lane; lane="$(pw_review_lane "$rel")"
  [ "$lane" = rfc ] && die "RFC comment staging has no pass-entry state (its comments keep their own has-open check — see docs/RFC.md)"
  [ "$lane" = other ] && die "$rel is not a review-lane artifact → fix: review files live under analysis/review/ or task/review/"
  local mode="repair" prov="n/a" mdl="n/a"
  if [ -n "$phase" ]; then
    case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
    pw_review_phase_lane_ok "$phase" "$lane" \
      || die "lane mismatch: $rel belongs to the '$lane' lane, not '$phase' → fix: select the surface that owns this artifact (context↔context readiness, analysis↔analysis topics, plan↔PLAN, task-plan/task-exec/ship↔task docs+results, rfc↔rfc/RFC.md content, close↔the CLOSE record)"
    mode="$(_ai_review_mode_of "$slug" "$phase")"
    [ "$mode" = advisory ] || [ "$mode" = auto ] \
      || die "AI Review mode for '$phase' is '$mode' — an independent AI pass needs advisory or auto → fix: run without --phase for the normal repair pass, or configure: /pw-config $slug set ai-review $phase=advisory"
    local ident; ident="$(_ai_identity "$provider" "$model")"
    prov="${ident%%$'\t'*}"; mdl="${ident#*$'\t'}"
    ST_BY="pw-reviewer ($mode; provider=$prov; model=$mdl)"
  else
    ST_BY="pw-review (repair)"
  fi
  local st; st="$(_dash_lane_state "$slug" "$rel")"
  [ "$st" = unknown ] && die "dashboard phase is missing or non-canonical — cannot judge consumed-phase safety → fix: repair the dashboard Status line (/pw-status $slug shows the current phase)"
  [ "$st" = earlier ] && [ "$confirm" != 1 ] && die "$rel's phase was already consumed by a later dashboard phase — a repair pass here may invalidate work that depends on the gate → fix: get the human's explicit confirmation, then re-run with --confirm-earlier"
  ST_REL="$rel"
  _START_REPORT="$(mktemp)" || die "cannot create pass report → fix: check the temporary directory"
  local start_rc=0
  pw_review_staged "$f" _start_body || start_rc=$?
  if [ "$start_rc" != 0 ]; then
    rm -f "$_START_REPORT"
    [ "$start_rc" != 3 ] || die "$f is locked by another writer → fix: retry after that writer finishes"
    exit 2
  fi
  local report kind; report="$(cat "$_START_REPORT")"; rm -f "$_START_REPORT"; kind="${report%% *}"; local counts="${report#* }"
  _log "$slug" pw-review "pass entry on $rel: mode=$mode phase=${phase:-repair} provider=$prov model=$mdl decision=$kind ($counts)"
  echo "$slug: $rel → pass entry ($kind by $ST_BY, mode=$mode${phase:+, phase=$phase}) — $counts"
  return 0
}

# ---------------------------------------------------------------- scan

# ---------------------------------------------------------------- prepare / import (handoff)
# Freeze ONE review unit into review/ai/<pass-id>/ — a manifest, an immutable snapshot, and a
# neutral reviewer request — WITHOUT launching a model. A manual (or later, a managed adapter's)
# session consumes the packet and returns a schema-conforming report; `import` validates it
# against the SAME manifest under the SAME validator. One packet + one validator; no second
# markdown parser, no session-transfer service.
# The imported result is ALWAYS advisory: it never approves a gate, never repairs, grants no
# publication authority, and cannot become a managed pass. Only a workflow-managed reviewer
# route (with trusted process evidence) may feed guarded auto-approval.
# Pass states: prepared → importing → imported, or stale (inputs moved). One report per pass;
# import is replay-safe (progress is recorded after each item, duplicates are skipped).

_pass_root() { printf '%s/review/ai' "$1"; }

_mf_read() { # <manifest> <key> — the scalar value after the first "key": on the first line
  # carrying it. Read correctly even when the pair is nested inside the one-line import
  # object (report_sha256 / verdict); strings stop at their closing quote, numbers at ,/}.
  local line
  line="$(grep -m1 "\"$2\":" "$1" 2>/dev/null || true)"
  printf '%s' "$line" | awk -v k="\"$2\":" '
    { i = index($0, k); if (!i) exit; s = substr($0, i + length(k)); sub(/^[ \t]+/, "", s)
      if (substr(s,1,1) == "\"") { s = substr(s,2); sub(/".*$/, "", s) } else { sub(/[,}].*$/, "", s) }
      print s }'
}

_mf_set_scalar() { # <manifest> <key> <raw-json-value> — rewrite one scalar, comma style kept
  local f="$1" k="$2" v="$3" tmp="$1.tmp.$$"
  if awk -v k="\"$k\":" -v v="\"$k\": $v" '
      !d && index($0, k) > 0 {
        tc = ($0 ~ /,[[:space:]]*$/) ? "," : ""
        print "  " v tc; d = 1; next
      }
      { print }
      END { if (!d) exit 3 }' "$f" > "$tmp"; then
    mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
    return 0
  fi
  rm -f "$tmp"; return 1
}

_json_list() { # <space-separated safe words> → ["a","b"] (empty → [])
  local out="" w
  for w in $1; do [ -n "$w" ] && out="$out,\"$w\""; done
  printf '[%s]' "${out#,}"
}

_fingerprint_of_lines() { # <newline-joined "rel\tsha" lines> — canonical digest
  printf '%s' "$1" | sed '/^$/d' | pw_review_fingerprint
}

_prepare_pass_id() { # <surface> → p-<surface>-<UTCstamp>-<hex4>
  printf 'p-%s-%s-%04x' "$1" "$(date -u +%Y%m%dT%H%M%SZ)" "$(( $$ % 65536 ))"
}

_rounds_of_file() { # <readme> — review-rounds budget (default 3)
  local line v
  line="$(grep -m1 '^- \*\*Review Budget:\*\*' "$1" 2>/dev/null || true)"
  v="$(printf '%s' "$line" | sed -n 's/.*rounds=\([0-9][0-9]*\).*/\1/p')"
  printf '%s' "${v:-3}"
}

# _prepare_resolve <slug> <projdir> <scope> → "surface\tartifact\treview" (artifact "-" = close)
_prepare_resolve() {
  local slug="$1" d="$2" scope="$3" tok
  tok="$(pw_phase_token "$("$ST" phase "$slug" 2>/dev/null || true)")"
  case "$scope" in
    context)
      [ -f "$d/context/REQUIREMENTS.md" ] || die "prepare context: no context/REQUIREMENTS.md yet → fix: /pw-context $slug prepare"
      printf 'context\tcontext/REQUIREMENTS.md\tcontext/review/CONTEXT.review.md\n' ;;
    rfc)
      [ -f "$d/rfc/RFC.md" ] || die "prepare rfc: no rfc/RFC.md yet → fix: /pw-rfc $slug init"
      printf 'rfc\trfc/RFC.md\trfc/review/RFC-CONTENT.review.md\n' ;;
    close)
      printf 'close\t-\treview/CLOSE.review.md\n' ;;
    analysis)
      local -a cands=()
      local f
      if [ -d "$d/analysis" ]; then
        for f in "$d"/analysis/*.md; do
          [ -e "$f" ] || continue
          case "$(basename "$f")" in _TEMPLATE*|README.md|RFC.md) continue ;; esac
          cands+=("${f#$d/}")
        done
      fi
      [ "${#cands[@]}" -eq 1 ] || die "prepare analysis: expected exactly ONE analysis doc (found ${#cands[@]}) → fix: name the path instead: /pw-review $slug prepare analysis/<topic>.md"
      _prepare_path_unit "$slug" "$d" "${cands[0]}" ""
      ;;
    plan)
      _prepare_path_unit "$slug" "$d" "task/PLAN.md" "plan" ;;
    task-plan|task-exec|ship)
      die "prepare $scope: name one task → fix: /pw-review $slug prepare T01   (the surface is inferred from the dashboard phase; use an explicit path for other units)" ;;
    T[0-9]*)
      case "$scope" in T[0-9][0-9]*) ;; *) die "invalid task id '$scope' (expected T01 …)" ;; esac
      [ -f "$d/task/$scope.md" ] || die "no task/$scope.md in $slug → fix: /pw-breakdown owns task creation"
      case "$tok" in
        breakdown) printf 'task-plan\ttask/%s.md\ttask/review/%s.review.md\n' "$scope" "$scope" ;;
        *)         printf 'task-exec\ttask/%s.md\ttask/review/%s.review.md\n' "$scope" "$scope" ;;
      esac ;;
    *)
      _prepare_path_unit "$slug" "$d" "$scope" "" ;;
  esac
}

# _prepare_path_unit <slug> <projdir> <artifact-rel> <forced-surface|""> — validate via the
# shared artifact mapper and infer the surface from the lane (+ dashboard for task docs).
_prepare_path_unit() {
  local slug="$1" d="$2" rel="$3" surf="$4" line lane tok
  if line="$(pw_review_reviewrel "$d" "$rel" 2>&1)"; then :; else die "prepare: $line"; fi
  lane="$(pw_review_lane "${line%%$'\t'*}")"
  if [ -z "$surf" ]; then
    case "$lane" in
      context)    surf=context ;;
      analysis)   surf=analysis ;;
      plan)       surf=plan ;;
      rfccontent) surf=rfc ;;
      task)
        tok="$(pw_phase_token "$("$ST" phase "$slug" 2>/dev/null || true)")"
        case "$tok" in breakdown) surf=task-plan ;; *) surf=task-exec ;; esac ;;
      *) die "prepare: unsupported artifact: $rel" ;;
    esac
  fi
  printf '%s\t%s\n' "$surf" "$line"
}

# _prepare_inputs <projdir> <surface> <artifact-rel> — one project-relative reviewed input per
# line (the artifact plus its declared supporting set; close = the evidence bundle).
_prepare_inputs() {
  local d="$1" surf="$2" artifact="$3" f
  case "$surf" in
    close)
      [ -f "$d/README.md" ] && echo "README.md"
      [ -f "$d/task/PLAN.md" ] && echo "task/PLAN.md"
      for f in "$d"/task/T*.md; do [ -e "$f" ] || continue; echo "${f#$d/}"; done
      for f in "$d"/task/review/T*.review.md; do [ -e "$f" ] || continue; echo "${f#$d/}"; done
      ;;
    context)
      echo "$artifact"
      [ -f "$d/context/INDEX.md" ] && echo "context/INDEX.md"
      ;;
    *) echo "$artifact" ;;
  esac
}

# _prepare_code_evidence <projdir> <task-id|""> — for each task worktree: repo, worktree path,
# head, base ref, patch digest. Tab-separated lines; empty when nothing is discoverable.
_prepare_code_evidence() {
  local d="$1" tid="$2" wt repo head base bref ds
  [ -n "$tid" ] || return 0
  [ -d "$d/worktree" ] || return 0
  for wt in "$d"/worktree/*/"$tid"-*; do
    [ -d "$wt" ] || continue
    repo="$(basename "$(dirname "$wt")")"
    head="$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)"
    base="$(pw_field "$d/task/$tid.md" "Base branch" 2>/dev/null || true)"
    bref=""
    if [ -n "$base" ]; then
      bref="$(git -C "$wt" rev-parse --verify --quiet "$base" || git -C "$wt" rev-parse --verify --quiet "origin/$base" || true)"
    fi
    if [ -n "$head" ] && [ -n "$bref" ]; then
      ds="$(git -C "$wt" diff "$bref...HEAD" 2>/dev/null | pw_review_hash_stdin || true)"
      [ -n "$ds" ] || ds="unavailable"
    else
      ds="unavailable"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "${wt#$d/}" "${head:-unavailable}" "${base:-unavailable}" "$ds"
  done
}

# _prepare_fingerprint <projdir> <manifest> — recompute the reviewed-identity digest from the
# manifest's recorded inputs plus freshly read code evidence (byte-identical generator).
_prepare_fingerprint() {
  local d="$1" mf="$2" path sha lines="" line inblock surf art tid ce
  inblock="$(sed -n '/"inputs": \[/,/^  \]/p' "$mf")"
  while IFS= read -r line; do
    case "$line" in
      *'"path"'*)
        path="$(printf '%s' "$line" | sed 's/.*"path":[[:space:]]*"\([^"]*\)".*/\1/')"
        sha="$(pw_review_sha256 "$d/$path" 2>/dev/null || true)"
        [ -n "$sha" ] || { echo "reviewed input missing or unhashable now: $path" >&2; return 1; }
        lines="$lines$path	$sha
" ;;
    esac
  done <<< "$inblock"
  surf="$(_mf_read "$mf" surface)"; art="$(_mf_read "$mf" artifact)"
  tid=""
  case "$surf" in task-plan|task-exec|ship) tid="$(basename "$art" .md)" ;; esac
  ce="$(_prepare_code_evidence "$d" "$tid")"
  [ -n "$ce" ] && lines="$lines$ce
"
  _fingerprint_of_lines "$lines"
  return 0
}

cmd_prepare() {
  [ $# -ge 2 ] || die "usage: prepare <slug> <scope> [--refresh] [--repair] [--pass-id <id>] [--print]   (scope: T0n | context|analysis|plan|task-plan|task-exec|ship|rfc|close | artifact path)"
  local slug="$1" scope="$2"; shift 2
  local refresh=0 repair=0 pass_override="" print_req=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --refresh) refresh=1; shift ;;
      --repair)  repair=1; shift ;;
      --pass-id) [ $# -ge 2 ] || die "--pass-id requires an argument"; pass_override="$2"; shift 2 ;;
      --pass-id=*) pass_override="${1#--pass-id=}"; shift ;;
      --print) print_req=1; shift ;;
      *) die "prepare: unknown option: $1 (try --help)" ;;
    esac
  done
  case "$pass_override" in
    '') ;;
    *[!A-Za-z0-9._-]*) die "invalid --pass-id '$pass_override' → fix: letters, digits, dot, underscore, dash only (it becomes a directory name)" ;;
  esac
  local d; d="$(proj_dir "$slug")" || return 2
  local unit surf artifact reviewrel
  if unit="$(_prepare_resolve "$slug" "$d" "$scope" 2>&1)"; then :; else die "prepare: $unit"; fi
  surf="${unit%%$'\t'*}"; unit="${unit#*$'\t'}"
  artifact="${unit%%$'\t'*}"; reviewrel="${unit#*$'\t'}"
  # the review record is the import target — create it before any report can land
  local docfor="$artifact"
  [ "$artifact" = "-" ] && docfor="close-report.md"
  if [ ! -f "$d/$reviewrel" ]; then
    _init_one "$slug" "$d" "$reviewrel" "$docfor" >/dev/null \
      || die "prepare: could not create $reviewrel → fix: see the error above; create it with: /pw-review $slug init-docs $docfor"
  fi
  # prior passes for the SAME artifact+surface: show the packet, or require --refresh/--repair
  local root pd m_surf m_art m_round maxround=0 count=0 newest=""
  root="$(_pass_root "$d")"
  if [ -d "$root" ]; then
    for pd in "$root"/*/; do
      [ -f "$pd/manifest.json" ] || continue
      m_surf="$(_mf_read "$pd/manifest.json" surface)"
      m_art="$(_mf_read "$pd/manifest.json" artifact)"
      [ "$m_surf" = "$surf" ] && [ "$m_art" = "$artifact" ] || continue
      count=$((count+1)); newest="$pd"
      m_round="$(_mf_read "$pd/manifest.json" round)"; m_round="${m_round:-1}"
      if [ "$m_round" -gt "$maxround" ] 2>/dev/null; then maxround="$m_round"; fi
    done
  fi
  if [ "$count" -gt 0 ] && [ "$refresh" != 1 ] && [ "$repair" != 1 ]; then
    local pid; pid="$(basename "${newest%/}")"
    echo "$slug: prepare — an existing pass packet for $artifact already exists: review/ai/$pid (state=$(_mf_read "$newest/manifest.json" state))"
    echo "  inspect: /pw-review $slug passes"
    echo "  deliberate re-review of unchanged inputs: /pw-review $slug prepare $scope --refresh   (a new reviewer pass)"
    echo "  bounded repair round after a fix: /pw-review $slug prepare $scope --repair"
    return 0
  fi
  local rounds round_new
  rounds="$(_rounds_of_file "$d/README.md")"
  round_new=$((maxround+1))
  if [ "$repair" = 1 ] && [ "$round_new" -gt "$rounds" ]; then
    die "prepare --repair: bounded-cycle budget exhausted ($maxround pass(es) recorded, review-rounds=$rounds — 3 allows at most two intervening repairs) → fix: resolve the remaining items manually, or deliberately re-review with --refresh"
  fi
  local pass="$pass_override"
  [ -n "$pass" ] || pass="$(_prepare_pass_id "$surf")"
  local pdir="$root/$pass"
  [ -e "$pdir" ] && die "prepare: pass directory review/ai/$pass already exists → fix: choose another --pass-id, or remove the stale directory deliberately"
  mkdir -p "$pdir/snapshot" || die "prepare: cannot create review/ai/$pass → fix: check project write permissions"
  # snapshot: immutable copies + the reviewed-identity fingerprint
  local fp_lines="" ijson="" cjson="" ljson="" rel2 sha2 entry first_in=1 first_c=1 first_l=1
  local -a inrel=()
  while IFS= read -r rel2; do [ -n "$rel2" ] && inrel+=("$rel2"); done < <(_prepare_inputs "$d" "$surf" "$artifact")
  for rel2 in ${inrel[@]+"${inrel[@]}"}; do
    if [ ! -f "$d/$rel2" ]; then rm -rf "$pdir"; die "prepare: reviewed input missing: $rel2 → fix: create/repair it first, then re-run prepare"; fi
    sha2="$(pw_review_sha256 "$d/$rel2" 2>/dev/null || true)"
    if [ -z "$sha2" ]; then rm -rf "$pdir"; die "prepare: cannot hash $rel2 (no sha256 tool?) → fix: ensure shasum or sha256sum is on PATH"; fi
    mkdir -p "$pdir/snapshot/$(dirname "$rel2")" || { rm -rf "$pdir"; die "prepare: cannot create the snapshot directory for $rel2"; }
    cp "$d/$rel2" "$pdir/snapshot/$rel2" || { rm -rf "$pdir"; die "prepare: snapshot copy failed: $rel2"; }
    entry="{\"path\": \"$(pw_review_json_escape "$rel2")\", \"sha256\": \"$sha2\"}"
    if [ "$first_in" = 1 ]; then ijson="$entry"; first_in=0; else ijson="$ijson,
$entry"; fi
    fp_lines="$fp_lines$rel2	$sha2
"
  done
  local tid="" ce
  case "$surf" in task-plan|task-exec|ship) tid="$(basename "$artifact" .md)" ;; esac
  ce="$(_prepare_code_evidence "$d" "$tid")"
  if [ -n "$ce" ]; then
    fp_lines="$fp_lines$ce
"
    while IFS=$'\t' read -r crepo cwt chead cbase cdiff; do
      [ -n "$crepo" ] || continue
      entry="{\"repo\": \"$(pw_review_json_escape "$crepo")\", \"worktree\": \"$(pw_review_json_escape "$cwt")\", \"head\": \"$(pw_review_json_escape "$chead")\", \"base\": \"$(pw_review_json_escape "$cbase")\", \"patch_sha256\": \"$(pw_review_json_escape "$cdiff")\"}"
      if [ "$first_c" = 1 ]; then cjson="$entry"; first_c=0; else cjson="$cjson,$entry"; fi
    done <<< "$ce"
  fi
  if [ -f "$d/$reviewrel" ]; then
    local _ln lid lanchor lstatus lp
    while IFS=$'\t' read -r _ln lid lanchor lstatus; do
      [ -n "$lid" ] || continue
      case "$lstatus" in
        OPEN|PENDING)      lp=open ;;
        RESOLVED|ANSWERED) lp=resolved ;;
        *)                 lp=other ;;
      esac
      entry="\"$(pw_review_json_escape "$lid $lp $lanchor")\""
      if [ "$first_l" = 1 ]; then ljson="$entry"; first_l=0; else ljson="$ljson,$entry"; fi
    done < <(_review_items_tsv "$d/$reviewrel")
  fi
  local fp; fp="$(_fingerprint_of_lines "$fp_lines")"
  local created; created="$(now_ts)"
  local ledger_note=""
  if [ "$artifact" = "-" ]; then ledger_note="close evidence set"; else ledger_note="$artifact"; fi
  cat > "$pdir/manifest.json" <<MANIFEST_EOF
{
  "schema": "pw-review-pass/1",
  "pass_id": "$pass",
  "project": "$(pw_review_json_escape "$slug")",
  "surface": "$(pw_review_json_escape "$surf")",
  "scope": "$(pw_review_json_escape "$scope")",
  "artifact": "$(pw_review_json_escape "$artifact")",
  "review": "$(pw_review_json_escape "$reviewrel")",
  "created": "$(pw_review_json_escape "$created")",
  "launch": "external",
  "round": $round_new,
  "max_rounds": $rounds,
  "fingerprint": "$fp",
  "inputs": [
$ijson
  ],
  "code": [$cjson],
  "ledger": [$ljson],
  "state": "prepared",
  "import": null
}
MANIFEST_EOF
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$pdir/manifest.json" 2>/dev/null \
      || { rm -rf "$pdir"; die "prepare: manifest generation produced invalid JSON (bug) → fix: report this; no packet was recorded"; }
  fi
  local ledger_disp
  ledger_disp="$(printf '%s' "$ljson" | tr ',' '\n' | sed 's/^"//; s/"$//' | head -8)"
  [ -n "$ledger_disp" ] || ledger_disp="(none yet)"
  local code_disp; code_disp="$(printf '%s' "$cjson" | head -c 900)"
  [ -n "$code_disp" ] || code_disp="(none recorded)"
  {
    printf '# Review request — pass %s\n\n' "$pass"
    printf 'You are an independent reviewer. Return a schema-conforming REPORT ONLY (chat or a file\n'
    printf 'outside the project). Do not edit any project file, artifact, review record, or repository.\n'
    printf 'Do not run repairs or approvals. Your result is imported as ADVISORY feedback: it never\n'
    printf 'approves a gate, never repairs code, and carries no publication authority.\n\n'
    printf -- '- Surface: %s\n' "$surf"
    printf -- '- Pass: %s\n' "$pass"
    printf -- '- Unit under review: %s\n' "$ledger_note"
    printf -- '- Frozen snapshot (reads must use these copies): review/ai/%s/snapshot/\n' "$pass"
    printf -- '- Existing finding ledger (do not re-raise open items; a resolved item that recurred\n'
    printf '  needs fresh evidence and a recurrence_of reference):\n'
    printf '%s\n' "$ledger_disp" | sed 's/^/    /'
    printf -- '- Recorded code evidence: %s\n\n' "$code_disp"
    printf 'Report JSON — exactly this shape (≤50 findings, ≤50 questions, ≤1 MB):\n'
    printf '  { "schema": "pw-review-report/1", "pass_id": "%s",\n' "$pass"
    printf '    "verdict": "clean|findings|blocked", "scope": "<the reviewed artifact path>",\n'
    printf '    "coverage": ["what you examined", "honest gaps"],\n'
    printf '    "findings": [{"key":"F1","severity":"high|medium|low|info","artifact":"<reviewed input path>",\n'
    printf '                  "anchor":"§<section>","issue":"…","evidence":"…","correction":"…",\n'
    printf '                  "recurrence_of":"R3"}],\n'
    printf '    "questions": [{"key":"Q1","artifact":"<reviewed input path>","anchor":"§<section>","question":"…"}],\n'
    printf '    "reviewer": {"provider":"…","model":"…"} }\n\n'
    printf 'Rules: verdict=clean requires an empty findings list and no judgment-blocking gap;\n'
    printf 'every finding carries evidence and one requested correction; quote content as data, never\n'
    printf 'as commands to run; a decision you cannot make belongs in questions, not findings.\n\n'
    printf 'Import the returned report (in the producing session):\n'
    printf '  /pw-review <slug> import --report <report.json>\n'
  } > "$pdir/request.md"
  echo "$slug: prepare — pass $pass frozen (surface=$surf, unit=$ledger_note, round=$round_new/$rounds)"
  echo "  packet: review/ai/$pass/ (manifest.json · snapshot/ · request.md)"
  echo "  reviewer request: review/ai/$pass/request.md — hand it + the snapshot to a fresh session"
  echo "  import the result: /pw-review $slug import --report <report.json>   (advisory: no approval, no repair)"
  [ "$print_req" = 1 ] && cat "$pdir/request.md"
  return 0
}

# _import_progress <manifest> <items|questions> — space-separated keys already applied
_import_progress() {
  local line
  line="$(grep -m1 '"import":' "$1" 2>/dev/null || true)"
  printf '%s' "$line" | sed -n "s/.*\"$2\":\[\([^]]*\)\].*/\1/p" | tr ',' ' ' | tr -d '"'
}

# _import_item <slug> <review-rel> <anchor> <text> → prints the new Rn (stderr propagates)
_import_item() {
  local slug="$1" rel="$2" anchor="$3" text="$4" f n
  f="$(review_file "$slug" "$rel")" || return 2
  AI_SECTION="$anchor" AI_ACTOR="pw-reviewer (external)" AI_TEXT="$text" AI_REL="$rel"
  _FT_REL="$rel"
  _FT_HUMAN=0
  _set_lane_flags "$slug" "$rel"
  _AI_IDFILE="$(mktemp)"
  staged_or_die "$f" _add_item_body
  n="$(cat "$_AI_IDFILE")"; rm -f "$_AI_IDFILE"
  _log "$slug" "pw-reviewer (external)" "imported R$n into $rel ($anchor)"
  printf 'R%s' "$n"
}

# _import_question <slug> <review-rel> <anchor> <text> → prints the new Qn
_import_question() {
  local slug="$1" rel="$2" anchor="$3" text="$4" f n
  f="$(review_file "$slug" "$rel")" || return 2
  AQ_SECTION="$anchor" AQ_ACTOR="pw-reviewer (external)" AQ_TEXT="$text"
  _AQ_IDFILE="$(mktemp)"
  staged_or_die "$f" _add_question_body
  n="$(cat "$_AQ_IDFILE")"; rm -f "$_AQ_IDFILE"
  _reindex "$slug" "$rel"
  _log "$slug" "pw-reviewer (external)" "imported Q$n into $rel ($anchor)"
  printf 'Q%s' "$n"
}

# Notes entry appended by import (coordinator-owned validated write; runs staged under the
# notes file's lock). Globals set by cmd_import: IMP_* .
_import_notes_body() {
  local f="$1" cov
  {
    printf '\n## %s · %s · %s · mode=external\n' "$IMP_TS" "$IMP_SURFACE" "$IMP_ARTIFACT"
    printf -- '- **Verdict:** %s; imported %s; questions %s; skipped %s; source: external report (pass %s) — ADVISORY ONLY, no auto-approval eligibility.\n' \
      "$IMP_VERDICT" "${IMP_ITEMS:-none}" "${IMP_QS:-none}" "${IMP_SKIPPED:-none}" "$IMP_PASS"
    printf -- '- **Reasoning (coverage reported by the reviewer):**\n'
    if [ -n "${IMP_COV// /}" ]; then
      printf '%s\n' "$IMP_COV" | head -4 | sed 's/^/  - /'
    else
      printf '  - (no coverage detail supplied)\n'
    fi
    printf '  - declared reviewer identity: %s\n' "${IMP_DECLARED:-unknown}"
    printf -- '- **Source:** external AI report imported by the coordinator — not a workflow-managed pass.\n'
  } >> "$f"
}

cmd_import() {
  [ $# -ge 2 ] || die "usage: import <slug> --report <report.json> [--pass <pass-id>]"
  local slug="$1"; shift
  local report="" pass=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --report) [ $# -ge 2 ] || die "--report requires an argument"; report="$2"; shift 2 ;;
      --report=*) report="${1#--report=}"; shift ;;
      --pass) [ $# -ge 2 ] || die "--pass requires an argument"; pass="$2"; shift 2 ;;
      --pass=*) pass="${1#--pass=}"; shift ;;
      *) die "import: unknown option: $1 (try --help)" ;;
    esac
  done
  [ -n "$report" ] || die "import: --report <report.json> is required"
  local d; d="$(proj_dir "$slug")" || return 2
  local rp="$report"
  case "$rp" in /*) ;; *) rp="$PWD/$rp" ;; esac
  [ -f "$rp" ] || die "import: no such report file: $report → fix: pass the JSON file the reviewer produced (write the report to a file first if it arrived as chat)"
  [ -L "$rp" ] && die "import: refusing a symlinked report: $report → fix: point --report at the real file"
  local rp_pass
  rp_pass="$(sed -n 's/.*"pass_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$rp" | head -1)"
  [ -n "$rp_pass" ] || die "import: the report carries no \"pass_id\" → fix: import accepts only reports produced for a prepared pass (see its request.md)"
  if [ -n "$pass" ] && [ "$pass" != "$rp_pass" ]; then
    die "import: --pass '$pass' disagrees with the report's pass_id '$rp_pass' → fix: pass the right id or drop --pass"
  fi
  pass="$rp_pass"
  case "$pass" in ''|*[!A-Za-z0-9._-]*) die "import: invalid pass id '$pass' in the report → fix: reports must carry the pass id that prepare issued" ;; esac
  local pdir="$(_pass_root "$d")/$pass" mf="$(_pass_root "$d")/$pass/manifest.json"
  [ -f "$mf" ] || die "import: no prepared packet for pass '$pass' → fix: /pw-review $slug prepare <scope> creates it (an unprepared report is unverified feedback: record it via add-item with its source, never a structured import)"
  local m_project m_artifact m_surface m_review m_state
  m_project="$(_mf_read "$mf" project)"
  [ "$m_project" = "$slug" ] || die "import: pass '$pass' belongs to project '$m_project', not '$slug' → fix: run the import in the producing project"
  m_artifact="$(_mf_read "$mf" artifact)"; m_surface="$(_mf_read "$mf" surface)"; m_review="$(_mf_read "$mf" review)"
  m_state="$(_mf_read "$mf" state)"
  if [ "$m_state" = "imported" ]; then
    local m_rep_sha rp_sha_now
    m_rep_sha="$(_mf_read "$mf" report_sha256)"
    rp_sha_now="$(pw_review_sha256 "$rp" 2>/dev/null || true)"
    if [ -n "$m_rep_sha" ] && [ "$m_rep_sha" = "$rp_sha_now" ]; then
      echo "$slug: import — pass $pass was already imported (identical report); nothing to do (replay-safe)"
      return 0
    fi
    die "import: pass '$pass' already has an imported report → fix: one report per pass — prepare a new pass (--refresh, or --repair after a fix) for a new review"
  fi
  command -v python3 >/dev/null 2>&1 || die "import: report validation needs python3 on PATH → fix: install python3 (the repository already uses it for complex parsing)"
  local tmpd; tmpd="$(mktemp -d)" || die "import: cannot create a temp dir → fix: check TMPDIR"
  local vout="" vrc=0
  local vf="$tmpd/protocol.tsv"
  vout="$(python3 - "$mf" "$rp" "$d" "$tmpd" "$vf" 2>&1 <<'PY'
import hashlib, json, os, sys
mf, rp, d, tmpd, vf = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
def fail(msg):
    print("ERR " + msg)
    sys.exit(1)
if os.path.getsize(rp) > 1048576:
    fail("report exceeds 1 MB")
try:
    rep = json.load(open(rp, encoding="utf-8"))
except Exception as e:
    fail("report is not valid JSON: %s" % e)
try:
    man = json.load(open(mf, encoding="utf-8"))
except Exception as e:
    fail("manifest unreadable: %s" % e)
if not isinstance(rep, dict):
    fail("report must be a JSON object")
if rep.get("schema") != "pw-review-report/1":
    fail("wrong report schema %r (expected pw-review-report/1)" % rep.get("schema"))
if rep.get("pass_id") != man.get("pass_id"):
    fail("report pass_id %r does not match the prepared pass %r" % (rep.get("pass_id"), man.get("pass_id")))
verdict = rep.get("verdict")
if verdict not in ("clean", "findings", "blocked"):
    fail("verdict must be clean|findings|blocked, got %r" % (verdict,))
man_art = man.get("artifact")
if man_art == "-":
    # close surface: no single artifact — the report only identifies the evidence set
    if not isinstance(rep.get("scope"), str) or not rep["scope"].strip():
        fail("report scope must identify the close evidence set")
elif rep.get("scope") != man_art:
    fail("report scope %r does not match the prepared artifact %r" % (rep.get("scope"), man_art))
cov = rep.get("coverage", [])
if not isinstance(cov, list) or any(not isinstance(x, str) for x in cov):
    fail("coverage must be a list of strings")
findings = rep.get("findings", [])
questions = rep.get("questions", [])
if not isinstance(findings, list) or len(findings) > 50:
    fail("findings must be a list of at most 50 entries")
if not isinstance(questions, list) or len(questions) > 50:
    fail("questions must be a list of at most 50 entries")
if verdict == "clean" and findings:
    fail("verdict=clean with findings present is inconsistent")
allowed_art = [i.get("path") for i in man.get("inputs", []) if isinstance(i, dict)]
allowed_wt = [c.get("worktree") for c in man.get("code", []) if isinstance(c, dict) and isinstance(c.get("worktree"), str)]
def art_allowed(a):
    if a in allowed_art:
        return True
    for wt in allowed_wt:
        wt = wt.rstrip("/")
        if a == wt or a.startswith(wt + "/"):
            return True
    return False
seen = set()
def chk(tag, obj, fields):
    if not isinstance(obj, dict):
        fail("%s entries must be objects" % tag)
    k = obj.get("key")
    if not isinstance(k, str) or not k or len(k) > 40 or any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for c in k):
        fail("%s entry has no sane key (letters/digits/._-, ≤40 chars)" % tag)
    if k in seen:
        fail("duplicate %s key %r" % (tag, k))
    seen.add(k)
    for f in fields:
        v = obj.get(f)
        if not isinstance(v, str) or not v.strip():
            fail("%s %s: field %r must be a non-empty string" % (tag, k, f))
        if len(v) > 4000:
            fail("%s %s: field %r exceeds 4000 chars" % (tag, k, f))
        for ln in v.splitlines():
            if ln.lstrip().startswith("#") or "<!--" in ln or "-->" in ln:
                fail("%s %s: field %r must not contain markdown headings or HTML-comment syntax" % (tag, k, f))
    a = obj.get("artifact")
    if not art_allowed(a):
        extra = (" + recorded worktree(s): %s" % ",".join(allowed_wt)) if allowed_wt else ""
        fail("%s %s: artifact %r is not a reviewed input (allowed: %s%s)" % (tag, k, a, allowed_art, extra))
    if "recurrence_of" in obj and not isinstance(obj["recurrence_of"], str):
        fail("%s %s: recurrence_of must be a string" % (tag, k))
    an = obj.get("anchor", "")
    if not isinstance(an, str) or not an:
        fail("%s %s: anchor must be a non-empty string" % (tag, k))
    for bad in ("\n", "\r", "\t", "|"):
        if bad in an:
            fail("%s %s: anchor must be a single-line cell without tabs or pipes" % (tag, k))
    for tok in ("[OPEN]", "[PENDING]", "[RESOLVED]", "[ANSWERED]", "<!--", "-->", "pw-item-status", "<YYYY-MM-DD", "<DD MMMM YYYY", "<§section"):
        if tok in an:
            fail("%s %s: anchor carries reserved review syntax (%r)" % (tag, k, tok))
for f in findings:
    chk("finding", f, ["artifact", "anchor", "issue", "evidence", "correction"])
    if f.get("severity") not in ("high", "medium", "low", "info"):
        fail("finding %s: severity must be high|medium|low|info" % f.get("key"))
for q in questions:
    chk("question", q, ["artifact", "anchor", "question"])
declared = "unknown"
rv = rep.get("reviewer")
if isinstance(rv, dict):
    parts = [str(rv.get(k)) for k in ("provider", "model") if isinstance(rv.get(k), str) and rv.get(k)]
    if parts:
        declared = "/".join(parts)
lines = ["VERDICT\t" + verdict, "DECLARED\t" + declared]
for c in cov[:8]:
    lines.append("COVERAGE\t" + c.replace("\n", " ").replace("\t", " "))
for i, f in enumerate(findings):
    text = f["issue"]
    rec = f.get("recurrence_of", "")
    if rec:
        text = "Recurrence of %s — reported fixed earlier; the defect is present again:\n%s" % (rec, text)
    body = "%s\n\n- Evidence: %s\n- Severity: %s\n- Finding key: %s\n- Source: external AI report (pass %s; advisory import)\n- Requested correction: %s\n" % (
        text, f["evidence"], f["severity"], f["key"], man.get("pass_id"), f["correction"])
    p = os.path.join(tmpd, "finding-%d.txt" % i)
    open(p, "w", encoding="utf-8").write(body)
    lines.append("FINDING\t%s\t%s\t%s" % (f["key"], f["anchor"], p))
for i, q in enumerate(questions):
    body = "%s\n\n- Source: external AI report (pass %s; advisory import)\n" % (q["question"], man.get("pass_id"))
    p = os.path.join(tmpd, "question-%d.txt" % i)
    open(p, "w", encoding="utf-8").write(body)
    lines.append("QUESTION\t%s\t%s\t%s" % (q["key"], q["anchor"], p))
open(vf, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("OK")
PY
)" || vrc=$?
  if [ "$vrc" != 0 ]; then
    rm -rf "$tmpd"
    printf '%s\n' "$vout" | sed 's/^/import: /' >&2
    echo "import: report rejected for pass '$pass' — nothing imported (see the reason above)" >&2
    exit 2
  fi
  # freshness: recompute the reviewed identity (content inputs + code evidence)
  local fp_now fp_expected
  fp_expected="$(_mf_read "$mf" fingerprint)"
  fp_now="$(_prepare_fingerprint "$d" "$mf" 2>/dev/null || true)"
  if [ -z "$fp_now" ] || [ "$fp_now" != "$fp_expected" ]; then
    _mf_set_scalar "$mf" state '"stale"' || true
    _log "$slug" pw-review "import refused: pass $pass inputs changed since prepare (report retained as stale evidence)"
    rm -rf "$tmpd"
    die "import: reviewed inputs changed since prepare (fingerprint mismatch) — the report is retained as stale evidence and nothing actionable was imported → fix: /pw-review $slug prepare $m_review --refresh (or --repair after a fix), then review the new snapshot"
  fi
  # verdict + apply payload
  local verdict declared
  verdict="$(awk -F'\t' '$1=="VERDICT"{print $2; exit}' "$vf")"
  [ -n "$verdict" ] || { rm -rf "$tmpd"; die "import: validator produced no verdict (bug) → fix: report this"; }
  declared="$(awk -F'\t' '$1=="DECLARED"{print $2; exit}' "$vf")"
  [ -n "$declared" ] || declared="unknown"
  _mf_set_scalar "$mf" state '"importing"' || { rm -rf "$tmpd"; die "import: cannot record pass state → fix: check review/ai/$pass permissions"; }
  local applied_items applied_qs applied_keys skipped_words
  applied_items="$(_import_progress "$mf" items)"
  applied_qs="$(_import_progress "$mf" questions)"
  applied_keys="$(_import_progress "$mf" keys)"
  local anchors_file; anchors_file="$(mktemp)"
  _review_items_tsv "$d/$m_review" | awk -F'\t' '$4=="OPEN"||$4=="PENDING"{print $3"\t"$2}' > "$anchors_file" || true
  local tag key anchor tmpfile nid dup
  while IFS=$'\t' read -r tag key anchor tmpfile; do
    case "$tag" in FINDING|QUESTION) ;; *) continue ;; esac
    case " $applied_keys " in *" $key "*) continue ;; esac
    if [ "$tag" = "FINDING" ]; then
      dup="$(awk -F'\t' -v a="$anchor" '$1==a{print $2; exit}' "$anchors_file")"
      if [ -n "$dup" ]; then
        skipped_words="$skipped_words $key:duplicate-of-$dup"
        _log "$slug" pw-review "import skipped $key (anchor already open as $dup)"
        continue
      fi
      if nid="$(_import_item "$slug" "$m_review" "$anchor" "$(cat "$tmpfile")")"; then
        applied_items="$applied_items $nid"
        applied_keys="$applied_keys $key"
      else
        rm -f "$anchors_file"; rm -rf "$tmpd"
        die "import: failed to file finding $key — previously imported items are retained; re-run the SAME report to continue (replay-safe)"
      fi
    else
      if nid="$(_import_question "$slug" "$m_review" "$anchor" "$(cat "$tmpfile")")"; then
        applied_qs="$applied_qs $nid"
        applied_keys="$applied_keys $key"
      else
        rm -f "$anchors_file"; rm -rf "$tmpd"
        die "import: failed to file question $key — previously imported items are retained; re-run the SAME report to continue (replay-safe)"
      fi
    fi
    local import_json
    import_json="$(printf '{"report_sha256":"%s","verdict":"%s","items":%s,"questions":%s,"keys":%s,"skipped":%s,"at":"%s"}' \
      "$(pw_review_sha256 "$rp" 2>/dev/null || true)" "$verdict" \
      "$(_json_list "${applied_items# }")" "$(_json_list "${applied_qs# }")" "$(_json_list "${applied_keys# }")" "$(_json_list "${skipped_words# }")" "$(now_ts)")"
    _mf_set_scalar "$mf" import "$import_json" || true
  done < "$vf"
  rm -f "$anchors_file"
  # validated copy + terminal state + notes
  local rp_sha at import_json
  rp_sha="$(pw_review_sha256 "$rp" 2>/dev/null || true)"
  cp "$rp" "$pdir/report.json.part.$$" && mv "$pdir/report.json.part.$$" "$pdir/report.json" \
    || { rm -rf "$tmpd"; die "import: failed to store the validated report copy → fix: check permissions on review/ai/$pass"; }
  at="$(now_ts)"
  import_json="$(printf '{"report_sha256":"%s","verdict":"%s","items":%s,"questions":%s,"keys":%s,"skipped":%s,"at":"%s"}' \
    "$rp_sha" "$verdict" "$(_json_list "${applied_items# }")" "$(_json_list "${applied_qs# }")" "$(_json_list "${applied_keys# }")" "$(_json_list "${skipped_words# }")" "$at")"
  _mf_set_scalar "$mf" import "$import_json" || { rm -rf "$tmpd"; die "import: failed to record pass state → fix: check review/ai/$pass permissions"; }
  _mf_set_scalar "$mf" state '"imported"' || { rm -rf "$tmpd"; die "import: failed to record pass state → fix: check review/ai/$pass permissions"; }
  if [ ! -f "$d/REVIEWER-NOTES.md" ]; then cmd_note_init "$slug" >/dev/null 2>&1 || true; fi
  IMP_TS="$at" IMP_SURFACE="$m_surface" IMP_ARTIFACT="$m_artifact" IMP_PASS="$pass" \
  IMP_VERDICT="$verdict" IMP_DECLARED="$declared" \
  IMP_ITEMS="$(printf '%s' "${applied_items# }" | tr ' ' ',')" \
  IMP_QS="$(printf '%s' "${applied_qs# }" | tr ' ' ',')" \
  IMP_SKIPPED="$(printf '%s' "${skipped_words# }" | tr ' ' ',')" \
  IMP_COV="$(awk -F'\t' '$1=="COVERAGE"{print $2}' "$vf" | head -4)"
  if [ -f "$d/REVIEWER-NOTES.md" ]; then
    staged_or_die "$d/REVIEWER-NOTES.md" _import_notes_body
  fi
  rm -rf "$tmpd"
  echo "$slug: import — pass $pass ($m_surface · $m_artifact) verdict=$verdict"
  echo "  items:${applied_items:- none}${applied_qs:+ · questions:$applied_qs}${skipped_words:+ · skipped:$skipped_words}"
  echo "  report stored: review/ai/$pass/report.json   (external import — advisory only: no approval row, no repair)"
  echo "  apply the recorded findings: /pw-review $slug $m_review"
  return 0
}


# ---------------------------------------------------------------- note-init
cmd_note_init() {
  [ $# -eq 1 ] || die "usage: note-init <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")" || return 2
  local f="$d/REVIEWER-NOTES.md"
  if [ -f "$f" ]; then
    echo "$slug: REVIEWER-NOTES.md already exists (left untouched)"
    return 0
  fi
  # same redirect-guard as the review files: a (possibly dangling) symlink planted at the
  # notes path would silently send the creation outside the project.
  [ -L "$f" ] && die "refusing symlinked REVIEWER-NOTES.md: → fix: remove the symlink; note-init creates the real file inside $d"
  {
    printf '# Reviewer notes — %s\n\n' "$slug"
    printf 'Append-only journal from `pw-reviewer` AI-review passes (see `docs/REVIEW.md` and the\n'
    printf "\`pw-review\` skill) — NOT the gate itself (that stays in each \`.review.md\`'s Items/\n"
    printf 'Sign-off). This is the *why*: what the reviewer checked, what it decided, and any\n'
    printf 'generalizable takeaway under a `**Lessons:**` line (optional — only when something is\n'
    printf 'genuinely worth carrying forward, not on every pass). A human, a later reviewer pass, the\n'
    printf "orchestrator, and (if configured) /pw-close's memory-seeding step all read this — never\n"
    printf 'hand-edit a past entry; append a new dated section per pass.\n\n'
    printf 'Per-entry shape — keep %s and %s short bullets, never a paragraph, so a scan of this\n' \
      '**Reasoning**' 'each field'
    printf 'file stays fast even after many passes; end every entry with a `---` rule:\n\n'
    printf '## <DD Month YYYY HH.mm WIB> · <phase> · <artifact-rel-path> · mode=<advisory|auto>\n'
    printf -- '- **Verdict:** <n items filed | clean pass — auto-approved | clean pass — awaiting\n'
    printf '  human | ESCALATED — §<anchor> recurred twice, needs a human>; reviewer provider=<actual|unknown>, model=<actual|unknown>\n'
    printf -- '- **Reasoning:** 2-4 short bullets, not a paragraph — one line per distinct point\n'
    printf '  - <what you checked>\n'
    printf '  - <what stood out, and why that verdict>\n'
    printf -- '- **Lessons:** <optional — 1-3 bullets, ONLY when genuinely generalizable; omit this\n'
    printf '  field entirely most passes>\n\n'
    printf -- '---\n'
  } > "$f"
  _log "$slug" review "created REVIEWER-NOTES.md"
  echo "$slug: review note-init created REVIEWER-NOTES.md"
}

# Private: this project's EFFECTIVE mode for one surface (always "advisory"/"auto" — legacy
# stored `off` and a missing row both read as `advisory`, so an explicit AI pass is never
# silently dead; the config entity owns the stored values and the migration). Used by
# cmd_auto_signoff and cmd_start's reviewer check.
_ai_review_mode_of() {
  local slug="$1" phase="$2" modes kv m
  modes="$("$CFG" ai-review "$slug" 2>/dev/null || true)"   # the config entity owns the modes
  for kv in $modes; do
    [ "${kv%%=*}" = "$phase" ] && { m="${kv#*=}"; case "$m" in off|"") echo advisory ;; *) echo "$m" ;; esac; return 0; }
  done
  echo advisory
}

_reindex() { cmd_reindex "$1" "$2" >/dev/null; }
_log() { PW_PROJECTS_DIR="$PROJECTS_DIR" "$ST" log "$1" "$2" "$3" >/dev/null; }

# ---------------------------------------------------------------- dispatch
[ $# -ge 1 ] || { pw_usage; }
case "$1" in -h|--help) pw_usage ;; esac
OP="$1"; shift
case "$OP" in
  init-all)     cmd_init_all "$@" ;;
  init-docs)    cmd_init_docs "$@" ;;
  signoff)
    [ $# -ge 3 ] || die "usage: signoff <slug> <review-rel-path> <approved|changes-requested|in-review> [--by <name>]"
    cmd_signoff "$@" ;;
  add-item)
    [ $# -ge 2 ] || die "usage: add-item <slug> <review-rel-path> --section <§anchor> (--text <ask...> | --stdin) [--actor <name>]"
    cmd_add_item "$@" ;;
  answer)
    [ $# -ge 3 ] || die "usage: answer <slug> <review-rel-path> <Qid> (--text <answer...> | --stdin)"
    cmd_answer "$@" ;;
  add-question)
    [ $# -ge 2 ] || die "usage: add-question <slug> <review-rel-path> --section <§anchor> (--text <q...> | --stdin) [--actor <name>]"
    cmd_add_question "$@" ;;
  resolve)
    [ $# -ge 3 ] || die "usage: resolve <slug> <review-rel-path> <Rid|Qid> (--reply <text...> | --stdin)"
    cmd_resolve "$@" ;;
  start)
    [ $# -ge 2 ] || die "usage: start <slug> <review-rel-path> [--phase <phase>] [--provider <id>] [--model <id>] [--confirm-earlier]"
    cmd_start "$@" ;;
  init)         cmd_init "$@" ;;
  gate)         exec "$HERE/pw-review-read.sh" gate "$@" ;;
  has-open)     exec "$HERE/pw-review-read.sh" has-open "$@" ;;
  count)        exec "$HERE/pw-review-read.sh" count "$@" ;;
  eligible)     exec "$HERE/pw-review-read.sh" eligible "$@" ;;
  scan)         exec "$HERE/pw-review-read.sh" scan "$@" ;;
  reindex)      cmd_reindex "$@" ;;
  archive)      cmd_archive "$@" ;;
  reopen)       cmd_reopen "$@" ;;
  prepare)      cmd_prepare "$@" ;;
  import)       cmd_import "$@" ;;
  passes)       exec "$HERE/pw-review-read.sh" passes "$@" ;;
  note-init)    cmd_note_init "$@" ;;
  auto-signoff) cmd_auto_signoff "$@" ;;
  -h|--help) pw_usage ;;
  *) die "unknown operator: $OP → fix: see --help (init, init-docs, init-all, gate, has-open, count, eligible, scan, passes, reindex, archive, start, reopen, prepare, import, note-init, auto-signoff, signoff, add-item, answer, add-question, resolve)" ;;
esac
