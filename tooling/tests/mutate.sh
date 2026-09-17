# shellcheck shell=bash
# mutate.sh — meta-test (plan 16 §3): revert a documented fix, the harness MUST fail.
# expectations/mutations.tsv columns (TAB): id \t file(tooling/…) \t OLD \t NEW \t tiers \t only
# Applied via python3 exact-string replace in the working tree; always restored (trap).
#
# Plan 19 hardening:
#   • every child runs under a watchdog (PWTEST_MUT_TIMEOUT, default 300 s). A timeout is
#     recorded as HUNG — the file is restored, the sweep CONTINUES, and the run exits non-zero
#     listing the hung rows. A stuck child can no longer stall the whole sweep forever.
#   • one progress line per row: "MUT n/N <id> rc=<rc> <elapsed>s".
#   • non-blocking warning if the whole sweep exceeds 600 s.

# _pwtest_timeout <secs> <cmd…> — run cmd under a timeout; sets PWTEST_TMO_HIT=1 on timeout
# and returns 124. Prefers coreutils timeout/gtimeout; falls back to a 1 s-granularity poll
# shim that kills the command's process subtree (cmd is expected to `exec` into the real work).
_pwtest_timeout() {
  local secs="$1"; shift
  PWTEST_TMO_HIT=0
  local rc=0
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    local tmo=timeout; command -v timeout >/dev/null 2>&1 || tmo=gtimeout
    "$tmo" "$secs" "$@"; rc=$?
    [ "$rc" = 124 ] && PWTEST_TMO_HIT=1
    return $rc
  fi
  local flag="${PWTEST_ROOT:-/tmp}/.tmo.$$.flag" pid
  rm -f "$flag"
  "$@" & pid=$!
  ( local w=0
    while [ "$w" -lt "$secs" ]; do kill -0 "$pid" 2>/dev/null || exit 0; sleep 1; w=$((w+1)); done
    kill -0 "$pid" 2>/dev/null || exit 0
    : > "$flag"
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null ) &
  wait "$pid"; rc=$?
  if [ -f "$flag" ]; then rm -f "$flag"; PWTEST_TMO_HIT=1; return 124; fi
  return $rc
}

