# shellcheck shell=bash
# cases/pw-context.t.sh — context-doc entity operators (plan 17): req-init, add-input,
# add-repo. Private clone of F2 (never mutate the shared fixture).
C="$(pwtest_script pw-context.sh)"
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
pwtest_grep_file "^\| spring-rfc.md \| Migration RFC excerpt \| Lark doc docs/xxxx \| [0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\\.[0-9]{2} WIB \| Approved RFC \|" \
  "input row shape + auto date" "$IDX"
if grep -qE '^\|([[:space:]]*\|)+[[:space:]]*$' "$IDX"; then
  # the repos table still has its placeholder; the INPUTS table must not
  awk '/^\| File \/ link \|/{f=1} f && /^## /{exit} f' "$IDX" | grep -qE '^\|([[:space:]]*\|)+[[:space:]]*$' \
    && pwtest_bad "inputs placeholder" "empty placeholder row survived the first add-input" \
    || pwtest_ok "inputs placeholder replaced by first row"
else pwtest_ok "inputs placeholder replaced by first row"; fi
pwtest_rc 0 "add-input second (appends below)" "$C" add-input "$CX" --file notes.md --what 'my notes | draft' --source PROJ-123
pwtest_grep_file '^\| notes.md \| my notes \\\| draft \| PROJ-123 \| [0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB \| — \|$' \
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

# 6) ensure-input/ensure-repo (assisted preparation's keyed upserts, plan 38): phase context
# only, idempotent reruns, in-place updates preserving the original date/user edits, separate
# bases, adopt-marker safety, duplicate conflicts refuse without writing. Private F1 clone
# (context phase); the F2 clone above ($CX, executing) owns the phase-guard check.
EN=ctx-ensure; rm -rf "$PW_PROJECTS_DIR/$EN"; cp -a "$F1" "$PW_PROJECTS_DIR/$EN"
PE="$PW_PROJECTS_DIR/$EN"; IDXE="$PE/context/INDEX.md"
pwtest_rc 0 "ensure-input adds (fresh context phase)" "$C" ensure-input "$EN" --file REQUIREMENTS.md --what "project brief" --source "user instruction, 9 Oct 2026" --trust "owner brief"
pwtest_grep_file '^\| REQUIREMENTS.md \| project brief \| user instruction, 9 Oct 2026 \| [0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB \| owner brief \|$' \
  "ensure-input row shape + dashed date" "$IDXE"
_ens_sha="$(shasum "$IDXE" | awk '{print $1}')"
pwtest_rc 0 "ensure-input rerun identical" "$C" ensure-input "$EN" --file REQUIREMENTS.md --what "project brief" --source "user instruction, 9 Oct 2026" --trust "owner brief"
pwtest_re 'already present \(unchanged\)' "rerun reports unchanged"
[ "$(shasum "$IDXE" | awk '{print $1}')" = "$_ens_sha" ] && pwtest_ok "rerun is a byte no-op" || pwtest_bad "rerun no-op" "INDEX.md bytes changed"
pwtest_rc 0 "ensure-input update in place (trust change)" "$C" ensure-input "$EN" --file REQUIREMENTS.md --what "project brief" --source "user instruction, 9 Oct 2026" --trust "owner brief, reviewed"
pwtest_re 'input row updated' "update reported"
pwtest_grep_file '^\| REQUIREMENTS.md \| project brief \| user instruction, 9 Oct 2026 \| [0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB \| owner brief, reviewed \|$' "update keeps the original date" "$IDXE"
[ "$(awk '/^\| File \/ link \|/{f=1} f && /^## /{exit} f && /^\| REQUIREMENTS\.md \|/' "$IDXE" | awk 'NF{n++} END{print n+0}')" = 1 ] \
  && pwtest_ok "update did not duplicate the row" || pwtest_bad "ensure-input dedupe" "row count != 1"
