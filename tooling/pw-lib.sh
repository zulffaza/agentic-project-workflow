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

cmd_selftest() {
  local SELF_LIB="$HERE/pw-lib.sh"   # re-spawn by resolved path — bare "$0" can't exec without a slash
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n  <!-- comment stays -->\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo analysis >/dev/null
  local got; got="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" phase demo)"
  [ "$got" = "analysis" ] || die "selftest FAIL: phase='$got' (expected analysis)"
  grep -q '<!-- comment stays -->' "$tmp/demo/README.md" || die "selftest FAIL: clobbered trailing comment"
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `status` — Status -> analysis$' "$tmp/demo/LOG.md" || die "selftest FAIL: log line missing/wrong format"
  # One-liner setter
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" oneliner demo "toggle kafka usage safely" >/dev/null
  grep -q '^- \*\*One-liner:\*\* toggle kafka usage safely$' "$tmp/demo/README.md" || die "selftest FAIL: one-liner not set"
  # Monotonic guard: a backward move without --rewind must fail…
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo context >/dev/null 2>&1; then
    die "selftest FAIL: backward status move was NOT blocked"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" phase demo)" = "analysis" ] || die "selftest FAIL: blocked move still mutated Status"
  # …but --rewind is allowed, and executing↔review (same rank) is never treated as backward.
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo executing >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo review >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo executing >/dev/null   # re-run a task: not a rewind
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" phase demo)" = "executing" ] || die "selftest FAIL: executing↔review blocked"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" status demo analysis --rewind >/dev/null
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" phase demo)" = "analysis" ] || die "selftest FAIL: --rewind did not apply"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" log demo analyze "wrote analysis/x.md" >/dev/null
  grep -qE '^- \*\*[0-9-]+ [0-9:]+\*\* · `analyze` — wrote analysis/x\.md$' "$tmp/demo/LOG.md" || die "selftest FAIL: custom log missing/wrong format"
  # Adopted pointer: inserted after One-liner when absent, then replaced in place (idempotent).
  grep -q '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" && die "selftest FAIL: Adopted line present before adopt"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" adopted demo "1 unit — see context/ADOPTED.md" >/dev/null
  grep -q '^- \*\*Adopted:\*\* 1 unit — see context/ADOPTED.md$' "$tmp/demo/README.md" || die "selftest FAIL: Adopted not inserted"
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*Adopted:\*\*' || die "selftest FAIL: Adopted not anchored after One-liner"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" adopted demo "2 units — see context/ADOPTED.md" >/dev/null
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
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" init demo >/dev/null
  [ -f "$RFC" ] || die "selftest FAIL: rfc init did not create rfc/RFC.md"
  grep -q '^# RFC: demo$' "$RFC" || die "selftest FAIL: rfc init did not stamp the project slug"
  [ -f "$META" ] || die "selftest FAIL: rfc init did not also create rfc/META.md"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc init (no backend arg) did not default META.md's Backend to markdown"
  printf '\nmanual edit\n' >> "$RFC"                          # simulate a human/agent edit
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" init demo >/dev/null
  grep -q '^manual edit$' "$RFC" || die "selftest FAIL: rfc init clobbered an existing RFC.md"

  # rfc init <slug> <backend>: on a FRESH project (no rfc/ yet), stamps the REAL backend into
  # META.md from the start — this is the actual regression test for the bug above.
  mkdir -p "$tmp/backend-check"
  printf -- '- **Status:** context\n- **One-liner:** <x>\n' > "$tmp/backend-check/README.md"
  : > "$tmp/backend-check/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" init backend-check lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$tmp/backend-check/rfc/META.md" || die "selftest FAIL: rfc init <slug> lark did not stamp the real backend"

  # rfc target: upserts Target on the ALREADY-EXISTING META.md (from rfc init above), sets Target;
  # a 2nd call with a different ref replaces in place (still exactly one Target: line) without
  # touching Backend.
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" target demo "https://example.com/doc/1" >/dev/null
  grep -q '^- \*\*Target:\*\* https://example.com/doc/1$' "$META" || die "selftest FAIL: rfc target not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" target demo "https://example.com/doc/2" >/dev/null
  [ "$(grep -c '^- \*\*Target:\*\*' "$META")" = "1" ] || die "selftest FAIL: rfc target duplicated instead of replaced"
  grep -q '^- \*\*Target:\*\* https://example.com/doc/2$' "$META" || die "selftest FAIL: rfc target not updated"
  grep -q '^- \*\*Backend:\*\* markdown$' "$META" || die "selftest FAIL: rfc target touched an unrelated field"

  # rfc state: round-trips for each allowed field; an unknown field is rejected and leaves the
  # file untouched (same idiom as the backward-status-move guard above).
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo Backend lark >/dev/null
  grep -q '^- \*\*Backend:\*\* lark$' "$META" || die "selftest FAIL: rfc state Backend not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo Wave1Published yes >/dev/null
  grep -q '^- \*\*Wave 1 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave1Published not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo Wave2Published yes >/dev/null
  grep -q '^- \*\*Wave 2 published:\*\* yes$' "$META" || die "selftest FAIL: rfc state Wave2Published not set"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo LastRevision 42 >/dev/null
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rfc state LastRevision not set"
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo Bogus x >/dev/null 2>&1; then
    die "selftest FAIL: rfc state accepted an unknown field"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" state demo CommentCursor thread-9 >/dev/null 2>&1; then
    die "selftest FAIL: rfc state still accepts the retired CommentCursor field"
  fi
  grep -q '^- \*\*Last revision pushed:\*\* 42$' "$META" || die "selftest FAIL: rejected rfc state call mutated the file"

  # rfc comment-seen: per-thread tracking (replaces the old single-scalar Comment cursor, which
  # couldn't tell "an earlier thread got new replies" from "already handled" once a later thread
  # became the recorded 'latest'). New thread → new row; re-seeing the SAME thread with a higher
  # reply count updates that row in place (no duplicate); flipping solved does the same.
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-A 1 no >/dev/null
  grep -q '^## Comment tracking' "$META" || die "selftest FAIL: comment-seen did not create the tracking section"
  grep -qF '<!-- pw-rfc-comment:thread-A -->' "$META" || die "selftest FAIL: thread-A row not created"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 1 | no ' || die "selftest FAIL: thread-A row has wrong reply-count/solved"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-B 1 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: expected 2 tracked threads after thread-B"
  # thread-A gets a 2nd reply later (the exact scenario the scalar cursor got wrong) → same row,
  # updated in place, still only 2 tracked threads total (no duplicate for thread-A).
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-A 2 no >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: re-seeing thread-A duplicated a row instead of updating in place"
  grep 'pw-rfc-comment:thread-A' "$META" | grep -q '| `thread-A` | 2 | no ' || die "selftest FAIL: thread-A reply-count not updated"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | no ' || die "selftest FAIL: thread-B wrongly changed by thread-A's update"
  # thread-B gets resolved externally → solved flips in place, still no duplicate.
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-B 1 yes >/dev/null
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: flipping solved duplicated thread-B's row"
  grep 'pw-rfc-comment:thread-B' "$META" | grep -q '| `thread-B` | 1 | yes ' || die "selftest FAIL: thread-B solved flag not updated"
  # validation: reply-count must be a non-negative integer, solved must be yes/no; a bad call is
  # rejected and doesn't touch existing rows.
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-C -1 no >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a negative reply-count"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" comment-seen demo thread-C 1 maybe >/dev/null 2>&1; then
    die "selftest FAIL: comment-seen accepted a non yes/no solved value"
  fi
  [ "$(grep -c 'pw-rfc-comment:' "$META")" = "2" ] || die "selftest FAIL: rejected comment-seen calls still mutated the tracking table"

