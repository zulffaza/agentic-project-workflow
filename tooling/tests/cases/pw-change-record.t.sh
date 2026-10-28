# shellcheck shell=bash
# cases/pw-change-record.t.sh — the change requirement/evidence record checker.
# Proves the structural contract: ids, states, evidence references and the
# draft-vs-complete disposition rules. Semantic completeness stays a review duty.
CR=pw-change-record
CRS="$PWTEST_TESTSDIR/change_record.sh"
CRD="$PWTEST_ROOT/$CR"
mkdir -p "$CRD"

cat > "$CRD/ok.tsv" <<'EOF'
# change-record v1
R1	delegation delegates	delivered	passed	E1	accepted	
R2	docs updated	delivered	not-applicable	-	accepted	prose-only change
EOF

cat > "$CRD/ev.tsv" <<'EOF'
# evidence-record v1
E1	tooling/tests/pw_test.sh --tier T4	ddd7211+clean	T4	92 pass, 0 fail	0
EOF

cat > "$CRD/dup.tsv" <<'EOF'
# change-record v1
R1	first	delivered	passed	E1	accepted	
R1	second	delivered	passed	E1	accepted	
EOF

cat > "$CRD/gap.tsv" <<'EOF'
# change-record v1
R1	first	delivered	passed	E1	accepted	
R3	third	delivered	passed	E1	accepted	
EOF

cat > "$CRD/noev.tsv" <<'EOF'
# change-record v1
R1	unproven	delivered	passed	-	accepted	
EOF

cat > "$CRD/pending.tsv" <<'EOF'
# change-record v1
R1	still open	pending	pending	-	accepted	
EOF

cat > "$CRD/narrowed.tsv" <<'EOF'
# change-record v1
R1	reduced	partial	passed	E1	narrowed	
EOF

cat > "$CRD/na.tsv" <<'EOF'
# change-record v1
R1	not applicable	delivered	not-applicable	-	accepted	
EOF

cat > "$CRD/missev.tsv" <<'EOF'
# change-record v1
R1	unknown evidence	delivered	passed	E9	accepted	
EOF

cat > "$CRD/noheader.tsv" <<'EOF'
R1	headerless	delivered	passed	E1	accepted	
EOF

cat > "$CRD/short.tsv" <<'EOF'
# change-record v1
R1	five fields	delivered	passed	E1
EOF

cat > "$CRD/blocked.tsv" <<'EOF'
# change-record v1
R1	blocked path	partial	blocked	-	accepted	waiting on an external owner
EOF

cat > "$CRD/blocked-nonote.tsv" <<'EOF'
# change-record v1
R1	blocked path	partial	blocked	-	accepted	
EOF

pwtest_rc 0 "valid draft record passes" bash "$CRS" check --mode draft --record "$CRD/ok.tsv"
pwtest_rc 0 "valid complete record with evidence passes" bash "$CRS" check --mode complete --record "$CRD/ok.tsv" --evidence "$CRD/ev.tsv"

pwtest_rc 1 "duplicate requirement id refuses" bash "$CRS" check --record "$CRD/dup.tsv"
pwtest_err 'duplicate requirement id R1' "duplicate id has a precise diagnostic"

pwtest_rc 1 "non-contiguous requirement ids refuse" bash "$CRS" check --record "$CRD/gap.tsv"
pwtest_err 'contiguous from R1' "gap has a precise diagnostic"

pwtest_rc 1 "passed verification without evidence refuses" bash "$CRS" check --record "$CRD/noev.tsv"
pwtest_err 'passed verification needs at least one evidence id' "missing evidence has a precise diagnostic"

pwtest_rc 1 "complete mode rejects a pending implementation" bash "$CRS" check --mode complete --record "$CRD/pending.tsv"
pwtest_err 'complete mode requires a final implementation state' "pending state has a precise diagnostic"

pwtest_rc 1 "narrowed scope without a note refuses" bash "$CRS" check --record "$CRD/narrowed.tsv"
pwtest_err 'narrowed scope needs a note' "narrowed scope has a precise diagnostic"

pwtest_rc 1 "not-applicable verification without a reason refuses" bash "$CRS" check --record "$CRD/na.tsv"
pwtest_err 'not-applicable verification needs a note' "not-applicable reason has a precise diagnostic"

pwtest_rc 1 "undefined evidence id refuses" bash "$CRS" check --record "$CRD/missev.tsv" --evidence "$CRD/ev.tsv"
pwtest_err 'evidence id E9 is not defined' "undefined evidence has a precise diagnostic"

pwtest_rc 1 "missing version header refuses" bash "$CRS" check --record "$CRD/noheader.tsv"
pwtest_err 'missing header' "missing header has a precise diagnostic"

pwtest_rc 1 "wrong column count refuses" bash "$CRS" check --record "$CRD/short.tsv"
pwtest_err 'expected 7 tab-separated fields' "column count has a precise diagnostic"

pwtest_rc 0 "a noted blocked path is structurally valid" bash "$CRS" check --record "$CRD/blocked.tsv"
pwtest_rc 1 "blocked verification without a note refuses" bash "$CRS" check --record "$CRD/blocked-nonote.tsv"
pwtest_err 'blocked verification needs a note' "blocked note has a precise diagnostic"

pwtest_rc 2 "missing record file is an invocation error" bash "$CRS" check --record "$CRD/nope.tsv"

cat > "$CRD/badev.tsv" <<'EOF'
# evidence-record v1
E1	tooling/tests/pw_test.sh --tier T4	ddd7211+clean	T4		0
EOF
pwtest_rc 1 "evidence row without a result refuses" bash "$CRS" check --record "$CRD/ok.tsv" --evidence "$CRD/badev.tsv"
pwtest_err 'needs command, identity, selection and result' "empty evidence result has a precise diagnostic"

cat > "$CRD/pending-ev.tsv" <<'EOF'
# evidence-record v1
E1	bash tooling/tests/pw_test.sh --mutation all	ddd7211+working-tree	full register	pending	-
EOF

cat > "$CRD/passed-pending.tsv" <<'EOF'
# change-record v1
R1	unproven pass	delivered	passed	E1	accepted	
EOF
pwtest_rc 1 "a passed requirement cannot reference pending evidence" bash "$CRS" check --record "$CRD/passed-pending.tsv" --evidence "$CRD/pending-ev.tsv"
pwtest_err 'passed verification references pending evidence E1' "pending evidence has a precise diagnostic"

cat > "$CRD/bad-pending-exit.tsv" <<'EOF'
# evidence-record v1
E1	bash tooling/tests/pw_test.sh --mutation all	ddd7211+working-tree	full register	pending	0
EOF
pwtest_rc 1 "pending evidence with a numeric exit refuses" bash "$CRS" check --record "$CRD/ok.tsv" --evidence "$CRD/bad-pending-exit.tsv"
pwtest_err 'is pending but carries exit 0' "pending/exit mismatch has a precise diagnostic"

cat > "$CRD/bad-dash-result.tsv" <<'EOF'
# evidence-record v1
E1	bash tooling/tests/pw_test.sh --mutation all	ddd7211+working-tree	full register	done	-
EOF
pwtest_rc 1 "unrun evidence with a non-pending result refuses" bash "$CRS" check --record "$CRD/ok.tsv" --evidence "$CRD/bad-dash-result.tsv"
pwtest_err 'uses exit - but result is not pending' "dash/result mismatch has a precise diagnostic"
