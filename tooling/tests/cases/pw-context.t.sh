# shellcheck shell=bash
# cases/pw-context.t.sh — context-doc entity operators (plan 17): req-init, add-input,
# add-repo. Private clone of F2 (never mutate the shared fixture).
C="$TOOL/pw-context.sh"
CX=ctxedit; rm -rf "$PW_PROJECTS_DIR/$CX"; cp -a "$F2" "$PW_PROJECTS_DIR/$CX"
P="$PW_PROJECTS_DIR/$CX"
IDX="$P/context/INDEX.md"

# 1) req-init: creates from template, idempotent, never clobbers
rm -f "$P/context/REQUIREMENTS.md"
pwtest_rc 0 "req-init creates REQUIREMENTS.md" "$C" req-init "$CX"
[ -f "$P/context/REQUIREMENTS.md" ] && pwtest_ok "REQUIREMENTS.md exists" || pwtest_bad "req-init" "file missing"
printf '\nowner edits\n' >> "$P/context/REQUIREMENTS.md"
pwtest_rc 0 "req-init rerun (idempotent)" "$C" req-init "$CX"
grep -q 'owner edits' "$P/context/REQUIREMENTS.md" && pwtest_ok "req-init preserves existing brief" \
  || pwtest_bad "req-init clobber" "existing content lost"

# 2) add-input: replaces the empty placeholder row, A2 unquoted multi-word values, date auto
pwtest_rc 0 "add-input (A2 segments, unquoted prose)" "$C" add-input "$CX" --file spring-rfc.md --what Migration RFC excerpt --source Lark doc docs/xxxx --trust Approved RFC
pwtest_grep_file "^\| spring-rfc.md \| Migration RFC excerpt \| Lark doc docs/xxxx \| [0-9-]* \| Approved RFC \|" \
  "input row shape + auto date" "$IDX"
if grep -qE '^\|([[:space:]]*\|)+[[:space:]]*$' "$IDX"; then
  # the repos table still has its placeholder; the INPUTS table must not
  awk '/^\| File \/ link \|/{f=1} f && /^## /{exit} f' "$IDX" | grep -qE '^\|([[:space:]]*\|)+[[:space:]]*$' \
    && pwtest_bad "inputs placeholder" "empty placeholder row survived the first add-input" \
    || pwtest_ok "inputs placeholder replaced by first row"
else pwtest_ok "inputs placeholder replaced by first row"; fi
pwtest_rc 0 "add-input second (appends below)" "$C" add-input "$CX" --file notes.md --what 'my notes | draft' --source PROJ-123
pwtest_grep_file '^\| notes.md \| my notes \\\| draft \| PROJ-123 \| [0-9-]* \| — \|$' \
  "second row appends, pipe escaped, trust defaults to —" "$IDX"
_n="$(awk '/^\| File \/ link \|/{f=1} f && /^## /{exit} f && /^\|/ && !/^\|[-| ]+\|$/ && !/_e\.g\._/ && !/^\| File \/ link/' "$IDX" | grep -c .)"
if [ "$_n" = 2 ]; then
  pwtest_ok "inputs table has exactly the 2 added rows (e.g. row untouched)"
else pwtest_bad "inputs table row count" "got $_n want 2: $(awk '/^\| File \/ link \|/{f=1} f && /^## /{exit} f && /^\|/' "$IDX" | tr '\n' ';')"
fi
# _e.g._ example row must survive untouched
pwtest_grep_file '_e\.g\._ `spring-boot-3-rfc\.md`' "example row preserved" "$IDX"

# refusals
pwtest_rc 2 "add-input refuses missing --source" "$C" add-input "$CX" --file x.md --what y
pwtest_fix "missing-source refusal actionable"
pwtest_rc 2 "add-input refuses unknown flag" "$C" add-input "$CX" --file x.md --what y --source s --bogus b
pwtest_rc 2 "add-input refuses value-less flag" "$C" add-input "$CX" --file

# 3) add-repo: rest-of-line why, backticked repo/base, placeholder replaced
pwtest_rc 0 "add-repo (rest-of-line why)" "$C" add-repo "$CX" hera master Owns the Kafka producer config the RFC wants toggled
pwtest_grep_file '^\| `hera` \| `master` \| Owns the Kafka producer config the RFC wants toggled \|$' \
  "repo row shape (backticked repo/base, verbatim why)" "$IDX"
pwtest_rc 0 "add-repo second" "$C" add-repo "$CX" common-config master Shared toggle config
pwtest_rc 2 "add-repo refuses empty why" "$C" add-repo "$CX" hera master
pwtest_rc 2 "add-repo refuses too-few args" "$C" add-repo "$CX" hera

# 4) adopt marker rows are never touched (append below them)
python3 - "$IDX" <<'PY'
import sys
f = sys.argv[1]; t = open(f).read()
marker = "| `adopted-repo` | `master` | adopted row <!-- pw-adopt-scope:adopted-repo@master --> |\n"
# insert a fake adopt marker row right after the repos header separator
lines = t.split("\n")
for i, l in enumerate(lines):
    if l.startswith("| Repo (in"):
        lines.insert(i + 2, marker.rstrip("\n"))
        break
open(f, "w").write("\n".join(lines))
PY
pwtest_rc 0 "add-repo with marker rows present" "$C" add-repo "$CX" valas master Payment rails
if [ "$(grep -c 'pw-adopt-scope:adopted-repo@master' "$IDX")" = 1 ]; then
  pwtest_ok "adopt marker row preserved exactly once"
else pwtest_bad "adopt marker" "marker row count != 1"; fi
python3 - "$IDX" <<'PY'
import sys
t = open(sys.argv[1]).read().split("\n")
mi = next(i for i, l in enumerate(t) if "pw-adopt-scope:adopted-repo" in l)
vi = next(i for i, l in enumerate(t) if l.startswith("| `valas`"))
sys.exit(0 if vi > mi else 1)
PY
[ $? = 0 ] && pwtest_ok "new row appended below the marker row" || pwtest_bad "marker append order" "new row landed above the marker"

# 5) logged
grep -q 'added context input' "$P/LOG.md" && pwtest_ok "add-input logged" || pwtest_bad "add-input LOG" "nothing recorded"
grep -q 'added repo' "$P/LOG.md" && pwtest_ok "add-repo logged" || pwtest_bad "add-repo LOG" "nothing recorded"

rm -rf "$PW_PROJECTS_DIR/$CX"