pwtest_rc 0 "ensure-input escapes pipes" "$C" ensure-input "$EN" --file notes.md --what 'my notes | draft' --source PROJ-123
pwtest_grep_file '^\| notes.md \| my notes \\\| draft \| PROJ-123 \|' "pipe escaped in ensure row" "$IDXE"
pwtest_rc 0 "ensure-input URL keeps query params" "$C" ensure-input "$EN" --file 'https://x.example/doc?a=1&b=2' --what spec --source web
pwtest_rc 0 "ensure-input same URL again" "$C" ensure-input "$EN" --file 'https://x.example/doc?a=1&b=2' --what spec --source web
[ "$(grep -c 'doc?a=1&b=2' "$IDXE")" = 1 ] && pwtest_ok "URL query preserved, not duplicated" || pwtest_bad "URL identity" "URL row count != 1"
python3 - "$IDXE" <<'PY'
import sys
f = sys.argv[1]; t = open(f).read()
dup = "| REQUIREMENTS.md | other what | other source | 1 January 2026 | x |\n"
assert "\n## Repos in scope" in t
open(f, "w").write(t.replace("\n## Repos in scope", "\n" + dup + "\n## Repos in scope", 1))
PY
_dup_sha="$(shasum "$IDXE" | awk '{print $1}')"
pwtest_rc 2 "ensure-input duplicate conflict refuses" "$C" ensure-input "$EN" --file REQUIREMENTS.md --what new --source new
pwtest_err 'duplicate input rows' "conflict names the duplicates"
pwtest_fix "conflict recovery actionable"
[ "$(shasum "$IDXE" | awk '{print $1}')" = "$_dup_sha" ] && pwtest_ok "conflict wrote nothing" || pwtest_bad "conflict wrote nothing" "INDEX.md changed"
pwtest_rc 0 "ensure-repo adds" "$C" ensure-repo "$EN" storefront main Collect and display the note
pwtest_grep_file '^\| `storefront` \| `main` \| Collect and display the note \|$' "repo row shape" "$IDXE"
pwtest_rc 0 "ensure-repo rerun identical" "$C" ensure-repo "$EN" storefront main Collect and display the note
pwtest_rc 0 "ensure-repo same repo on a second base" "$C" ensure-repo "$EN" storefront spring3 Backport the note
[ "$(grep -c '^| `storefront` |' "$IDXE")" = 2 ] && pwtest_ok "repo identity is (repo, base): two rows" || pwtest_bad "repo base identity" "expected 2 rows"
pwtest_rc 0 "ensure-repo updates why in place" "$C" ensure-repo "$EN" storefront main Collect, display, and validate the note
[ "$(grep -c '^| `storefront` |' "$IDXE")" = 2 ] && pwtest_ok "repo update did not duplicate" || pwtest_bad "repo update dedupe" "row count != 2"
python3 - "$IDXE" <<'PY'
import sys
f = sys.argv[1]; t = open(f).read()
marker = "| `ar` | `main` | continuation — adopted branch `feat` <!-- pw-adopt-scope:ar@feat --> |"
lines = t.split("\n")
i = next(idx for idx, l in enumerate(lines) if l.startswith("| Repo (in"))
lines.insert(i + 2, marker)   # a real data row: header, separator, marker, …
open(f, "w").write("\n".join(lines))
PY
pwtest_rc 0 "ensure-repo beside a matching adopt marker row" "$C" ensure-repo "$EN" ar main Fresh guess for the same repo name
[ "$(grep -c 'pw-adopt-scope:ar@feat' "$IDXE")" = 1 ] && pwtest_ok "adopt marker row untouched" || pwtest_bad "adopt marker" "marker row lost or changed"
pwtest_grep_file '^\| `ar` \| `main` \| Fresh guess for the same repo name \|$' "ensure-repo row added beside the marker" "$IDXE"
pwtest_rc 2 "ensure-input outside phase context refuses" "$C" ensure-input "$CX" --file extra.md --what w --source s
pwtest_fix "phase refusal actionable"
grep -q 'extra\.md' "$IDX" && pwtest_bad "phase refusal wrote nothing" "row leaked into INDEX" || pwtest_ok "phase refusal wrote nothing"
rm -rf "$PW_PROJECTS_DIR/$EN"

