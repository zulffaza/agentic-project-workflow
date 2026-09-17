# shellcheck shell=bash
# cases/pw-mr-state-batch.t.sh — inferred + explicit rows (C6/C8).
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 closed\n43 closed\n" >> "$PWTEST_FORGE_STATE_FILE"
pwtest_rc 0 "batch F2 every task" "$(pwtest_script pw-mr-state-batch.sh)" "$S2"
pwtest_re 'T02\|closed' "closed state mapped (glab vocab)"
: > "$PWTEST_FORGE_STATE_FILE"; printf "42 merged\n43 opened\n" >> "$PWTEST_FORGE_STATE_FILE"
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 T02+T04 (linked cell + decoy)" "$(pwtest_script pw-mr-state-batch.sh)" "$S3" T02 T04
if grep -q '000-stencil' "$PWTEST_FORGE_LOG"; then pwtest_bad "decoy never queried" "$(cat "$PWTEST_FORGE_LOG")"; else pwtest_ok "decoy never queried (C6/C21)"; fi
pwtest_re 'T02\|merged' "merged via shim"
# auto-list (no explicit IDs) must normalize markdown-linked ID cells in the PLAN (C4):
: > "$PWTEST_FORGE_LOG"
pwtest_rc 0 "batch F3 auto-list over linked cells" "$(pwtest_script pw-mr-state-batch.sh)" "$S3"
pwtest_re 'T02\|merged' "linked-cell T02 picked up by auto-list"
if grep -q '000-stencil' "$PWTEST_FORGE_LOG"; then pwtest_bad "auto-list decoy query" "$(cat "$PWTEST_FORGE_LOG")"; else pwtest_ok "auto-list kept decoy unqueried"; fi
# C21 (lib-owner): exercise _resolve_task_mr_url's SOURCE directly (eval-extract, as the lib's
# own selftest does — the function has no CLI). Discriminating shapes = the exact b5a4da7
# regression: a Result field next to a Steps stencil (field must win), and a Steps-only task
# (must resolve EMPTY — never leak the decoy into the parse path).
_pwt_lib_resolve() {
  eval "$(sed -n '/^_resolve_task_mr_url()/,/^}/p' "$(pwtest_script pw-lib.sh)")"
  _resolve_task_mr_url "$1"
}
tf="$ROOT/c21-field.md"
printf '# T\n## Steps\n- See https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil (placeholder)\n\n## Result\n- **MR:** https://gitlab.example.com/pwtest/api/-/merge_requests/44\n' > "$tf"
pwtest_eq "C21 lib: Result field beats Steps decoy" "$(_pwt_lib_resolve "$tf")" "https://gitlab.example.com/pwtest/api/-/merge_requests/44"
tf="$ROOT/c21-decoy-only.md"
printf '# T\n## Steps\n- Decoy: https://gitlab.example.com/pwtest/api/-/merge_requests/000-stencil\n\n## Result\n- **Commit(s):** —\n' > "$tf"
pwtest_eq "C21 lib: Steps-only resolves EMPTY (b5a4da7 symptom)" "$(_pwt_lib_resolve "$tf")" ""
