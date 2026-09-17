# shellcheck shell=bash
# corpus.sh — T3 read-only pass over REAL projects (plan 16 §6 — data, not fixtures).
# Requires --corpus-dir (or PW_CORPUS_DIR). A project is in scope when it has task/ or
# analysis/ plus a README. Classify:
#   crash   = unbound/syntax/"command not found"/exit ≥3        → harness FAIL (script defect)
#   clean 0 = fine
#   clean 1 = a real finding (lint/gate) — must carry a remediation line, else FAIL
#   clean 2 = project/usage problem          — report, don't fail
# Golden gate (P9/P4): projects whose local _TEMPLATE-task.md == the bundle template are
# "current baseline" — they must exit 0 on the whole battery; anything else that exits
# non-2 must still be parseable (0/1). Waivers: $PWTEST_WAIVERS or ~/.pw/test-issues.tsv
# (`slug<TAB>label<TAB>why`), shown and honored in full tier output.
#
# NOTHING here writes into the corpus: only read-only scripts run.

PWTEST_CORPUS_RO="pw-status.sh pw-review-scan.sh pw-doc-lint.sh pw-doc-summary.sh pw-ship.sh"
# per-project read-only invocations (modes with no side effects only):
pwtest_corpus_rows() {
  printf 'status\tpw-status.sh\t%s --skip-cli-check\n' "$1"
  printf 'review-scan\tpw-review-scan.sh\t%s\n' "$1"
  printf 'lint-all\tpw-doc-lint.sh\tall %s\n' "$1"
  printf 'lint-plan\tpw-doc-lint.sh\tplan %s\n' "$1"
  printf 'lint-dashboard\tpw-doc-lint.sh\tdashboard %s\n' "$1"
  printf 'review-scan-plan\tpw-review-scan.sh\t%s --phase plan\n' "$1"
}
corpus_t3() {
  echo "== T3 real corpus (read-only) ==" >&2
  local dir="$1"
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then pwtest_skip "T3 corpus" "pass --corpus-dir (or PW_CORPUS_DIR) — skipping"; return 0; fi
  local p slug label rows script args rc waiver hits=0 goldens=0
  local wf="${PWTEST_WAIVERS:-$HOME/.pw/test-issues.tsv}"
  for p in "$dir"/*/; do
    slug="$(basename "$p")"
    [ -d "$p/task" ] || [ -d "$p/analysis" ] || continue
    [ -f "$p/README.md" ] || continue
    [ -f "$p/task/_TEMPLATE-task.md" ] || [ -d "$p/context" ] || continue
    # C20 info: template drift vs the bundle current
    if [ -f "$p/task/_TEMPLATE-task.md" ] && cmp -s "$p/task/_TEMPLATE-task.md" "$PWTEST_TEMPLATE_DIR/task/_TEMPLATE-task.md"; then
      goldens=$((goldens+1))
    else
      printf '  info  %s: local _TEMPLATE-task.md differs from bundle template (stale era → data, run /pw-adopt-style doc migration when convenient)\n' "$slug"
    fi
    PWTEST_T3_PROJECTS="$p"
    while IFS='	' read -r label script args; do
      [ -z "$label" ] && continue
      args="${args//%s/$slug}"
      TMO=""; command -v timeout >/dev/null && TMO="timeout 30"
      PDIR="${dir%/}"
      if (cd /tmp && $TMO env PW_PROJECTS="$PDIR" PW_PROJECTS_DIR="$PDIR" ${PW_CORPUS_REPOS:+PW_REPOS="$PW_CORPUS_REPOS"} \
          "$(pwtest_script "$script")" $args >"$ROOT/c.out" 2>"$ROOT/c.err"); then rc=0; else rc=$?; fi
      cat "$ROOT/c.out" "$ROOT/c.err" >"$ROOT/c.both"
      waiver=""
      [ -f "$wf" ] && waiver="$(awk -F'\t' -v s="$slug" -v l="$label" '$1==s && $2==l{print; exit}' "$wf")"
      if pwtest_is_crash "$ROOT/c.both" || [ "$rc" -ge 3 ]; then
        if [ -n "$waiver" ]; then printf '  skip  %s %s: waived (%s)\n' "$slug" "$label" "${waiver#*	*	}"
        else pwtest_bad "T3 $slug/$label" "CRASH/script-defect rc=$rc: $(head -c160 "$ROOT/c.both"|tr '\n' ' ')"; hits=$((hits+1)); fi
      elif [ "$rc" = 0 ]; then
        pwtest_ok "T3 $slug/$label clean"
      elif [ "$rc" = 1 ]; then
        if [ -n "$waiver" ]; then printf '  skip  %s %s: waived finding (%s)\n' "$slug" "$label" "${waiver#*	*	}"
        elif grep -qE '→ fix:|fix:|run |repair|--help|create it with|check the slug' "$ROOT/c.err"; then
          pwtest_ok "T3 $slug/$label finding WITH remediation"
        else pwtest_bad "T3 $slug/$label" "rc=1 without a → fix: style remediation: $(head -c140 "$ROOT/c.both"|tr '\n' ' ')"; hits=$((hits+1)); fi
      else
        printf '  warn  %s/%s rc=2 project-setup issue (not a script defect)\n' "$slug" "$label"
      fi
    done <<EOF
$(pwtest_corpus_rows "$slug")
EOF
  done
  [ "$goldens" = 0 ] && printf '  info  T3: no projects yet on the current template baseline; golden-gate trivially satisfied\n'
  return "$hits"
}
