#!/usr/bin/env bash
# pw-lib.sh — mechanical helpers the /pw-* commands call so the load-bearing, format-sensitive
# steps (dashboard Status, One-liner, LOG.md, phase read) are deterministic instead of hand-edited
# prose. Deterministic + phase-validated so a flaky/cheap executor can't corrupt the dashboard.
#
#   pw-lib.sh status      <slug> <phase> [--rewind]   set dashboard Status: (validated, no accidental
#                                                     backward move) + auto-log the change
#   pw-lib.sh oneliner    <slug> <text...>            set the dashboard One-liner (agent, at analysis)
#   pw-lib.sh adopted     <slug> <text...>            set/insert the dashboard Adopted: pointer (/pw-adopt)
#   pw-lib.sh adopt       <slug> <repo> <branch> <base> [mr]   append/upsert one adoption unit (no clobber)
#   pw-lib.sh review-init <slug> <review-rel-path> <doc-rel-path>   create a review file from the
#                                                     template if missing (idempotent — never
#                                                     overwrites an existing one with your items)
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
#   pw-lib.sh ship comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable>
#                                <replied:yes|no> [note...]
#                                                     upsert one MR-comment thread's tracked state
#                                                     into task/review/T0n.review.md (inserted
#                                                     before ## Sign-off, never after) — the LOCAL
#                                                     authority for "already replied", since an
#                                                     unresolvable thread (a plain one-off comment,
#                                                     diff-anchored or general — see tooling/docs/forges.md)
#                                                     can never report resolved=true on the forge
#   pw-lib.sh ai-review    <slug> [<phase> <mode>]   get (no extra args) or set one phase's AI-review
#                                                     mode on the dashboard (phase: analysis|plan|
#                                                     task-plan|task-exec|ship; mode: off|advisory|auto)
#   pw-lib.sh review note-init    <slug>              create REVIEWER-NOTES.md if missing (idempotent)
#   pw-lib.sh review auto-signoff <slug> <review-rel-path> <phase>
#                                                     write a Sign-off row WITHOUT a human — refuses
#                                                     unless this project's AI Review mode for <phase>
#                                                     is genuinely "auto" AND zero 🔴/⏳ remain open;
#                                                     the ONE tool-enforced exception to "only a human
#                                                     clears a gate" — see docs/REVIEW.md
#   pw-lib.sh review gate   <slug> <review-rel-path>  print + exit-0/1 on the Sign-off table's
#                                                     CURRENT (latest) row only — never "was this
#                                                     ever approved" (a stale historical row must
#                                                     not keep satisfying a hard gate after a later
#                                                     `in-review` row supersedes it)
#   pw-lib.sh review reopen <slug> <review-rel-path>  append a fresh `in-review` Sign-off row —
#                                                     ONLY if the current row is `approved ✅`
#                                                     (idempotent no-op otherwise); never deletes the
#                                                     old approval, same append-only history rule as
#                                                     a human's own reopen. Used when a fix lands on
#                                                     an already-approved doc (e.g. an RFC comment
#                                                     folded back into the analysis) — see docs/RFC.md
#   pw-lib.sh review has-open <slug> <review-rel-path>  print yes/no + exit 0/1 on whether the file
#                                                     has any unresolved 🔴 open item or ⏳ awaiting-
#                                                     answer question (missing file → "no", exit 1 —
#                                                     not an error, just "nothing in flight"). A
#                                                     generic open-item check, unlike `review gate`
#                                                     which reads a Sign-off decision — used by
#                                                     /pw-breakdown's RFC-negotiation hard block on
#                                                     analysis/review/RFC.review.md, which has no
#                                                     Sign-off table of its own — see docs/RFC.md
#   pw-lib.sh model-check   <provider> <model-id>    pass/refuse a model against
#                                                     PW_MODEL_ALLOWLIST_<PROVIDER> in pw.config.sh
#                                                     — empty/unset = ALL models allowed (the
#                                                     default). Called by /pw-breakdown and
#                                                     /pw-execute; not meant to be run by hand.
#   pw-lib.sh selftest                                 run an isolated round-trip test
#
# Portable across Claude Code and KiloCode executors (plain bash; call by absolute path).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # …/agentic-project-workflow/tooling
PROJECTS_DIR="${PW_PROJECTS_DIR:-$(cd "$HERE/../.." && pwd)}"  # …/projects  (override for tests)
VALID_PHASES="context analysis breakdown executing review done"

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
cmd_log() {
  [ $# -ge 3 ] || die "usage: log <slug> <actor> <msg...>"
  local slug="$1" actor="$2"; shift 2
  local d; d="$(proj_dir "$slug")"
  printf -- '- **%s** · `%s` — %s\n' "$(date '+%F %H:%M')" "$actor" "$*" >> "$d/LOG.md"
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

# Ensure the context/INDEX.md provenance table has EXACTLY ONE, generic `ADOPTED.md` row —
# inserted once on first adopt, then left alone. This replaces the old free-form agent edit that
# re-enumerated every unit into that row's description and thus rewrote it on every /pw-adopt
# (the "one-liner replaced each attempt" bug). The row stays generic ("see the file"); per-unit
# detail lives in ADOPTED.md, so it never needs churning. No-ops if INDEX.md is missing.
_index_provenance_ensure() {
  local f="$1"
  [ -f "$f" ] || return 0
  grep -qE '^\|[^|]*ADOPTED\.md' "$f" && return 0     # a row already references ADOPTED.md → leave it
  local today; today="$(date +%F)"
  local row="| \`ADOPTED.md\` | Adoption record — all continuation units (one section per unit; see the file) | git state snapshot, gathered by /pw-adopt | $today | authoritative — live repo state |"
  # Insert right after the FIRST table's separator (the provenance table, above "## Repos in
  # scope"); drop that table's single empty placeholder row if present.
  awk -v row="$row" '
    /^## Repos in scope/ { stop=1 }
    {
      if (!stop && !ins && $0 ~ /^\|[-: |]+\|[[:space:]]*$/) { print; print row; ins=1; next }
      if (!stop && ins && !dropped && $0 ~ /^\|[[:space:]]*(\|[[:space:]]*)+$/) { dropped=1; next }
      print
    }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# Deterministically append/upsert ONE row per adoption unit into the context/INDEX.md
# "Repos in scope" table, keyed by a hidden `<!-- pw-adopt-scope:<repo>@<branch> -->` marker.
# Append-only per unit (new rows go at the end of that table; re-adopting the same repo@branch
# rewrites its OWN row in place) — so adopting the Nth branch can NEVER clobber the earlier rows
# (the bug free-form editing caused in INDEX.md, same class as the ADOPTED.md clobber). No-ops
# safely if INDEX.md or the section is missing — adoption never hard-fails on a weird index.
_scope_upsert() {
  local f="$1" repo="$2" branch="$3" base="$4" mr="$5"
  [ -f "$f" ] || return 0
  local key="$repo@$branch" mrtxt
  case "$mr" in
    http*://*)               mrtxt="[MR]($mr)" ;;
    ""|none|"none yet")      mrtxt="no MR yet — ⚠️ base unconfirmed" ;;
    *)                       mrtxt="MR $mr" ;;
  esac
  local marker="<!-- pw-adopt-scope:$key -->"
  local row="| \`$repo\` | \`origin/$base\` | continuation — adopted branch \`$branch\`, $mrtxt $marker |"
  if grep -Fq "$marker" "$f"; then                     # unit already has a row → rewrite it in place
    awk -v marker="$marker" -v row="$row" 'index($0,marker){print row; next} {print}' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else                                                 # new unit → append at the end of the table
    awk -v row="$row" '
      {
        if ($0 ~ /^## Repos in scope/) insec=1
        else if ($0 ~ /^## /) { if (insec && sep && !ins) { print row; ins=1 } insec=0 }
        if (insec && !sep && $0 ~ /^\|[-: |]+\|[[:space:]]*$/) { print; sep=1; next }
        if (insec && sep && !ins) {
          if ($0 ~ /^\|/) { t=$0; gsub(/[ |]/,"",t); if (t=="") next; print; next }  # drop empty placeholder
          print row; ins=1; print; next                                             # insert before first non-row line
        }
        print
      }
      END { if (insec && sep && !ins) print row }' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
}

# Deterministically append/upsert ONE adoption unit into context/ADOPTED.md, keyed by repo@branch.
# Append-only per unit (new units go at EOF; re-adopting the same repo@branch updates that unit's
# Base/MR in place) — so adopting a 2nd branch can NEVER clobber the 1st (the bug free-form editing
# caused). The agent fills each unit's prose after; the structure/IDs/count are owned here.
#   adopt <slug> <repo> <branch> <base> [mr]
cmd_adopt() {
  [ $# -ge 4 ] || die "usage: adopt <slug> <repo> <branch> <base> [mr-url]"
  local slug="$1" repo="$2" branch="$3" base="$4" mr="${5:-none yet}"
  local d; d="$(proj_dir "$slug")"; local cdir="$d/context"; local f="$cdir/ADOPTED.md"
  mkdir -p "$cdir"
  local key="$repo @ $branch"
  if [ ! -f "$f" ]; then
    {
      printf '# Adopted work — %s   (CONTINUATION workflow)\n\n' "$slug"
      printf 'Builds on existing in-progress branches. Serialization is PER-BRANCH: tasks on the same\n'
      printf 'branch run serially in its shared worktree; tasks on different branches run in parallel.\n'
      printf 'Unit headings/IDs + the Base/MR lines are managed by `pw-lib.sh adopt` — do NOT hand-edit\n'
      printf 'them or the dashboard; fill the prose under each unit. [🤖🧑 both]\n'
    } > "$f"
  fi
  # Existing unit for this exact repo@branch? (heading form: "## A<k> · <repo> @ <branch>").
  # Suffix-match on the ASCII "<repo> @ <branch>" key — avoids byte-offset math around the
  # multibyte "·" separator (that was the clobber-adjacent bug).
  local uid; uid="$(awk -v key="$key" '
    /^## A[0-9]+ · / {
      h=$0; sub(/^## /,"",h);          # "A1 · <repo> @ <branch>"
      u=h; sub(/ .*/,"",u);            # first token = unit id
      if (length(h) >= length(key) && substr(h, length(h)-length(key)+1) == key) { print u; exit }
    }' "$f")"
  if [ -n "$uid" ]; then
    # update this unit's Base/MR lines in place, leave prose untouched
    awk -v u="$uid" -v base="$base" -v mr="$mr" '
      $0 ~ ("^## " u " · ") { inU=1; print; next }
      inU && /^## A[0-9]+ · / { inU=0 }
      inU && /^- Base: / { print "- Base: " base; next }
      inU && /^- MR: /   { print "- MR: " mr;   next }
      { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    # new unit → next id, append a fresh section at EOF (collision-free)
    local n; n="$(grep -cE '^## A[0-9]+ · ' "$f" 2>/dev/null || true)"; : "${n:=0}"
    uid="A$((n+1))"
    {
      printf '\n## %s · %s @ %s\n' "$uid" "$repo" "$branch"
      printf -- '- Base: %s\n' "$base"
      printf -- '- MR: %s\n' "$mr"
      printf '### Already done\n<!-- pw-adopt %s already-done: replace with the commit list + diffstat summary -->\n' "$uid"
      printf '### Remaining work\n🧑 <!-- pw-adopt %s remaining: fill with what to change on top of this branch -->\n' "$uid"
    } >> "$f"
  fi
  # Keep context/INDEX.md in lockstep (deterministic, no clobber): a one-time generic ADOPTED.md
  # provenance row + one "Repos in scope" row per unit.
  _index_provenance_ensure "$cdir/INDEX.md"
  _scope_upsert "$cdir/INDEX.md" "$repo" "$branch" "$base" "$mr"
  local count; count="$(grep -cE '^## A[0-9]+ · ' "$f" 2>/dev/null || true)"; : "${count:=0}"
  cmd_adopted "$slug" "$count unit(s) — continuation; see context/ADOPTED.md" >/dev/null
  cmd_log "$slug" adopt "unit $uid: $repo@$branch (base $base, MR $mr)"
  echo "$slug: adopted $uid ($key) — base $base, MR $mr  [$count unit(s)]"
}

# Create a review file from the canonical template if (and only if) it doesn't exist yet —
# idempotent, so calling this on every /pw-analyze or /pw-breakdown run never clobbers a review
# already in progress (your items, replies, Sign-off history). This is the deterministic fix for
# "I had to manually copy the review template myself" and for review files silently missing the
# permanent format hints under ## Items / ## Open questions (this always copies the template
# byte-for-byte, so those hints and the worked examples are never dropped).
#   review-init <slug> <review-rel-path> <doc-rel-path>
#   e.g. review-init myproj analysis/review/topic.review.md analysis/topic.md
cmd_review_init() {
  [ $# -eq 3 ] || die "usage: review-init <slug> <review-rel-path> <doc-rel-path>"
  local slug="$1" rel="$2" docrel="$3"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  if [ -f "$f" ]; then
    echo "$slug: review already exists: $rel (left untouched)"
    return 0
  fi
  local tmpl="$HERE/../template/_REVIEW.template.md"
  [ -f "$tmpl" ] || die "template not found: $tmpl"
  local docname; docname="$(basename "$docrel")"
  mkdir -p "$(dirname "$f")"
  sed "s|<doc\\.md>|$docname|g" "$tmpl" > "$f"
  cmd_log "$slug" review "created $rel (in-review, awaiting your items)"
  echo "$slug: review-init created $rel (reviewing ../$docname)"
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

# Ensure task/review/T0n.review.md has a "## MR comment tracking" table (create the header +
# explainer if missing) — lazily added only once a thread is actually seen. Private helper for
# cmd_ship_comment_seen.
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
    printf '\n## MR comment tracking   [🤖-owned — never hand-edit; see `pw-lib.sh ship comment-seen`]\n\n'
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
# cmd_rfc_comment_seen (append-or-rewrite-in-place), applied to /pw-ship … comments instead of
# /pw-rfc comments. This is what makes a rerun able to tell "already replied to this unresolvable
# comment" from "new one, never seen" — without it, an unresolvable thread either gets silently
# skipped forever (looks perpetually "not resolved" on the forge, so a naive resolved-filter treats
# it as not-actionable) or gets re-processed/re-replied-to every single run (no forge-side flag
# ever flips to stop it recurring).
#   ship comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]
cmd_ship_comment_seen() {
  [ $# -ge 5 ] || die "usage: ship comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]"
  local slug="$1" task="$2" thread="$3" kind="$4" replied="$5"; shift 5; local note="$*"
  case "$kind" in resolvable|unresolvable) ;; *) die "kind must be 'resolvable' or 'unresolvable' (got '$kind')" ;; esac
  case "$replied" in yes|no) ;; *) die "replied must be 'yes' or 'no' (got '$replied')" ;; esac
  local d; d="$(proj_dir "$slug")"
  local f="$d/task/review/$task.review.md"
  [ -f "$f" ] || die "no review file: task/review/$task.review.md (run 'pw-lib.sh review-init $slug task/review/$task.review.md task/$task.md' first)"
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
  cmd_log "$slug" ship "comment-seen $task/$thread ($kind): replied=$replied"
  echo "$slug: ship comment-seen $task/$thread ($kind) -> replied=$replied"
}

cmd_ship() {
  case "${1:-}" in
    comment-seen) shift; cmd_ship_comment_seen "$@" ;;
    *) die "usage: ship comment-seen <slug> <task-id> <thread-id> <kind:resolvable|unresolvable> <replied:yes|no> [note...]" ;;
  esac
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

# Private: this project's mode for one phase (always "off"/"advisory"/"auto" — never empty, since
# cmd_ai_review ensures the line first). Used by cmd_review_auto_signoff's gate check.
_ai_review_mode_of() {
  local slug="$1" phase="$2" modes kv
  modes="$(cmd_ai_review "$slug")"
  for kv in $modes; do
    [ "${kv%%=*}" = "$phase" ] && { echo "${kv#*=}"; return 0; }
  done
  echo "off"
}

# Create REVIEWER-NOTES.md with its header if (and only if) it doesn't exist yet — idempotent,
# same shape as cmd_review_init/cmd_rfc_init. pw-reviewer appends its own dated section directly
# after this (free-form reasoning prose doesn't fit a CLI-args shape — same precedent as a task's
# ## Result section, which executors already fill by hand rather than through a wrapper).
#   review note-init <slug>
cmd_review_note_init() {
  [ $# -eq 1 ] || die "usage: review note-init <slug>"
  local slug="$1" d; d="$(proj_dir "$slug")"
  local f="$d/REVIEWER-NOTES.md"
  if [ -f "$f" ]; then
    echo "$slug: REVIEWER-NOTES.md already exists (left untouched)"
    return 0
  fi
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
    printf '## <YYYY-MM-DD HH:MM> · <phase> · <artifact-rel-path> · mode=<advisory|auto>\n'
    printf -- '- **Verdict:** <n items filed | clean pass — auto-approved | clean pass — awaiting\n'
    printf '  human | ESCALATED — §<anchor> recurred twice, needs a human>\n'
    printf -- '- **Reasoning:** 2-4 short bullets, not a paragraph — one line per distinct point\n'
    printf '  - <what you checked>\n'
    printf '  - <what stood out, and why that verdict>\n'
    printf -- '- **Lessons:** <optional — 1-3 bullets, ONLY when genuinely generalizable; omit this\n'
    printf '  field entirely most passes>\n\n'
    printf -- '---\n'
  } > "$f"
  cmd_log "$slug" review "created REVIEWER-NOTES.md"
  echo "$slug: review note-init created REVIEWER-NOTES.md"
}

# Private: true if <file> has a REAL unresolved item/question — a genuine "### ..." heading
# that's still open — OUTSIDE any HTML comment. This is NOT a plain whole-file grep:
# template/_REVIEW.template.md's permanent format-hint blockquotes (kept forever, by design,
# "even once items exist or the section is emptied") and its deletable WORKED EXAMPLE block both
# contain open-item syntax verbatim as demonstrations — a naive grep would treat every review file
# ever created as permanently, unfixably "open".
#
# Comment-stripping is an explicit line-by-line state machine (awk), NOT `sed '/<!--/,/-->/d'`:
# that one-liner checks the CLOSING pattern starting from the line AFTER the one that matched the
# opening pattern — never the same line (verified empirically — a real, reproducible sed gotcha,
# not a hypothetical). A same-line self-contained comment (`<!-- foo -->`, which every real
# item/question heading now carries, see below) would falsely open a multi-line range that then
# swallows everything up to the NEXT `-->` anywhere later in the file. The state machine instead:
# a line with BOTH `<!--` and `-->` is a self-contained one-liner — kept, unstripped, exactly as
# written; a line with only `<!--` opens a genuine multi-line comment (skipped along with every
# line up to and including the next line containing `-->`). template/_REVIEW.template.md's own
# WORKED EXAMPLE blocks deliberately use bracket notation (`[marker: pw-item-status open]`), not
# real `<!-- -->` syntax, for exactly this reason — HTML comments cannot nest, so a real same-line
# comment inside an already-open multi-line one would prematurely close the outer one and leak the
# rest of the worked example into "real" content. Never put real `<!-- -->` syntax inside a
# multi-line comment block in this template.
#
# Primary signal: a real heading carrying `<!-- pw-item-status: open -->` — a dedicated machine
# marker (template/_REVIEW.template.md), immune to a future reword of the human-facing 🔴/⏳ prose
# breaking this check. Fallback: the legacy emoji-text match, for a review file created before
# this marker existed — never drop real open items in an older file just because it predates the
# marker; when in doubt, this errs toward "still open," matching auto-signoff's own refuse-by-default stance.
_review_has_open_marker() {
  local f="$1" stripped
  stripped="$(awk '
    BEGIN { in_comment = 0 }
    {
      line = $0
      if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; next }
      if (line ~ /<!--/ && line ~ /-->/) { print line; next }
      if (line ~ /<!--/) { in_comment = 1; next }
      print line
    }
  ' "$f")"
  printf '%s\n' "$stripped" | grep -qE '^### .*<!-- pw-item-status: open -->' && return 0
  printf '%s\n' "$stripped" | grep -qE '^### .*(🔴 open|⏳ awaiting answer)'
}

# Line number (in the ORIGINAL file) of the ## Sign-off table's real last data row — never a
# WORKED-EXAMPLE row sitting inside the template's own trailing <!-- --> comment block. That block
# contains two lines that look exactly like real table rows ("| 2026-08-06 11:30 | you | approved
# ✅ |" and the pw-reviewer-auto variant) — a naive "last line starting with |, from ## Sign-off to
# EOF" scan (what a first cut of this helper did) picks THOSE, since they're the last such lines in
# the whole file, silently corrupting where a real row gets inserted on any RE-review cycle (a
# fresh file's very first sign-off is unaffected — it replaces the literal placeholder line by
# exact text match instead, a different code path). Fix: blank out (never delete — callers need
# original line numbers for a head/tail splice) every comment line first, reusing the same
# same-line-vs-multi-line state machine as _review_has_open_marker, THEN scan for the last `|` line
# from ## Sign-off onward. Returns 0 if the table has no real rows yet (malformed file).
_signoff_last_real_row_line() {
  local f="$1"
  awk '
    BEGIN { in_comment = 0 }
    {
      line = $0
      if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; print ""; next }
      if (line ~ /<!--/ && line ~ /-->/) { print line; next }
      if (line ~ /<!--/) { in_comment = 1; print ""; next }
      print line
    }
  ' "$f" | awk '/^## Sign-off/{s=1} s && /^\|/{n=NR} END{print n+0}'
}

# The Sign-off table's CURRENT (latest) Decision cell only — "approved ✅" / "in-review" /
# "changes-requested" — never "was this ever approved anywhere in the file's history". Empty
# output (+ non-zero exit) if the file has no real Sign-off rows at all.
_signoff_latest_decision() {
  local f="$1" lastrow
  lastrow="$(_signoff_last_real_row_line "$f")"
  [ "$lastrow" -gt 0 ] || return 1
  sed -n "${lastrow}p" "$f" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4 }'
}

