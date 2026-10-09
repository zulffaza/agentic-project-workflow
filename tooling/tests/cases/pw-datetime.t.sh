# shellcheck shell=bash
# Exact event output, mixed-generation readers, and fail-before-write checks.
WD_LIB="$TOOL/scripts/lib/pw-mdlib.sh"
WD_BIN="$ROOT/wib-date-bin"; mkdir -p "$WD_BIN"
WD_REAL_DATE="$(command -v date)"
cat > "$WD_BIN/date" <<'DATE'
#!/usr/bin/env bash
case "${1:-}" in
  +%s) printf '%s\n' "$PWTEST_CLOCK" ;;
  +*)
    [ "${PWTEST_DATE_FAIL:-0}" != 2 ] || exit 0
    [ "${PWTEST_DATE_FAIL:-0}" = 0 ] || exit 1
    if [ "${PWTEST_DATE_GNU:-0}" = 1 ]; then
      exec "$PWTEST_NATIVE_DATE" -d "@$PWTEST_CLOCK" "$@"
    fi
    exec "$PWTEST_NATIVE_DATE" -r "$PWTEST_CLOCK" "$@" ;;
  *) exec "$PWTEST_NATIVE_DATE" "$@" ;;
esac
DATE
chmod +x "$WD_BIN/date"
WD_PATH="$WD_BIN:$PATH"
pwtest_rc 1 'successful date command with empty output is rejected' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK=0 PWTEST_DATE_FAIL=2 bash -c '. "$1"; pw_now_wib' _ "$WD_LIB"
pwtest_eq 'empty formatter emits no timestamp' '' "$(cat "$PWTEST_OUT")"
# 2026-12-31 17:00 UTC is midnight on New Year's Day in WIB.
WD_CLOCK=1798736400
for WD_TZ in UTC America/New_York Asia/Tokyo; do
  pwtest_rc 0 "formatter ignores host timezone $WD_TZ" env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" TZ="$WD_TZ" LC_ALL=fr_FR.UTF-8 bash -c '. "$1"; pw_now_wib' _ "$WD_LIB"
  pwtest_eq "exact English unpadded WIB output $WD_TZ" '1 January 2027 - 00.00 WIB' "$(cat "$PWTEST_OUT")"
done
WD_LEAP="$(TZ=UTC "$WD_REAL_DATE" -j -f '%Y-%m-%d %H:%M:%S' '2024-02-29 16:59:00' +%s 2>/dev/null || TZ=UTC "$WD_REAL_DATE" -d '2024-02-29 16:59:00' +%s)"
pwtest_rc 0 'leap-day boundary before midnight' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_LEAP" TZ=UTC bash -c '. "$1"; pw_now_wib' _ "$WD_LIB"
pwtest_eq 'leap-day exact output' '29 February 2024 - 23.59 WIB' "$(cat "$PWTEST_OUT")"
pwtest_rc 0 'leap-day rollover' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$((WD_LEAP + 60))" TZ=UTC bash -c '. "$1"; pw_now_wib' _ "$WD_LIB"
pwtest_eq 'March rollover exact output' '1 March 2024 - 00.00 WIB' "$(cat "$PWTEST_OUT")"

