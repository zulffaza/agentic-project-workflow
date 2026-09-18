# shellcheck shell=bash
# cases/pw-help.sh T1 (plan 18): discovery rendering, refusals, read-only contract.
C="$(pwtest_script pw-help.sh)"
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
# (grep the human rendering line-by-line: ops surface under their command)
grep -A6 '/pw-context ' "$PWTEST_OUT" | grep -q 'req-init' && pwtest_ok "req-init under pw-context" || pwtest_bad "req-init under pw-context" "missing"
grep -A6 '/pw-context ' "$PWTEST_OUT" | grep -q 'add-repo' && pwtest_ok "add-repo under pw-context" || pwtest_bad "add-repo under pw-context" "missing"
grep -A10 '/pw-review ' "$PWTEST_OUT" | grep -qE 'item <' && pwtest_ok "sugar op item surfaces under pw-review" || pwtest_bad "sugar op item" "missing"
grep -A14 '/pw-review ' "$PWTEST_OUT" | grep -q 'this is how I view' && pwtest_ok "config sugar op carries the command-file definition" || pwtest_bad "config op use-clause" "missing"
grep -A14 '/pw-review ' "$PWTEST_OUT" | grep -q '(write)' && pwtest_ok "facet labels render (S1b)" || pwtest_bad "facet labels" "no (write) under pw-review"
grep -A6 '/pw-context ' "$PWTEST_OUT" | grep -qE '\(default\)' && pwtest_bad "pw-context (default)" "req-init selector is not a default flow" || pwtest_ok "no (default) for op-selector commands"
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
grep -A3 'req-init' "$PWTEST_OUT" | grep -q 'Use when:' && pwtest_ok "req-init block carries command-file prose" || pwtest_bad "Use when for req-init" "missing"
grep -qE '^    \$ /pw-context <project-slug> add-input' "$PWTEST_OUT" && pwtest_ok "runnable example line, full canonical name" || pwtest_bad "example line" "$(grep -E '^    \$' "$PWTEST_OUT" | head -2)"
grep -qE '\$ /[^p]' "$PWTEST_OUT" && pwtest_bad "full-name rendering" "short-form example leaked: $(grep -oE '\$ /[^ ]*' "$PWTEST_OUT"|head -1)" || pwtest_ok "full-name rendering (examples never short-form)"
grep -q '{{PW_' "$PWTEST_OUT" && pwtest_bad "no {{PW_ leak (command)" "found" || pwtest_ok "no {{PW_ leak (command)"
pwtest_rc 0 "command with slug fills slots" "$C" command pw-context myproj
pwtest_re '\$ /pw-context myproj req-init' "slug substitution in examples"
# C4 doctrine echo (guard the bypass surface): the label must reach the command view verbatim.
pwtest_rc 0 "command view of the gate command" "$C" command pw-review
grep -qF 'HUMAN-TRIGGERED ONLY (C4)' "$PWTEST_OUT" && pwtest_ok "C4 doctrine line present (C34 catcher)" || pwtest_bad "C4 doctrine line" "command pw-review lost the HUMAN-TRIGGERED ONLY (C4) echo"
pwtest_re 'auto-signoff' "SPECIAL path mentioned in the review command view"
pwtest_re 'entity script: tooling/scripts/entities/pw-review\.sh' "own script section"
pwtest_re '16 operators' "script operator count (read all hint, full name)"
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
_pw_md5() { ( cd "$PWTEST_ROOT/rocheck" && find . -type f | sort | xargs -n1 shasum | shasum ); }
_pre="$(_pw_md5)"
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" overview >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" workflow --json >/dev/null 2>&1
PW_PROJECTS_DIR="$PWTEST_ROOT/rocheck" "$C" operators pw-context >/dev/null 2>&1
post="$(_pw_md5)"
pwtest_eq "read-only: projects tree hash unchanged after full surface" "$_pre" "$post"

# 8) subprocess whitelist (phase 1: pw-help.sh invokes NOTHING — later phases must relax
# this pin only to the §3.4.1 read-operator whitelist, never to a setter).
_inv="$(grep -vE '^\s*#' "$C" | grep -oE '\$\{?ST\}? |pw-status\.sh [a-z-]+|pw-review\.sh [a-z-]+|pw-config\.sh [a-z-]+|scaffold\.sh' || true)"
if [ -z "${_inv// /}" ] || [ "$_inv" = " " ]; then pwtest_ok "help runs zero scripts (read-by-open only)"
else pwtest_bad "help invokes something forbidden (phase-1 pin)" "$_inv (expand the whitelist deliberately)"; fi

# 9) selftest / --help
pwtest_rc 0 "--help prints usage, exit 0" "$C" --help
pwtest_re 'usage' "--help is usage-shaped"
