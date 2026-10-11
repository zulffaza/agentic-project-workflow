# shellcheck shell=bash
# Security hardening — sink-gate refusals (plan 43, phase 1). Each check pins a guard so a
# later refactor cannot silently drop it; matching mutations.tsv rows bite on the same lines.
# Threat model: task-file fields, PLAN cells, and flag values are agent-authored (see
# tooling/docs/SECURITY.md); the guards refuse content before any path/git/arithmetic sink.
SEC=pwsec; SEC_DIR="$PW_PROJECTS_DIR/$SEC"; rm -rf "$SEC_DIR"; cp -a "$F2" "$SEC_DIR"
SH="$(pwtest_script pw-ship.sh)"; CFG="$(pwtest_script pw-config.sh)"
REV="$(pwtest_script pw-review.sh)"; WT="$(pwtest_script pw-worktree.sh)"; SES="$(pwtest_script pw-session.sh)"
pwtest_repo secrepo
PWN="$PWTEST_ROOT/pwsec-pwned"

# --- model-check: the provider token feeds ${!var}; a crafted token must be refused, never
# --- expanded. (On bash >= 4.3 the unguarded form evaluates the subscript as arithmetic.)
pwtest_rc 2 "model-check refuses a bracket-shaped provider token" "$CFG" model-check --provider "kilo[\$(touch $PWN)]" --model m
[ ! -e "$PWN" ] && pwtest_ok "crafted provider token never executed" || pwtest_bad "provider token executed" "sentinel created"
pwtest_err "invalid provider token" "model-check refusal names the token problem"
pwtest_rc 0 "model-check still accepts a plain provider token" "$CFG" model-check --provider kilotest --model test-model

# --- proj_dir: one component, physically inside the projects root (all entities share it).
pwtest_rc 2 "config get refuses a traversal slug" "$CFG" get --project ../out --key ai-review
pwtest_rc 2 "config get refuses a nested-path slug" "$CFG" get --project a/b --key ai-review
# Nested EXISTING path: a real project inside another project must still be refused by the
# one-component shape rule (a raw concatenation would happily resolve it).
cp -a "$F2" "$PW_PROJECTS_DIR/pwsec-outer"
cp -a "$F2" "$PW_PROJECTS_DIR/pwsec-outer/pwsec-inner"
pwtest_rc 2 "config get refuses a nested existing path" "$CFG" get --project pwsec-outer/pwsec-inner --key ai-review
rm -rf "$PW_PROJECTS_DIR/pwsec-outer"
# Symlinked slug resolving OUTSIDE the projects root: the physical pin refuses it even though
# the directory itself exists (and, mutated, the get would happily operate on the outside copy).
cp -a "$F2" "$PWTEST_ROOT/outside-proj"
ln -sfn "$PWTEST_ROOT/outside-proj" "$PW_PROJECTS_DIR/pwsec-escape"
pwtest_rc 2 "config get refuses a symlinked slug resolving outward" "$CFG" get --project pwsec-escape --key ai-review
rm -f "$PW_PROJECTS_DIR/pwsec-escape"

# --- exec: task-file Branch / Base / Repo values are content-gated before any git use.
printf 'probe\n' > "$PWTEST_ROOT/pwsec-desc"
cat > "$SEC_DIR/task/T90.md" <<'EOF'
# T90 — branch guard probe
- **Repo:** secrepo
- **Branch:** --force
- **Base branch:** master
EOF
pwtest_rc 2 "exec refuses a dash-leading Branch" "$SH" exec --project "$SEC" --task T90 --file "$PWTEST_ROOT/pwsec-desc"
pwtest_err "refusing unsafe Branch" "exec refusal names the Branch guard"
cat > "$SEC_DIR/task/T91.md" <<'EOF'
# T91 — repo containment probe
- **Repo:** secret
- **Branch:** agent/pwsec/T91-ok
- **Base branch:** master
EOF
pwtest_rc 2 "exec refuses an unknown Repo" "$SH" exec --project "$SEC" --task T91 --file "$PWTEST_ROOT/pwsec-desc"
mkdir -p "$PWTEST_ROOT/outside-repo"
ln -sfn "$PWTEST_ROOT/outside-repo" "$PW_REPOS/pwsec-evil"
cat > "$SEC_DIR/task/T91.md" <<'EOF'
# T91 — repo containment probe
- **Repo:** pwsec-evil
- **Branch:** agent/pwsec/T91-ok
- **Base branch:** master
EOF
pwtest_rc 2 "exec refuses a Repo resolving outside the repos dir" "$SH" exec --project "$SEC" --task T91 --file "$PWTEST_ROOT/pwsec-desc"
pwtest_err "repo path outside" "exec refusal names the containment rule"
rm -f "$PW_REPOS/pwsec-evil"

# --- monitor: --timeout reaches $(( )) — non-numeric values are refused before arithmetic.
# The probe task's MR host matches its repo origin, so with the gate mutated away the flow
# REACHES the arithmetic (and the sentinel proves execution) instead of dying for the wrong
# reason earlier (the S12 host pin).
cat > "$SEC_DIR/task/T93.md" <<'EOF'
# T93 — timeout guard probe
- **Repo:** secrepo
- **Branch:** agent/pwsec/T93-ok
- **Base branch:** master

