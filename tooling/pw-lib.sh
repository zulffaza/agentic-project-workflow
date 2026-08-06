#!/usr/bin/env bash
# pw-lib.sh — mechanical helpers the /pw-* commands call so the load-bearing, format-sensitive
# steps (dashboard Status, One-liner, LOG.md, phase read) are deterministic instead of hand-edited
# prose. Deterministic + phase-validated so a flaky/cheap executor can't corrupt the dashboard.
#
#   pw-lib.sh status   <slug> <phase> [--rewind]   set dashboard Status: (validated, no accidental
#                                                  backward move) + auto-log the change
#   pw-lib.sh oneliner <slug> <text...>            set the dashboard One-liner (agent, at analysis)
#   pw-lib.sh adopted  <slug> <text...>            set/insert the dashboard Adopted: pointer (/pw-adopt)
#   pw-lib.sh adopt    <slug> <repo> <branch> <base> [mr]   append/upsert one adoption unit (no clobber)
#   pw-lib.sh log      <slug> <actor> <msg...>     append a timestamped LOG.md line
#   pw-lib.sh phase    <slug>                       print the current Status value (for scoping/status)
#   pw-lib.sh selftest                              run an isolated round-trip test
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

cmd_log() {
  [ $# -ge 3 ] || die "usage: log <slug> <actor> <msg...>"
  local slug="$1" actor="$2"; shift 2
  local d; d="$(proj_dir "$slug")"
  printf '%s | %s | %s\n' "$(date '+%F %H:%M')" "$actor" "$*" >> "$d/LOG.md"
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
      printf 'them or the dashboard; fill the prose under each unit. [🧑🤖 both]\n'
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

cmd_phase() {
  [ $# -eq 1 ] || die "usage: phase <slug>"
  local f; f="$(proj_dir "$1")/README.md"
  [ -f "$f" ] || die "no README.md in project $1"
  grep -m1 '^- \*\*Status:\*\*' "$f" | sed 's/^- \*\*Status:\*\*[[:space:]]*//'
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
  grep -q '| status | Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing"
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
  grep -q '| analyze | wrote analysis/x.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing"
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
  echo "selftest OK"
}

case "${1:-}" in
  status)   shift; cmd_status "$@" ;;
  oneliner) shift; cmd_oneliner "$@" ;;
  adopted)  shift; cmd_adopted "$@" ;;
  adopt)    shift; cmd_adopt "$@" ;;
  log)      shift; cmd_log "$@" ;;
  phase)    shift; cmd_phase "$@" ;;
  selftest) cmd_selftest ;;
  -h|--help|"") sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
