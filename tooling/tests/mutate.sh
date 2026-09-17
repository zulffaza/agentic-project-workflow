# shellcheck shell=bash
# mutate.sh — meta-test (plan 16 §3): revert a documented fix, the harness MUST fail.
# expectations/mutations.tsv columns (TAB): id \t file(tooling/…) \t OLD \t NEW \t tiers \t only
# Applied via python3 exact-string replace; always restored (trap/worker copy).
#
# Plan 19 hardening:
#   • every child runs under a watchdog (PWTEST_MUT_TIMEOUT, default 300 s). A timeout is
#     recorded as HUNG — the file is restored, the sweep CONTINUES, and the run exits non-zero
#     listing the hung rows. A stuck child can no longer stall the whole sweep forever.
#   • one progress line per row: "MUT n/N <id> rc=<rc> <elapsed>s" (serial) / "MUT <id> …" (parallel).
#   • non-blocking warning if the whole sweep exceeds 600 s.
#   • PARALLEL (F5, PWTEST_MUT_JOBS>1, default auto): one WORKER per row, each operating on a
#     disposable rsync copy of the bundle (excluding .git, ~1.3 MB). Mutations never touch the
#     live tree, so workers cannot see each other's reverted files — the false-"caught" hazard
#     of parallel-on-live — and same-file rows need no serialization because copies are
#     independent. PWTEST_MUT_JOBS=1 keeps the original serial live-tree path (with the
#     crash-safety stack).

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

