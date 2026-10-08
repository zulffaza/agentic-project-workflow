# shellcheck shell=bash
# cases/pw-guidance.t.sh — command-only user guidance (plan 30): rendered outputs carry /pw-*
# recovery instead of script names, and the project-doctor --guidance engine previews without
# writing, applies exact-byte repairs idempotently, and refuses unsafe combinations. Works on
# private clones of F1/F2 (never the shared fixtures — C22).
E="$(pwtest_script pw-project-doctor.sh)"
CTX="$(pwtest_script pw-context.sh)"
REV="$(pwtest_script pw-review.sh)"
RFC="$(pwtest_script pw-rfc.sh)"
SHIP="$(pwtest_script pw-ship.sh)"
PF="$(pwtest_script pw-preflight.sh)"

# --- 1) req-init renders a command hint, not a script name (F1 clone) -------------------------
G1=guidance-f1; rm -rf "$PW_PROJECTS_DIR/$G1"; cp -a "$F1" "$PW_PROJECTS_DIR/$G1"
pwtest_rc 0 "req-init on fresh scaffold" "$CTX" req-init "$G1"
pwtest_re '/pw-context '"$G1"' add-input' "req-init hint names the command"
if grep -qF 'pw-context.sh' "$PWTEST_BOTH"; then pwtest_bad "req-init hint script-free" "pw-context.sh leaked"
else pwtest_ok "req-init hint script-free"; fi

# --- 2) missing-project die names /pw-new, not scaffold.sh ------------------------------------
pwtest_rc any "req-init missing project dies" "$CTX" req-init guidance-no-such-project
[ "$PWTEST_RC" != 0 ] && pwtest_ok "missing project refused" || pwtest_bad "missing project refused" "rc=0"
pwtest_err '/pw-new guidance-no-such-project' "missing-project hint names /pw-new"
if grep -qF 'scaffold.sh' "$PWTEST_ERR"; then pwtest_bad "missing-project hint script-free" "scaffold.sh leaked"
else pwtest_ok "missing-project hint script-free"; fi

# --- 3) ADOPTED.md header (F2 clone, adopt-snapshot like the battery row) ---------------------
G2=guidance-f2; rm -rf "$PW_PROJECTS_DIR/$G2"; cp -a "$F2" "$PW_PROJECTS_DIR/$G2"
P2="$PW_PROJECTS_DIR/$G2"
pwtest_repo api "branch:agent/$G2/T01-thing"   # the repo branch adopt records (fixture-slug-scoped)
pwtest_rc 0 "adopt seeds ADOPTED.md" "$CTX" adopt "$G2" api "agent/$G2/T01-thing" master
pwtest_grep_file 'managed by `/pw-adopt`' "ADOPTED.md header names the command" "$P2/context/ADOPTED.md"
if grep -qF 'pw-context.sh' "$P2/context/ADOPTED.md"; then pwtest_bad "ADOPTED.md header script-free" "pw-context.sh leaked"
else pwtest_ok "ADOPTED.md header script-free"; fi

# --- 4) archive sibling banner is actor-neutral (F2 clone: T04 review, add → resolve → archive) -
RV="task/review/T04.review.md"
pwtest_rc 0 "add item R1" "$REV" add-item "$G2" "$RV" --section '§4' --text guidance leak check item
pwtest_rc 0 "resolve R1" "$REV" resolve "$G2" "$RV" R1 --reply 'resolved for the banner check'
pwtest_rc 0 "archive R1" "$REV" archive "$G2" "$RV"
if grep -qF 'pw-review.sh' "$P2/task/review/T04.archive.md"; then pwtest_bad "archive banner script-free" "pw-review.sh leaked"
else pwtest_ok "archive banner script-free"; fi
pwtest_grep_file 'text preserved verbatim' "archive banner keeps the preservation promise" "$P2/task/review/T04.archive.md"

# --- 5) RFC META headers name /pw-rfc (F2 clone) -----------------------------------------------
pwtest_rc 0 "rfc init creates META" "$RFC" init "$G2" markdown
if grep -qF 'pw-rfc.sh' "$P2/rfc/META.md"; then pwtest_bad "META header script-free" "pw-rfc.sh leaked"
else pwtest_ok "META header script-free"; fi
pwtest_grep_file 'maintained via /pw-rfc' "META header names the command" "$P2/rfc/META.md"

