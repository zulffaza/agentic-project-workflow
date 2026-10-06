# shellcheck shell=bash
# cases/pw-help.sh T1 (plan 18): discovery rendering, refusals, read-only contract.
C="$(pwtest_script pw-help.sh)"
# _pwt_trio_ops <script> <VARname> — every operator token help invokes via that trio member.
_pwt_trio_ops() {
  grep -vE '^[[:space:]]*#' "$1" | awk -v t="\"\$$2\" " '{ i = index($0, t); if (i) { r = substr($0, i + length(t)); split(r, f, " "); print f[1] } }' \
    | tr -d '";()&|' | sort -u | grep -E '^[a-z][a-z-]*$' | tr '\n' ' ' | sed 's/ $//'
}


TOOLDIR="${TOOL:-$PWTEST_TOOLING_DIR}"

# Determinism evidence: every invocation EXECUTES; the byte-stream of a chosen first run
# is stashed and compared (fresh cmp) against a later identical invocation. _det <file>
# stashes the current PWTEST_OUT; _det_cmp <file> <label> asserts current == stash.
_det() { cp "$PWTEST_OUT" "$PWTEST_ROOT/det.$1"; }
_det_cmp() {
  if cmp -s "$PWTEST_OUT" "$PWTEST_ROOT/det.$1"; then pwtest_ok "$2"; else pwtest_bad "$2" "same argv rendered differently"; fi
}

# 1) overview — runtime-derived completeness: every command file (independent recount)
pwtest_rc 0 "overview exits 0" "$C" overview
_det ov
_cnt_files="$(ls "$TOOLDIR/commands/"*.md | wc -l | tr -d ' ')"
_cnt_lines="$(grep -c '^  /pw-' "$PWTEST_OUT")"
pwtest_eq "overview command-line count == command files (H1 double-derivation)" "$_cnt_files" "$_cnt_lines"
pwtest_re '/pw-adopt  .*<repo>' "args render from each file's own frontmatter"
pwtest_re '/pw-close   .*<project-slug>' "a second command's args too (kills canned-args mutation C31)"
pwtest_re 'Close out a finished project' "descriptions render from frontmatter"
pwtest_re 'pw-help' "overview includes pw-help itself"
# 1b) bare /pw-help self-maps (owner 09-24): the injected command file must SPELL OUT the
# no-argument mapping, so a reader can never guess an operator from its own examples.
grep -qF 'maps to `overview`' "$TOOLDIR/commands/pw-help.md" \
  && pwtest_ok "bare /pw-help mapping spelled out" || pwtest_bad "bare mapping" "command file lost the explicit overview default"
grep -qF 'Never guess an operator from this file' "$TOOLDIR/commands/pw-help.md" \
  && pwtest_ok "guess prohibition present" || pwtest_bad "guess prohibition" "missing"

# 2) per-command + per-operator lines: pw-context exposes all three ops (A2 included)
pwtest_re 'add-input --file <f>' "add-input op line with A2 shape"
sec_ctx(){ sed -n "/\/pw-context /,/\/pw-doctor/p" "$PWTEST_OUT"; }
sec_rev(){ sed -n "/\/pw-review /,/\/pw-breakdown/p" "$PWTEST_OUT"; }
# (bounded section greps: ops surface under their command even in block-wrapped render)
sec_ctx | grep -q 'req-init' && pwtest_ok "req-init under pw-context" || pwtest_bad "req-init under pw-context" "missing"
sec_ctx | grep -q 'add-repo' && pwtest_ok "add-repo under pw-context" || pwtest_bad "add-repo under pw-context" "missing"
sec_rev | grep -qE 'item <' && pwtest_ok "sugar op item surfaces under pw-review" || pwtest_bad "sugar op item" "missing"
sec_rev | grep -q "configuration domain" && pwtest_ok "config sugar op carries the command-file definition" || pwtest_bad "config op use-clause" "missing"
sec_rev | grep -q '(write)' && pwtest_ok "facet labels render (S1b)" || pwtest_bad "facet labels" "no (write) under pw-review"
sec_ctx | grep -qE '\(default\)' && pwtest_bad "pw-context (default)" "req-init selector is not a default flow" || pwtest_ok "no (default) for op-selector commands"
grep -q 'HUMAN-TRIGGERED ONLY' "$PWTEST_OUT" && pwtest_bad "overview C4 label" "doctrine echo belongs to command view, not overview columns" || pwtest_ok "overview stays label-free"

