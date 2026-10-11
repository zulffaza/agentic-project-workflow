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
pwtest_rc 2 "monitor refuses a non-numeric --timeout" "$SH" monitor --project "$SEC" --task T01 --timeout "q[\$(touch $PWN)]"
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

# --- refusals are pure: no sentinel, no stray project, and the fixture stayed intact.
[ ! -e "$PWN" ] && pwtest_ok "no refusal leaked a side effect" || pwtest_bad "refusal purity" "sentinel present"
[ ! -e "$PW_PROJECTS_DIR/out" ] || pwtest_bad "traversal purity" "../out was created above the projects dir"
[ -f "$SEC_DIR/task/PLAN.md" ] && pwtest_ok "fixture intact after refusals" || pwtest_bad "fixture integrity" "PLAN.md vanished"

# cleanup — leave shared fixtures as found.
rm -rf "$SEC_DIR" "$PWTEST_ROOT/outside-repo" "$PWTEST_ROOT/outside-proj" "$PWTEST_ROOT/pwsec-desc"
