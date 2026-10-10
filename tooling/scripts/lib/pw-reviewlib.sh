# shellcheck shell=bash
# ============================================================================
# pw-reviewlib.sh — SOURCE-ONLY library of review-workflow mechanics for the
# review-doc entity (S5 of tooling/docs/conventions.md). No CLI, no
# dispatch, no exit, no slug resolution — every function takes explicit paths
# or plain values and returns via rc; the entity script owns die messages.
#
# Pure document primitives (sign-off reads, detectors, splices) live in
# pw-mdlib.sh; THIS library holds the operational mechanics a review state
# machine needs that are not document parsing:
#   pw_now_wib              shared event formatter from pw-mdlib.sh
#   pw_meta_check           table-cell metadata validation (injection guard)
#   pw_heading_meta_check   reserved-syntax guard for heading metadata
#                           (status tags, HTML comments, machine markers, stub tokens)
#   pw_review_lane          artifact path -> review lane (not a dashboard phase)
#   pw_review_dirs          the canonical review-lane directory list (ONE copy for all readers)
#   pw_review_files         immediate review files per lane (+ escape records)
#   pw_review_lane_rank     lane order on the phase ladder
#   pw_dash_rank            dashboard-phase order on the same ladder
#   pw_review_phase_lane_ok  lane-vs-phase binding (auto policy applies to its own lane)
#   pw_review_contain       project-relative path containment + symlink guard
#   pw_review_reviewrel     artifact path -> canonical review path (or rc 1 + reason)
#   pw_review_lock/unlock   per-file mkdir serialization (owned by the writer; NEVER
#                           auto-stolen — a busy lock fails, stale removal is explicit)
#   pw_review_staged        lock + copy + run-fn + one atomic publish + cleanup
#   pw_signoff_row_put      place one Sign-off row (append after the latest data row;
#                           replace the template placeholder only when no rows exist)
#   pw_review_gate_refresh  derive the header "Gate:" line from the shared latest readers
#
# Timestamp policy: review writers emit "D MMMM YYYY HH.mm WIB" (explicit UTC+7,
# English locale, unpadded day); readers keep accepting legacy "YYYY-MM-DD HH:MM",
# the legacy "approved ✅" decoration, and the template's `<YYYY-MM-DD HH:MM>`
# stub tokens — nothing historical is rewritten (standalone scope rule).
# bash 3.2 compatible (macOS default).
# ============================================================================

# --- metadata injection guard -------------------------------------------------

# pw_meta_check <label> <value> — one-line reason to stderr + rc 1 when <value>
# would corrupt a markdown table cell or heading: a newline/CR (row injection),
# a TAB (cell splitting differs across renderers), or a pipe (cell boundary).
# Sign-off By/Decision rows, item headings, and the regenerated Contents table
# all embed these values — validating here is the single choke point (readers
# must never have to guess which row a crafted cell started).
pw_meta_check() {
  local label="$1" value="$2"
  case "$value" in
    *$'\n'*|*$'\r'*) echo "$label: must not contain a newline (it would inject a row or heading)" >&2; return 1 ;;
    *$'\t'*)         echo "$label: must not contain a tab character" >&2; return 1 ;;
    *"|"*)           echo "$label: must not contain a pipe character (it would break the Sign-off/Contents table)" >&2; return 1 ;;
  esac
  return 0
}