# --- 6) MR comment tracking header names /pw-ship comments (F2 clone, T04 review) --------------
pwtest_rc 0 "comment-seen creates the tracking section" "$SHIP" comment-seen "$G2" T04 thr-guidance-1 resolvable yes
if grep -qF 'pw-ship.sh' "$P2/task/review/T04.review.md"; then pwtest_bad "MR tracking header script-free" "pw-ship.sh leaked"
else pwtest_ok "MR tracking header script-free"; fi
pwtest_grep_file 'maintained by /pw-ship comments' "MR tracking header names the command" "$P2/task/review/T04.review.md"

# --- 7) close gate hint is command-only (F2 clone: unaccepted tasks → rc 1) --------------------
pwtest_rc 1 "close gate refuses unaccepted tasks" "$PF" close "$G2"
pwtest_err 'accept' "close hint explains acceptance"
_closeleak="$(grep -E 'pw-status\.sh|pw-preflight\.sh' "$PWTEST_ERR" | head -1)"
[ -z "$_closeleak" ] && pwtest_ok "close hint script-free" || pwtest_bad "close hint script-free" "$_closeleak"

# --- 8) guidance engine: seeded legacy project (F2 clone) --------------------------------------
G3=guidance-legacy; rm -rf "$PW_PROJECTS_DIR/$G3"; cp -a "$F2" "$PW_PROJECTS_DIR/$G3"
P3="$PW_PROJECTS_DIR/$G3"
python3 - "$P3" <<'PY'
import sys
p = sys.argv[1]
def repl(path, old, new):
    f = p + "/" + path
    s = open(f, encoding="utf-8").read()
    assert old in s, "seed anchor missing in " + path
    open(f, "w", encoding="utf-8").write(s.replace(old, new, 1))
# context/README.md: new brief paragraph → legacy manual-copy paragraph
repl("context/README.md",
     "run `/pw-context <slug> req-init` to create `REQUIREMENTS.md` from its template, then fill it in\n"
     "(problem, goal, scope, constraints, success criteria) and register it:\n"
     "`/pw-context <slug> add-input --file REQUIREMENTS.md --what <one line> --source <where it came from>`.\n"
     "It's optional — the pipeline never requires it — but it sharpens the analysis phase.",
     "start a short brief: `cp _REQUIREMENTS.template.md REQUIREMENTS.md` and fill it (problem, goal,\n"
     "scope, constraints, success criteria). It's optional — the pipeline never requires it — but it\n"
     "sharpens the analysis phase. Add a row for it in [`INDEX.md`](./INDEX.md) like any other input.")
# task/PLAN.md: legacy task-accept hint (the template's acceptance bullet wraps across two lines —
# seed the legacy single-line form the engine rule actually matches)
repl("task/PLAN.md",
     "zero open review items — acceptance stays your\n  call; tell the agent to record it (one step syncs the task file + PLAN row + dashboard);",
     "zero open review items via `pw-status.sh task-accept`;")
# PROJECT.md: legacy ai-model comment line (F2 may not carry a dashboard — seed a minimal one)
import os
if not os.path.exists(p + "/PROJECT.md"):
    open(p + "/PROJECT.md", "w", encoding="utf-8").write(
        "# guidance-legacy\n\n- **Status:** executing\n  <!-- 🤖 set via `/pw-config <slug> ai-model <role> <provider:model>` — one row per spawn\n"
        "       See docs/EXECUTION.md §Spawning phase work + `pw-config.sh project ai-model`. -->\n")
else:
    repl("PROJECT.md",
         "set via `/pw-config <slug> set ai-model <role>=<provider:model>` — one row per spawn",
         "set via `/pw-config <slug> ai-model <role> <provider:model>` — one row per spawn")
    repl("PROJECT.md",
         "See docs/EXECUTION.md §Spawning phase work; set rows with `/pw-config <slug> set ai-model <role>=<provider:model>`.",
         "See docs/EXECUTION.md §Spawning phase work + `pw-config.sh project ai-model`.")
open(p + "/context/ADOPTED.md", "w", encoding="utf-8").write(
    "# Adopted work — guidance-legacy\n\nUnit headings/IDs + the Base/MR lines are managed by `pw-context.sh adopt` — do NOT hand-edit\n"
    "them or the dashboard; fill the prose under each unit. [🤖🧑 both]\n")
