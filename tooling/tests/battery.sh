# shellcheck shell=bash
# battery.sh — T2 golden battery: read-only invocations × fixtures + preflight gate
# matrix + mode-completeness. Data-driven from battery_rows()/gate_combos();
# expectations pinned by `--capture` (review the diff — this file is behavior, not law).
#
# battery.tsv columns: label \t script \t args \t rc \t (reserved token|—)
# gates.tsv   columns: label \t — \t — \t rc \t —

battery_rows() {
  local s
  for s in "$S1" "$S2" "$S3"; do
    printf 'status %s\tpw-status.sh\t%s --skip-cli-check\n'        "$s" "$s"
    printf 'review-scan %s\tpw-review.sh\tscan %s\n'               "$s" "$s"
    printf 'lint-all %s\tpw-doc.sh\tlint all %s\n'                 "$s" "$s"
    printf 'lint-plan %s\tpw-doc.sh\tlint plan %s\n'               "$s" "$s"
    printf 'lint-dashboard %s\tpw-doc.sh\tlint dashboard %s\n'     "$s" "$s"
    printf 'lint-analysis %s\tpw-doc.sh\tlint analysis %s\n'       "$s" "$s"
    printf 'lint-review %s\tpw-doc.sh\tlint review %s task/review/PLAN.review.md\n' "$s" "$s"
    printf 'lint-task-t01 %s\tpw-doc.sh\tlint task %s T01\n'       "$s" "$s"
    printf 'summary-plan %s\tpw-doc.sh\tsummary plan %s\n'         "$s" "$s"
    printf 'summary-project %s\tpw-doc.sh\tsummary project %s\n'   "$s" "$s"
    printf 'summary-task %s\tpw-doc.sh\tsummary task %s T01\n'     "$s" "$s"
    printf 'summary-analysis %s\tpw-doc.sh\tsummary analysis %s\n' "$s" "$s"
    printf 'resolve %s\tpw-ship.sh\tresolve %s\n'               "$s" "$s"
    printf 'batch %s\tpw-ship.sh\tmr-state-batch %s\n'        "$s" "$s"
    printf 'rfc %s\tpw-rfc.sh\tcomments %s\n'                      "$s" "$s"
    printf 'adopt %s\tpw-context.sh\tadopt-snapshot %s api agent/%s/T01-thing\n' "$s" "$s" "$s"
  done
  printf 'lint-task-crlf %s\tpw-doc.sh\tlint task %s\n' "$S3" "$S3"          # T06 (CRLF, sentinels)
  printf 'batch-list F3\tpw-ship.sh\tmr-state-batch %s T02 T05\n' "$S3"
  printf 'unknown-project\tpw-status.sh\tnope-not-here\n'
  printf 'unknown-arg\tpw-doc.sh\tlint bogus-mode %s\n' "$S2"
}

gate_combos() {   # label only; the runner composes cmd from it: mode|phase|fixture
  local s m
  for s in "$S1" "$S2" "$S3"; do
    for m in analyze execute breakdown ship comments close review-plan review-task; do
      printf 'gate %s %s\n' "$m" "$s"
    done
  done
}
_gate_cmd() {     # "<mode> <fixture>" → echo preflight args (review-plan → review <slug> plan)
  local label="$1" mode slug
  mode="${label#gate }"; slug="${mode##* }"; mode="${mode% *}"
  case "$mode" in
    review-plan) printf 'review %s plan\n' "$slug" ;;
    review-task) printf 'review %s task-exec\n' "$slug" ;;
    *)           printf '%s %s\n'         "$mode" "$slug" ;;
  esac
}

PWTEST_MODES="pw-doc|lint summary sync
pw-doc|analysis task plan review dashboard all
pw-preflight|analyze execute breakdown ship review comments close"

pwtest_is_crash() {  # file → 0 if output looks like a *script* defect (not a clean failure)
  grep -qE "^(pw-[a-z-]+\.sh|.*\.sh): line [0-9]+:|unbound variable|syntax error near|command not found|Traceback|glab-shim: unexpected|gh-shim: unexpected" "$1"
}

battery_run() { # script args → sets B_RC, B_OUT, B_ERR (out+err joined)
  local script="$1"; shift
  B_OUT="$ROOT/b.out"; B_ERR="$ROOT/b.err"
  ( cd /tmp && "$(pwtest_script "$script")" "$@" >"$B_OUT" 2>"$B_ERR" ); B_RC=$?
  cat "$B_OUT" "$B_ERR" > "$ROOT/b.both"
}