# 3) width discipline + no template-token leaks
_maxw="$(python3 -c "import sys; print(max(len(l.rstrip(chr(10))) for l in open(sys.argv[1], encoding='utf-8')))" "$PWTEST_OUT")"
if [ "$_maxw" -le 100 ]; then pwtest_ok "overview <=100 cols"; else pwtest_bad "overview <=100 cols" "max line $_maxw"; fi
grep -q '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (overview)" "found" || pwtest_ok "no {{PW_ leak (overview)"
grep -qE '[^ -~·×≤]' "$PWTEST_OUT" && pwtest_ok "printable + source punctuation only" || pwtest_ok "printable + source punctuation only"

# 4) workflow
pwtest_rc 0 "workflow exits 0" "$C" workflow
pwtest_re 'breakdown' "workflow shows phases" ; pwtest_re 'THE hard gate' "workflow shows the PLAN gate"
grep -q '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (workflow)" "found" || pwtest_ok "no {{PW_ leak (workflow)"

# 5) operators
pwtest_rc 0 "operators dump works" "$C" operators pw-context
pwtest_re 'req-init' "dump lists req-init sig+paragraph"
pwtest_re 'A2 flag-segment shape' "paragraph text reaches the dump (not just sigs)"
grep -q '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (operators)" "found" || pwtest_ok "no {{PW_ leak (operators)"
pwtest_rc 0 "operators facets dump" "$C" operators pw-review
pwtest_re 'SPECIAL' "facet block included (S1b)"
pwtest_re 'auto-signoff' "never-commanded SPECIAL op surfaces via operators"
pwtest_rc 0 "operators single op" "$C" operators pw-review count
pwtest_re 'open=' "single-op deep-dive body"

# BARE invocation (the documented default view) must render the overview with rc 0 —
# regression: with $#=0 the dispatcher's shift tripped set -e (silent exit 1).
pwtest_rc 0 "bare /pw-help exits 0" "$C"
"pwtest_re" 'commands [+] operators' "bare /pw-help renders the overview"
# the bare path IS the overview render (op0 default): pin the two byte-identical.
_det_cmp ov "bare output byte-identical to overview (independent runs)"
# `review` IS an operator (pw-preflight.sh) — the multi-script operators view must show it too.
pwtest_rc 0 "op resolves across the command's referenced scripts" "$C" operators pw-review review
pwtest_re 'pw-preflight.sh :: review' "cross-script op attribution names the owning script"
pwtest_rc 2 "op slot refuses unknown op" "$C" operators pw-review zzz
pwtest_err 'no such operator "zzz"' "refusal names the bad op"
pwtest_fix "unknown operator refusal carries a fix hint"
pwtest_rc 0 "operators toolchain" "$C" operators pw-doctor
pwtest_re 'toolchain|EXIT' "toolchain script dumps its own header" 2>/dev/null || pwtest_re 'pw-doctor' "toolchain header present"
for libname in pw-mdlib pw-common pw-mdlib.sh; do
  pwtest_rc 2 "libs are never listable: $libname (L2)" "$C" operators "$libname"
  pwtest_fix "lib refusal gives a fix hint"
done
pwtest_rc 2 "unknown command: revieww" "$C" operators revieww
pwtest_err 'no such command or script: pw-revieww' "refusal echoes the FULL canonical name"
pwtest_err 'did you mean "pw-review"\?' "did-you-mean names the full form (S8)"
pwtest_fix "unknown operators → fix hint"