# _pwtest_run_row <root> <id> <file> <old> <new> <tiers> <only> <logdir> <runner> — apply the
# revert inside <root>, run one harness child, restore. Sets MUT_STATUS
# (caught|hung|vacuous|died|drift|applyfail), MUT_RC, MUT_ELAPSED. No stack bookkeeping here —
# the serial live-tree caller wraps it with _pwt_mutable_push/pop; workers use disposable copies.
_pwtest_run_row() {
  local root="$1" id="$2" file="$3" old="$4" new="$5" tiers="$6" only="$7" logdir="$8" runner="$9"
  local target="$root/tooling/$file" t0=$SECONDS rc=0
  MUT_RC=0; MUT_ELAPSED=0
  python3 -c "import sys; sys.exit(0 if sys.argv[1] in open(sys.argv[2], encoding='utf-8').read() else 1)" "$old" "$target" \
    || { MUT_STATUS=drift; return 0; }
  local bak="$logdir/$id.orig"; cp "$target" "$bak"
  ( cd "$root/tooling" && python3 -c "import sys
old,new,fn=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(fn,encoding='utf-8').read(); assert old in s, 'anchor vanished'
open(fn,'w',encoding='utf-8').write(s.replace(old,new))" "$old" "$new" "$file" ) \
    || { cp "$bak" "$target"; rm -f "$bak"; MUT_STATUS=applyfail; return 0; }
  _pwtest_timeout "${PWTEST_MUT_TIMEOUT:-300}" bash -c "cd '$root/tooling/tests' && PWTEST_INNER=1 exec bash '$runner' --tier '$tiers' ${only:+--only '$only'} </dev/null >'$logdir/$id.child.log' 2>&1" || rc=$?
  cp "$bak" "$target"; rm -f "$bak"
  MUT_RC=$rc; MUT_ELAPSED=$((SECONDS-t0))
  if [ "$PWTEST_TMO_HIT" = 1 ]; then MUT_STATUS=hung
  elif [ "$rc" -gt 0 ] && [ "$rc" -le 1 ]; then MUT_STATUS=caught
  elif [ "$rc" = 2 ]; then MUT_STATUS=died
  else MUT_STATUS=vacuous; fi
  return 0
}

# _pwtest_mut_worker <src-root> <rows-tsv> <start> <end> <base> <cache> <resdir> — one file-group:
# copy the bundle once, run its rows serially on the copy, publish per-row results.
_pwtest_mut_worker() {
  local src="$1" tsv="$2" rng="$3" base="$4" cache="$5" resdir="$6"
  local wt="$base/wt.$rng" id file old new tiers only n=0
  mkdir -p "$wt" "$resdir"
  if ! rsync -a --exclude .git "$src/" "$wt/"; then
    printf 'copyfail\t%s\n' "$rng" >> "$resdir/results.tsv"; return 1
  fi
  local start="${rng%-*}" end="${rng#*-}"
  while IFS=$'\t' read -r id file old new tiers only; do
    n=$((n+1)); [ "$n" -lt "$start" ] && continue; [ "$n" -gt "$end" ] && break
    [ -n "$tiers" ] || tiers=T0
    id="${id%%|*}"
    _pwtest_run_row "$wt" "$id" "$file" "$old" "$new" "$tiers" "$only" "$resdir" "$wt/tooling/tests/pw_test.sh"
    printf '%s\t%s\t%s\n' "$id" "$MUT_STATUS" "$MUT_ELAPSED" >> "$resdir/results.tsv"
    printf 'MUT %s %s %ss\n' "$id" "$MUT_STATUS" "$MUT_ELAPSED" >&2
  done < "$tsv"
  rm -rf "$wt"
  return 0
}

pwtest_run_mutations() {
  local filter="$1" runner="$2"
  local id file old new tiers only n=0 caught=0 hung=0 _rowel
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

  # --- scheduling (F5): one worker per row (disposable copies make same-file rows independent) ---
  local rows="$PWTEST_ROOT/mut-rows.tsv" ranges="$PWTEST_ROOT/mut-ranges.txt"
  awk -F'\t' -v f="$filter" '!/^#/ && $1 { if (f=="" || f=="all" || $1 ~ f) print }' "$TOOL/tests/expectations/mutations.tsv" > "$rows"
  local nrows; nrows="$(grep -c . "$rows" 2>/dev/null || echo 0)"
  seq 1 "$nrows" | awk '{print $1"-"$1}' > "$ranges"
  local jobs="${PWTEST_MUT_JOBS:-}"
  if [ -z "$jobs" ]; then
    jobs="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    [ "${jobs:-1}" -gt 8 ] && jobs=8
    [ "$jobs" -gt "$nrows" ] && jobs="$nrows"
  fi
  [ "${jobs:-1}" -lt 1 ] && jobs=1

  if [ "$jobs" -le 1 ] || [ "$nrows" -le 1 ]; then
    # --- serial path (live tree, crash-safety stack) — original semantics ---
    while IFS=$'\t' read -r id file old new tiers only; do
      case "$id" in ''|'#'*) continue ;; esac
      if [ -n "$filter" ] && [ "$filter" != all ]; then
        printf '%s' "$id" | grep -qE -- "$filter" || continue
      fi
      [ -n "$tiers" ] || tiers=T0
      n=$((n+1)); id="${id%%|*}"; _rowel=$SECONDS
      pwtest_note "MUTATE $id"
      # crash-safety: _pwtest_run_row backs up to $_bak/$id.orig and restores it; the stack
      # entry lets the EXIT trap replay the restore if the sweep is killed mid-row.
      _pwt_mutable_push "$TOOL/$file|$_bak/$id.orig"
      _pwtest_run_row "$PW_HOME" "$id" "$file" "$old" "$new" "$tiers" "$only" "$_bak" "$runner"
      _pwt_mutable_pop "$TOOL/$file|$_bak/$id.orig"
      case "$MUT_STATUS" in
        caught)   caught=$((caught+1)); pwtest_ok "mutation caught: $id" ;;
        hung)     hung=$((hung+1)); hung_ids="$hung_ids $id"
                  pwtest_bad "$id" "HUNG — child exceeded ${tmo}s (killed; tree restored) — see child log: $_bak/$id.child.log" ;;
        died)     pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log in kept dir"; cp "$_bak/$id.child.log" "$PWTEST_ROOT/mut-$id.child.log" ;;
        drift)    pwtest_bad "$id drift" "old pattern not in $file — update mutations.tsv" ;;
        applyfail) pwtest_bad "$id" "apply failed" ;;
        *)        pwtest_bad "$id" "VACUOUS: reverted $file on --tier $tiers and everything stayed green" ;;
      esac
      printf 'MUT %s/%s %s rc=%s %ss\n' "$n" "$total" "$id" "$MUT_RC" "$((SECONDS-_rowel))" >&2
    done < "$TOOL/tests/expectations/mutations.tsv"
  else
    # --- parallel path (F5): one disposable bundle-copy per file-group ---
    pwtest_note "MUT parallel: $nrows rows on $jobs workers (disposable bundle copies)"
    local wbase="$PWTEST_ROOT/mut-workers" resdir="$PWTEST_ROOT/mut-results"
    mkdir -p "$wbase" "$resdir"
    local fifo="$PWTEST_ROOT/mut-fifo" rng _tok
    [ -p "$fifo" ] || mkfifo "$fifo" || { echo "mutate: mkfifo failed" >&2; return 2; }
    exec 9<>"$fifo" || { echo "mutate: semaphore init failed" >&2; return 2; }
    local _i=0; while [ "$_i" -lt "$jobs" ]; do printf '\n' >&9; _i=$((_i+1)); done
    while IFS= read -r rng; do
      [ -n "$rng" ] || continue
      read -r _tok <&9
      ( _pwtest_mut_worker "$PW_HOME" "$rows" "$rng" "$wbase" "$cache" "$resdir"; printf '\n' >&9 ) &
    done < "$ranges"
    wait
    exec 9>&- ; exec 9<&-
    # aggregate in original row order (stable counters + progress)
    n=0
    while IFS=$'\t' read -r id file old new tiers only; do
      n=$((n+1)); id="${id%%|*}"
      local st; st="$(awk -F'\t' -v i="$id" '$1==i{print $2; exit}' "$resdir/results.tsv" 2>/dev/null)"
      local el;  el="$(awk -F'\t' -v i="$id" '$1==i{print $3; exit}' "$resdir/results.tsv" 2>/dev/null)"
      cp "$resdir/$id.child.log" "$_bak/$id.child.log" 2>/dev/null || true
      case "$st" in
        caught)   caught=$((caught+1)); pwtest_ok "mutation caught: $id" ;;
        hung)     hung=$((hung+1)); hung_ids="$hung_ids $id"
                  pwtest_bad "$id" "HUNG — child exceeded ${tmo}s (killed; worker copy discarded) — see child log: $_bak/$id.child.log" ;;
        died)     pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log: $_bak/$id.child.log" ;;
        drift)    pwtest_bad "$id drift" "old pattern not in $file — update mutations.tsv" ;;
        applyfail) pwtest_bad "$id" "apply failed" ;;
        ''|copyfail) pwtest_bad "$id" "worker produced no result (copy failure?)" ;;
        *)        pwtest_bad "$id" "VACUOUS: reverted $file on --tier $tiers and everything stayed green" ;;
      esac
      printf 'MUT %s/%s %s %s %ss\n' "$n" "$total" "$id" "${st:-none}" "${el:-0}" >&2
    done < "$rows"
  fi

  local _el=$((SECONDS-_sw0))
  printf '\nmutate: %d mutations, %d caught, %d hung, %d vacuous/drift — %ss total\n' "$n" "$caught" "$hung" "$((n-caught-hung))" "$_el" >&2
  [ -n "$hung_ids" ] && printf 'mutate: HUNG rows:%s\n' "$hung_ids" >&2
  [ "$_el" -gt 600 ] && printf 'mutate: WARN sweep took %ss (>600) — see tooling/docs/testing.md (timing canary, non-blocking)\n' "$_el" >&2
  [ "$n" -gt 0 ] && [ "$caught" -eq "$n" ]
}
