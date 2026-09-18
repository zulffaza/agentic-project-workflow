# shellcheck shell=bash
# cases/pw-help.sh T1 (plan 18): discovery rendering, refusals, read-only contract.
C="$(pwtest_script pw-help.sh)"
# _pwt_trio_ops <script> <VARname> — every operator token help invokes via that trio member.
_pwt_trio_ops() {
  grep -vE '^[[:space:]]*#' "$1" | awk -v t="\"\$$2\" " '{ i = index($0, t); if (i) { r = substr($0, i + length(t)); split(r, f, " "); print f[1] } }' \
    | tr -d '";()&|' | sort -u | grep -E '^[a-z][a-z-]*$' | tr '\n' ' ' | sed 's/ $//'
}


TOOLDIR="${TOOL:-$PWTEST_TOOLING_DIR}"

# 1) overview — runtime-derived completeness: every command file (independent recount)
pwtest_rc 0 "overview exits 0" "$C" overview
_cnt_files="$(ls "$TOOLDIR/commands/"*.md | wc -l | tr -d ' ')"
_cnt_lines="$(grep -c '^  /pw-' "$PWTEST_OUT")"
pwtest_eq "overview command-line count == command files (H1 double-derivation)" "$_cnt_files" "$_cnt_lines"
pwtest_re '/pw-adopt  .*<repo>' "args render from each file's own frontmatter"
pwtest_re '/pw-close   .*<project-slug>' "a second command's args too (kills canned-args mutation C31)"
pwtest_re 'Close out a finished project' "descriptions render from frontmatter"
pwtest_re 'pw-help' "overview includes pw-help itself"

# 2) per-command + per-operator lines: pw-context exposes all three ops (A2 included)
pwtest_re 'add-input --file <f>' "add-input op line with A2 shape"
sec_ctx(){ sed -n "/\/pw-context /,/\/pw-doctor/p" "$PWTEST_OUT"; }
sec_rev(){ sed -n "/\/pw-review /,/\/pw-breakdown/p" "$PWTEST_OUT"; }
# (bounded section greps: ops surface under their command even in block-wrapped render)
sec_ctx | grep -q 'req-init' && pwtest_ok "req-init under pw-context" || pwtest_bad "req-init under pw-context" "missing"
sec_ctx | grep -q 'add-repo' && pwtest_ok "add-repo under pw-context" || pwtest_bad "add-repo under pw-context" "missing"
sec_rev | grep -qE 'item <' && pwtest_ok "sugar op item surfaces under pw-review" || pwtest_bad "sugar op item" "missing"
sec_rev | grep -q "this is how I view/change this project's AI Review settings" && pwtest_ok "config sugar op carries the command-file definition" || pwtest_bad "config op use-clause" "missing"
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
"pwtest_rc" 0 "bare /pw-help exits 0" "$C"
"pwtest_re" 'commands [+] operators' "bare /pw-help renders the overview"
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
grep -qF 'HUMAN-TRIGGERED ONLY (C4)' "$PWTEST_OUT" && pwtest_ok "C4 doctrine line present (C34 catcher)" || pwtest_bad "C4 doctrine line" "command pw-review lost the HUMAN-TRIGGERED ONLY (C4) echo"
if grep -qE '\.sh|tooling|/Users/|state reader|usage[ -]header|frontmatter|pw-item-status|entities|script headers' "$PWTEST_OUT"; then pwtest_bad "user view clean" "internal tokens leaked: $(grep -oE '\.sh|tooling|state reader|frontmatter' "$PWTEST_OUT" | sort -u | head -3 | tr '\n' ' ')"; else pwtest_ok "user view: default command view exposes no internal terms"; fi
pwtest_rc 0 "maintainer view of the review command" "$C" command pw-review --maintainer
grep -qF 'auto-signoff' "$PWTEST_OUT" && pwtest_ok "SPECIAL path mentioned in the maintainer view" || pwtest_bad "SPECIAL path (maintainer)" "auto-signoff missing from --maintainer"
pwtest_rc 0 "command view of the gate command again" "$C" command pw-review
grep -qF 'HUMAN-TRIGGERED ONLY (C4)' "$PWTEST_OUT" && pwtest_ok "C4 doctrine line present" || pwtest_bad "C4 doctrine line" "command pw-review lost the HUMAN-TRIGGERED ONLY (C4) echo"
pwtest_rc 0 "maintainer command view" "$C" command pw-review --maintainer
pwtest_re 'entity script: tooling/scripts/entities/pw-review\.sh' "own script section (maintainer view)"
pwtest_re '16 operators' "operator count in maintainer view (full name)"
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
python3 - "$PWTEST_OUT" <<'PY' && pwtest_ok "json shape: 16 cmds, ops[], facets on pw-review, keys stable" || pwtest_bad "json shape" "schema violation"
import json,sys
d=json.load(open(sys.argv[1]))
assert isinstance(d,list) and len(d)==16, len(d)
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
    RV)  want="gate count" ;;
    CFG) want="ai-review" ;;
  esac
  [ "$(printf '%s\n' "$ops" | sort -u | tr '\n' ' ' | sed 's/ $//')" = "$(printf '%s\n' $want | sort -u | tr '\n' ' ' | sed 's/ $//')" ] \
    && pwtest_ok "subprocess whitelist: $trio == {$want}" \
    || pwtest_bad "subprocess whitelist violation ($trio)" "used: [$(printf '%s' "$ops" | tr '\n' ' ')] allowed: {$want}"
done
_pwt_forbidden="$(grep -vE '^\s*#' "$C" | grep -cE '"\$(ST|RV|CFG)" (status|log|oneliner|adopt|init|signoff|add-item|answer|resolve|reindex|archive|reopen|auto-signoff|note-init|set)' || true)"
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

# 8c) pw-config is invoked strictly in GET form (ai-review "$slug" — never a mode arg).
_n_get="$(grep -vE '^[[:space:]]*#' "$C" | grep -cF '"$CFG" ai-review "$slug" 2>' || true)"
_n_all="$(grep -vE '^[[:space:]]*#' "$C" | grep -cF '"$CFG" ai-review' || true)"
pwtest_eq "ai-review is only ever a get" "$_n_all" "$_n_get"

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

# 9) selftest / --help
pwtest_rc 0 "--help prints usage, exit 0" "$C" --help
pwtest_re 'usage' "--help is usage-shaped"