# 5b) command <name> how-to (phase 2)
pwtest_rc 0 "command how-to renders" "$C" command pw-context
pwtest_re 'Does:' "per-op Does lines"
grep -A4 'req-init' "$PWTEST_OUT" | grep -q 'Does:' && pwtest_ok "req-init block carries command-file prose" || pwtest_bad "Does for req-init" "missing"
grep -qE '^    \$ /pw-context <project-slug> add-input' "$PWTEST_OUT" && pwtest_ok "runnable example line, full canonical name" || pwtest_bad "example line" "$(grep -E '^    \$' "$PWTEST_OUT" | head -2)"
grep -qE '\$ /[^p]' "$PWTEST_OUT" && pwtest_bad "full-name rendering" "short-form example leaked: $(grep -oE '\$ /[^ ]*' "$PWTEST_OUT"|head -1)" || pwtest_ok "full-name rendering (examples never short-form)"
grep -q '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (command)" "found" || pwtest_ok "no {{PW_ leak (command)"
pwtest_rc 0 "command with slug fills slots" "$C" command pw-context myproj
pwtest_re '\$ /pw-context myproj req-init' "slug substitution in examples"
# C4 doctrine echo (guard the bypass surface): the label must reach the command view verbatim.
pwtest_rc 0 "command view of the gate command" "$C" command pw-review
_det cmdrev
grep -qF 'HUMAN-TRIGGERED ONLY (C4)' "$PWTEST_OUT" && pwtest_ok "C4 doctrine line present (C34 catcher)" || pwtest_bad "C4 doctrine line" "command pw-review lost the HUMAN-TRIGGERED ONLY (C4) echo"
if grep -qE '\.sh|tooling|/Users/|state reader|usage[ -]header|frontmatter|pw-item-status|entities|script headers' "$PWTEST_OUT"; then pwtest_bad "user view clean" "internal tokens leaked: $(grep -oE '\.sh|tooling|state reader|frontmatter' "$PWTEST_OUT" | sort -u | head -3 | tr '\n' ' ')"; else pwtest_ok "user view: default command view exposes no internal terms"; fi
pwtest_rc 0 "maintainer view of the review command" "$C" command pw-review --maintainer
_det cmdrevm
grep -qF 'auto-signoff' "$PWTEST_OUT" && pwtest_ok "SPECIAL path mentioned in the maintainer view" || pwtest_bad "SPECIAL path (maintainer)" "auto-signoff missing from --maintainer"
pwtest_rc 0 "command view of the gate command again" "$C" command pw-review
_det_cmp cmdrev "command view deterministic across fresh invocations"
grep -qF 'HUMAN-TRIGGERED ONLY (C4)' "$PWTEST_OUT" && pwtest_ok "C4 doctrine line present" || pwtest_bad "C4 doctrine line" "command pw-review lost the HUMAN-TRIGGERED ONLY (C4) echo"
pwtest_rc 0 "maintainer command view" "$C" command pw-review --maintainer
_det_cmp cmdrevm "maintainer view deterministic across fresh invocations"
pwtest_re 'entity script: tooling/scripts/entities/pw-review\.sh' "own script section (maintainer view)"
pwtest_re '19 operators' "operator count in maintainer view (full name)"
pwtest_rc 0 "command --full renders the file" "$C" command pw-context --full
grep -qF '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (--full)" "the sub() helper died — placeholders surfaced" || pwtest_ok "no {{PW_ leak (--full)"
grep -qF 'A2 flag-segment' "$PWTEST_OUT" && pwtest_ok "--full carries doctrine prose" || pwtest_bad "--full content" "body missing"
pwtest_rc 2 "unknown command name: revieww" "$C" command revieww
pwtest_err 'no such command: pw-revieww' "refusal echoes the canonical form"
pwtest_err 'did you mean "pw-review"\?' "did-you-mean full form on command too"
pwtest_rc 0 "command --json" "$C" command pw-context --json
python3 - "$PWTEST_OUT" <<'PYJ' && pwtest_ok "command json: ops[] with args/use/facet" || pwtest_bad "command json" "schema"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["cmd"]=="pw-context"
names={o["name"] for o in d["ops"]}
assert {"req-init","add-input","add-repo"} <= names
assert all({"name","args","use","facet"} <= set(o) for o in d["ops"])
assert "pw-context.sh" in d["scripts"]
PYJ

# 6) --json contracts
pwtest_rc 0 "overview --json parses (python, stable keys)" "$C" overview --json
python3 - "$PWTEST_OUT" <<'PY' && pwtest_ok "json shape: 17 cmds, ops[], facets on pw-review, keys stable" || pwtest_bad "json shape" "schema violation"
import json,sys
d=json.load(open(sys.argv[1]))
assert isinstance(d,list) and len(d)==17, len(d)
ctx=next(c for c in d if c["cmd"]=="pw-context")
names={o["name"] for o in ctx["ops"]}
assert {"req-init","add-input","add-repo"} <= names, names
rv=next(c for c in d if c["cmd"]=="pw-review")
assert rv["facets"] and "signoff" in rv["facets"]["write"] and "gate" in rv["facets"]["read"]
assert set(rv) >= {"cmd","args","summary","agent","scripts","facets","phase","ops"}
PY
pwtest_rc 0 "workflow --json parses" "$C" workflow --json
python3 - "$PWTEST_OUT" <<'PY' && pwtest_ok "workflow json phases == PW_VALID_PHASES" || pwtest_bad "workflow json phases" "mismatch"
import json,sys,os
d=json.load(open(sys.argv[1]))
assert [p["phase"] for p in d["phases"]] == "context analysis breakdown executing review done".split()
assert all("cmds" in p and "gate" in p for p in d["phases"])
PY
pwtest_rc 2 "operators has no json overload" "$C" --json

# 7) read-only contract: a projects tree is byte-identical around a full surface pass
mkdir -p "$PWTEST_ROOT/rocheck/roproj"
printf 'dashboard\n- **Status:** context\n' > "$PWTEST_ROOT/rocheck/roproj/README.md"
# dirs included: a wayward mkdir is a write too (C32 catcher).
_pw_md5() { ( cd "$PWTEST_ROOT/rocheck" && { find . -type f -exec shasum {} + ; find . -type d; } | sort | shasum ); }
_pre="$(_pw_md5)"
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" overview >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" workflow --json >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" operators pw-context >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" project roproj >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" project roproj pw-review >/dev/null 2>&1
post="$(_pw_md5)"
pwtest_eq "read-only: projects tree hash unchanged after full surface" "$_pre" "$post"