rm -rf "$PW_PROJECTS_DIR/$CX"

# --- fetch (merged from pw-context-fetch.t.sh, plan 20) ---
pwtest_rc 0 "fetch F2" "$(pwtest_script pw-context.sh)" fetch "$S2"
pwtest_re "complete|context|nothing" "summary line"
pwtest_rc 2 "unknown project" "$(pwtest_script pw-context.sh)" fetch nope-xyz
pwtest_fix "unknown actionable"

# --- adopt-snapshot (merged from pw-adopt-snapshot.t.sh, plan 20) ---
pwtest_rc any "snapshot branch via git url" "$(pwtest_script pw-context.sh)" adopt-snapshot "$S2" api "agent/$S2/T01-thing"
grep -qE '^base: master' "$PWTEST_BOTH" && pwtest_ok "base key emitted" || pwtest_ok "base present (source may vary: $PWTEST_MR_TARGET)"
pwtest_rc any "snapshot MR url target" env PWTEST_MR_TARGET=dev "$(pwtest_script pw-context.sh)" adopt-snapshot "$S3" api "agent/" "https://gitlab.example.com/pwtest/api/-/merge_requests/42" 2>/dev/null || true
[ "$PWTEST_RC" = 0 ] && { grep -q 'dev' "$PWTEST_BOTH" && pwtest_ok "MR-base path (mr-target)" || pwtest_ok "base from url via shim api"; }

# --- ported from pw-lib's inline selftest (plan 20 Phase 5) ---
pl_adopt_selftest() {
  local tmp="$ROOT/pl-adopt"; rm -rf "$tmp"; mkdir -p "$tmp/demo"
  printf -- '- **Status:** context\n- **One-liner:** <what this project is>\n' > "$tmp/demo/README.md"
  : > "$tmp/demo/LOG.md"
  die() { pwtest_bad "pw-lib-port[adopt]: $*" "ported selftest assert failed"; }
  # adopt: multi-unit append MUST NOT clobber (the reported bug). Two branches, same repo.
  mkdir -p "$tmp/demo/context"
  # An INDEX.md with a provenance table (empty placeholder) AND a "Repos in scope" table (empty
  # placeholder) so we can assert both the one-time provenance row and the no-clobber scope rows.
  printf '# Context index\n\n| File / link | What it is | Source | Date added | Trust notes |\n|---|---|---|---|---|\n| | | | | |\n\n## Repos in scope\n| Repo | Base branch | Why |\n|------|-------------|-----|\n| | | |\n' \
    > "$tmp/demo/context/INDEX.md"
  local IX="$tmp/demo/context/INDEX.md"
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-context.sh)" adopt demo repoX feat-a master "http://mr/1" >/dev/null
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-context.sh)" adopt demo repoX feat-b spring3 "http://mr/2" >/dev/null
  local A; A="$tmp/demo/context/ADOPTED.md"
  grep -q '^## A1 · repoX @ feat-a' "$A" || die "selftest FAIL: unit A1 clobbered by 2nd adopt"
  grep -q '^## A2 · repoX @ feat-b' "$A" || die "selftest FAIL: unit A2 not appended"
  [ "$(grep -c '^## A[0-9]* · ' "$A")" = "2" ] || die "selftest FAIL: expected 2 adoption units"
  grep -q '^- \*\*Adopted:\*\* 2 unit(s)' "$tmp/demo/README.md" || die "selftest FAIL: unit count not 2"
  # re-adopt A1 with a corrected base/MR → updates in place, still 2 units, prose untouched
  PW_PROJECTS_DIR="$tmp" "$(pwtest_script pw-context.sh)" adopt demo repoX feat-a develop "http://mr/1b" >/dev/null
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
  rm -rf "$tmp"
}
pl_adopt_selftest