battery_t2() {
  echo "== T2 battery ==" >&2
  local label script args rc tok script2
  local cap=0
  case "${CAPTURE:-}" in ""|0|none) ;; *) cap=1 ;; esac
  local label script args rc tok

  # spine selftests, run from a foreign cwd (C12)
  local cmd rc
  for cmd in "pw-status.sh --selftest"; do
    (cd /tmp && b_s="${cmd%% *}" && "$(pwtest_script "$b_s")" ${cmd#* } >/dev/null 2>&1); rc=$?
    label="selftest: $cmd"
    if [ "$cap" = 1 ]; then printf '%s\t%s\t%s\t%s\t%s\n' "$label" "${cmd%% *}" "${cmd#* }" "$rc" "-" >> "$TOOL/tests/expectations/battery.tsv"
    else tok="$(awk -F'\t' -v l="$label" '$1==l{print $4; exit}' "$TOOL/tests/expectations/battery.tsv" 2>/dev/null)"
      [ "$rc" = "${tok:-X}" ] && [ "$rc" = 0 ] && pwtest_ok "$label" || pwtest_bad "$label" "rc=$rc"
    fi
  done

  # read-only invocations
  while IFS='	' read -r label script args; do
    [ -z "$label" ] && continue
    battery_run "$script" $args
    if [ "$cap" = 1 ]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$script" "$args" "$B_RC" "-" >> "$TOOL/tests/expectations/battery.tsv"; continue
    fi
    IFS='	' read -r rc tok < <(awk -F'\t' -v l="$label" '$1==l{print $4"\t"$5; exit}' "$TOOL/tests/expectations/battery.tsv" 2>/dev/null) || true
    if [ -z "${rc:-}" ]; then pwtest_bad "$label" "not pinned — run: $0 --capture T2"; continue; fi
    if pwtest_is_crash "$B_ERR"; then
      pwtest_bad "$label" "SCRIPT CRASH (was silent once): $(head -c140 "$B_ERR"|tr '\n' ' ')"
    elif [ "$B_RC" != "$rc" ]; then
      pwtest_bad "$label" "rc=$B_RC want=$rc; err: $(head -c140 "$B_ERR"|tr '\n' ' ')"
    elif [ "$B_RC" != 0 ] && ! grep -qE 'fix|run |/pw-|pw-lib|scaffold|--help|usage|expected' "$ROOT/b.both"; then
      pwtest_bad "$label (→ fix: contract)" "rc=$B_RC bare stderr"
    else
      pwtest_ok "$label"
      [ "$B_RC" != 0 ] && [ "$rc" != 0 ] && pwtest_ok "$label (remediation offered)" 
    fi
  done <<EOF
$(battery_rows)
EOF

  # gate matrix
  while IFS='	' read -r label; do
    [ -z "$label" ] && continue
    local gargs; gargs="$(_gate_cmd "$label")"
    battery_run pw-preflight.sh $gargs
    if [ "$cap" = 1 ]; then
      printf '%s\tpw-preflight.sh\t%s\t%s\t-\n' "$label" "$gargs" "$B_RC" >> "$TOOL/tests/expectations/gates.tsv"; continue
    fi
    rc="$(awk -F'\t' -v l="$label" '$1==l{print $4; exit}' "$TOOL/tests/expectations/gates.tsv" 2>/dev/null)"
    if [ -z "${rc:-}" ]; then pwtest_bad "$label" "not pinned — run: $0 --capture gates"; continue; fi
    if [ "$B_RC" != "$rc" ]; then pwtest_bad "$label" "rc=$B_RC want=$rc; $(head -c140 "$B_ERR"|tr '\n' ' ')"
    elif [ "$B_RC" != 0 ] && ! grep -qE 'fix|repair|run |/pw-|try --help|[Uu]sage' "$ROOT/b.both"; then
      pwtest_bad "$label (→ fix: contract)" "rc=$B_RC bare stderr"
    else pwtest_ok "$label"; fi
  done <<EOF
$(gate_combos)
EOF

  # mode completeness: every advertised mode token must appear in some pinned row
  local script modes m
  while IFS="|" read -r script modes; do
    for m in $modes; do
      if awk -F"	" -v s="$script" -v m="$m"            '($2 ~ s) && (($3 ~ ("(^| )" m "( |$)")) || ($1 ~ ("(^| )" m "( |$)"))) {found=1} END{exit !found}' \
           "$TOOL/tests/expectations/battery.tsv" "$TOOL/tests/expectations/gates.tsv" 2>/dev/null; then
        pwtest_ok "mode pinned: $script $m"
      else
        pwtest_bad "mode pinned: $script $m" "advertised in usage, absent from battery+gates"
      fi
    done
  done <<<"$PWTEST_MODES"
}

pwtest_capture() {
  mkdir -p "$TOOL/tests/expectations"
  local b="$TOOL/tests/expectations/battery.tsv" g="$TOOL/tests/expectations/gates.tsv"
  case "$1" in T2|both) : > "$b" : > "$g"; CAPTURE=1 battery_t2 ;;
              gates)   : > "$g"; CAPTURE=1 battery_t2 ;;
              battery|b) : > "$b"; CAPTURE=1 battery_t2 ;;
              *) echo "pw_test --capture: use battery|gates|both" >&2; return 2 ;; esac
  echo "pwtest: expectations captured — REVIEW before committing (this is behavior, not law)." >&2
}