# Deterministic, unambiguous replacement for prose like "look for an approved ✅ row anywhere in
# this file" — the ambiguity that let a stale historical approval keep satisfying a hard gate after
# a later `in-review`/`changes-requested` row superseded it (exactly what /pw-breakdown's analysis
# gate and /pw-execute's PLAN gate must NOT do once a doc is reopened post-approval — see
# docs/RFC.md). Prints the current decision text; exits 0 iff it's exactly "approved ✅".
#   review gate <slug> <review-rel-path>
cmd_review_gate() {
  [ $# -eq 2 ] || die "usage: review gate <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local decision; decision="$(_signoff_latest_decision "$f")" \
    || die "no Sign-off table rows found in $rel — not a valid review file"
  echo "$decision"
  [ "$decision" = "approved ✅" ]
}

# The other half of the analysis/RFC parity fix (docs/RFC.md): a fix applied to a doc AFTER its
# review file was already approved (e.g. an RFC comment folded back into the analysis post-
# approval) must invalidate that stale approval, or `review gate` above would still wrongly pass.
# Appends a fresh `in-review` row — NEVER deletes the old approval, same append-only-history rule
# as a human's own manual reopen (template's Sign-off section: "Add a new 'in-review' row, don't
# delete the old approval"). Idempotent no-op if the file isn't currently `approved ✅` (nothing
# stale to invalidate) — safe for a caller to call unconditionally before applying a fix, no extra
# branching needed. Tagged "pw-review (auto-reopen)" so it's never mistaken for a human's own
# `changes-requested` decision on a skim of the file or its git history.
#   review reopen <slug> <review-rel-path>
cmd_review_reopen() {
  [ $# -eq 2 ] || die "usage: review reopen <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local decision; decision="$(_signoff_latest_decision "$f")" \
    || die "no Sign-off table rows found in $rel — not a valid review file"
  if [ "$decision" != "approved ✅" ]; then
    echo "$slug: $rel already open (current: $decision) — nothing to reopen"
    return 0
  fi
  local lastrow; lastrow="$(_signoff_last_real_row_line "$f")"
  local ts row; ts="$(date '+%F %H:%M')"; row="| $ts | pw-review (auto-reopen) | in-review |"
  { head -n "$lastrow" "$f"; printf '%s\n' "$row"; tail -n "+$((lastrow+1))" "$f"; } \
    > "$f.tmp" && mv "$f.tmp" "$f"
  cmd_log "$slug" pw-review "AUTO-REOPENED $rel — a fix was applied after it was already approved ✅ (new row: in-review); re-approve once settled"
  echo "$slug: $rel reopened (was approved ✅, now in-review)"
}

# Write the Sign-off row on a review file WITHOUT a human — the ONE tool-enforced exception to
# "only a human clears a gate" (template/_REVIEW.template.md's own rule). Refuses unless BOTH:
# (1) this project's AI Review mode for <phase> is genuinely "auto" (checked here, never taken on
# the caller's word), and (2) the file has no real remaining open item/question per
# _review_has_open_marker above. The row is tagged "pw-reviewer (auto)", never blended with a
# human "you" row, so it's never mistaken for a human decision on a skim of the file or its git
# history.
#   review auto-signoff <slug> <review-rel-path> <phase>
cmd_review_auto_signoff() {
  [ $# -eq 3 ] || die "usage: review auto-signoff <slug> <review-rel-path> <phase>   (phase: $AI_REVIEW_PHASES)"
  local slug="$1" rel="$2" phase="$3"
  case " $AI_REVIEW_PHASES " in *" $phase "*) ;; *) die "invalid phase '$phase' (allowed: $AI_REVIEW_PHASES)" ;; esac
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  [ -f "$f" ] || die "no such review file: $rel"
  local mode; mode="$(_ai_review_mode_of "$slug" "$phase")"
  [ "$mode" = "auto" ] || die "refusing auto-signoff: this project's AI Review mode for '$phase' is '$mode', not 'auto' (pw-lib.sh ai-review $slug $phase auto to enable)"
  _review_has_open_marker "$f" && die "refusing auto-signoff: $rel still has an unresolved 🔴 open item or ⏳ awaiting-answer question"
  local signline; signline="$(grep -n '^## Sign-off' "$f" | head -1 | cut -d: -f1)"
  [ -n "$signline" ] || die "no '## Sign-off' section in $rel — not a valid review file"
  local ts row; ts="$(date '+%F %H:%M')"; row="| $ts | pw-reviewer (auto) | approved ✅ |"
  if grep -q '^| | | in-review |$' "$f"; then
    # first sign-off on this file → replace the template's lone placeholder row
    awk -v row="$row" '{ if ($0 == "| | | in-review |") { print row; next } print }' \
      "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    # a re-review cycle already replaced/added rows → append ours as the table's new last row
    # (head/tail splice, not awk -v — same portability reasoning as _ship_comment_section_ensure:
    # no shell-quote gymnastics, no awk variable involved). Uses the comment-stripped scanner, not
    # a raw "last | line from ## Sign-off to EOF" — the raw version picks the template's own
    # WORKED-EXAMPLE Sign-off rows (inside a trailing <!-- --> block) since they're the last such
    # lines in the whole file, corrupting a SECOND-or-later signoff. See _signoff_last_real_row_line.
    local lastrow; lastrow="$(_signoff_last_real_row_line "$f")"
    [ "$lastrow" -gt 0 ] || die "no Sign-off table rows found in $rel"
    { head -n "$lastrow" "$f"; printf '%s\n' "$row"; tail -n "+$((lastrow+1))" "$f"; } \
      > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  cmd_log "$slug" pw-reviewer "AUTO-APPROVED $rel (phase=$phase, AI Review mode=auto, zero open items) — no human sign-off"
  echo "$slug: $rel auto-signed-off by pw-reviewer (phase=$phase)"
}

# Generic open-item check — reuses _review_has_open_marker (the same detector `auto-signoff` relies
# on) but exposed standalone, since not every open-item check hangs off a Sign-off gate.
# `analysis/review/RFC.review.md` has no Sign-off table of its own (pulled comments there are
# informational staging, never individually approved as a unit) — so `review gate` doesn't apply to
# it, but /pw-breakdown still needs to know whether any pulled comment is sitting unresolved before
# letting the analysis's own approval unblock breakdown. Missing file → "no" + exit 1 (no RFC
# negotiation in flight, not an error) rather than dying — plenty of projects never touch the RFC
# side-loop at all, and that must never be treated as a failure.
#   review has-open <slug> <review-rel-path>
cmd_review_has_open() {
  [ $# -eq 2 ] || die "usage: review has-open <slug> <review-rel-path>"
  local slug="$1" rel="$2"
  local d; d="$(proj_dir "$slug")"
  local f="$d/$rel"
  if [ ! -f "$f" ]; then
    echo "no"
    return 1
  fi
  if _review_has_open_marker "$f"; then
    echo "yes"
    return 0
  fi
  echo "no"
  return 1
}

cmd_review() {
  case "${1:-}" in
    note-init)    shift; cmd_review_note_init "$@" ;;
    auto-signoff) shift; cmd_review_auto_signoff "$@" ;;
    gate)         shift; cmd_review_gate "$@" ;;
    reopen)       shift; cmd_review_reopen "$@" ;;
    has-open)     shift; cmd_review_has_open "$@" ;;
    *) die "usage: review <note-init|auto-signoff|gate|reopen|has-open> ..." ;;
  esac
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

