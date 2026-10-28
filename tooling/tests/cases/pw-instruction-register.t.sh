# shellcheck shell=bash
# cases/pw-instruction-register.t.sh — the bounded instruction-consistency checker.
# Covers section resolution, required/retired text and malformed registers. The
# live register is also validated so a renamed owner section is not silent.
IR=pw-instruction-register
IRS="$PWTEST_TESTSDIR/instruction_register.sh"
IRD="$PWTEST_ROOT/$IR"
mkdir -p "$IRD/root/tooling/skills"

cat > "$IRD/root/tooling/skills/a.md" <<'EOF'
# A
intro
## Contract
delegate that work
## Other
unrelated
EOF

cat > "$IRD/root/tooling/skills/b.md" <<'EOF'
# B
owner records the result
EOF

_ir_write() { # <name> <body>
  printf '%s\n' "$2" > "$IRD/$1"
}

_ir_write pass.tsv '# instruction-register v1
I1	skills/a.md	Contract	skills/b.md	delegate that work	driver resolves it'

_ir_write missing-required.tsv '# instruction-register v1
I1	skills/a.md	Contract	skills/b.md	delegate nothing	-'

_ir_write missing-section.tsv '# instruction-register v1
I1	skills/a.md	Renamed	-	delegate that work	-'

_ir_write missing-owner.tsv '# instruction-register v1
I1	skills/nope.md	-	-	-	-'

_ir_write duplicate.tsv '# instruction-register v1
I1	skills/a.md	Contract	-	delegate that work	-
I1	skills/a.md	Contract	-	delegate that work	-'

_ir_write noheader.tsv 'I1	skills/a.md	Contract	-	delegate that work	-'

_ir_write short.tsv '# instruction-register v1
I1	skills/a.md	Contract	-	delegate that work'

_ir_write wholefile.tsv '# instruction-register v1
I1	skills/a.md	-	-	# A	-'

pwtest_rc 0 "valid register passes" bash "$IRS" check --register "$IRD/pass.tsv" --root "$IRD/root"
pwtest_rc 0 "whole-file rows with no retired pattern pass" bash "$IRS" check --register "$IRD/wholefile.tsv" --root "$IRD/root"

pwtest_rc 1 "missing required text refuses" bash "$IRS" check --register "$IRD/missing-required.tsv" --root "$IRD/root"
pwtest_err 'required text missing from skills/a.md' "missing required text has a precise diagnostic"

pwtest_rc 1 "renamed owner section refuses" bash "$IRS" check --register "$IRD/missing-section.tsv" --root "$IRD/root"
pwtest_err 'owner section not found or empty: Renamed' "missing section has a precise diagnostic"

pwtest_rc 1 "missing owner file refuses" bash "$IRS" check --register "$IRD/missing-owner.tsv" --root "$IRD/root"
pwtest_err 'owner file not found: skills/nope.md' "missing owner has a precise diagnostic"

pwtest_rc 1 "duplicate contract id refuses" bash "$IRS" check --register "$IRD/duplicate.tsv" --root "$IRD/root"
pwtest_err 'duplicate contract id' "duplicate id has a precise diagnostic"

pwtest_rc 1 "missing version header refuses" bash "$IRS" check --register "$IRD/noheader.tsv" --root "$IRD/root"
pwtest_err 'missing header' "missing header has a precise diagnostic"

pwtest_rc 1 "wrong column count refuses" bash "$IRS" check --register "$IRD/short.tsv" --root "$IRD/root"
pwtest_err 'expected 6 tab-separated fields' "column count has a precise diagnostic"

printf '%s\n' 'driver resolves it' >> "$IRD/root/tooling/skills/b.md"
pwtest_rc 1 "reintroduced retired text refuses" bash "$IRS" check --register "$IRD/pass.tsv" --root "$IRD/root"
pwtest_err 'retired text reappeared in skills/b.md' "retired text has a precise diagnostic"
printf '%s\n' '# B' 'owner records the result' > "$IRD/root/tooling/skills/b.md"

pwtest_rc 2 "missing register is an invocation error" bash "$IRS" check --register "$IRD/nope.tsv" --root "$IRD/root"

pwtest_rc 0 "the live instruction register is consistent" bash "$IRS" check