open(p + "/task/review/T01.review.md", "w", encoding="utf-8").write(
    "# Review — T01\n\n"
    "<!-- pw-contents:begin -->\n## Contents   [🤖-owned — regenerated by `pw-review.sh reindex`; never hand-edit]\n\n"
    "| ID | Section / anchor | Status |\n|----|-------------------|--------|\n| _(none yet)_ | | |\n<!-- pw-contents:end -->\n\n"
    "## MR comment tracking   [🤖-owned — never hand-edit; see `pw-ship.sh comment-seen`]\n\n"
    "| Thread | Kind | Replied | Notes |\n|--------|------|---------|-------|\n\n"
    "<!-- QUICK REFERENCE\n"
    "- **The `## Contents` table above is 🤖-owned** — heading-text-anchored (never a line number, so\n"
    "  it never goes stale on a rewrite), regenerated by `pw-review.sh reindex <slug> <this-file>`\n"
    "  after any edit that adds/resolves a heading. Applying ONE item only needs that item's own block\n"
    "  + the section(s) `## Contents` (or the doc's own analysis) names — never the whole file.\n"
    "- **Once several items are `[RESOLVED]`/`[ANSWERED]`, run `pw-review.sh archive <slug>\n"
    "  <this-file>`** — moves them verbatim into a sibling `<topic>.archive.md`, leaving a pointer row\n"
    "  in a `## Archived items` table (appears once anything's been archived). This never touches\n"
    "  `[OPEN]`/`[PENDING]` headings or the Sign-off table — see docs/REVIEW.md.\n"
    "- **Agents:** the `> **Add an item:**` / `> **Answer a question:**` hints are permanent — never\n"
    "  remove them, even once a section reads \"No blocking …\". Create this file via `pw-review.sh\n"
    "  init` (copies the template verbatim) — or `pw-review.sh init-all <slug>` for every\n"
    "  missing review file in the project at once — never by hand. -->\n\n"
    "> **Add an item:** easiest is the deterministic operator — `/pw-review <slug> item <this-file>\n"
    "> §4 <your ask, spaces and all>` (script: `pw-review.sh add-item`; it writes the heading,\n"
    "> timestamp, marker, `---` rule, and reindexes `## Contents` for you). By hand instead: start a\n\n"
    "> **Answer a question:** easiest is `/pw-review <slug> answer <this-file> Qn <your answer>`\n"
    "> (script: `pw-review.sh answer` — writes the styled `↳ you:` line under the question).\n\n"
    "## Archived items   [🤖-owned — see `pw-review.sh archive`; never hand-edit]\n\n"
    "| ID | Summary | Archived |\n|----|---------|----------|\n\n"
    "## Sign-off  (human only — an agent never writes here)\n\n"
    "Easiest: `/pw-review <slug> signoff <this-file> approved` (script: `pw-review.sh signoff` —\n"
    "stamps the date-time and appends the row; human-triggered only, an agent never runs it on its own\n"
    "initiative). By hand: fill the row below.\n\n"
    "- Reopening BY HAND (your own decision, not the auto-reopen above)? Add a new \"in-review\" row\n"
    "  (keep the old approval), `pw-status.sh status <slug> <phase> --rewind`, re-run the phase — see\n"
    "  README \"Going back a phase\".\n\n"
    "| By | Decision | When |\n|----|----------|------|\n| you | approved | 1 October 2026 10.00 WIB |\n")
open(p + "/analysis/review/topic.review.md", "w", encoding="utf-8").write(
    "# Review: topic.md\n\n<!-- pw-contents:begin -->\n## Contents   [🤖-owned — regenerated by `pw-review.sh reindex`; never hand-edit]\n\n"
    "| ID | Section / anchor | Status |\n|----|-------------------|--------|\n| _(none yet)_ | | |\n<!-- pw-contents:end -->\n\n"
    "- Reopening BY HAND (your own decision, not the auto-reopen above)? Add a new \"in-review\" row\n"
    "  (keep the old approval), `pw-status.sh status <slug> <phase> --rewind`, re-run the phase — see\n"
    "  README \"Going back a phase\".\n\n"
    "Easiest: `/pw-review <slug> signoff <this-file> approved` (script: `pw-review.sh signoff` —\n"
    "stamps the date-time and appends the row; human-triggered only, an agent never runs it on its own\n"
    "initiative). By hand: fill the row below.\n")
open(p + "/task/review/T01.archive.md", "w", encoding="utf-8").write(
    "# Archived review items — T01\n\nItems/questions moved out of `task/review/T01.review.md` once fully [RESOLVED]/[ANSWERED], by `pw-review.sh\n"
    "archive` — text preserved verbatim, never edited. See that file's \"## Archived items\"\ntable for one pointer row per entry moved here.\n")
