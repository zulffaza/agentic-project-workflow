# shellcheck shell=bash
# cases/pw-common.t.sh — the shared readers are THE contract (P2).
export PW_HOME="${PW_HOME:-$(cd "$TOOL/.." && pwd)}"; . "$(pwtest_script pw-common.sh)"

got="$(printf "  a's \"b\" c  " | pw_trim)"
expected=$(printf "a's \"b\" c")
[ "$got" = "$expected" ] && pwtest_ok "pw_trim quotes-safe (C14)" || pwtest_bad "pw_trim quotes-safe" "got [$got]"

tf="$PWTEST_ROOT/pf.txt"
printf -- '- **Repo:** api            **Base branch:** master\n' > "$tf"
pwtest_eq "pw_field bold-packed (C1)" "$(pw_field "$tf" "Base branch")" "master"
pwtest_eq "pw_field bold-packed first field cuts at ** (C1)" "$(pw_field "$tf" "Repo")" "api"
printf -- '- **Repo:** api\n- **Base branch:** main\n' > "$tf"
pwtest_eq "pw_field value-per-line (baseline)" "$(pw_field "$tf" "Repo")" "api"
printf -- 'Repo: hera\n' > "$tf"
pwtest_eq "pw_field line-start" "$(pw_field "$tf" "Repo")" "hera"

u="$(_pw_url_from_line 'see https://gitlab.example.com/a/b/-/merge_requests/7 done')"
pwtest_eq "url extracted from prose" "$u" "https://gitlab.example.com/a/b/-/merge_requests/7"
u="$(_pw_url_from_line '- **MR:** [MR 7](https://gitlab.example.com/a/b/-/merge_requests/8)')"
case "$u" in */merge_requests/8) pwtest_ok "linked-cell url (C4)" ;; *) pwtest_bad "linked-cell url" "got [$u]";; esac
u="$(_pw_url_from_line '- **MR:** none of the above (zero)')"
pwtest_eq "sentinel passthrough (no URL)" "$u" "none of the above (zero)"

t="$(pw_phase_token "executing — 11/11 done (verify ✓)")"; pwtest_eq "phase token from prose line" "$t" "executing"
pw_phase_valid executing && pwtest_ok "executing valid" || pwtest_bad "executing valid" "rejected"
pw_phase_valid "executed" && pwtest_bad "invalid token rejected (C19)" "accepted" || pwtest_ok "invalid token rejected (C19)"

pl="$PWTEST_ROOT/pl.md"
printf '# p\n\n## Task table\n\n| SP | Status | ID | Group | Title |\n|---|---|---|---|---|\n| 1 | done | [T1](./T1.md) | G1 | A "quoted" title |\n' > "$pl"
pwtest_eq "shuffled PLAN read by name (C3/C4)" "$(pw_plan_pairs "$pl" | head -1)" "T1|done"

# Result-scoped MR resolution — the C21 family (decoy must lose):
export F3="${F3:-$PW_PROJECTS_DIR/pwt-f3-hostile}"
pwtest_eq "Steps decoy NEVER resolves (C21)" "$(pw_task_mr_url "$F3/task/T05.md")" ""