## Result

- **MR:** https://gitlab.example.com/pwtest/secreto/-/merge_requests/9
EOF
pwtest_rc 2 "monitor refuses a non-numeric --timeout" "$SH" monitor --project "$SEC" --task T93 --timeout "q[\$(touch $PWN)]"
[ ! -e "$PWN" ] && pwtest_ok "timeout payload never executed" || pwtest_bad "timeout payload executed" "sentinel created"

# --- task-id gates: every CLI task id is a strict T0n token (no traversal, no glob, no ERE).
pwtest_rc 2 "mr-state refuses a traversal task id" "$SH" mr-state --project "$SEC" --task '../../PLAN'
pwtest_rc 2 "mr-state refuses a regex-shaped task id" "$SH" mr-state --project "$SEC" --task '.*'
pwtest_rc 2 "exec refuses a traversal task id" "$SH" exec --project "$SEC" --task '../x' --file "$PWTEST_ROOT/pwsec-desc"
pwtest_rc 2 "comment-seen refuses a traversal task id" "$SH" comment-seen --project "$SEC" --task '../x' --thread aaaa1111 --kind resolvable --replied yes
pwtest_rc 2 "dashboard-mr-state refuses a traversal task id" "$SH" dashboard-mr-state --project "$SEC" --task '../x' --state merged
pwtest_rc 2 "stack-plan refuses a traversal task id" "$SH" stack-plan --project "$SEC" --task 'T1/../x'
pwtest_rc 2 "stack-adopt refuses a traversal task id" "$SH" stack-adopt --project "$SEC" --task 'T1/../x'
pwtest_rc 2 "set pin refuses a traversal task id" "$CFG" set --project "$SEC" --key pin --set 'T1/../x=claude:opus'
pwtest_rc 2 "review prepare refuses a traversal task id" "$REV" prepare --project "$SEC" --task 'T12/../../x'
pwtest_err "prepare: --task expects a task id" "prepare refusal comes from the parse gate"
pwtest_rc 2 "worktree remove refuses a glob task" "$WT" remove --project "$SEC" --task '*'
pwtest_rc 2 "worktree create refuses a traversal repo" "$WT" create --project "$SEC" --task T01 --repo '../x' --base master
pwtest_rc 2 "worktree create refuses a traversal task" "$WT" create --project "$SEC" --task '../x' --repo secrepo --base master
pwtest_rc 2 "session task form refuses a traversal slug" "$SES" session-check --project '../x' --task T01
pwtest_rc 1 "session form refuses a traversal session id" "$SES" session-check --provider claude --session '../x'

# --- Phase 2: comment tracking rows are value-gated (| / newline forge columns, markers forge)
# The tracking target must EXIST first, or every call would fail for the wrong reason (a missing
# review file) and these guards could never bite.
"$(pwtest_script pw-review.sh)" init --project "$SEC" --file task/review/T01.review.md --doc task/T01.md >/dev/null 2>&1
pwtest_rc 2 "comment-seen refuses a traversal thread id" "$SH" comment-seen --project "$SEC" --task T01 --thread '../x' --kind resolvable --replied yes
pwtest_rc 2 "comment-seen refuses a pipe in --note" "$SH" comment-seen --project "$SEC" --task T01 --thread aaaa1111 --kind resolvable --replied yes --note 'x | forged'
pwtest_rc any "comment-seen refuses an HTML comment opener in --note" "$SH" comment-seen --project "$SEC" --task T01 --thread aaaa1111 --kind resolvable --replied yes --note 'see <!-- pw-mr-comment:dead -->'
[ "$PWTEST_RC" != 0 ] && pwtest_ok "marker forge note refused" || pwtest_bad "marker forge" "HTML comment opener accepted"

# --- Phase 2: table-cell writers refuse reserved characters (awk -v escape / cell forgery)
_before_dash="$(cksum "$SEC_DIR/README.md" 2>/dev/null || true)"
pwtest_rc any "dashboard writer refuses a pipe in the state value" "$SH" dashboard-mr-state --project "$SEC" --task T01 --state 'x|y'
[ "$PWTEST_RC" != 0 ] && pwtest_ok "pipe-state refused" || pwtest_bad "dashboard value guard" "pipe accepted"
[ "$(cksum "$SEC_DIR/README.md" 2>/dev/null || true)" = "$_before_dash" ] && pwtest_ok "refused write left the README untouched" || pwtest_bad "refusal purity" "README mutated by a refused write"
. "$TOOL/scripts/lib/pw-mdlib.sh"
_cellf="$PWTEST_ROOT/pwsec-cell.md"
printf '# PLAN\n\n## Task\n\n| ID | Title | Status |\n|----|-------|--------|\n| T01 | x | todo |\n' > "$_cellf"
pwtest_rc 1 "plan cell writer refuses a pipe" _plan_cell_update "$_cellf" T01 status 'a|b'
grep -q 'a|b' "$_cellf" && pwtest_bad "cell refusal purity" "value leaked into the cell" || pwtest_ok "cell left untouched by the refused value"