_wd_parser_cases() {
  local native="$1" gnu="$2" stamp
  for stamp in '1 January 2027 00.00 WIB' '1 January 2027 - 00.00 WIB' '01 January 2027 00.00 WIB' '01 January 2027 - 00.00 WIB' '2026-12-31 17:00' '2026-12-31T17:00:00Z' '2027-01-01T00:00:00+07:00' '2026-12-31T12:00-0500'; do
    pwtest_rc 0 "complete timestamp parses ($gnu): $stamp" env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$native" PWTEST_DATE_GNU="$gnu" PWTEST_CLOCK="$WD_CLOCK" TZ=UTC bash -c '. "$1"; pw_timestamp_epoch "$2"' _ "$WD_LIB" "$stamp"
    pwtest_eq "timestamp epoch ($gnu): $stamp" "$WD_CLOCK" "$(cat "$PWTEST_OUT")"
  done
  for stamp in '2026-12-31' '31 February 2026 00.00 WIB' '2026-02-30 17:00' '0 January 2027 00.00 WIB' '1 January 2027 24.00 WIB' '1 janvier 2027 00.00 WIB' '1 January 2027 00.00 WIB trailing' '<DD MMMM YYYY HH.mm WIB>' '<DD MMMM YYYY - HH.mm WIB>' '2026-12-31T17:00:00+99:00'; do
    pwtest_rc 1 "invalid/incomplete timestamp rejected ($gnu): $stamp" env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$native" PWTEST_DATE_GNU="$gnu" PWTEST_CLOCK="$WD_CLOCK" TZ=UTC bash -c '. "$1"; pw_timestamp_epoch "$2"' _ "$WD_LIB" "$stamp"
    pwtest_eq "invalid timestamp emits no epoch ($gnu)" '' "$(cat "$PWTEST_OUT")"
  done
  pwtest_rc 0 "legacy local interpretation ($gnu)" env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$native" PWTEST_DATE_GNU="$gnu" PWTEST_CLOCK="$WD_CLOCK" TZ=Asia/Jakarta bash -c '. "$1"; pw_timestamp_epoch "$2"' _ "$WD_LIB" '2027-01-01 00:00'
  pwtest_eq "legacy stays host-local ($gnu)" "$WD_CLOCK" "$(cat "$PWTEST_OUT")"
}
_wd_parser_cases "$WD_REAL_DATE" 0
WD_GDATE="$(command -v gdate || true)"
if [ -n "$WD_GDATE" ]; then
  _wd_parser_cases "$WD_GDATE" 1
  pwtest_rc 0 'GNU formatter timezone/locale independence' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_GDATE" PWTEST_DATE_GNU=1 PWTEST_CLOCK="$WD_CLOCK" TZ=UTC LC_ALL=fr_FR.UTF-8 bash -c '. "$1"; pw_now_wib' _ "$WD_LIB"
  pwtest_eq 'GNU exact WIB output' '1 January 2027 - 00.00 WIB' "$(cat "$PWTEST_OUT")"
else
  pwtest_skip 'additional native GNU date coverage' 'gdate not installed; default date branch remains exercised'
fi

# Runtime writers from a foreign cwd use private projects, never shared fixtures.
WD_PROJ=wib-runtime; WD_P="$PW_PROJECTS_DIR/$WD_PROJ"
pwtest_rc 0 'scaffold emits one timestamp for Created and LOG' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PW_PROJECTS="$PW_PROJECTS_DIR" PW_REPOS="$PW_REPOS" bash -c 'cd /; exec bash "$1" "$2"' _ "$(pwtest_script scaffold.sh)" "$WD_PROJ"
pwtest_grep_file '^\- \*\*Created:\*\* 1 January 2027 - 00.00 WIB$' 'dashboard Created uses WIB' "$WD_P/README.md"
pwtest_grep_file '^\- \*\*1 January 2027 - 00.00 WIB\*\*' 'initial LOG uses matching WIB' "$WD_P/LOG.md"
WD_ST="$(pwtest_script pw-status.sh)"; WD_CT="$(pwtest_script pw-context.sh)"; WD_RV="$(pwtest_script pw-review.sh)"; WD_RD="$(pwtest_script pw-review-read.sh)"
_wd_run() { env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" TZ=UTC "$@"; }
pwtest_rc 0 'context provenance event uses WIB' _wd_run "$WD_CT" add-input "$WD_PROJ" --file source.md --what 'source date 2020-01-01' --source original
pwtest_grep_file '\| 1 January 2027 - 00.00 WIB \|' 'context row timestamp is full WIB' "$WD_P/context/INDEX.md"
pwtest_grep_file 'source date 2020-01-01' 'imported source date preserved' "$WD_P/context/INDEX.md"
pwtest_rc 0 'adoption provenance uses shared formatter' _wd_run bash -c '. "$1"; _index_provenance_ensure "$2"' _ "$WD_LIB" "$WD_P/context/INDEX.md"
pwtest_grep_file 'ADOPTED.md.*\| 1 January 2027 - 00.00 WIB \|' 'adoption provenance timestamp' "$WD_P/context/INDEX.md"
WD_BEFORE="$(cksum < "$WD_P/context/INDEX.md")"
pwtest_rc 0 'adoption provenance rerun preserves original stamp' _wd_run bash -c '. "$1"; _index_provenance_ensure "$2"' _ "$WD_LIB" "$WD_P/context/INDEX.md"
pwtest_eq 'adoption provenance byte-idempotence' "$WD_BEFORE" "$(cksum < "$WD_P/context/INDEX.md")"

# Duplicate guard: last entry only, exact key, strict window, no future/date-only suppression.
for WD_STAMP in '31 December 2026 23.59 WIB' '31 December 2026 - 23.59 WIB' '2026-12-31 16:59' '31 December 2026 23.55 WIB' '31 December 2026 - 23.55 WIB' '2026-12-31 16:55' '31 December 2026' '2026-12-31' '1 January 2027 00.01 WIB' '1 January 2027 - 00.01 WIB' '2026-12-31 17:01' 'garbage' '31 February 2026 23.59 WIB' '31 February 2026 - 23.59 WIB'; do
  printf -- '- **%s** · `you` — repeat\n' "$WD_STAMP" > "$WD_P/LOG.md"
  pwtest_rc 0 "LOG legacy/WIB window: $WD_STAMP" _wd_run "$WD_ST" log "$WD_PROJ" you repeat
  WD_LINES="$(wc -l < "$WD_P/LOG.md" | tr -d ' ')"; WD_EXPECT=2
  case "$WD_STAMP" in '31 December 2026 23.59 WIB'|'31 December 2026 - 23.59 WIB'|'2026-12-31 16:59') WD_EXPECT=1 ;; esac
  pwtest_eq "LOG append count: $WD_STAMP" "$WD_EXPECT" "$WD_LINES"