cmd_selftest() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n  <!-- comment stays -->\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$0" status demo analysis >/dev/null
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$0" phase demo)"
  [ "$got" = "analysis" ] || die "selftest FAIL: phase='$got' (expected analysis)"
  grep -q '<!-- comment stays -->' "$tmp/demo/README.md" || die "selftest FAIL: clobbered trailing comment"
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `status` — Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing/wrong format"
  # One-liner setter
  PW_PROJECTS_DIR="$tmp" "$0" oneliner demo "toggle kafka usage safely" >/dev/null
  grep -q '^- \*\*One-liner:\*\* toggle kafka usage safely$' "$tmp/demo/README.md" || die "selftest FAIL: one-liner not set"
  # Monotonic guard: a backward move without --rewind must fail…
  if PW_PROJECTS_DIR="$tmp" "$0" status demo context >/dev/null 2>&1; then
    die "selftest FAIL: backward status move was NOT blocked"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$0" phase demo)" = "analysis" ] || die "selftest FAIL: blocked move still mutated Status"
  # …but --rewind is allowed, and executing↔review (same rank) is never treated as backward.
  PW_PROJECTS_DIR="$tmp" "$0" status demo executing >/dev/null
  PW_PROJECTS_DIR="$tmp" "$0" status demo review >/dev/null
  PW_PROJECTS_DIR="$tmp" "$0" status demo executing >/dev/null   # re-run a task: not a rewind
  [ "$(PW_PROJECTS_DIR="$tmp" "$0" phase demo)" = "executing" ] || die "selftest FAIL: executing↔review blocked"
  PW_PROJECTS_DIR="$tmp" "$0" status demo analysis --rewind >/dev/null
  [ "$(PW_PROJECTS_DIR="$tmp" "$0" phase demo)" = "analysis" ] || die "selftest FAIL: --rewind did not apply"
  PW_PROJECTS_DIR="$tmp" "$0" log demo analyze "wrote analysis/x.md" >/dev/null
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `analyze` — wrote analysis/x\.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing/wrong format"
  # Adopted pointer: inserted after One-liner when absent, then replaced in place (idempotent).
  grep -q '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" && die "selftest FAIL: Adopted line present before adopt"
  PW_PROJECTS_DIR="$tmp" "$0" adopted demo "1 unit — see context/ADOPTED.md" >/dev/null
  grep -q '^- \*\*Adopted:\*\* 1 unit — see context/ADOPTED.md$' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not inserted"
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*Adopted:\*\*' || die "selftest FAIL: Adopted not anchored after One-liner"
  PW_PROJECTS_DIR="$tmp" "$0" adopted demo "2 units — see context/ADOPTED.md" >/dev/null
  [ "$(grep -c '^- \*\*Adopted:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: Adopted duplicated instead of replaced"
  grep -q '^- \*\*Adopted:\*\* 2 units' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not updated"
  # adopt: multi-unit append MUST NOT clobber (the reported bug). Two branches, same repo.
  mkdir -p "$tmp/demo/context"
  # An INDEX.md with a provenance table (empty placeholder) AND a "Repos in scope" table (empty
  # placeholder) so we can assert both the one-time provenance row and the no-clobber scope rows.
  printf '# Context index\n\n| File / link | What it is | Source | Date added | Trust notes |\n|---|---|---|---|---|\n| | | | | |\n\n## Repos in scope\n| Repo | Base branch | Why |\n|------|-------------|-----|\n| | | |\n' \
    > "$tmp/demo/context/INDEX.md"
  local IX="$tmp/demo/context/INDEX.md"
  PW_PROJECTS_DIR="$tmp" "$0" adopt demo repoX feat-a master "http://mr/1" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$0" adopt demo repoX feat-b spring3 "http://mr/2" >/dev/null
  local A; A="$tmp/demo/context/ADOPTED.md"
  grep -q '^## A1 · repoX @ feat-a' "$A" || die "selftest FAIL: unit A1 clobbered by 2nd adopt"
  grep -q '^## A2 · repoX @ feat-b' "$A" || die "selftest FAIL: unit A2 not appended"
  [ "$(grep -c '^## A[0-9]* · ' "$A")" = "2" ] || die "selftest FAIL: expected 2 adoption units"
  grep -q '^- \*\*Adopted:\*\* 2 unit(s)' "$tmp/demo/README.md" || die "selftest FAIL: unit count not 2"
  # re-adopt A1 with a corrected base/MR → updates in place, still 2 units, prose untouched
  PW_PROJECTS_DIR="$tmp" "$0" adopt demo repoX feat-a develop "http://mr/1b" >/dev/null
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
  # review-init: creates a review file verbatim from the template (header + Reviewing: link
  # stamped, format hints intact), and is idempotent — a 2nd call never clobbers your items.
  mkdir -p "$tmp/demo/analysis"
  printf '# Analysis: demo\n' > "$tmp/demo/analysis/topic.md"
  PW_PROJECTS_DIR="$tmp" "$0" review-init demo analysis/review/topic.review.md analysis/topic.md >/dev/null
  local RV="$tmp/demo/analysis/review/topic.review.md"
  [ -f "$RV" ] || die "selftest FAIL: review-init did not create the file"
  grep -q '^# Review: topic.md$' "$RV" || die "selftest FAIL: review header not stamped"
  grep -qF 'Reviewing: [topic.md](../topic.md)' "$RV" || die "selftest FAIL: Reviewing link not stamped"
  grep -q '^> \*\*Add an item:\*\*' "$RV" || die "selftest FAIL: permanent Items format hint missing"
  grep -q '^> \*\*Answer a question:\*\*' "$RV" || die "selftest FAIL: permanent Open-questions format hint missing"
  printf '\n### R1 · your item\n' >> "$RV"                    # simulate the human adding an item
  PW_PROJECTS_DIR="$tmp" "$0" review-init demo analysis/review/topic.review.md analysis/topic.md >/dev/null
  grep -q '^### R1 · your item$' "$RV" || die "selftest FAIL: review-init clobbered an existing review file"

  # --- rfc side-loop -----------------------------------------------------
  # rfc init: creates rfc/RFC.md verbatim from the template (placeholder stamped), idempotent —
  # a 2nd call never clobbers a manual edit. Also ensures rfc/META.md, stamped with the REAL
  # backend passed in (not a hardcoded guess) — the bug a live fresh-context test caught.
  local RFC="$tmp/demo/rfc/RFC.md" META="$tmp/demo/rfc/META.md"
  PW_PROJECTS_DIR="$tmp" "$0" rfc init demo >/dev/null
  [ -f "$RFC" ] || die "selftest FAIL: rfc init did not create rfc/RFC.md"
  grep -q '^# RFC: demo$' "$RFC" || die "selftest FAIL: rfc init did not stamp the project slug"
  [ -f "$META" ] || die "selftest FAIL: rfc init did not also create rfc/META.md"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc init (no backend arg) did not default META.md's Backend to markdown"
  printf '\nmanual edit\n' >> "$RFC"                          # simulate a human/agent edit
  PW_PROJECTS_DIR="$tmp" "$0" rfc init demo >/dev/null
  grep -q '^manual edit$' "$RFC" || die "selftest FAIL: rfc init clobbered an existing RFC.md"

  # rfc init <slug> <backend>: on a FRESH project (no rfc/ yet), stamps the REAL backend into
  # META.md from the start — this is the actual regression test for the bug above.
  mkdir -p "$tmp/backend-check"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/backend-check/README.md"
  : > "$tmp/backend-check/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$0" rfc init backend-check lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$tmp/backend-check/rfc/META.md" || die "selftest FAIL: rfc init <slug> lark did not stamp the real backend"

  # rfc target: upserts Target on the ALREADY-EXISTING META.md (from rfc init above), sets Target;
  # a 2nd call with a different ref replaces in place (still exactly one Target: line) without
  # touching Backend.
  PW_PROJECTS_DIR="$tmp" "$0" rfc target demo "https://example.com/doc/1" >/dev/null
  grep -q '^- \*\*Target:\*\* https://example.com/doc/1$' "$META" || die "selftest FAIL: rfc target not set"
  PW_PROJECTS_DIR="$tmp" "$0" rfc target demo "https://example.com/doc/2" >/dev/null
  [ "$(grep -c '^- \*\*Target:\*\*' "$META")" = "1" ] || die "selftest FAIL: rfc target duplicated instead of replaced"
  grep -q '^- \*\*Target:\*\* https://example.com/doc/2$' "$META" || die "selftest FAIL: rfc target not updated"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc target touched an unrelated field"

  # rfc state: round-trips for each allowed field; an unknown field is rejected and leaves the
  # file untouched (same idiom as the backward-status-move guard above).
  PW_PROJECTS_DIR="$tmp" "$0" rfc state demo Backend lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$META" || die "selftest FAIL: rfc state Backend not set"
  PW_PROJECTS_DIR="$tmp" "$0" rfc state demo Wave1Published yes >/dev/null
  grep -q '^- \*\*Wave 1 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave1Published not set"
  PW_PROJECTS_DIR="$tmp" "$0" rfc state demo Wave2Published yes >/dev/null
  grep -q '^- \*\*Wave 2 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave2Published not set"
  PW_PROJECTS_DIR="$tmp" "$0" rfc state demo LastRevision 42 >/dev/null
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rfc state LastRevision not set"
  if PW_PROJECTS_DIR="$tmp" "$0" rfc state demo Bogus x >/dev/null 2>&1; then
    die "selftest FAIL: rfc state accepted an unknown field"
  fi
  if PW_PROJECTS_DIR="$tmp" "$0" rfc state demo CommentCursor thread-9 >/dev/null 2>&1; then
    die "selftest FAIL: rfc state still accepts the retired CommentCursor field"
  fi
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rejected rfc state call mutated the file"

  # rfc comment-seen: per-thread tracking (replaces the old single-scalar Comment cursor, which
  # couldn't tell "an earlier thread got new replies" from "already handled" once a later thread
  # became the recorded 'latest'). New thread → new row; re-seeing the SAME thread with a higher
  # reply count updates that row in place (no duplicate); flipping solved does the same.
  PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-A 1 no >/dev/null
  grep -q '^## Comment tracking' "$META" || die "selftest FAIL: comment-seen did not create the tracking section"
  grep -qF '<!-- pw-rfc-comment:thread-A -->' "$META" || die "selftest FAIL: thread-A row not created"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 1 | no ' || die "selftest FAIL: thread-A row has wrong reply-count/solved"
  PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-B 1 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: expected 2 tracked threads after thread-B"
  # thread-A gets a 2nd reply later (the exact scenario the scalar cursor got wrong) → same row,
  # updated in place, still only 2 tracked threads total (no duplicate for thread-A).
  PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-A 2 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: re-seeing thread-A duplicated a row instead of updating in place"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 2 | no ' || die "selftest FAIL: thread-A reply-count not updated"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | no ' || die "selftest FAIL: thread-B wrongly changed by thread-A's update"
  # thread-B gets resolved externally → solved flips in place, still no duplicate.
  PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-B 1 yes >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: flipping solved duplicated thread-B's row"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | yes ' || die "selftest FAIL: thread-B solved flag not updated"
  # validation: reply-count must be a non-negative integer, solved must be yes/no; a bad call is
  # rejected and doesn't touch existing rows.
  if PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-C -1 no >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a negative reply-count"
  fi
  if PW_PROJECTS_DIR="$tmp" "$0" rfc comment-seen demo thread-C 1 maybe >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a non yes/no solved value"
  fi
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: rejected comment-seen calls still mutated the tracking table"

  # ship comment-seen: same per-thread upsert shape as rfc comment-seen, but for /pw-ship …
  # comments — this is what makes an unresolvable MR comment (a plain one-off comment the forge
  # itself can never mark "resolved", diff-anchored or general — see tooling/docs/forges.md) idempotent
  # across reruns. Thread IDs below deliberately differ in their first 8 chars (the truncated
  # display prefix) so the two rows are visually distinguishable in the assertions.
  PW_PROJECTS_DIR="$tmp" "$0" review-init demo task/review/T01.review.md task/T01.md >/dev/null
  local TREV="$tmp/demo/task/review/T01.review.md"
  PW_PROJECTS_DIR="$tmp" "$0" ship comment-seen demo T01 aaaaaaaa1111 resolvable yes >/dev/null
  grep -q '^## MR comment tracking' "$TREV" || die "selftest FAIL: ship comment-seen did not create the tracking section"
  # placement: the tracking section must land BEFORE ## Sign-off, never after (a blind end-of-file
  # append was the actual bug this fixes — a real project's review files ended up with duplicate,
  # orphaned rows sitting below the human-owned Sign-off gate).
  local sec_line sign_line
  sec_line="$(grep -n '^## MR comment tracking' "$TREV" | head -1 | cut -d: -f1)"
  sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
  [ "$sec_line" -lt "$sign_line" ] || die "selftest FAIL: MR comment tracking landed at/after ## Sign-off (line $sec_line vs $sign_line)"
  grep -qF '<!-- pw-mr-comment:aaaaaaaa1111 -->' "$TREV" || die "selftest FAIL: aaaaaaaa1111 row not created"
  grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | yes ' || die "selftest FAIL: aaaaaaaa1111 row has wrong kind/replied"
  PW_PROJECTS_DIR="$tmp" "$0" ship comment-seen demo T01 bbbbbbbb2222 unresolvable yes "reviewer asked for X" >/dev/null
  [ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] || die "selftest FAIL: expected 2 tracked MR-comment threads after bbbbbbbb2222"
  grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' || die "selftest FAIL: optional note text not recorded"
  # both new-row inserts must land INSIDE the table (right after its header/separator), not at the
  # true end of the file — assert both marker lines still sit before ## Sign-off.
  local last_marker_line; last_marker_line="$(grep -n 'pw-mr-comment:' "$TREV" | tail -1 | cut -d: -f1)"
  sign_line="$(grep -n '^## Sign-off' "$TREV" | head -1 | cut -d: -f1)"
  [ "$last_marker_line" -lt "$sign_line" ] || die "selftest FAIL: a tracked row landed at/after ## Sign-off"
  # re-seeing aaaaaaaa1111 updates in place, never duplicates — and leaves bbbbbbbb2222 untouched
  PW_PROJECTS_DIR="$tmp" "$0" ship comment-seen demo T01 aaaaaaaa1111 resolvable no >/dev/null
  [ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] || die "selftest FAIL: re-seeing aaaaaaaa1111 duplicated a row instead of updating in place"
  grep 'pw-mr-comment:aaaaaaaa1111' "$TREV" | grep -q '| `aaaaaaaa` | resolvable | no ' || die "selftest FAIL: aaaaaaaa1111 replied flag not updated"
  grep 'pw-mr-comment:bbbbbbbb2222' "$TREV" | grep -q '| `bbbbbbbb` | unresolvable | yes | reviewer asked for X ' || die "selftest FAIL: bbbbbbbb2222 wrongly changed by aaaaaaaa1111's update"
  if PW_PROJECTS_DIR="$tmp" "$0" ship comment-seen demo T01 cccccccc3333 bogus-kind yes >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted an invalid kind"
  fi
  if PW_PROJECTS_DIR="$tmp" "$0" ship comment-seen demo T01 cccccccc3333 unresolvable maybe >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a non yes/no replied value"
  fi
  [ "$(grep -c 'pw-mr-comment:' "$TREV")" = "2" ] || die "selftest FAIL: rejected ship comment-seen calls still mutated the tracking table"

  # rfc dashboard: inserted after Adopted: when one exists (demo already has one from the adopt
  # tests above); inserted after One-liner when no Adopted: line exists (a fresh project); a 2nd
  # call replaces in place (still exactly one RFC: line either way).
  PW_PROJECTS_DIR="$tmp" "$0" rfc dashboard demo "wave 1 published — https://example.com/doc/2" >/dev/null
  grep -q '^- \*\*RFC:\*\* wave 1 published' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not inserted"
  grep -A1 '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after Adopted:"
  PW_PROJECTS_DIR="$tmp" "$0" rfc dashboard demo "wave 2 published" >/dev/null
  [ "$(grep -c '^- \*\*RFC:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: RFC line duplicated instead of replaced"
  grep -q '^- \*\*RFC:\*\* wave 2 published$' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not updated"

  mkdir -p "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$0" rfc dashboard demo2 "wave 1 published" >/dev/null
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo2/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after One-liner when no Adopted: exists"

  # --- AI-assisted review -------------------------------------------------
  # ai-review: get on a project with no AI Review line yet auto-creates it, all-off; set updates
  # exactly one phase, leaving the other four untouched; invalid phase/mode rejected.
  local got_ai; got_ai="$(PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=off task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review default line wrong: '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 plan auto >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review set did not update only 'plan': '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 analysis advisory >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2)"
  [ "$got_ai" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review 2nd set clobbered the 1st: '$got_ai'"
  [ "$(grep -c '^- \*\*AI Review:\*\*' "$tmp/demo2/README.md")" = "1" ] || die "selftest FAIL: AI Review line duplicated"
  if PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 bogus-phase auto >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid phase"
  fi
  if PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 plan bogus-mode >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid mode"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2)" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: rejected ai-review calls still mutated the line"

  # review note-init: idempotent, same shape as review-init/rfc init.
  PW_PROJECTS_DIR="$tmp" "$0" review note-init demo2 >/dev/null
  local NOTES="$tmp/demo2/REVIEWER-NOTES.md"
  [ -f "$NOTES" ] || die "selftest FAIL: review note-init did not create REVIEWER-NOTES.md"
  printf '\n## manual entry\n' >> "$NOTES"
  PW_PROJECTS_DIR="$tmp" "$0" review note-init demo2 >/dev/null
  grep -q '^## manual entry$' "$NOTES" || die "selftest FAIL: review note-init clobbered an existing file"

  # review auto-signoff: refuses when mode isn't auto (demo2/analysis is "advisory" above), refuses
  # while the template's own live R1/Q1 stubs are still unresolved (review-init always copies them
  # verbatim, so a just-created review file genuinely has one 🔴 open + one ⏳ awaiting-answer by
  # default — this is realistic, not a contrived case), and succeeds — with a distinctly-tagged row
  # placed INSIDE the Sign-off table — only once mode is auto AND both stubs are cleared.
  PW_PROJECTS_DIR="$tmp" "$0" review-init demo2 analysis/review/topic2.review.md analysis/topic2.md >/dev/null
  local RV2="$tmp/demo2/analysis/review/topic2.review.md"
  grep -q '🔴 open' "$RV2" || die "selftest FAIL: fresh review-init unexpectedly has no 🔴 open stub (test assumption invalid)"
  if PW_PROJECTS_DIR="$tmp" "$0" review auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null 2>&1; then
    die "selftest FAIL: auto-signoff succeeded although mode is 'advisory', not 'auto'"
  fi
  PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 analysis auto >/dev/null
  if PW_PROJECTS_DIR="$tmp" "$0" review auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null 2>&1; then
    die "selftest FAIL: auto-signoff succeeded although the R1/Q1 stubs are still open"
  fi
  # simulate pw-reviewer clearing both never-filled-in stubs on a genuinely clean pass (the
  # template's own documented convention — "emptied back to 'No blocking …'" — not a flip, since
  # there was never a real ask/question here to resolve, just a template placeholder).
  sed -i '' -e '/^### R1 · <§section or anchor> — 🔴 open/,+1d' \
            -e '/^### Q1 · <§section> — ⏳ awaiting answer/,+1d' "$RV2"
  _review_has_open_marker "$RV2" && die "selftest FAIL: clearing the stubs did not resolve _review_has_open_marker (still tripping on the permanent hint / worked example)"

  # --- _review_has_open_marker: dedicated unit-level checks for the machine marker itself,
  # isolated from the full auto-signoff integration flow above ---
  local MKT="$tmp/marker-test.md"
  # 1. A real heading whose ONLY open signal is the new marker (no legacy emoji at all) must
  #    still be detected — proves the marker path works independently of the emoji fallback.
  printf '### R1 · §1 something — status pending <!-- pw-item-status: open -->\nbody\n' > "$MKT"
  _review_has_open_marker "$MKT" || die "selftest FAIL: marker-only open heading (no emoji) not detected as open"
  # 2. A resolved marker must NOT be treated as open even when unrelated prose elsewhere on the
  #    SAME line mentions the legacy "open" words — proves the marker, not stray text, decides.
  printf '### R1 · §1 something resolved, previously open <!-- pw-item-status: resolved -->\nbody\n' > "$MKT"
  _review_has_open_marker "$MKT" && die "selftest FAIL: a resolved-marker heading was treated as open because of unrelated 'open' text on the same line"
  # 3. A same-line marker on a real heading must never be swallowed by, or itself swallow, a
  #    separate genuinely-multi-line comment elsewhere in the file (the sed-range gotcha this
  #    mechanism was rewritten to avoid) — content after the multi-line block must survive.
  printf '### R1 real — open <!-- pw-item-status: open -->\n<!-- multiline wrapper\nswallowed middle line\nend of wrapper -->\n### R2 real — resolved <!-- pw-item-status: resolved -->\n' > "$MKT"
  _review_has_open_marker "$MKT" || die "selftest FAIL: real open marker lost across an unrelated multi-line comment block"
  grep -q "swallowed middle line" <(awk '
    BEGIN { in_comment = 0 }
    { line = $0
      if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; next }
      if (line ~ /<!--/ && line ~ /-->/) { print line; next }
      if (line ~ /<!--/) { in_comment = 1; next }
      print line }
  ' "$MKT") && die "selftest FAIL: multi-line comment content was not actually stripped"

  PW_PROJECTS_DIR="$tmp" "$0" review auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null
  grep -q '| pw-reviewer (auto) | approved ✅ |$' "$RV2" || die "selftest FAIL: auto-signoff row not written/tagged correctly"
  grep -q '^| | | in-review |$' "$RV2" && die "selftest FAIL: auto-signoff left the placeholder row instead of replacing it"
  # anchor to an actual table ROW (starts with "| ", not prose mentioning the tag elsewhere in the
  # file's explanatory text, e.g. the template's own HOW-THIS-WORKS comment).
  local as_line as_sign; as_line="$(grep -nE '^\|.*pw-reviewer \(auto\).*approved ✅ \|$' "$RV2" | head -1 | cut -d: -f1)"
  as_sign="$(grep -n '^## Sign-off' "$RV2" | head -1 | cut -d: -f1)"
  [ -n "$as_line" ] || die "selftest FAIL: no auto-signoff table row found"
  [ "$as_line" -gt "$as_sign" ] || die "selftest FAIL: auto-signoff row landed before ## Sign-off"

  # --- review gate / review reopen: the analysis/RFC-parity mechanism (docs/RFC.md) ---
  # RV2 is currently approved ✅ (the auto-signoff row just above) — and, being a verbatim
  # review-init copy, STILL carries the template's own trailing Sign-off WORKED-EXAMPLE comment
  # block, containing two lines that look exactly like real approved-row table rows. This is
  # exactly the fixture that would trip the naive "last | line from ## Sign-off to EOF" bug.
  local gd
  gd="$(PW_PROJECTS_DIR="$tmp" "$0" review gate demo2 analysis/review/topic2.review.md)" \
    || die "selftest FAIL: review gate exited non-zero on a genuinely approved ✅ file"
  [ "$gd" = "approved ✅" ] || die "selftest FAIL: review gate printed '$gd', expected 'approved ✅'"

  # reopen: must succeed, append (never delete) an in-review row, and gate must now report open.
  PW_PROJECTS_DIR="$tmp" "$0" review reopen demo2 analysis/review/topic2.review.md >/dev/null
  grep -q '| pw-reviewer (auto) | approved ✅ |$' "$RV2" \
    || die "selftest FAIL: review reopen deleted the prior approval instead of appending after it"
  grep -q '| pw-review (auto-reopen) | in-review |$' "$RV2" \
    || die "selftest FAIL: review reopen did not append the expected in-review row"
  if gd="$(PW_PROJECTS_DIR="$tmp" "$0" review gate demo2 analysis/review/topic2.review.md)"; then
    die "selftest FAIL: review gate exited 0 right after reopen (should read in-review now)"
  fi
  [ "$gd" = "in-review" ] || die "selftest FAIL: review gate printed '$gd' after reopen, expected 'in-review'"

  # From here on, count/locate rows against a COMMENT-STRIPPED view of RV2 — the template's own
  # trailing WORKED-EXAMPLE block (still present, since review-init copies it verbatim and nothing
  # in this flow ever deletes it) contains a decorative "pw-reviewer (auto) | approved ✅ |" line
  # of its own, which would otherwise inflate a naive grep -c on the raw file. Blank (never delete)
  # commented lines so real line numbers still line up — same technique as
  # _signoff_last_real_row_line, duplicated here since it's a private helper.
  strip_rv2() {
    awk '
      BEGIN { in_comment = 0 }
      { line = $0
        if (in_comment) { if (line ~ /-->/) { in_comment = 0 }; print ""; next }
        if (line ~ /<!--/ && line ~ /-->/) { print line; next }
        if (line ~ /<!--/) { in_comment = 1; print ""; next }
        print line }
    ' "$RV2"
  }

  # reopen again while already open: idempotent no-op, must NOT append a second in-review row.
  PW_PROJECTS_DIR="$tmp" "$0" review reopen demo2 analysis/review/topic2.review.md >/dev/null
  [ "$(strip_rv2 | grep -c '| pw-review (auto-reopen) | in-review |$')" -eq 1 ] \
    || die "selftest FAIL: review reopen was not idempotent — appended a second in-review row"

  # re-approve (a SECOND auto-signoff on this file) must land as the table's new LAST row, not
  # inside/after the template's trailing WORKED-EXAMPLE comment block — the exact regression this
  # round's _signoff_last_real_row_line fix targets (a raw scan previously picked the example's
  # own "approved ✅" lines, since they're the last such lines in the whole file).
  PW_PROJECTS_DIR="$tmp" "$0" ai-review demo2 analysis auto >/dev/null   # already auto from above; explicit for clarity
  PW_PROJECTS_DIR="$tmp" "$0" review auto-signoff demo2 analysis/review/topic2.review.md analysis >/dev/null
  [ "$(strip_rv2 | grep -c '| pw-reviewer (auto) | approved ✅ |$')" -eq 2 ] \
    || die "selftest FAIL: second auto-signoff didn't produce a second distinct real approved row"
  gd="$(PW_PROJECTS_DIR="$tmp" "$0" review gate demo2 analysis/review/topic2.review.md)" \
    || die "selftest FAIL: review gate exited non-zero after the second (re-)approval"
  [ "$gd" = "approved ✅" ] || die "selftest FAIL: review gate printed '$gd' after re-approval, expected 'approved ✅'"
  # and the row order must still be [1st approved, in-review, 2nd approved] top-to-bottom in the
  # file — proof the second approval landed AFTER the reopen row, not before/inside the example
  # block (line numbers, not just gate's reported decision, so this doesn't just re-check the same
  # function under test — it checks the row actually got spliced into the right physical spot).
  local ln_row1 ln_reopen ln_row2
  ln_row1="$(strip_rv2 | grep -n '| pw-reviewer (auto) | approved ✅ |$' | sed -n '1p' | cut -d: -f1)"
  ln_reopen="$(strip_rv2 | grep -n '| pw-review (auto-reopen) | in-review |$' | cut -d: -f1)"
  ln_row2="$(strip_rv2 | grep -n '| pw-reviewer (auto) | approved ✅ |$' | sed -n '2p' | cut -d: -f1)"
  [ -n "$ln_row1" ] && [ -n "$ln_reopen" ] && [ -n "$ln_row2" ] \
    || die "selftest FAIL: couldn't locate all 3 expected real Sign-off rows in $RV2"
  [ "$ln_row1" -lt "$ln_reopen" ] && [ "$ln_reopen" -lt "$ln_row2" ] \
    || die "selftest FAIL: Sign-off rows out of order (1st-approved=$ln_row1 reopen=$ln_reopen 2nd-approved=$ln_row2) — the second approval didn't land after the reopen row"

  # reopen must refuse silently (no-op, exit 0) when the file is NOT currently approved.
  PW_PROJECTS_DIR="$tmp" "$0" review reopen demo2 analysis/review/topic2.review.md >/dev/null
  PW_PROJECTS_DIR="$tmp" "$0" review reopen demo2 analysis/review/topic2.review.md >/dev/null || \
    die "selftest FAIL: reopen on an already-open file exited non-zero (should be a harmless no-op)"

  # --- review has-open: the generic open-item check /pw-breakdown's RFC hard block relies on ---
  # a project with no RFC.review.md at all (never touched the side-loop) must report "no"/exit 1,
  # never an error.
  local RFCRV="$tmp/demo2/analysis/review/RFC.review.md" hn
  if hn="$(PW_PROJECTS_DIR="$tmp" "$0" review has-open demo2 analysis/review/RFC.review.md)"; then
    die "selftest FAIL: review has-open exited 0 for a nonexistent RFC.review.md (should be 'no'/exit 1)"
  fi
  [ "$hn" = "no" ] || die "selftest FAIL: review has-open printed '$hn' for a missing file, expected 'no'"

  # a real pulled-comment item, still open — must report "yes"/exit 0.
  mkdir -p "$(dirname "$RFCRV")"
  printf '# RFC comments\n\n### R1 — a pulled comment <!-- pw-item-status: open -->\n\n> quoted comment text\n' \
    > "$RFCRV"
  if ! PW_PROJECTS_DIR="$tmp" "$0" review has-open demo2 analysis/review/RFC.review.md >/dev/null; then
    die "selftest FAIL: review has-open exited non-zero on a file with a real open item"
  fi
  hn="$(PW_PROJECTS_DIR="$tmp" "$0" review has-open demo2 analysis/review/RFC.review.md)"
  [ "$hn" = "yes" ] || die "selftest FAIL: review has-open printed '$hn' with an open item present, expected 'yes'"

  # resolve it in place — has-open must now report clean ("no"/exit 1), same file, no other rows.
  # Capture the printed value INSIDE the if-guard (not a separate call) — the expected exit here is
  # 1, and an ungated `hn="$(...)"` on a nonzero-exit command would trip `set -e` and abort the
  # whole selftest silently, same reasoning as the existing `review gate` checks above.
  sed -i '' -e 's/<!-- pw-item-status: open -->/<!-- pw-item-status: resolved -->/' "$RFCRV"
  if hn="$(PW_PROJECTS_DIR="$tmp" "$0" review has-open demo2 analysis/review/RFC.review.md)"; then
    die "selftest FAIL: review has-open exited 0 after the only open item was resolved"
  fi
  [ "$hn" = "no" ] || die "selftest FAIL: review has-open printed '$hn' after resolving, expected 'no'"

  # review gate on a review file with no Sign-off rows fabricated at all → dies, doesn't crash.
  local NOSIGN="$tmp/demo2/no-signoff.review.md"
  printf '# not a real review file\nno Sign-off section here\n' > "$NOSIGN"
  if PW_PROJECTS_DIR="$tmp" "$0" review gate demo2 no-signoff.review.md >/dev/null 2>&1; then
    die "selftest FAIL: review gate succeeded on a file with no ## Sign-off section at all"
  fi

  # --- model-check: empty/unset allowlist = all models allowed (the default rule) ---
  local mc
  mc="$(PW_MODEL_ALLOWLIST_CLAUDE="" "$0" model-check claude some-random-model-nobody-configured)" \
    || die "selftest FAIL: model-check refused with an empty allowlist (should always pass)"
  echo "$mc" | grep -q "all models allowed" || die "selftest FAIL: model-check's empty-allowlist message didn't state the 'all models allowed' rule"
  # a configured allowlist passes a matching model...
  PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$0" model-check claude sonnet >/dev/null \
    || die "selftest FAIL: model-check refused a model matching its configured allowlist"
  # ...glob patterns match...
  PW_MODEL_ALLOWLIST_KILO="command_code/deepseek/*" "$0" model-check kilo command_code/deepseek/deepseek-v4-flash >/dev/null \
    || die "selftest FAIL: model-check refused a model matching a glob pattern in its allowlist"
  # ...and refuses one that doesn't, without silently passing.
  if PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$0" model-check claude opus >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a model NOT in its configured allowlist"
  fi

  echo "selftest OK"
}

case "${1:-}" in
  status)      shift; cmd_status "$@" ;;
  oneliner)    shift; cmd_oneliner "$@" ;;
  adopted)     shift; cmd_adopted "$@" ;;
  adopt)       shift; cmd_adopt "$@" ;;
  review-init) shift; cmd_review_init "$@" ;;
  log)         shift; cmd_log "$@" ;;
  phase)       shift; cmd_phase "$@" ;;
  rfc)         shift; cmd_rfc "$@" ;;
  ship)        shift; cmd_ship "$@" ;;
  ai-review)   shift; cmd_ai_review "$@" ;;
  review)      shift; cmd_review "$@" ;;
  model-check) shift; cmd_model_check "$@" ;;
  selftest)    cmd_selftest ;;
  -h|--help|"") sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