pwtest_run_mutations() {
  local filter="$1" runner="$2"
  local id file old new tiers only rc n=0 caught=0 hung=0 _orig _rowel
  local hung_ids=""
  local _bak="${PWTEST_KEEP_DIR:-$PWTEST_ROOT/mut}"; mkdir -p "$_bak"
  local _sw0=$SECONDS
  local total
  total="$(awk -F'\t' -v f="$filter" '!/^#/ && $1 { if (f=="" || f=="all" || $1 ~ f) c++ } END{print c+0}' "$TOOL/tests/expectations/mutations.tsv")"
  local tmo="${PWTEST_MUT_TIMEOUT:-300}"
  command -v python3 >/dev/null 2>&1 || { echo "mutate: python3 required" >&2; return 2; }
  # plan 19 F2: one warm build into a shared pristine cache; children then copy (~1-2 s)
  # instead of paying the ~46 s fixture build each. Cache lives OUTSIDE PWTEST_ROOT (the
  # parent's EXIT trap wipes that). Override dir: PWTEST_MUT_CACHE; disable: PWTEST_FIXTURE_CACHE="".
  local cache="${PWTEST_MUT_CACHE:-${TMPDIR:-/tmp}/pwtest-fixture-cache}"
  mkdir -p "$cache" 2>/dev/null || true
  export PWTEST_FIXTURE_CACHE="$cache"
  local _h="" _wt
  _h="$(_pwtest_recipe_hash 2>/dev/null)" || _h=""
  if [ -n "$_h" ] && [ -f "$cache/$_h/.done-$S2" ]; then
    pwtest_note "MUT warm cache present ($_h)"
  else
    _wt=$SECONDS
    PWTEST_WARM=1 PWTEST_FORCE_FIXTURES=1 bash "$runner" --tier T0 </dev/null >"$_bak/warm.log" 2>&1 \
      || pwtest_note "MUT warm FAILED — children fall back to per-run builds (see $_bak/warm.log)"
    pwtest_note "MUT warm cache $((SECONDS-_wt))s"
  fi
  ( cd "$cache" 2>/dev/null && ls -1t 2>/dev/null | tail -n +6 | while read -r d; do [ -d "$d" ] && rm -rf "$d"; done ) 2>/dev/null || true
  while IFS=$'\t' read -r id file old new tiers only; do
    case "$id" in ''|'#'*) continue ;; esac
    if [ -n "$filter" ] && [ "$filter" != all ]; then
      printf '%s' "$id" | grep -qE -- "$filter" || continue
    fi
    [ -n "$tiers" ] || tiers=T0
    n=$((n+1)); id="${id%%|*}"; _rowel=$SECONDS
    pwtest_note "MUTATE $id"
    python3 -c "import sys; sys.exit(0 if sys.argv[1] in open(sys.argv[2], encoding='utf-8').read() else 1)" "$old" "$TOOL/$file" \
      || { pwtest_bad "$id drift" "old pattern not in $file — update mutations.tsv"; continue; }
    local _orig="$_bak/$(printf '%s' "$file" | tr '/.' '__')"; cp "$TOOL/$file" "$_orig"
    _pwt_mutable_push "$TOOL/$file|$_orig"
    ( cd "$TOOL" && python3 -c "import sys
old,new,fn=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(fn,encoding='utf-8').read(); assert old in s, 'anchor vanished'
open(fn,'w',encoding='utf-8').write(s.replace(old,new))" "$old" "$new" "$file" ) \
      || { pwtest_bad "$id" "apply failed"; cp "$_orig" "$TOOL/$file"; continue; }
    local sub_rc=0
    _pwtest_timeout "$tmo" bash -c "cd '$TOOL/tests' && PWTEST_INNER=1 exec bash '$runner' --tier '$tiers' ${only:+--only '$only'} </dev/null >'$_bak/$id.child.log' 2>&1" || sub_rc=$?
    cp "$_orig" "$TOOL/$file"; rm -f "$_orig"
    _pwt_mutable_pop "$TOOL/$file|$_orig"
    if [ "$PWTEST_TMO_HIT" = 1 ]; then
      hung=$((hung+1)); hung_ids="$hung_ids $id"
      pwtest_bad "$id" "HUNG — child exceeded ${tmo}s (killed; tree restored) — see child log: $_bak/$id.child.log"
    elif [ "$sub_rc" -gt 0 ] && [ "$sub_rc" -le 1 ]; then
      caught=$((caught+1)); pwtest_ok "mutation caught: $id"
    elif [ "$sub_rc" = 2 ]; then
      pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log in kept dir"; cp "$_bak/$id.child.log" "$PWTEST_ROOT/mut-$id.child.log"
    else
      pwtest_bad "$id" "VACUOUS: reverted $file on --tier $tiers and everything stayed green"
    fi
    printf 'MUT %s/%s %s rc=%s %ss\n' "$n" "$total" "$id" "$sub_rc" "$((SECONDS-_rowel))" >&2
  done < "$TOOL/tests/expectations/mutations.tsv"
  local _el=$((SECONDS-_sw0))
  printf '\nmutate: %d mutations, %d caught, %d hung, %d vacuous/drift — %ss total\n' "$n" "$caught" "$hung" "$((n-caught-hung))" "$_el" >&2
  [ -n "$hung_ids" ] && printf 'mutate: HUNG rows:%s\n' "$hung_ids" >&2
  [ "$_el" -gt 600 ] && printf 'mutate: WARN sweep took %ss (>600) — see tooling/docs/testing.md (timing canary, non-blocking)\n' "$_el" >&2
  [ "$n" -gt 0 ] && [ "$caught" -eq "$n" ]
}
