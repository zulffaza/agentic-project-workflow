# shellcheck shell=bash
# cases/pw-worktree-create.t.sh
pwtest_rc 0 "create T02 worktree (fresh branch from master)" "$TOOL/pw-worktree-create.sh" "$S2" T95 api master
pwtest_re "worktree" "prints worktree path"
wt2="$PW_PROJECTS_DIR/$S2/worktree/api/$S2-T95-$(true)"
ls "$PW_PROJECTS_DIR/$S2/worktree/api/" >/dev/null 2>&1 && pwtest_ok "worktree dir created under project" || pwtest_bad "worktree dir" "ls failed"
pwtest_rc 2 "fake repo → 2" "$TOOL/pw-worktree-create.sh" "$S2" T01 nope-repo master
pwtest_fix "missing repo names the remedy"