open(p + "/rfc/META.md", "w", encoding="utf-8").write(
    "# RFC metadata — guidance-legacy   [🤖-owned — never hand-edit; see `pw-rfc.sh target|state`]\n\n"
    "- **Backend:** markdown\n\n## Comment tracking   [🤖-owned — never hand-edit; see `pw-rfc.sh comment-seen`]\n\n"
    "| Thread | Replies seen | Solved |\n|--------|--------------|--------|\n")
# preservation targets: machine-owned stack state + a custom human section
open(p + "/task/stack.tsv", "w", encoding="utf-8").write(
    "# pw-stack-state v1 — machine-owned; edit via pw-ship.sh stack-* operators\n"
    "task\t 零\t zero\n")
open(p + "/task/stack-ops.tsv", "w", encoding="utf-8").write("opkey\tstage\tancestors\topenc\n")
open(p + "/context/README.md", "a", encoding="utf-8").write("\n## Custom notes\n\nkeep me exactly\n")
PY
[ $? -eq 0 ] && pwtest_ok "legacy seeds applied" || pwtest_bad "legacy seeds applied" "python seeder failed"
for seeded in context/ADOPTED.md task/PLAN.md context/README.md task/review/T01.review.md task/review/T01.archive.md analysis/review/topic.review.md rfc/META.md task/stack.tsv task/stack-ops.tsv; do
  [ -f "$P3/$seeded" ] && pwtest_ok "seed present: $seeded" || pwtest_bad "seed present: $seeded" "missing before engine ran"
done

tree_sha() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256); }
SHA0="$(tree_sha "$P3")"

# stubs that fail loudly if anything touches the forge
STUB="$PWTEST_ROOT/forge-stubs"; mkdir -p "$STUB"
for s in gh glab; do printf '#!/bin/sh\necho "%s-shim: forge called during guidance" >&2\nexit 99\n' "$s" > "$STUB/$s"; chmod +x "$STUB/$s"; done

# preview: reports the repairs, writes NOTHING
pwtest_rc 0 "guidance preview rc" env PATH="$STUB:$PATH" "$E" "$G3" --guidance
pwtest_re 'would repair context/ADOPTED.md' "preview lists ADOPTED.md"
pwtest_re 'would repair context/README.md' "preview lists context/README.md"
pwtest_re 'would repair task/review/T01.review.md' "preview lists the review file"
pwtest_re 'would repair analysis/review/topic.review.md' "preview lists the analysis review"
pwtest_re 'would repair task/review/T01.archive.md' "preview lists the archive banner"
pwtest_re 'would repair task/PLAN.md' "preview lists PLAN"
pwtest_re 'guidance preview: .* repairable' "preview prints a summary"
[ "$(tree_sha "$P3")" = "$SHA0" ] && pwtest_ok "preview wrote nothing" || pwtest_bad "preview wrote nothing" "tree bytes changed"

