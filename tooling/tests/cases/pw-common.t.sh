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

# --- codex provider surfaces (plan 28): FIRST command-less provider — /pw-* commands are
# generated SKILL DIRS in the shared skills root; D13 skip list is DERIVED (never hardcoded);
# the catalog reader parses the REAL one-line JSON shape (tests/bin/codex shim, captured from
# codex-cli 0.160.0 — plan-27 rev-h lesson: shims match real CLI byte-shape). ---
pwtest_eq "codex command_style = skill" "$(pw_provider_command_style codex)" "skill"
pwtest_eq "flat providers keep the flat command layout" "$(pw_provider_command_style cursor)" "flat"
pwtest_eq "codex commanddir IS the skills root (commands are skills)" "$(codex_commanddir)" "$(codex_skilldir)"
pwtest_eq "D13 skips derived from canonical command names" "$(pw_skill_skips_for codex | sort | tr '\n' ' ')" "pw-review pw-rfc "
# pipefail regression (shipped once, 2026-10-04): bootstrap/offboard/doctor run `set -o pipefail`
# — an early-exit `grep -q` inside the helper SIGPIPEs its writer and the skip list comes back
# EMPTY, silently installing colliding skills. The helper must produce identical output under
# pipefail; re-introducing a grep -q pipeline fails this assert.
pwtest_eq "D13 skips survive pipefail (bootstrap context)" \
  "$(set -o pipefail; pw_skill_skips_for codex | sort | tr '\n' ' ')" "pw-review pw-rfc "
pwtest_eq "flat providers skip no bundle skills" "$(pw_skill_skips_for cursor)" ""
pwtest_eq "codex catalog = visible slugs only, real one-line JSON shape" \
  "$(pw_api_catalog codex)" "$(printf 'codex-test-luna\ncodex-test-astra')"

# generator layout contract: skill = <name>/SKILL.md + agents/openai.yaml (explicit-only);
# flat = <name>.md unchanged (regression pin for the other four providers).
GEN="$TOOL/scripts/toolchain/gen-commands.sh"
GD="$PWTEST_ROOT/gen-layout"; rm -rf "$GD"
PW_CONFIG_FILE="$PWTEST_TESTSDIR/pw.config.test.noscope.sh" bash "$GEN" --outdir "$GD" codex cursor >/dev/null 2>&1
[ -f "$GD/codex/pw-status/SKILL.md" ] \
  && pwtest_ok "codex commands generate as <name>/SKILL.md dirs" \
  || pwtest_bad "codex skill layout" "no $GD/codex/pw-status/SKILL.md"
head -2 "$GD/codex/pw-status/SKILL.md" 2>/dev/null | grep -q '^name: pw-status$' \
  && pwtest_ok "codex SKILL.md frontmatter carries name" \
  || pwtest_bad "codex SKILL.md frontmatter" "$(head -3 "$GD/codex/pw-status/SKILL.md" 2>/dev/null)"
grep -q 'allow_implicit_invocation: false' "$GD/codex/pw-status/agents/openai.yaml" 2>/dev/null \
  && pwtest_ok "codex command-skills are explicit-only (agents/openai.yaml policy)" \
  || pwtest_bad "codex policy file" "missing/false agents/openai.yaml under $GD/codex/pw-status"
if grep -rl '{{ARGS}}' "$GD/codex" >/dev/null 2>&1; then
  pwtest_bad "codex {{ARGS}} substitution" "literal {{ARGS}} left in a generated SKILL.md"
else
  pwtest_ok "codex {{ARGS}} substituted (<arguments>)"
fi
[ -f "$GD/cursor/pw-status.md" ] && [ ! -d "$GD/cursor/pw-status" ] \
  && pwtest_ok "flat providers still generate <name>.md (no regression)" \
  || pwtest_bad "flat layout regression" "cursor output shape changed under $GD/cursor"
rm -rf "$GD"