# --- Phase 2 (S12): monitor pins the forge host to the task repo's origin (decoy URL refused)
cat > "$SEC_DIR/task/T92.md" <<'EOF'
# T92 — decoy MR host probe
- **Repo:** secrepo
- **Branch:** agent/pwsec/T92-ok
- **Base branch:** master

## Result

- **MR:** https://evil.example.com/pwtest/secreto/-/merge_requests/9
EOF
pwtest_rc 2 "monitor refuses an MR URL whose host differs from the repo origin" "$SH" monitor --project "$SEC" --task T92 --timeout 0 --interval 1
pwtest_err "does not match the repo origin" "monitor refusal names the host mismatch"

# --- Phase 2 (S23): read paths never write — a missing axis line reads its defaults and the
# README stays byte-identical.
S23=pwsec23; S23_DIR="$PW_PROJECTS_DIR/$S23"; rm -rf "$S23_DIR"; cp -a "$F2" "$S23_DIR"
grep -v '^- \*\*AI Review:\*\*' "$S23_DIR/README.md" > "$S23_DIR/README.md.new" && mv "$S23_DIR/README.md.new" "$S23_DIR/README.md"
grep -v '^- \*\*Review Budget:\*\*' "$S23_DIR/README.md" > "$S23_DIR/README.md.new" && mv "$S23_DIR/README.md.new" "$S23_DIR/README.md"
_s23_before="$(cksum "$S23_DIR/README.md")"
pwtest_rc 0 "ai-review get on a line-less README succeeds" "$CFG" get --project "$S23" --key ai-review
pwtest_re 'context=advisory' "get reports the effective default rows"
pwtest_rc 0 "review-rounds get on a line-less README succeeds" "$CFG" review-rounds --project "$S23"
pwtest_re '^rounds=3$' "review-rounds get reports the default"
[ "$(cksum "$S23_DIR/README.md")" = "$_s23_before" ] && pwtest_ok "reads left the README untouched" || pwtest_bad "read-only contract" "README changed on a read"

# --- Phase 2: template token stamping is bash replacement (install paths stay data)
_stf="$PWTEST_ROOT/pwsec-stamp.md"
printf 'home={{PW_HOME}}\nproj={{PW_PROJECTS}}\nrepos={{PW_REPOS}}\n' > "$_stf"
pwtest_rc 0 "stamp tokens rewrites the file" bash -c '. "$1"; PW_REPOS="/x/r"; pw_stamp_tokens "$2"' pw-stamp "$TOOL/scripts/lib/pw-common.sh" "$_stf"
grep -q '^home={{PW_HOME}}$' "$_stf" && pwtest_bad "stamp tokens" "{{PW_HOME}} not replaced" || pwtest_ok "{{PW_HOME}} replaced"
grep -q '^repos=/x/r$' "$_stf" && pwtest_ok "{{PW_REPOS}} replaced" || pwtest_bad "stamp tokens" "{{PW_REPOS}} not replaced"

# --- Phase 3: generators replace symlinked targets instead of writing through them, and every
# rendered artifact carries the bundle marker the doctor's orphan sweep requires.
_genout="$PWTEST_ROOT/pwsec-gen"; rm -rf "$_genout"; mkdir -p "$_genout/claude"
_genvictim="$PWTEST_ROOT/pwsec-victim"; printf 'keep me\n' > "$_genvictim"
ln -s "$_genvictim" "$_genout/claude/pw-help.md"
pwtest_rc 0 "gen-commands replaces a symlinked command target" "$TOOL/scripts/toolchain/gen-commands.sh" --outdir "$_genout" claude
[ "$(cat "$_genvictim")" = "keep me" ] && pwtest_ok "symlink target untouched" || pwtest_bad "gen symlink guard" "victim overwritten"
[ ! -L "$_genout/claude/pw-help.md" ] && pwtest_ok "target replaced by a regular file" || pwtest_bad "gen symlink guard" "still a symlink"
grep -q 'pw-generated' "$_genout/claude/pw-help.md" && pwtest_ok "generated artifact carries the bundle marker" || pwtest_bad "gen marker" "marker missing"

# --- refusals are pure: no sentinel, no stray project, and the fixture stayed intact.
[ ! -e "$PWN" ] && pwtest_ok "no refusal leaked a side effect" || pwtest_bad "refusal purity" "sentinel present"
[ ! -e "$PW_PROJECTS_DIR/out" ] || pwtest_bad "traversal purity" "../out was created above the projects dir"
[ -f "$SEC_DIR/task/PLAN.md" ] && pwtest_ok "fixture intact after refusals" || pwtest_bad "fixture integrity" "PLAN.md vanished"

# cleanup — leave shared fixtures as found.
rm -rf "$SEC_DIR" "$S23_DIR" "$PWTEST_ROOT/outside-repo" "$PWTEST_ROOT/outside-proj" "$PWTEST_ROOT/pwsec-desc" "$_cellf" "$_stf" "$PWTEST_ROOT/pwsec-cell.md" "$_genout" "$_genvictim"