done
printf -- '- **1 January 2027 00.00 WIB** · `you` — repeat\n' > "$WD_P/LOG.md"
pwtest_rc 0 'LOG changed actor is not suppressed' _wd_run "$WD_ST" log "$WD_PROJ" agent repeat
pwtest_rc 0 'LOG older matching nonfinal entry is not suppressed' _wd_run "$WD_ST" log "$WD_PROJ" you repeat
pwtest_eq 'LOG compares only last actor/message' 3 "$(wc -l < "$WD_P/LOG.md" | tr -d ' ')"
pwtest_rc 0 'LOG changed message is not suppressed' _wd_run "$WD_ST" log "$WD_PROJ" you changed
pwtest_eq 'LOG changed message appends' 4 "$(wc -l < "$WD_P/LOG.md" | tr -d ' ')"
printf -- '- **31 December 2026 23.59 WIB** · `you` — repeat\n' > "$WD_P/LOG.md"
pwtest_rc 0 'LOG zero window disables suppression' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" TZ=UTC PW_LOG_DEDUP_WINDOW_MIN=0 "$WD_ST" log "$WD_PROJ" you repeat
pwtest_eq 'zero window appends' 2 "$(wc -l < "$WD_P/LOG.md" | tr -d ' ')"

# New and old placeholders with a filled anchor stay invisible to every reader.
mkdir -p "$WD_P/analysis/review"
WD_RF=analysis/review/mixed.review.md
for WD_TOKEN in '<YYYY-MM-DD HH:MM>' '<DD MMMM YYYY HH.mm WIB>' '<DD MMMM YYYY - HH.mm WIB>'; do
  printf '# Review\nGate: see Sign-off\n## Items\n### R1 · §1 — [OPEN] (you, %s) <!-- pw-item-status: open -->\nstub\n\n---\n## Open questions\n## Sign-off\n| Date-time | By | Decision |\n|---|---|---|\n| 2026-09-15 00:00 | you | approved |\n' "$WD_TOKEN" > "$WD_P/$WD_RF"
  pwtest_rc 0 "stub gate accepts legacy/new token $WD_TOKEN" _wd_run "$WD_RD" gate "$WD_PROJ" "$WD_RF"
  pwtest_rc 0 "stub count ignores token $WD_TOKEN" _wd_run "$WD_RD" count "$WD_PROJ" "$WD_RF"
  pwtest_re '^open=0 resolved=0 items=0$' 'both stub counts are zero'
  pwtest_rc 0 "replace stub through add-item $WD_TOKEN" _wd_run "$WD_RV" add-item "$WD_PROJ" "$WD_RF" --section '§1' --text 'real ask'
  pwtest_grep_file 'R1 .*1 January 2027 - 00.00 WIB' 'first real heading reuses R1 with WIB timestamp' "$WD_P/$WD_RF"
  pwtest_rc 1 'real item blocks old approval' _wd_run "$WD_RD" gate "$WD_PROJ" "$WD_RF"
  pwtest_rc 0 'real item resolves with WIB reply' _wd_run "$WD_RV" resolve "$WD_PROJ" "$WD_RF" R1 --reply fixed
  pwtest_grep_file 'agent\*\* \(1 January 2027 - 00.00 WIB\)' 'resolution reply stamps WIB' "$WD_P/$WD_RF"
  WD_BEFORE="$(cksum < "$WD_P/$WD_RF")"
  WD_ARCHIVE_BEFORE=missing
  [ ! -f "$WD_P/analysis/review/mixed.archive.md" ] || WD_ARCHIVE_BEFORE="$(cksum < "$WD_P/analysis/review/mixed.archive.md")"
  pwtest_rc 2 'archive formatter failure precedes sibling publication' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PWTEST_DATE_FAIL=1 "$WD_RV" archive "$WD_PROJ" "$WD_RF"
  pwtest_eq 'failed archive preserves review bytes' "$WD_BEFORE" "$(cksum < "$WD_P/$WD_RF")"
  WD_ARCHIVE_AFTER=missing
  [ ! -f "$WD_P/analysis/review/mixed.archive.md" ] || WD_ARCHIVE_AFTER="$(cksum < "$WD_P/analysis/review/mixed.archive.md")"
  pwtest_eq 'failed archive creates/changes no sibling' "$WD_ARCHIVE_BEFORE" "$WD_ARCHIVE_AFTER"
  pwtest_rc 0 'archive mixed-generation review' _wd_run "$WD_RV" archive "$WD_PROJ" "$WD_RF"
  pwtest_grep_file '1 January 2027 - 00.00 WIB' 'archive event stamp' "$WD_P/analysis/review/mixed.archive.md"