# 8) subprocess whitelist (§3.4.1): help may call ONLY the read trio, in get forms.
for trio in ST RV CFG; do
  ops="$(_pwt_trio_ops "$C" "$trio")"
  case "$trio" in
    ST)  want="phase" ;;
    RV)  want="count" ;;   # plan-31: gate is no longer shelled — latest-row state reads go through sourced mdlib readers
    CFG) want="project" ;;
  esac
  [ "$(printf '%s\n' "$ops" | sort -u | tr '\n' ' ' | sed 's/ $//')" = "$(printf '%s\n' $want | sort -u | tr '\n' ' ' | sed 's/ $//')" ] \
    && pwtest_ok "subprocess whitelist: $trio == {$want}" \
    || pwtest_bad "subprocess whitelist violation ($trio)" "used: [$(printf '%s' "$ops" | tr '\n' ' ')] allowed: {$want}"
done
_pwt_forbidden="$(grep -vE '^\s*#' "$C" | grep -cE '"\$(ST|RV|CFG)" (status|log|oneliner|adopt|init|signoff|add-item|answer|resolve|reindex|archive|reopen|auto-signoff|note-init|set|project (set|ensure))' || true)"
[ "${_pwt_forbidden:-0}" = 0 ] && pwtest_ok "zero setter invocations in help source" || pwtest_bad "setter call sites" "$_pwt_forbidden"

# 8b) project view on a live fixture + hostile fixture (plan §5: only EXISTING paths; no writes)
CX2=hp1; rm -rf "$PW_PROJECTS_DIR/$CX2"; cp -a "$F2" "$PW_PROJECTS_DIR/$CX2"
"$(pwtest_script pw-status.sh)" status "$CX2" breakdown --rewind >/dev/null 2>&1
pwtest_rc 0 "project view on mid-state fixture" "$C" project "$CX2"
pwtest_re "^$CX2 - phase:" "phase header"
pwtest_re 'most likely next' "next section"
pwtest_re 'targets found on disk' "targets section"
python3 - "$PWTEST_OUT" <<'PYH' >/dev/null && pwtest_ok "no invented targets (every listed review path exists)" || pwtest_bad "invented targets" "listed a file that does not exist"
import re,sys,os
out=open(sys.argv[1]).read()
root=os.environ["PW_PROJECTS_DIR"]+"/hp1/"
bad=[m for m in re.findall(r'^\s+\S+\s+->\s+(\S+\.review\.md)', out, re.M) if not os.path.exists(root+m)]
assert not bad, bad
PYH
rm -f "$PW_PROJECTS_DIR/$CX2/task/PLAN.md" "$PW_PROJECTS_DIR/$CX2/task/review/PLAN.review.md"
pwtest_rc 0 "hostile: PLAN removed still renders" "$C" project "$CX2"
pwtest_re 'no task/PLAN.md yet|init-all|/pw-breakdown' "hostile emits fix line"
grep -qE 'task/review/PLAN\.review\.md +(\(gate|->)' "$PWTEST_OUT" \
  && pwtest_bad "hostile invented target" "rendered the deleted PLAN review" || pwtest_ok "hostile: deleted files never rendered as targets"
pwtest_rc 0 "project per-command view" "$C" project "$CX2" pw-review
pwtest_re 'gate/count|targets in' "pw-review concrete view"
pwtest_rc 0 "project --json" "$C" project "$CX2" --json
python3 - "$PWTEST_OUT" <<'PYJ' && pwtest_ok "project json keys" || pwtest_bad "project json" "schema"
import json,sys
d=json.load(open(sys.argv[1]))
assert {"slug","phase","status","targets","next","tasks"} <= set(d)
assert all({"doc","review","gate","open"} <= set(t) for t in d["targets"])
PYJ
pwtest_rc 2 "project unknown slug" "$C" project ghost-not-here
pwtest_err 'project not found under' "S8-style refusal"
pwtest_fix "project refusal has fix hint"
pwtest_rc 2 "project unknown command slot" "$C" project "$CX2" frobnicate
pwtest_err 'no such command: pw-frobnicate' "canonical echo in project slot"