# pw_heading_meta_check <label> <value> — rc 1 + one-line reason when <value> carries
# RESERVED review syntax that must never ride into an item heading's anchor/actor slots:
# canonical status tags ([OPEN]/[PENDING]/[RESOLVED]/[ANSWERED]), HTML-comment delimiters,
# the pw-item-status machine marker, the reply-line prefix, and the template's stub
# tokens (<YYYY-MM-DD, <§section>). A heading embeds these values verbatim; an actor like
# `x) — [RESOLVED] (you` used to make a freshly written [OPEN] item parse as resolved
# (greedy last-tag readers), and stub tokens hid real items from every stub filter —
# both turn a live blocker into an auto-approvable file. The writers refuse this input;
# the readers additionally classify marker-first (pw-mdlib sttag) so even hand-written
# disagreement can never read as settled.
pw_heading_meta_check() {
  local label="$1" value="$2"
  case "$value" in
    *"[OPEN]"*|*"[PENDING]"*|*"[RESOLVED]"*|*"[ANSWERED]"*)
      echo "$label: must not contain a status tag ([OPEN]/[PENDING]/[RESOLVED]/[ANSWERED]) — headings carry exactly one, written by the tool" >&2
      return 1 ;;
    *"<!--"*|*"-->"*|*"pw-item-status"*)
      echo "$label: must not contain HTML-comment or pw-item-status machine-marker syntax" >&2
      return 1 ;;
    *"↳"*)
      echo "$label: must not contain the ↳ reply-line marker" >&2
      return 1 ;;
    *"<YYYY-MM-DD"*|*"<DD MMMM YYYY"*|*"<§section"*)
      echo "$label: must not contain template stub tokens — they would hide the item from every reader" >&2
      return 1 ;;
    *"🔴 open"*|*"⏳ awaiting answer"*)
      echo "$label: must not contain the legacy emoji status tags" >&2
      return 1 ;;
  esac
  return 0
}

# --- lanes and phase binding ---------------------------------------------------