done
pwtest_rc 2 'legacy timestamp stub injection is refused' _wd_run "$WD_RV" add-item "$WD_PROJ" "$WD_RF" --section '§1' --actor 'x <DD MMMM YYYY HH.mm WIB>' --text hidden
pwtest_rc 2 'new timestamp stub injection is refused' _wd_run "$WD_RV" add-item "$WD_PROJ" "$WD_RF" --section '§1' --actor 'x <DD MMMM YYYY - HH.mm WIB>' --text hidden

# Failure cannot publish a blank timestamp or partial row/project.
WD_BEFORE="$(cksum < "$WD_P/LOG.md")"
pwtest_rc 2 'LOG formatter failure is loud' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PWTEST_DATE_FAIL=1 "$WD_ST" log "$WD_PROJ" you failed
pwtest_eq 'failed LOG write keeps bytes' "$WD_BEFORE" "$(cksum < "$WD_P/LOG.md")"
WD_BEFORE="$(cksum < "$WD_P/context/INDEX.md")"
pwtest_rc 2 'context formatter failure is loud' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PWTEST_DATE_FAIL=1 "$WD_CT" add-input "$WD_PROJ" --file failed.md --what failure --source test
pwtest_eq 'failed context write keeps bytes' "$WD_BEFORE" "$(cksum < "$WD_P/context/INDEX.md")"
WD_BEFORE="$(cksum < "$WD_P/$WD_RF")"
pwtest_rc 2 'review formatter failure aborts staged write' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PWTEST_DATE_FAIL=1 "$WD_RV" add-item "$WD_PROJ" "$WD_RF" --section '§1' --text failure
pwtest_eq 'failed review write keeps bytes' "$WD_BEFORE" "$(cksum < "$WD_P/$WD_RF")"
pwtest_rc 1 'scaffold formatter failure before directory creation' env PATH="$WD_PATH" PWTEST_NATIVE_DATE="$WD_REAL_DATE" PWTEST_CLOCK="$WD_CLOCK" PWTEST_DATE_FAIL=1 PW_PROJECTS="$PW_PROJECTS_DIR" PW_REPOS="$PW_REPOS" bash "$(pwtest_script scaffold.sh)" wib-failed
[ ! -e "$PW_PROJECTS_DIR/wib-failed" ] && pwtest_ok 'failed scaffold creates nothing' || pwtest_bad 'failed scaffold' 'partial project remains'
for WD_SOURCE in template/analysis/_TEMPLATE.md template/task/_TEMPLATE-orchestration-plan.md template/PROJECT.template.md template/_REVIEW.template.md tooling/skill/project-workflow/SKILL.md tooling/skill/pw-review/SKILL.md tooling/skill/pw-rfc/SKILL.md; do
  pwtest_grep_file 'DD MMMM YYYY - HH.mm WIB' "canonical timestamp guidance $WD_SOURCE" "$PW_HOME/$WD_SOURCE"
done
rm -rf "$WD_BIN" "$WD_P"
unset -f _wd_run _wd_parser_cases
