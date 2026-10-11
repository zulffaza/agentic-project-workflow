#!/usr/bin/env bash
# pw-help-usecases.sh — standalone use-case matrix for /pw-help: every view, every
# refusal, and the scope contract, against a live sample project. Not part of the
# T0–T4 tiers; run it on demand after touching pw-help.sh, the command files, or
# the scope metadata.
#   bash tooling/tests/pw-help-usecases.sh [repo-root] [results-dir]
# Creates $PW_PROJECTS/pw42-help-demo (scaffold + minimal context + one repo row),
# runs the matrix, captures each output under the results dir, prints a PASS/FAIL
# table. Removal hint for the sample project prints at the end.
set -u
WT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
OUT="${2:-$(mktemp -d "${TMPDIR:-/tmp}/pw-help-usecases.XXXXXX")}"
PROJECTS="${PW_PROJECTS_DIR:-$HOME/IdeaProjects/projects}"
export PW_PROJECTS_DIR="$PROJECTS"
export PW_PROJECTS="$PROJECTS"
export PW_HOME="$WT"
H="$WT/tooling/scripts/entities/pw-help.sh"
S="$WT/tooling/scripts/entities/pw-status.sh"
C="$WT/tooling/scripts/entities/pw-context.sh"
SC="$WT/tooling/scripts/toolchain/scaffold.sh"
PROJ=pw42-help-demo

rm -rf "$OUT"; mkdir -p "$OUT"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s — %s\n' "$1" "$2"; }

# run <label> <expected-rc> <cmd...> — capture stdout+stderr, check rc, save output
run() {
  local label="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" > "$OUT/$label.txt"
  if [ "$rc" = "$want" ]; then ok "$label (rc=$rc)"; else bad "$label" "rc=$rc want=$want"; fi
}

say() { printf '\n== %s\n' "$*"; }

say "setup: sample project $PROJ"
rm -rf "$PROJECTS/$PROJ"   # idempotent: rebuild the throwaway sample from scratch
bash "$SC" --project "$PROJ" > "$OUT/setup-scaffold.txt" 2>&1 || true
bash "$C" req-init --project "$PROJ" >> "$OUT/setup-scaffold.txt" 2>&1 || true
bash "$C" add-input --project "$PROJ" --file REQUIREMENTS.md --what 'project brief' --source 'written by the owner' >> "$OUT/setup-scaffold.txt" 2>&1 || true
bash "$C" add-repo --project "$PROJ" --repo demo-service --base main --why 'the one service this demo touches' >> "$OUT/setup-scaffold.txt" 2>&1 || true
bash "$PW_HOME/tooling/scripts/entities/pw-review.sh" init-all --project "$PROJ" > "$OUT/setup-review.txt" 2>&1 || true

say "1. overview (bare and explicit)"
run "overview-bare" 0 "$H"
run "overview-explicit" 0 "$H" overview
run "overview-json" 0 "$H" overview --json

say "2. command how-to"
run "command-help" 0 "$H" command --name pw-help
run "command-context" 0 "$H" command --name pw-context
run "command-config" 0 "$H" command --name pw-config
run "command-status" 0 "$H" command --name pw-status
run "command-review" 0 "$H" command --name pw-review
run "command-doctor" 0 "$H" command --name pw-doctor
run "command-with-project" 0 "$H" command --name pw-context --project "$PROJ"
run "command-json" 0 "$H" command --name pw-config --json
run "command-full" 0 "$H" command --name pw-context --full
run "command-maintainer" 0 "$H" command --name pw-review --maintainer
run "command-unknown" 2 "$H" command --name revieww
run "command-no-name" 2 "$H" command

say "3. operators deep dump"
run "operators-context" 0 "$H" operators --name pw-context
run "operators-review" 0 "$H" operators --name pw-review
run "operators-one" 0 "$H" operators --name pw-review --operator count
run "operators-lib-refused" 2 "$H" operators --name pw-common
run "operators-unknown" 2 "$H" operators --name revieww

say "4. project view"
run "project-view" 0 "$H" project --project "$PROJ"
run "project-command" 0 "$H" project --project "$PROJ" --name pw-review
run "project-command-mixed" 0 "$H" project --project "$PROJ" --name pw-config
run "project-json" 0 "$H" project --project "$PROJ" --json
run "project-unknown" 2 "$H" project --project ghost-not-here
run "project-no-flag" 2 "$H" project

say "5. workflow spine"
run "workflow" 0 "$H" workflow
run "workflow-json" 0 "$H" workflow --json

say "6. find"
run "find-hit" 0 "$H" find --term HUMAN-TRIGGERED
run "find-phrase" 0 "$H" find --term "named-argument"
run "find-zero" 0 "$H" find --term zqx-nothing-here-xyz
run "find-json" 0 "$H" find --term auto-signoff --json
run "find-no-term" 2 "$H" find

say "7. refusals and grammar"
run "unknown-op" 2 "$H" frobnicate
run "unknown-flag" 2 "$H" overview --frob
run "stray-positional" 2 "$H" command pw-context
run "json-shortcut" 0 "$H" --json

say "8. scope contract checks (greps)"
grep -q "Global Operations - no existing workflow project required" "$OUT/overview-bare.txt" && ok "global section header" || bad "global section header" missing
grep -q "Project Operations - explicitly select --project <project-slug>" "$OUT/overview-bare.txt" && ok "project section header" || bad "project section header" missing
grep -q "Create or Attach - an existing scaffold is not required" "$OUT/overview-bare.txt" && ok "create-or-attach label" || bad "create-or-attach label" missing
grep -q "\-\-all \[--attention\]" "$OUT/overview-bare.txt" && ok "pw-status --all under Global Operations" || bad "pw-status --all" missing
python3 - "$OUT/overview-json.txt" <<'PY' && ok "overview json: 17 cmds, scopes on every cmd+op" || bad "overview json scopes" "schema"
import json,sys
d=json.load(open(sys.argv[1]))
assert isinstance(d,list) and len(d)==17, len(d)
assert all(c.get("scope") in ("global","project","mixed") for c in d)
assert all(o.get("scope") in ("global","project") for c in d for o in c["ops"])
PY
grep -q "global forms (no project)" "$OUT/project-command-mixed.txt" && ok "mixed project view: global footer" || bad "mixed footer" missing
if grep -q "/pw-config <project-slug> global" "$OUT/command-config.txt"; then bad "no slug-prefixed global config form" "found"; else ok "no slug-prefixed global config form"; fi
python3 - "$OUT/project-json.txt" <<'PY' && ok "project json schema" || bad "project json" "schema"
import json,sys
d=json.load(open(sys.argv[1]))
assert {"slug","phase","status","targets","next","tasks"} <= set(d)
PY

say "9. no template-token leaks"
for f in "$OUT"/*.txt; do case "$f" in *setup-*) continue;; esac
  if grep -q '{{PW_' "$f"; then bad "leak $(basename "$f")" "{{PW_ token"; fi
done
ok "template-token scan done"

printf '\nRESULT: %s pass, %s fail  (outputs in %s)\n' "$pass" "$fail" "$OUT"
printf 'Cleanup later: rm -rf "%s" ; rm -rf "%s/%s"\n' "$OUT" "$PROJECTS" "$PROJ"
[ "$fail" = 0 ]