# pw_review_lane <project-rel review or artifact path> → context | analysis | plan | task | rfc |
# rfccontent | close | other.
# A LANE is an artifact family, deliberately distinct from a dashboard PHASE
# (context/analysis/breakdown/executing/review/done) and from the config surface tokens
# (context/analysis/plan/task-plan/task-exec/ship/rfc/close): the resolver both directions
# lives here. `rfc` is the fetched-comment STAGING lane (never gets a pass/approval row);
# `rfccontent` is the local rfc/RFC.md content review record (a real surface).
pw_review_lane() {
  case "$1" in
    analysis/review/RFC.review.md)      echo rfc ;;
    analysis/review/*.review.md)        echo analysis ;;
    analysis/RFC.md)                    echo rfc ;;
    analysis/*.md)                      echo analysis ;;
    context/review/CONTEXT.review.md)   echo context ;;
    context/REQUIREMENTS.md)            echo context ;;
    rfc/review/*.review.md)             echo rfccontent ;;
    rfc/RFC.md)                         echo rfccontent ;;
    review/CLOSE.review.md)             echo close ;;
    task/review/PLAN.review.md)         echo plan ;;
    task/review/T*.review.md)           echo task ;;
    task/review/T*.archive.md)          echo task ;;
    task/PLAN.md)                       echo plan ;;
    task/T*.md)                         echo task ;;
    *)                                  echo other ;;
  esac
}

# --- review-lane discovery (the ONE list every reader shares) ------------------
#
# pw_review_dirs — the review lanes as project-relative directories, one per line, in
# canonical scan order. THE single directory list: pw-review-read.sh scan and the
# pw-status.sh surfaces consume it instead of keeping private copies — a missed dir is
# how context/rfc/close coverage drifted once already.
pw_review_dirs() {
  printf '%s\n' "analysis/review" "task/review" "context/review" "rfc/review" "review"
}

# pw_review_files <projdir> — enumerate the immediate review files of a project.
# Records on stdout, one per line, TAB-separated:
#   file<TAB><lane-dir><TAB><file-abspath>     an existing *.review.md of that lane
#   symlink<TAB><lane-dir><TAB><file-abspath>  the review FILE is a symlink — never read
#   escape<TAB><lane-dir>                      the lane DIRECTORY is/contains a symlink, or
#                                              otherwise resolves outside the project
# Missing lanes are skipped silently; `find -maxdepth 1` (never recursive: review/ai/
# handoff packets hold snapshot copies of review files and must never be re-counted).
# A lane symlink is checked with an explicit -L walk: pw_review_contain's logical-PWD
# resolution cannot see a LAST-segment symlink pointing outside, so the -L walk is the
# authority for lane directories. rc 1 when any lane escaped — the escape records are
# still emitted so each caller can choose its own policy (the scan dies; the status
# surfaces flag uncertainty).
pw_review_files() {
  local d="$1" rel f seg p sy rc=0
  for rel in $(pw_review_dirs); do
    [ -d "$d/$rel" ] || continue
    sy=0; p=""
    for seg in $(printf '%s' "$rel" | tr '/' ' '); do
      p="$p/$seg"
      if [ -L "$d$p" ]; then sy=1; break; fi
    done
    if [ "$sy" = 1 ] || ! pw_review_contain "$d" "$rel" >/dev/null 2>&1; then
      printf 'escape\t%s\n' "$rel"
      rc=1
      continue
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -L "$f" ]; then
        printf 'symlink\t%s\t%s\n' "$rel" "$f"
      else
        printf 'file\t%s\t%s\n' "$rel" "$f"
      fi
    done <<EOFL
$(find "$d/$rel" -maxdepth 1 -name '*.review.md' 2>/dev/null | LC_ALL=C sort)
EOFL
  done
  return $rc
}

# pw_review_lane_rank <lane> — position on the phase ladder (0 = unranked/exempt).
# context ranks with analysis (reviewing readiness while analysis runs is fine; after
# breakdown it is "earlier"). rfccontent is exempt (its side-loop runs across phases and
# its published-content gate is the RFC flow's own). close ranks at done.
pw_review_lane_rank() {
  case "$1" in
    context)    echo 1 ;;
    analysis)   echo 1 ;;
    plan)       echo 2 ;;
    task)       echo 3 ;;
    close)      echo 4 ;;
    *)          echo 0 ;;
  esac
}

# pw_dash_rank <dashboard-phase-token> — same ladder (mirrors pw-status.sh's monotonic
# guard ranks; executing and review share rank 3 on purpose). -1 = not a valid phase.
pw_dash_rank() {
  case "$1" in
    context) echo 0 ;; analysis) echo 1 ;; breakdown) echo 2 ;;
    executing) echo 3 ;; review) echo 3 ;; done) echo 4 ;;
    *) echo -1 ;;
  esac
}

# pw_review_phase_lane_ok <config-surface> <lane> — the selected review surface must own the
# artifact being approved/entered: context↔context readiness, analysis↔analysis topics,
# plan↔PLAN, task-plan↔task, task-exec↔task results, ship↔the mirrored task reviews,
# rfc↔the LOCAL rfc/RFC.md content record (never the fetched-comment staging, which matches
# NO surface, and close↔the local CLOSE record, whose approval carries no teardown permission).
pw_review_phase_lane_ok() {
  local phase="$1" lane="$2"
  case "$phase" in
    context)    [ "$lane" = "context" ] ;;
    analysis)   [ "$lane" = "analysis" ] ;;
    plan)       [ "$lane" = "plan" ] ;;
    task-plan)  [ "$lane" = "task" ] ;;
    task-exec)  [ "$lane" = "task" ] ;;
    ship)       [ "$lane" = "task" ] ;;
    rfc)        [ "$lane" = "rfccontent" ] ;;
    close)      [ "$lane" = "close" ] ;;
    *)          return 1 ;;
  esac
}

# --- path safety -----------------------------------------------------------------

# pw_review_contain <projdir> <project-rel-path> — print the resolved absolute path,
# rc 1 + one-line reason when the path escapes the project (absolute, empty, a `..`
# hop that resolves outside, or any symlink component that leaves the project tree).
# Comparison is PHYSICAL on both sides: macOS /var is a symlink to /private/var, so a
# logical-vs-physical compare would false-flag every temp-root path; `cd` resolves
# symlinks, and files can't be cd'd into — so the deepest existing DIRECTORY ancestor
# is resolved and the remaining components are re-appended.
pw_review_contain() {
  local d="$1" rel="$2" dreal probe rest phys
  case "$rel" in
    ""|/*)      echo "path must be project-relative and non-empty (got: '$rel')" >&2; return 1 ;;
  esac
  case "$rel" in
    *$'\n'*|*$'\r'*) echo "path must not contain a newline" >&2; return 1 ;;
  esac
  dreal="$(cd "$d" 2>/dev/null && printf '%s' "$PWD")" || { echo "cannot resolve project directory: $d" >&2; return 1; }
  probe="$dreal/$rel"; rest=""
  while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
    rest="$(basename "$probe")${rest:+/$rest}"
    probe="$(dirname "$probe")"
  done
  if [ ! -d "$probe" ]; then
    rest="$(basename "$probe")${rest:+/$rest}"
    probe="$(dirname "$probe")"
  fi
  phys="$(cd "$probe" 2>/dev/null && printf '%s' "$PWD")" || { echo "cannot resolve path: $rel" >&2; return 1; }
  [ -n "$rest" ] && phys="$phys/$rest"
  case "$phys" in
    "$dreal"/*) printf '%s' "$phys" ;;
    *)      echo "path escapes the project directory: $rel" >&2; return 1 ;;
  esac
}

# pw_review_reviewrel <projdir> <artifact-rel-path> — validate one selected artifact and
# print "<docrel>\t<reviewrel>". Accepts exactly the reviewable artifact families:
# analysis topic docs, task/PLAN.md, task/T0n.md, context/REQUIREMENTS.md (readiness), and
# rfc/RFC.md (local RFC content). Rejects: anything outside the project (incl. symlink
# escapes), missing/non-regular targets, README/_TEMPLATE sources, RFC comment staging
# (analysis/RFC.md + its review — the side-loop owns that lane), the CLOSE record (created
# by its own flow, not by artifact selection), and review/archive files selected as if they
# were artifacts.
pw_review_reviewrel() {
  local d="$1" rel="$2" abs lane base
  # normalize cosmetic forms before containment
  case "$rel" in ./*) rel="${rel#./}" ;; esac
  abs="$(pw_review_contain "$d" "$rel")" || return 1
  [ -e "$abs" ] || { echo "no such document: $rel" >&2; return 1; }
  [ -L "$abs" ] && { echo "refusing symlinked document: $rel" >&2; return 1; }
  [ -f "$abs" ] || { echo "not a regular file: $rel" >&2; return 1; }
  base="$(basename "$rel")"
  case "$base" in README.md|_TEMPLATE*|*.archive.md|*.review.md) echo "not a reviewable artifact: $rel" >&2; return 1 ;; esac
  case "$rel" in
    analysis/review/*|task/review/*|context/review/*|rfc/review/*|review/ai/*) echo "already a review path, not an artifact: $rel" >&2; return 1 ;;
  esac
  lane="$(pw_review_lane "$rel")"
  case "$lane" in
    rfc)     echo "RFC comment staging keeps its own comment side-loop — no topic review for: $rel" >&2; return 1 ;;
    context) printf '%s\tcontext/review/CONTEXT.review.md\n' "$rel" ;;
    rfccontent) printf '%s\trfc/review/RFC-CONTENT.review.md\n' "$rel" ;;
    close)   echo "the close record is created by its own flow, not by artifact selection: $rel" >&2; return 1 ;;
    analysis) printf '%s\tanalysis/review/%s.review.md\n' "$rel" "${base%.md}" ;;
    plan)     printf '%s\ttask/review/PLAN.review.md\n' "$rel" ;;
    task)     printf '%s\ttask/review/%s.review.md\n' "$rel" "${base%.md}" ;;
    *)        echo "unsupported artifact (reviewable: analysis/*.md, task/PLAN.md, task/T0n.md, context/REQUIREMENTS.md, rfc/RFC.md): $rel" >&2; return 1 ;;
  esac
}

# --- handoff primitives (prepare/import snapshot+report machinery) ------------------

# pw_review_hash_stdin — hex sha256 of stdin (shasum first, sha256sum fallback).
pw_review_hash_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    cat >/dev/null
    echo "no sha256 tool on PATH (shasum/sha256sum)" >&2
    return 1
  fi
}

# pw_review_sha256 <file> — hex digest of a file's bytes (rc 1 + reason when unhashable).
pw_review_sha256() {
  local f="$1"
  [ -f "$f" ] && [ ! -L "$f" ] || { echo "no hashable regular file: $f" >&2; return 1; }
  pw_review_hash_stdin < "$f"
}

# pw_review_fingerprint — digest of the canonical reviewed-identity byte stream: a version
# header line plus the caller's "rel\tsha256" (or "code\t…") lines, SORTED. Reads lines on
# stdin; prepare and import feed the same generator so recomputation is byte-identical.
pw_review_fingerprint() {
  { printf 'pw-review-inputs/1\n'; LC_ALL=C sort; } | pw_review_hash_stdin
}

# pw_review_json_escape <value> — one-line JSON string escape (the prepare writer builds its
# manifest with this; values are validated beforehand, this is the belt).
pw_review_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

# --- per-file serialization + staged publish ---------------------------------------

# pw_review_lock <file> — mkdir lock beside the file (atomic on every filesystem;
# no flock dependency on bash 3.2/macOS). rc 1 when a lock exists, for ANY age: there is
# NO time-based takeover — a "stale" lock was indistinguishable from a live writer whose
# machine paused, and the old 2-minute `find -mmin +2` rmdir released live owners while
# their staged publish was still in flight (two writers, one file). A crashed writer
# leaves the lock until a human removes it — the entity's busy message carries that exact
# → fix: guidance, which is the safe and sufficient recovery path. Ownership is recorded
# (holder PID inside the lock dir) so pw_review_unlock can only ever remove OUR lock.
pw_review_lock() {
  local f="$1" lock="$1.pwlock" tries=0
  while ! mkdir "$lock" 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -gt 100 ] && return 1
    sleep 0.1
  done
  if ! printf '%s\n' "$$" > "$lock/owner" 2>/dev/null; then
    rmdir "$lock" 2>/dev/null || true
    return 1
  fi
  return 0
}

# pw_review_unlock <file> — remove the lock ONLY when its owner token is this process.
# A lock we never acquired (or that another writer took over after an explicit stale
# removal) is left exactly where it is: unlock must never delete somebody else's lock.
pw_review_unlock() {
  local lock="$1.pwlock"
  [ -d "$lock" ] || return 0
  if [ -f "$lock/owner" ] && [ "$(cat "$lock/owner" 2>/dev/null)" = "$$" ]; then
    rm -f "$lock/owner" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
  fi
  return 0
}

# pw_review_staged <file> <fn> [args…] — THE serialized mutation primitive the entity
# routes every review-file write through (feedback + state change publish as
# ONE validated replacement, no visible stale-approval interval; plain splices reuse
# it so concurrent writers can't interleave a lost update). Copies the file, runs
# <fn> <workfile> [args…] against the copy, publishes with one atomic same-directory
# mv on success; any failure (fn rc, or a failed copy/publish) leaves the ORIGINAL
# untouched and cleans the temp + lock. rc: 1 failure (fn already wrote its reason to
# stderr), 3 lock busy.
pw_review_staged() {
  local f="$1" fn="$2"; shift 2
  local dir work rc=0
  pw_review_lock "$f" || return 3
  dir="$(dirname "$f")"
  work="$dir/.pwrev.$(basename "$f").$$"
  if cp "$f" "$work" 2>/dev/null; then
    if "$fn" "$work" "$@"; then
      if mv "$work" "$f" 2>/dev/null; then rc=0; else rc=1; echo "staged publish failed for $f (original left untouched)" >&2; fi
    else
      rc=1
    fi
  else
    rc=1; echo "could not stage a copy of $f" >&2
  fi
  [ "$rc" -ne 0 ] && { rm -f "$work" "$work".tmp "$work".hdr "$work".gate "$work".dash-err "$work".fill-err "$work".plan-err; }
  pw_review_unlock "$f"
  return "$rc"
}

# --- sign-off row placement ---------------------------------------------------------

# pw_signoff_row_put <file> <ts> <by> <decision> — place one row in the Sign-off table:
# when the table already has AUTHORED DATA rows, append after the current latest one
# (the template placeholder sitting unreplaced ABOVE real rows is never a placement
# anchor — it used to route the new decision above the old latest, so the newest
# transition read as an older decision and history order broke). Only when there are
# no data rows yet does the template's untouched placeholder ("| | | in-review |") get
# REPLACED — the first attributed decision takes the placeholder's row, same code path
# signoff/auto-signoff have always used. rc 1 — and NO change to the file — when the
# table has neither (malformed table never silently invented); every splice/publish
# failure propagates as rc 1 too, so callers can abort a staged write and never report
# a success that did not land.
pw_signoff_row_put() {
  local f="$1" ts="$2" by="$3" decision="$4"
  local row="| $ts | $by | $decision |"
  local lastdata; lastdata="$(_signoff_last_data_row_line "$f")"
  if [ "${lastdata:-0}" -gt 0 ]; then
    local tmp; tmp="$(mktemp)" || return 1
    if ! printf '%s\n' "$row" > "$tmp"; then rm -f "$tmp"; return 1; fi
    if md_insert_lines_after "$f" "$lastdata" "$tmp"; then rm -f "$tmp"; return 0; fi
    rm -f "$tmp"
    echo "pw_signoff_row_put: failed to splice the new Sign-off row into $f (file left as it was)" >&2
    return 1
  fi
  if grep -q '^| | | in-review |$' "$f"; then
    if ! awk -v row="$row" '{ if ($0 == "| | | in-review |") { print row; next } print }' "$f" > "$f.tmp"; then
      rm -f "$f.tmp"
      echo "pw_signoff_row_put: failed to rewrite the placeholder row in $f (file left as it was)" >&2
      return 1
    fi
    if ! mv "$f.tmp" "$f"; then
      rm -f "$f.tmp"
      echo "pw_signoff_row_put: failed to publish the placeholder replacement in $f (file left as it was)" >&2
      return 1
    fi
    return 0
  fi
  return 1
}

# --- derived header state -------------------------------------------------------------

# pw_review_gate_refresh <file> — rewrite the generated header's "Gate:" line from the
# SHARED latest-row readers, so it can never again sit stale next to the table it claims
# to summarize. Human script-free (displays decision + actor only, no command text). A
# file with no "Gate:" header line (older shape) is left untouched — never injected.
# Placeholder/blank state renders "Gate: in-review (not yet signed off)". rc 1 (and the
# row left unwritten) when the header splice/publish fails — callers must abort the whole
# staged operation, never publish a mutated table behind an unwritten header.
pw_review_gate_refresh() {
  local f="$1" d a state
  grep -q '^Gate:' "$f" || return 0
  if d="$(_signoff_latest_decision "$f")"; then
    a="$(_signoff_latest_actor "$f")" || a=""
    if [ -n "$a" ]; then state="$d ($a)"; else state="$d (not yet signed off)"; fi
  else
    state="in-review (not yet signed off)"
  fi
  local line="Gate: $state"
  local hl; hl="$(grep -n '^Gate:' "$f" | head -1 | cut -d: -f1)"
  [ -n "$hl" ] || return 1
  printf '%s\n' "$line" > "$f.gate" || { rm -f "$f.gate"; return 1; }
  if ! md_replace_line "$f" "$hl" "$f.gate"; then rm -f "$f.gate"; return 1; fi
  rm -f "$f.gate"
}

# pw_review_contents_rebuild <file> — regenerate the heading-anchored "## Contents"
# block in place (the pure document half of the reindex operator, extracted so staged
# writers rebuild it on their working copy before publishing; the entity wrapper owns
# the log line and stdout). Anchored by pw-contents:begin/end markers; inserted after
# the header "Gate:" line when the block does not exist yet.
# MARKER CONTRACT: replace only a PAIRED, ORDERED, UNIQUE block (exactly one begin and
# one end, begin above end). A begin without its end (or a doubled marker) used to fall
# into `tail -n +$((e+1))` with an empty e — the whole file got copied back after the
# fresh block, duplicating every heading, table, and sign-off row with no error. Here
# the malformed pair is reported rc 1 BEFORE anything is written, so the staged publish
# aborts and the original stays byte-identical. Every splice/publish failure likewise
# propagates rc 1 after cleaning the temp.
pw_review_contents_rebuild() {
  local f="$1"
  local rows; rows="$(_review_items_tsv "$f" | cut -f2-)"
  local block; block="$(mktemp)" || return 1
  if ! {
    printf '<!-- pw-contents:begin -->\n'
    printf '## Contents   [agent-owned; refreshed automatically; do not edit]\n\n'
    printf '| ID | Section / anchor | Status |\n|----|-------------------|--------|\n'
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows" | awk -F'\t' '{printf "| %s | %s | [%s] |\n", $1, $2, $3}'
    else
      printf '| _(none yet)_ | | |\n'
    fi
    printf '<!-- pw-contents:end -->\n'
  } > "$block"; then
    rm -f "$block"; return 1
  fi
  local nb ne b e anchor
  nb="$(grep -c '<!-- pw-contents:begin -->' "$f" || true)"; nb="${nb:-0}"
  ne="$(grep -c '<!-- pw-contents:end -->' "$f" || true)"; ne="${ne:-0}"
  if [ "$nb" -gt 0 ] || [ "$ne" -gt 0 ]; then
    if [ "$nb" != 1 ] || [ "$ne" != 1 ]; then
      echo "pw_review_contents_rebuild: $f has a malformed Contents block ($nb begin marker(s), $ne end marker(s); exactly one ordered pair required) — nothing written" >&2
      rm -f "$block"; return 1
    fi
    b="$(grep -n '<!-- pw-contents:begin -->' "$f" | head -1 | cut -d: -f1)"
    e="$(grep -n '<!-- pw-contents:end -->' "$f" | head -1 | cut -d: -f1)"
    if [ -z "$b" ] || [ -z "$e" ] || [ "$b" -ge "$e" ]; then
      echo "pw_review_contents_rebuild: $f Contents begin/end markers are not an ordered pair (begin line ${b:-?}, end line ${e:-?}) — nothing written" >&2
      rm -f "$block"; return 1
    fi
    # the window between the markers must BE the Contents block (exactly one `## ` heading:
    # the Contents heading itself) — a stray end marker dragged below Sign-off would make
    # the "replacement" swallow live sections between begin and end.
    local nh; nh="$(sed -n "${b},${e}p" "$f" | grep -c '^## ' || true)"; nh="${nh:-0}"
    if [ "$nh" != 1 ]; then
      echo "pw_review_contents_rebuild: $f Contents begin/end pair spans a $((e-b))-line region containing $nh section heading(s) — not a Contents block; nothing written" >&2
      rm -f "$block"; return 1
    fi
    if ! md_replace_range "$f" "$b" "$e" "$block"; then
      echo "pw_review_contents_rebuild: failed to splice the Contents block into $f (file left as it was)" >&2
      rm -f "$block"; return 1
    fi
  else
    anchor="$(grep -n '^Gate:' "$f" | head -1 | cut -d: -f1)"
    if [ -n "$anchor" ]; then
      printf '\n' >> "$block" || { rm -f "$block"; return 1; }
      if ! md_insert_lines_after "$f" "$anchor" "$block"; then
        echo "pw_review_contents_rebuild: failed to insert the Contents block into $f (file left as it was)" >&2
        rm -f "$block"; return 1
      fi
    else
      { cat "$block"; printf '\n'; cat "$f"; } > "$f.tmp" || { rm -f "$block" "$f.tmp"; return 1; }
      if ! mv "$f.tmp" "$f"; then rm -f "$block" "$f.tmp"; return 1; fi
    fi
  fi
  rm -f "$block"
}