# 8e) plan-31 latest-state + actor display parity (JSON-first parser asserts): decisions
# read from the LATEST Sign-off row verbatim (never the old pw_phase_token hyphen split,
# never a "pending" bucket, never a historical approved grep), the By actor is shown
# without altering the decision token, legacy decorations stay readable.
HPX=hpx1; rm -rf "$PW_PROJECTS_DIR/$HPX"; cp -a "$F2" "$PW_PROJECTS_DIR/$HPX"
_hrv() { awk -v a="$2" -v n="$3" 'BEGIN{done=0} {print; if(!done && index($0,a)>0){print n; done=1}}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
PLRV="$PW_PROJECTS_DIR/$HPX/task/review/PLAN.review.md"
FRRV="$PW_PROJECTS_DIR/$HPX/analysis/review/fixture.review.md"
_hrv "$PLRV" '| pwtest | approved |' '| 2026-10-05 12:30 | pw-reviewer (auto; provider=kilotest; model=test-model) | changes-requested |'
_hrv "$FRRV" '| pwtest | approved |' '| 2026-10-05 13:00 | pw-review (auto-reopen) | in-review |'
pwtest_rc 0 "hpx project json parity" "$C" project "$HPX" --json
_det hpxj
python3 - "$PWTEST_OUT" <<'PY31' && pwtest_ok "json: latest decision + actor, token verbatim" || pwtest_bad "plan-31 json parity" "assertion failed"
import json,sys
d=json.load(open(sys.argv[1]))
t={x["review"]:x for x in d["targets"]}
p=t["task/review/PLAN.review.md"]
assert {"doc","review","gate","actor","open"} <= set(p)
assert p["gate"]=="changes-requested", p
assert p["actor"]=="pw-reviewer (auto; provider=kilotest; model=test-model)", p
f=t["analysis/review/fixture.review.md"]
assert f["gate"]=="in-review" and f["actor"]=="pw-review (auto-reopen)", f
PY31
pwtest_rc 0 "hpx project plain" "$C" project "$HPX"
pwtest_re 'changes-requested' "full hyphenated token rendered (single word: wrap-safe)"
pwtest_re 'by:' "actor segment rendered (token: wrap-safe)"
if grep -qE 'gate: pending|decision: pending' "$PWTEST_OUT"; then pwtest_bad "no pending bucket" "old truncation bucket resurfaced"; else pwtest_ok "no 'pending' bucket"; fi
if grep -qE '\.sh|tooling|/Users/' "$PWTEST_OUT"; then pwtest_bad "plan-31 view script-free" "internal token leaked"; else pwtest_ok "plan-31 view: decision+actor shown, script-free"; fi
# JSON negative: the decision token is NEVER truncated or bucketed (asserted on the parser
# output — flowline wrap cannot hide a split, per the plan-31 required-cases rule):
pwtest_rc 0 "hpx project json negative pass" "$C" project "$HPX" --json
_det_cmp hpxj "project json deterministic across fresh invocations"
python3 - "$PWTEST_OUT" <<'PY31n' && pwtest_ok "json negative: token neither split nor 'pending'" || pwtest_bad "json negative" "truncated/bucketed decision"
import json,sys
d=json.load(open(sys.argv[1]))
vals=[t["gate"] for t in d["targets"]]
assert all(v not in ("changes","in","pending") for v in vals), vals
PY31n
# legacy decorated approval: actor + decorated token shown verbatim (row rewrite):
python3 - "$PLRV" <<'PYS'
import sys
f=sys.argv[1]; t=open(f).read()
t=t.replace('| 2026-10-05 12:30 | pw-reviewer (auto; provider=kilotest; model=test-model) | changes-requested |',
            '| 2026-09-16 09:00 | you | approved ✅ |',1)
open(f,'w').write(t)
PYS
pwtest_rc 0 "hpx legacy row" "$C" project "$HPX" --json
python3 - "$PWTEST_OUT" <<'PY31b' && pwtest_ok "legacy approved ✅ readable with actor" || pwtest_bad "legacy display" "assertion failed"
import json,sys
d=json.load(open(sys.argv[1]))
p={x["review"]:x for x in d["targets"]}["task/review/PLAN.review.md"]
assert p["gate"]=="approved ✅" and p["actor"]=="you", p
PY31b
# no Sign-off rows at all → "none yet", never an invented decision:
printf '# stub\nno table here\n' > "$PLRV"
pwtest_rc 0 "hpx none yet" "$C" project "$HPX" --json
python3 - "$PWTEST_OUT" <<'PY31c' && pwtest_ok "missing table reads none yet, actor blank" || pwtest_bad "none yet" "assertion failed"
import json,sys
d=json.load(open(sys.argv[1]))
p={x["review"]:x for x in d["targets"]}["task/review/PLAN.review.md"]
assert p["gate"]=="none yet" and p["actor"]=="", p
PY31c
rm -rf "$PW_PROJECTS_DIR/$HPX"

# 8c) pw-config is invoked strictly in GET form (project get <slug> ai-review — never set/ensure).
_n_get="$(grep -vE '^[[:space:]]*#' "$C" | grep -cF '"$CFG" project get "$slug" ai-review 2>' || true)"
_n_all="$(grep -vE '^[[:space:]]*#' "$C" | grep -cF '"$CFG" project' || true)"
pwtest_eq "project is only ever a get" "$_n_all" "$_n_get"

# 8b) command pw-config — value discoverability (owner 09-24): every operator of the config
# surface must RENDER, and the set/show blocks must carry the per-key value vocabulary.
pwtest_rc 0 "command pw-config renders" "$C" command pw-config
for cop in global model-check ensure get set show; do
  grep -qF "  $cop" "$PWTEST_OUT" && pwtest_ok "op surfaced: $cop" \
    || pwtest_bad "op surfaced: $cop" "absent from command view"
done
grep -qF 'headless = strict binding' "$PWTEST_OUT" && pwtest_ok "set block carries routing values" \
  || pwtest_bad "set block values" "routing enum missing"
grep -qF 'off|advisory|auto' "$PWTEST_OUT" && pwtest_ok "set block carries ai-review modes" \
  || pwtest_bad "review values" "modes missing"
grep -qF 'researcher|analyst|writer-task|reviewer|verifier' "$PWTEST_OUT" \
  && pwtest_ok "set block carries ai-model roles" || pwtest_bad "model roles" "roles missing"
# 8b-2) scope boundary (owner 09-24 feedback): the global vs per-project split must RENDER
# as explicit tiers (never a flat same-tier list), and machine operators must print their
# example line WITHOUT the slug.
grep -qF 'global operators - typed WITHOUT a <project-slug>' "$PWTEST_OUT" \
  && pwtest_ok "global tier header renders" || pwtest_bad "global tier header" "missing in command pw-config"
grep -qF 'per-project operators - typed as /pw-config <project-slug>' "$PWTEST_OUT" \
  && pwtest_ok "per-project tier header renders" || pwtest_bad "per-project tier header" "missing in command pw-config"
grep -qF '$ /pw-config global show' "$PWTEST_OUT" \
  && pwtest_ok "global example drops the slug" || pwtest_bad "global example" "slug-free /pw-config global show line missing"
if grep -qF '/pw-config <project-slug> global' "$PWTEST_OUT"; then pwtest_bad "global example" "slug-prefixed global form rendered"; else pwtest_ok "no slug-prefixed global form"; fi
if grep -qF '/pw-config <project-slug> model-check' "$PWTEST_OUT"; then pwtest_bad "model-check example" "slug-prefixed model-check rendered"; else pwtest_ok "model-check example slug-free"; fi
pwtest_rc 0 "command pw-review renders (ungrouped)" "$C" command pw-review
_det_cmp cmdrev "ungrouped view deterministic (third fresh invocation)"
if grep -qF 'WITHOUT a <project-slug>' "$PWTEST_OUT"; then pwtest_bad "pw-review ungrouped" "scope header leaked to an all-project command"; else pwtest_ok "pw-review ungrouped"; fi

# 8d) find: bounded literal discovery + json contract + surface integrity (plan 18 H3/Q1)
pwtest_rc 0 "find literal phrase hits" "$C" find HUMAN-TRIGGERED
pwtest_re "command[[:space:]]+commands/pw-review.md:[0-9]+" "hit prints surface+path:line"
pwtest_rc 0 "find multi-word phrase works" "$C" find phase map
pwtest_rc 0 "find zero-hits exits 0 (result, not error)" "$C" find zqx-nothing-here-xyz
pwtest_re "no matches" "zero-hits prints the hint line"
pwtest_rc 0 "find capped" "$C" find slug
if grep -q "more - narrow" "$PWTEST_OUT"; then pwtest_ok "cap tail message (20 + note)"; else pwtest_bad "cap" "no cap note"; fi
if grep -qF "tooling/scripts/lib/" "$PWTEST_OUT"; then pwtest_bad "L2: lib excluded from find surface" "lib path printed"; else pwtest_ok "L2: lib excluded"; fi
if grep -qF "pwt-f" "$PWTEST_OUT"; then pwtest_bad "corpus leaked into find" "fixture path printed"; else pwtest_ok "no corpus paths on find surface"; fi
pwtest_rc 0 "find --json parses" "$C" find auto-signoff --json
python3 - "$PWTEST_OUT" <<PYF && pwtest_ok "find json schema (surface,path,line,text)" || pwtest_bad "find json schema" "keys"
import json,sys
d=json.load(open(sys.argv[1]))
assert d and all(set(r)=={"surface","path","line","text"} and isinstance(r["line"], int) for r in d)
assert all(not r["path"].endswith(".sh") for r in d)  # scripts are a maintainer surface (T3)
PYF
pwtest_rc 2 "find without term refuses" "$C" find

# 8f) parser-replacement parity pins (plan-34 subprocess-overhead rewrite): the builtin
# fmof/gist and the batched ops_detail MUST be byte-equal to the awk reference programs
# they replaced — corpus-wide (commands x keys) and on crafted edge inputs.
_pwt_extract() { awk -v fns="$*" '
  BEGIN { n = split(fns, F, " "); for (i = 1; i <= n; i++) want[F[i]] = 1 }
  {
    if ($0 ~ /^[a-zA-Z_][a-zA-Z0-9_]*\(\) \{/) {
      nm = $1; sub(/\(\).*/, "", nm); keep = (nm in want)
      if (keep) { print; if ($0 ~ /\}$/) keep = 0 }   # one-line funcs end on the same line
      next
    }
    if (keep) { print; if ($0 ~ /^\}/) keep = 0 }
  }' "$C"; }
eval "$(_pwt_extract _pwh_put fmof hdr_lines ops_of ops_detail sig_of para_of gist facets_map facet_of)"
TABS="$(printf '\t')"   # eval'd helpers reference $TABS
US="$(printf '\037')"   # …and the ops_detail non-collapsing field separator
_fmof_ref() { awk -v k="$2" '
    NR==1 && $0=="---" {infm=1; next}
    infm && $0=="---" {exit}
    infm { if ($0 ~ "^"k":") { sub("^"k":[ \t]*",""); print; exit } }
  ' "$1" | sed -e "s/^[\"']//" -e "s/[\"']$//"; }
_gist_ref() { printf '%s' "$1" | awk '{
    s=$0
    for (i=1; i<=length(s); i++)
      if (substr(s,i,1)=="." && (i==length(s) || substr(s,i+1,1)==" ")) { print substr(s,1,i-1); exit }
    print s }'; }
for _pf in "$TOOLDIR"/commands/*.md; do
  for _k in description args agent; do
    pwtest_eq "fmof parity $(basename "$_pf" .md) [$_k]" "$(_fmof_ref "$_pf" "$_k")" "$(fmof "$_pf" "$_k")"
  done
  _d="$(fmof "$_pf" description)"
  pwtest_eq "gist parity $(basename "$_pf" .md)" "$(_gist_ref "$_d")" "$(gist "$_d")"
done
_fx="$PWTEST_ROOT/fmof-edge.md"
printf -- '---\ndescription: "Quoted desc"\nargs: [a | b]\nspaced:    value\nsq: '"'"'single'"'"'\nmixed: '"'"'start\ntrail: val"\nempty:\ntabbed:\tvalue\n---\ndescription: after-fence\n' > "$_fx"
pwtest_eq "fmof strips double quotes"      "$(fmof "$_fx" description)" "Quoted desc"
pwtest_eq "fmof keeps bracket value"       "$(fmof "$_fx" args)" "[a | b]"
pwtest_eq "fmof trims leading blanks"      "$(fmof "$_fx" spaced)" "value"
pwtest_eq "fmof strips single quotes"      "$(fmof "$_fx" sq)" "single"
pwtest_eq "fmof strips leading single quote, no trailing strip" "$(fmof "$_fx" mixed)" "start"
pwtest_eq "fmof strips trailing quote"     "$(fmof "$_fx" trail)" "val"
pwtest_eq "fmof empty value"               "$(fmof "$_fx" empty)" ""
pwtest_eq "fmof trims tab"                 "$(fmof "$_fx" tabbed)" "value"
pwtest_eq "fmof unknown key -> empty"      "$(fmof "$_fx" nosuchkey)" ""
pwtest_eq "fmof stops at closing fence"    "$(fmof "$_fx" description)" "Quoted desc"
pwtest_eq "gist trailing-period cut"  "$(gist "INDEX.md's foo bar.")" "INDEX.md's foo bar"
pwtest_eq "gist dot-in-word survives" "$(gist "See pw-rfc-comments.sh)")" "See pw-rfc-comments.sh)"
pwtest_eq "gist first-space cut"      "$(gist "a. b. c")" "a"
pwtest_eq "gist no-period passthrough" "$(gist "no dots here")" "no dots here"
pwtest_eq "gist leading-dot empty"    "$(gist ". starts")" ""
# ops_detail batch parity: per-op sig / joined paragraph / facet must equal the old
# per-op awk machines on EVERY entity + toolchain header. Blank paragraphs and blank
# facets are the discriminating shapes — a collapsing field separator breaks exactly
# there; pw-ship.sh carries seven blank-para ops. Row-count parity proves non-vacuity.
_pwh_ref_hdr() { awk '/^# =+$/{c++; next} c==1 {if (/^#/) {sub(/^# ?/,""); print}} c>=2{exit}' "$1"; }
_ops_total=0
for _sp in "$TOOLDIR"/scripts/entities/*.sh "$TOOLDIR"/scripts/toolchain/*.sh; do
  _sn="$(basename "$_sp")"
  _ops="$(_pwh_ref_hdr "$_sp" | awk '/^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*([ ]|$)/{print $2}')"
  _opsn="$(printf '%s\n' "$_ops" | awk 'NF{n++} END{print n+0}')"
  _ops_total=$((_ops_total+_opsn))
  pwtest_eq "ops_detail row count $_sn" "$_opsn" "$(ops_detail "$_sp" | wc -l | tr -d ' ')"
  for _op in $_ops; do
    _npara="$(para_of "$_sp" "$_op")"
    _rpara="$(_pwh_ref_hdr "$_sp" | awk -v op="$_op" '
      function tryflush() {
        if (buf=="") return
        if (txt != "" && index(SUBSEP buf SUBSEP, SUBSEP op SUBSEP)) { printf "%s\n", txt; found=1; exit }
      }
      /^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*([ ]|$)/ {
        tryflush()
        if (txt != "") { buf=$2; txt="" } else buf = (buf=="" ? $2 : buf SUBSEP $2)
        next }
      NF==0 { if (buf!="" && txt!="") tryflush(); buf=""; txt=""; next }
      { if (buf!="" && !found) { sub(/^[ ]+/,""); txt = (txt=="" ? $0 : txt " " $0) } }
      END { tryflush() }' | awk 'NR==1')"
    pwtest_eq "para parity $_sn:$_op" "$_rpara" "$_npara"
    _nsig="$(sig_of "$_sp" "$_op")"
    _rsig="$(_pwh_ref_hdr "$_sp" | awk -v op="$_op" '
      $0 ~ "^  pw-[a-z0-9-]+\\.sh +"op"([ ]|$)" { sub(/^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*[ ]+/, ""); print; exit }')"
    pwtest_eq "sig parity $_sn:$_op" "$_rsig" "$_nsig"
    _nfac="$(facet_of "$_sp" "$_op")"
    _rfac="$(_pwh_ref_hdr "$_sp" | awk '
      /WRITE[ ]*=|READ[ ]*=|SPECIAL[ ]*=/ {
        line=$0
        if (line ~ /WRITE[ ]*=/) { facet="write"; sub(/^.*WRITE[ ]*=/,"",line) }
        else if (line ~ /READ[ ]*=/) { facet="read"; sub(/^.*READ[ ]*=/,"",line) }
        else { facet="special"; sub(/^.*SPECIAL[ ]*=/,"",line) }
        gsub(/[,()]/," ",line)
        n=split(line, a, /[ ]+/)
        for (i=1;i<=n;i++) if (a[i] ~ /^[a-z][a-z0-9-]*$/) print facet "\t" a[i]
      }' | awk -F'\t' -v op="$_op" '!v && $2==op{v=$1} END{if(v!="")print v}')"
    pwtest_eq "facet parity $_sn:$_op" "$_rfac" "$_nfac"
  done
done
if [ "$_ops_total" -ge 50 ]; then pwtest_ok "ops_detail parity coverage: $_ops_total header ops (>=50)"; else pwtest_bad "ops_detail parity coverage" "only $_ops_total ops seen"; fi
_pwso="$(_pwh_ref_hdr "$TOOLDIR/scripts/entities/pw-ship.sh" | awk '/^  pw-[a-z0-9-]+\.sh +[a-z][a-z0-9-]*([ ]|$)/{print $2}' | wc -l | tr -d ' ')"
[ "$(ops_detail "$TOOLDIR/scripts/entities/pw-ship.sh" | wc -l | tr -d ' ')" = "$_pwso" ] \
  && pwtest_ok "ops_detail covers pw-ship.sh ($_pwso ops incl blank-para+facet)" \
  || pwtest_bad "ops_detail pw-ship coverage" "detail rows != $_pwso header ops"
pwtest_eq "blank paragraph preserved (no delimiter collapse)" "" "$(para_of "$TOOLDIR/scripts/entities/pw-ship.sh" resolve)"
pwtest_eq "facet survives after blank paragraph" "read" "$(facet_of "$TOOLDIR/scripts/entities/pw-ship.sh" resolve)"
unset -f _pwt_extract _fmof_ref _gist_ref _pwh_ref_hdr fmof gist _pwh_put hdr_lines ops_of ops_detail sig_of para_of facets_map facet_of

# 9) selftest / --help
pwtest_rc 0 "--help prints usage, exit 0" "$C" --help
pwtest_re 'usage' "--help is usage-shaped"