# (ship comment-seen asserts moved to scripts/entities/pw-ship.sh + tests/cases/pw-ship.t.sh — plan 20)

  # rfc dashboard: inserted after Adopted: when one exists (demo already has one from the adopt
  # tests above); inserted after One-liner when no Adopted: line exists (a fresh project); a 2nd
  # call replaces in place (still exactly one RFC: line either way).
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" dashboard demo "wave 1 published — https://example.com/doc/2" >/dev/null
  grep -q '^- \*\*RFC:\*\* wave 1 published' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not inserted"
  grep -A1 '^- \*\*Adopted:\*\*' "$tmp/demo/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after Adopted:"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" dashboard demo "wave 2 published" >/dev/null
  [ "$(grep -c '^- \*\*RFC:\*\*' "$tmp/demo/README.md")" = "1" ] || die "selftest FAIL: RFC line duplicated instead of replaced"
  grep -q '^- \*\*RFC:\*\* wave 2 published$' "$tmp/demo/README.md" || die "selftest FAIL: RFC line not updated"

  mkdir -p "$tmp/demo2"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo2/README.md"
  : > "$tmp/demo2/LOG.md"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-rfc.sh" dashboard demo2 "wave 1 published" >/dev/null
  grep -A1 '^- \*\*One-liner:\*\*' "$tmp/demo2/README.md" | grep -q '^- \*\*RFC:\*\*' || die "selftest FAIL: RFC not anchored after One-liner when no Adopted: exists"

  # --- AI-assisted review -------------------------------------------------
  # ai-review: get on a project with no AI Review line yet auto-creates it, all-off; set updates
  # exactly one phase, leaving the other four untouched; invalid phase/mode rejected.
  local got_ai; got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=off task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review default line wrong: '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2 plan auto >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=off plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review set did not update only 'plan': '$got_ai'"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2 analysis advisory >/dev/null
  got_ai="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2)"
  [ "$got_ai" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: ai-review 2nd set clobbered the 1st: '$got_ai'"
  [ "$(grep -c '^- \*\*AI Review:\*\*' "$tmp/demo2/README.md")" = "1" ] || die "selftest FAIL: AI Review line duplicated"
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2 bogus-phase auto >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid phase"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2 plan bogus-mode >/dev/null 2>&1; then
    die "selftest FAIL: ai-review accepted an invalid mode"
  fi
  [ "$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-review demo2)" = "analysis=advisory plan=auto task-plan=off task-exec=off ship=off" ] || die "selftest FAIL: rejected ai-review calls still mutated the line"


  # --- model-check: empty/unset allowlist = all models allowed (the default rule) ---
  local mc
  mc="$(PW_MODEL_ALLOWLIST_CLAUDE="" "$HERE/scripts/entities/pw-config.sh" model-check claude some-random-model-nobody-configured)" \
    || die "selftest FAIL: model-check refused with an empty allowlist (should always pass)"
  echo "$mc" | grep -q "all models allowed" || die "selftest FAIL: model-check's empty-allowlist message didn't state the 'all models allowed' rule"
  # a configured allowlist passes a matching model...
  PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$HERE/scripts/entities/pw-config.sh" model-check claude sonnet >/dev/null \
    || die "selftest FAIL: model-check refused a model matching its configured allowlist"
  # ...glob patterns match...
  PW_MODEL_ALLOWLIST_KILO="command_code/deepseek/*" "$HERE/scripts/entities/pw-config.sh" model-check kilo command_code/deepseek/deepseek-v4-flash >/dev/null \
    || die "selftest FAIL: model-check refused a model matching a glob pattern in its allowlist"
  # ...and refuses one that doesn't, without silently passing.
  if PW_MODEL_ALLOWLIST_CLAUDE="sonnet,haiku" "$HERE/scripts/entities/pw-config.sh" model-check claude opus >/dev/null 2>&1; then
    die "selftest FAIL: model-check allowed a model NOT in its configured allowlist"
  fi
  # ...cursor provider (2026-09): the rules are provider-generic, but the bracket-param quirk is
  # cursor-specific and worth locking: catalog ids carry 'gpt-5.6-sol-high[effort=high]' style
  # suffixes; model-check's shell `case` GLOB treats a bracket literal-ish (char class), so docs
  # steer allowlist patterns to the suffix-free id part with '*' — here we assert the plain, glob,
  # and refuse paths so a future refactor can't silently change that contract.
  mc="$(PW_MODEL_ALLOWLIST_CURSOR="" "$HERE/scripts/entities/pw-config.sh" model-check cursor cursor-grok-4.6-low)" \
    || die "selftest FAIL: model-check refused cursor with an empty allowlist (should always pass)"
  PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*,gpt-5*" "$HERE/scripts/entities/pw-config.sh" model-check cursor gpt-5.6-sol >/dev/null \
    || die "selftest FAIL: model-check refused cursor model matching an allowlist glob"
  if PW_MODEL_ALLOWLIST_CURSOR="claude-opus-5*" "$HERE/scripts/entities/pw-config.sh" model-check cursor gpt-5.6-everything >/dev/null 2>&1; then
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
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" log logtest review "3 items resolved in analysis/review/x.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "1" ] || die "selftest FAIL: duplicate log entry was not deduped"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
  [ "$(grep -c '^- ' "$LT")" = "2" ] || die "selftest FAIL: a distinct message was wrongly deduped"
  sed -i '' -e 's/^- \*\*[^*]*\*\*/- **2020-01-01 00:00**/' "$LT"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" log logtest review "1 items resolved in analysis/review/y.review.md" >/dev/null
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

  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" dashboard-task-status demo T01 "accepted (MR merged)" >/dev/null
  grep -q '^| T01 | fix x | repo-a | accepted (MR merged) | |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status did not update the Status column"
  grep -q '^| T01 | repo-a | http://forge/x/-/merge_requests/12 | main | open | green |$' "$tmp/demo/README.md" \
    || die "selftest FAIL: dashboard-task-status leaked into the MR table"

  # (dashboard-mr-state asserts moved to scripts/entities/pw-ship.sh — plan 20)

  # failure path: a task with no row must fail loudly and leave the file untouched.
  local readme_before; readme_before="$(cat "$tmp/demo/README.md")"
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-status.sh" dashboard-task-status demo T99 done >/dev/null 2>&1; then
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
  local got_m; got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model default line wrong: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2 researcher kilo:command_code/x >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2)"
  [ "$got_m" = "researcher=kilo:command_code/x analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model set not isolated to researcher: '$got_m'"
  PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2 researcher — >/dev/null
  got_m="$(PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2)"
  [ "$got_m" = "researcher=— analyst=— writer-task=— reviewer=— verifier=—" ] \
    || die "selftest FAIL: ai-model clear-to-default failed: '$got_m'"
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2 executor claude:sonnet >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted the executor lane (the task file binds the executor)"
  fi
  if PW_PROJECTS_DIR="$tmp" "$HERE/scripts/entities/pw-config.sh" ai-model demo2 analyst sonnet-no-provider >/dev/null 2>&1; then
    die "selftest FAIL: ai-model accepted a row without <provider>:<model> form"
  fi
  grep -q '^- \*\*AI Models:\*\*' "$tmp/demo2/README.md" \
    || die "selftest FAIL: ai-model line vanished after clears"

  echo "selftest OK"
}

case "${1:-}" in
  selftest)    cmd_selftest ;;
  -h|--help|"") awk 'NR>1{ if ($0 ~ /^#/) { sub(/^# ?/, "", $0); print } else exit }' "$0" ;;
  *) die "unknown subcommand: $1 (try --help)" ;;
esac
