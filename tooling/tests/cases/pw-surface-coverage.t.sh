# shellcheck shell=bash
# cases/pw-surface-coverage.t.sh — the prompt-surface coverage ledger checker.
# Covers discovery symmetry, required text, harness-selector resolution, gap
# accounting and malformed ledgers. The live ledger is also validated so a new
# uncovered surface is not silent.
SC=pw-surface-coverage
SCS="$PWTEST_TESTSDIR/surface_coverage.sh"
SCD="$PWTEST_ROOT/$SC"
mkdir -p "$SCD"/root/tooling/skills/human/a "$SCD"/root/tooling/skills/model/m/references \
         "$SCD"/root/tooling/agents "$SCD"/root/tooling/tests/cases

cat > "$SCD/root/tooling/skills/human/a/SKILL.md" <<'EOF'
# A entry
Read the `pw-orchestration` skill first.
EOF
cat > "$SCD/root/tooling/agents/pw-worker.md" <<'EOF'
# worker
Read-only.
EOF
cat > "$SCD/root/tooling/skills/model/m/SKILL.md" <<'EOF'
# model skill
EOF
cat > "$SCD/root/tooling/skills/model/m/references/r.md" <<'EOF'
# reference
EOF
printf '%s\n' 'grep -qF "shared ladder" "$X"' > "$SCD/root/tooling/tests/static.sh"
printf '%s\n' '# case' > "$SCD/root/tooling/tests/cases/a.t.sh"

_sc_write() { # <name> <body>
  printf '%s\n' "$2" > "$SCD/$1"
}

_ROW_A='entry	skills/human/a/SKILL.md	pw-orchestration	T1:a	-'
_ROW_W='worker	agents/pw-worker.md	-	gap	role text has no case yet'
_ROW_M='model-skill	skills/model/m/SKILL.md	-	T4:shared ladder	-'
_ROW_R='reference	skills/model/m/references/r.md	-	T4:shared ladder	-'

SC_HEAD='# surface-coverage v1 gaps=1'

_sc_write pass.tsv "$SC_HEAD
$_ROW_A
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write unmapped.tsv "$SC_HEAD
$_ROW_A
$_ROW_W
$_ROW_M"

_sc_write stale.tsv "$SC_HEAD
$_ROW_A
$_ROW_W
$_ROW_M
$_ROW_R
reference	skills/model/m/references/gone.md	-	gap	removed file"

_sc_write missing-required.tsv "$SC_HEAD
entry	skills/human/a/SKILL.md	pw-orchestration is loaded here	T1:a	-
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write missing-case.tsv "$SC_HEAD
entry	skills/human/a/SKILL.md	pw-orchestration	T1:nope	-
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write missing-canary.tsv "$SC_HEAD
$_ROW_A
$_ROW_W
$_ROW_M
reference	skills/model/m/references/r.md	-	T4:a phrase no canary carries	-"

_sc_write gap-drift.tsv '# surface-coverage v1 gaps=0
'"$_ROW_A
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write gap-nonote.tsv "$SC_HEAD
$_ROW_A
worker	agents/pw-worker.md	-	gap	-
$_ROW_M
$_ROW_R"

_sc_write bad-kind.tsv "$SC_HEAD
reference	skills/human/a/SKILL.md	pw-orchestration	T1:a	-
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write duplicate.tsv "$SC_HEAD
$_ROW_A
$_ROW_A
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write noheader.tsv "$_ROW_A
$_ROW_W
$_ROW_M
$_ROW_R"

_sc_write short.tsv "$SC_HEAD
entry	skills/human/a/SKILL.md	pw-orchestration
$_ROW_W
$_ROW_M
$_ROW_R"

pwtest_rc 0 "complete ledger passes" bash "$SCS" check --ledger "$SCD/pass.tsv" --root "$SCD/root"

pwtest_rc 1 "a discovered surface with no row refuses" bash "$SCS" check --ledger "$SCD/unmapped.tsv" --root "$SCD/root"
pwtest_err 'discovered surface has no ledger row' "unmapped surface has a precise diagnostic"

pwtest_rc 1 "a row with no matching surface refuses" bash "$SCS" check --ledger "$SCD/stale.tsv" --root "$SCD/root"
pwtest_err 'ledger row has no matching surface' "stale row has a precise diagnostic"

pwtest_rc 1 "missing required text refuses" bash "$SCS" check --ledger "$SCD/missing-required.tsv" --root "$SCD/root"
pwtest_err 'required text missing' "missing required text has a precise diagnostic"

pwtest_rc 1 "an unmapped T1 case refuses" bash "$SCS" check --ledger "$SCD/missing-case.tsv" --root "$SCD/root"
pwtest_err 'harness case not found: nope' "missing case has a precise diagnostic"

pwtest_rc 1 "a dead T4 canary phrase refuses" bash "$SCS" check --ledger "$SCD/missing-canary.tsv" --root "$SCD/root"
pwtest_err 'T4 canary phrase not found' "dead canary phrase has a precise diagnostic"

pwtest_rc 1 "a widened gap count refuses" bash "$SCS" check --ledger "$SCD/gap-drift.tsv" --root "$SCD/root"
pwtest_err 'surface count changed' "gap drift has a precise diagnostic"

pwtest_rc 1 "a gap row without a note refuses" bash "$SCS" check --ledger "$SCD/gap-nonote.tsv" --root "$SCD/root"
pwtest_err 'a gap row must explain the residual risk' "unexplained gap has a precise diagnostic"

pwtest_rc 1 "a kind that contradicts the path refuses" bash "$SCS" check --ledger "$SCD/bad-kind.tsv" --root "$SCD/root"
pwtest_err 'does not match its path' "kind/path mismatch has a precise diagnostic"

pwtest_rc 1 "a duplicate surface row refuses" bash "$SCS" check --ledger "$SCD/duplicate.tsv" --root "$SCD/root"
pwtest_err 'duplicate ledger row' "duplicate row has a precise diagnostic"

pwtest_rc 1 "a missing version header refuses" bash "$SCS" check --ledger "$SCD/noheader.tsv" --root "$SCD/root"
pwtest_err 'missing header' "missing header has a precise diagnostic"

pwtest_rc 1 "a short row refuses" bash "$SCS" check --ledger "$SCD/short.tsv" --root "$SCD/root"
pwtest_err 'expected 5 tab-separated fields' "short row has a precise diagnostic"

pwtest_rc 2 "missing ledger is an invocation error" bash "$SCS" check --ledger "$SCD/nope.tsv" --root "$SCD/root"

pwtest_rc 0 "the live coverage ledger is consistent" bash "$SCS" check