# apply: exact replacements, everything else byte-identical
pwtest_rc 0 "guidance apply rc" env PATH="$STUB:$PATH" "$E" "$G3" --guidance --apply
pwtest_re 'repaired context/ADOPTED.md' "apply repairs ADOPTED.md"
pwtest_grep_file 'managed by `/pw-adopt`' "ADOPTED.md repaired" "$P3/context/ADOPTED.md"
if grep -qF 'pw-context.sh' "$P3/context/ADOPTED.md"; then pwtest_bad "ADOPTED.md leak gone" "old bytes remain"
else pwtest_ok "ADOPTED.md leak gone"; fi
if grep -qF 'pw-status.sh' "$P3/task/PLAN.md"; then pwtest_bad "PLAN leak gone" "old bytes remain"
else pwtest_ok "PLAN leak gone"; fi
pwtest_grep_file 'acceptance stays your call' "PLAN replacement present" "$P3/task/PLAN.md"
if grep -qF 'pw-ship.sh' "$P3/task/review/T01.review.md"; then pwtest_bad "review leak gone" "old bytes remain"
else pwtest_ok "review leak gone"; fi
pwtest_grep_file 'maintained by /pw-ship comments' "review replacement present" "$P3/task/review/T01.review.md"
if grep -qF 'pw-status.sh' "$P3/task/review/T01.review.md"; then pwtest_bad "review hint family leak gone" "pw-status.sh remains"
else pwtest_ok "review hint family leak gone"; fi
if grep -qF 'pw-review.sh' "$P3/task/review/T01.review.md"; then pwtest_bad "review hint prose script-free" "pw-review.sh remains"
else pwtest_ok "review hint prose script-free"; fi
pwtest_grep_file '`/pw-status <slug> rewind <phase>`' "rewind hint repaired" "$P3/task/review/T01.review.md"
pwtest_grep_file 'refreshed automatically by every write that adds or resolves a heading' "reindex hint repaired" "$P3/task/review/T01.review.md"
grep -qF '## Contents   [agent-owned; refreshed automatically; do not edit]' "$P3/task/review/T01.review.md" && pwtest_ok "contents stamp repaired" || pwtest_bad "contents stamp repaired" "old stamp remains"
grep -qF '## Archived items   [agent-owned; refreshed automatically; do not edit]' "$P3/task/review/T01.review.md" && pwtest_ok "archived-items heading repaired" || pwtest_bad "archived-items heading repaired" "old heading remains"
if grep -qF 'pw-status.sh' "$P3/analysis/review/topic.review.md"; then pwtest_bad "analysis review leak gone" "pw-status.sh remains"
else pwtest_ok "analysis review leak gone"; fi
if grep -qF 'pw-review.sh' "$P3/analysis/review/topic.review.md"; then pwtest_bad "analysis review prose script-free" "pw-review.sh remains"
else pwtest_ok "analysis review prose script-free"; fi
pwtest_grep_file '`/pw-status <slug> rewind <phase>`' "analysis rewind hint repaired" "$P3/analysis/review/topic.review.md"
if grep -qF ', by `pw-review.sh' "$P3/task/review/T01.archive.md"; then pwtest_bad "archive leak gone" "old bytes remain"
else pwtest_ok "archive leak gone"; fi
pwtest_grep_file 'text preserved verbatim' "archive keeps preservation sentence" "$P3/task/review/T01.archive.md"
if grep -qF 'pw-rfc.sh' "$P3/rfc/META.md"; then pwtest_bad "META leak gone" "old bytes remain"
else pwtest_ok "META leak gone"; fi
pwtest_grep_file 'maintained via /pw-rfc' "META replacement present" "$P3/rfc/META.md"
pwtest_grep_file 'keep me exactly' "custom section preserved" "$P3/context/README.md"
pwtest_grep_file '## Sign-off' "review sign-off table preserved" "$P3/task/review/T01.review.md"
pwtest_grep_file '\| you \| approved \|' "sign-off row preserved verbatim" "$P3/task/review/T01.review.md"
if grep -qE 'forge called during guidance' "$PWTEST_BOTH"; then pwtest_bad "no forge access" "a forge stub was invoked"
else pwtest_ok "no forge access (stubs silent)"; fi
[ "$(printf '%s' "$(cat "$P3/task/stack.tsv")")" = "$(printf '# pw-stack-state v1 — machine-owned; edit via pw-ship.sh stack-* operators\ntask\t 零\t zero')" ] \
  && pwtest_ok "stack.tsv byte-preserved" || pwtest_bad "stack.tsv byte-preserved" "state file changed"
SHA1="$(tree_sha "$P3")"

# idempotence: second apply changes nothing
pwtest_rc 0 "second apply rc" "$E" "$G3" --guidance --apply
pwtest_re 'guidance repair: 0 occurrence\(s\) replaced' "second apply repairs nothing"
[ "$(tree_sha "$P3")" = "$SHA1" ] && pwtest_ok "second apply is a byte no-op" || pwtest_bad "second apply no-op" "tree bytes changed"

# refusals: --guidance --fix and bare --apply
SHA2="$(tree_sha "$P3")"
pwtest_rc 2 "guidance refuses --fix combination" "$E" "$G3" --guidance --fix
pwtest_rc 2 "bare --apply refuses" "$E" "$G3" --apply
[ "$(tree_sha "$P3")" = "$SHA2" ] && pwtest_ok "refusals wrote nothing" || pwtest_bad "refusals wrote nothing" "tree bytes changed"

# customized text: a changed leak line is skipped, not forced
python3 - "$P3" <<'PY'
import sys
p = sys.argv[1] + "/context/ADOPTED.md"
s = open(p, encoding="utf-8").read().replace("fill the prose under each unit", "fill the prose under each unit (custom)")
open(p, "w", encoding="utf-8").write(s)
PY
pwtest_rc 0 "customized run rc" "$E" "$G3" --guidance
pwtest_re 'already repaired or customized' "customized text reported as skipped"
