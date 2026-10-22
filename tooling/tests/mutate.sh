# shellcheck shell=bash
# mutate.sh — meta-test (plan 16 §3): revert a documented fix, the harness MUST fail.
# expectations/mutations.tsv columns (TAB): id \t file(tooling/…) \t OLD \t NEW \t tiers \t only
# Applied via python3 exact-string replace; always restored (trap/worker copy).
#
# Plan 19 hardening:
#   • every child runs under a watchdog (PWTEST_MUT_TIMEOUT, or a per-row value derived
#     from the measured per-case durations). A timeout is recorded as HUNG — the file is
#     restored, the sweep CONTINUES, and the run exits non-zero listing the hung rows.
#     A row that times out under sweep contention is re-run ALONE with a longer watchdog
#     first, so a watchdog kill is never reported as a verdict.
#   • one progress line per row: "MUT n/N <id> rc=<rc> <elapsed>s" (serial) / "MUT <id> …" (parallel).
#   • non-blocking warning if the whole sweep exceeds 600 s.
#   • PARALLEL (F5, PWTEST_MUT_JOBS>1, default auto): one WORKER per row, each operating on a
#     disposable rsync copy of the bundle (excluding .git and ignored .cache scratch).
#     Mutations never touch the
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
    # SIGTERM alone is not enough: a shell waiting on a long foreground command defers the
    # signal until that command returns, so the child could outlive the watchdog by hours.
    # Escalate to SIGKILL so the watchdog is a real bound.
    local ka=""
    case "$("$tmo" --help 2>&1 || true)" in *kill-after*) ka="--kill-after=30" ;; esac
    "$tmo" $ka "$secs" "$@"; rc=$?
    [ "$rc" = 124 ] && PWTEST_TMO_HIT=1
    return $rc
  fi
  # the shim's flag file must be unique per call: parallel sweep workers share the
  # parent's $$, so a fixed name let one worker's timeout be read as another's.
  local flag; flag="$(mktemp "${TMPDIR:-/tmp}/.tmo.XXXXXX" 2>/dev/null)" \
    || flag="${PWTEST_ROOT:-/tmp}/.tmo.$$.${RANDOM:-0}.flag"
  rm -f "$flag"
  local pid
  "$@" & pid=$!
  ( local w=0
    while [ "$w" -lt "$secs" ]; do kill -0 "$pid" 2>/dev/null || exit 0; sleep 1; w=$((w+1)); done
    kill -0 "$pid" 2>/dev/null || exit 0
    : > "$flag"
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    sleep 2
    kill -9 "$pid" 2>/dev/null ) &
  wait "$pid"; rc=$?
  if [ -f "$flag" ]; then rm -f "$flag"; PWTEST_TMO_HIT=1; return 124; fi
  rm -f "$flag"
  return $rc
}

# _pwtest_row_timeout <tiers> <only> <root> [jobs] — watchdog seconds for ONE row.
# A flat 300 s fitted an era when a T1 case file took seconds. The slowest ones now take
# 90-200 s each, and the parallel sweep inflates that further through host contention, so a
# flat ceiling killed rows that were never stuck. The watchdog is therefore derived from the
# measured per-case durations (the T1 tier records them) and scaled by how many children
# share the host: with N workers a child gets roughly 1/N of the machine, and the inflation
# over the measured single-child time is about (1+N)/2 (measured ~3.7x with 8 workers on a
# loaded host). No table, or a non-T1 tier, falls back to the ceiling.
_pwtest_row_timeout() {
  local tiers="$1" only="$2" root="$3" jobs="${4:-}"
  if [ -n "${PWTEST_MUT_TIMEOUT:-}" ]; then printf '%s' "$PWTEST_MUT_TIMEOUT"; return 0; fi
  local floor="${PWTEST_MUT_TIMEOUT_MIN:-300}" ceiling="${PWTEST_MUT_TIMEOUT_MAX:-1800}"
  [ -n "$jobs" ] || jobs="${PWTEST_MUT_JOBS:-8}"
  [ "$jobs" -lt 1 ] && jobs=1
  case "$tiers" in
    T1) ;;
    *) printf '%s' "$ceiling"; return 0 ;;
  esac
  local est=0 c s
  if [ -f "${PWTEST_CASE_TIMES:-}" ]; then
    for c in "$root/tooling/tests/cases"/*.t.sh; do
      [ -f "$c" ] || continue
      [ -n "$only" ] && { printf '%s' "$(basename "$c")" | grep -q -- "$only" || continue; }
      s="$(awk -F'\t' -v n="$(basename "$c" .t.sh)" '$1==n{v=$2} END{print v+0}' "$PWTEST_CASE_TIMES")"
      est=$((est + s))
    done
  fi
  # (1+workers)/2 covers the contention; +60 covers the disposable copy and the
  # fixture-cache restore.
  local tmo=$(( est * (1 + jobs) / 2 + 60 ))
  [ "$tmo" -lt "$floor" ] && tmo="$floor"
  [ "$tmo" -gt "$ceiling" ] && tmo="$ceiling"
  printf '%s' "$tmo"
}

# _pwtest_run_row <root> <id> <file> <old> <new> <tiers> <only> <logdir> <runner> [timeout] [baselog] [baserc] —
# apply the revert inside <root>, run one harness child, restore. Sets MUT_STATUS
# (caught|hung|vacuous|baselinered|died|drift|applyfail), MUT_RC, MUT_ELAPSED, MUT_NEWFAILS.
# No stack bookkeeping here — the serial live-tree caller wraps it with
# _pwt_mutable_push/pop; workers use disposable copies.
# _pwt_resolve <bundle-root> <script-basename> — layout resolver (scripts/{entities,lib,toolchain}/
# + tooling root + bundle root); the register's file column stays a basename so layout moves
# never touch anchors.
_pwt_resolve() {
  local r="$1" n="$2" d
  for d in "$r/tooling/scripts/entities" "$r/tooling/scripts/lib" "$r/tooling/scripts/toolchain" "$r/tooling" "$r"; do
    [ -f "$d/$n" ] && { printf '%s/%s' "$d" "$n"; return 0; }
  done
  return 1
}
# _pwtest_sel_tag <tiers> <only> — a filesystem-safe tag for one (tier, only) selection.
_pwtest_sel_tag() {
  printf '%s' "${1}_${2}" | tr -c 'A-Za-z0-9_-' '_'
}
# _pwtest_fail_names <logfile> — the names of the failing assertions in a child log.
# A FAIL line reads "  FAIL <name> — <detail>"; the name is the stable part.
_pwtest_fail_names() {
  [ -f "$1" ] || return 0
  grep '^  FAIL ' "$1" | awk -F' — ' '{print $1}' | sort -u
}
# _pwtest_attribute <baseline-log> <child-log> — the failing assertions the mutated child
# has that the unmutated baseline did not. A catch needs a NEW failure: a tree that is
# already red for an environmental reason must not turn every row into a false catch, and
# a red baseline must not mask a real catch.
_pwtest_attribute() {
  local base="$1" child="$2"
  [ -f "$base" ] && [ -f "$child" ] || return 0
  comm -13 <(_pwtest_fail_names "$base") <(_pwtest_fail_names "$child") | tr '\n' ' '
}
_pwtest_run_row() {
  local root="$1" id="$2" file="$3" old="$4" new="$5" tiers="$6" only="$7" logdir="$8" runner="$9" tmo="${10:-}" baselog="${11:-}" baserc="${12:-}"
  local target rel t0=$SECONDS rc=0 MUT_NEWFAILS MUT_NOBASE
  target="$(_pwt_resolve "$root" "$file")" || { MUT_STATUS=drift; return 0; }
  rel="${target#"$root/tooling/"}"
  MUT_RC=0; MUT_ELAPSED=0
  python3 -c "import sys; sys.exit(0 if sys.argv[1] in open(sys.argv[2], encoding='utf-8').read() else 1)" "$old" "$target" \
    || { MUT_STATUS=drift; return 0; }
  local bak="$logdir/$id.orig"; cp "$target" "$bak"
  ( cd "$root/tooling" && python3 -c "import sys
old,new,fn=sys.argv[1],sys.argv[2],sys.argv[3]
s=open(fn,encoding='utf-8').read(); assert old in s, 'anchor vanished'
open(fn,'w',encoding='utf-8').write(s.replace(old,new))" "$old" "$new" "$rel" ) \
    || { cp "$bak" "$target"; rm -f "$bak"; MUT_STATUS=applyfail; return 0; }
  [ -n "$tmo" ] || tmo="$(_pwtest_row_timeout "$tiers" "$only" "$root" "${PWTEST_MUT_JOBS:-}")"
  _pwtest_timeout "$tmo" bash -c "cd '$root/tooling/tests' && PWTEST_INNER=1 exec bash '$runner' --tier '$tiers' ${only:+--only '$only'} </dev/null >'$logdir/$id.child.log' 2>&1" || rc=$?
  cp "$bak" "$target"; rm -f "$bak"
  MUT_RC=$rc; MUT_ELAPSED=$((SECONDS-t0))
  if [ "$PWTEST_TMO_HIT" = 1 ]; then MUT_STATUS=hung
  elif [ "$rc" = 2 ]; then MUT_STATUS=died
  else
    # Attribution: a failing child only counts as a catch when the mutation introduced a
    # failing assertion the unmutated tree did not already have. A tree that is red for
    # an environmental reason (a disposable copy cannot match the installed provider
    # bodies, which are stamped with the source PW_HOME) would otherwise turn every row
    # into a false catch — and, in the other direction, a red baseline would mask a real
    # catch. The baseline diff separates the two.
    MUT_NEWFAILS=""; MUT_NOBASE=0
    if [ -n "$baselog" ] && [ -f "$baselog" ]; then
      MUT_NEWFAILS="$(_pwtest_attribute "$baselog" "$logdir/$id.child.log")"
    else
      MUT_NOBASE=1
    fi
    # a child that dies before recording an assertion is still a detection: the mutation
    # broke the run. It only counts when the unmutated tree ran that selection cleanly.
    if [ -z "$MUT_NEWFAILS" ] && [ "$rc" != 0 ] && [ "$rc" != 2 ] && [ "$MUT_NOBASE" = 0 ] \
       && [ "${baserc:-0}" = 0 ] && [ -z "$(_pwtest_fail_names "$logdir/$id.child.log")" ]; then
      MUT_NEWFAILS="child exited $rc without recording an assertion"
    fi
    if [ -n "$MUT_NEWFAILS" ]; then MUT_STATUS=caught
    elif [ "$MUT_NOBASE" = 1 ]; then MUT_STATUS=baselinered
    elif [ "$rc" = 0 ]; then MUT_STATUS=vacuous
    else MUT_STATUS=baselinered; fi
  fi
  return 0
}

# _pwtest_mut_retry <src-root> <id> <file> <old> <new> <tiers> <only> <timeout> <base> <resdir> —
# re-run ONE row in a fresh disposable copy with a longer watchdog, alone (no sweep
# contention). A watchdog kill is not a verdict, so a row that timed out under parallel
# load is re-measured before the sweep calls it hung. Sets MUT_STATUS.
_pwtest_mut_retry() {
  local src="$1" id="$2" file="$3" old="$4" new="$5" tiers="$6" only="$7" tmo="$8" base="$9" resdir="${10}"
  local wt="$base/retry.$id"
  local runner="$wt/tooling/tests/pw_test.sh"
  rm -rf "$wt"
  mkdir -p "$wt" || { MUT_STATUS=hung; return 0; }
  rsync -a --exclude .git --exclude .cache "$src/" "$wt/" || { rm -rf "$wt"; MUT_STATUS=hung; return 0; }
  local _brc; _brc="$(awk -F'\t' -v t="$tiers" -v o="$only" '$1==t && $2==o{print $3; exit}' "$resdir/baseline.tsv" 2>/dev/null)"
  _pwtest_run_row "$wt" "$id" "$file" "$old" "$new" "$tiers" "$only" "$resdir" "$runner" "$tmo" \
    "$resdir/base.$(_pwtest_sel_tag "$tiers" "$only").log" "${_brc:-0}"
  rm -rf "$wt"
  return 0
}

# _pwtest_mut_baseline <src-root> <tiers> <only> <base> <resdir> — run the row's selection
# WITHOUT any mutation, in a disposable copy, and record the exit code. A green baseline is
# what makes a failing child attributable to the mutation. A red baseline means the tree (or
# its environment) is already broken, and the row's failure would be a false catch: the
# mutation sweep then reports the baseline, not a catch.
_pwtest_mut_baseline() {
  local src="$1" tiers="$2" only="$3" base="$4" resdir="$5"
  local tag; tag="$(_pwtest_sel_tag "$tiers" "$only")"
  local wt="$base/base.$tag"
  local runner="$wt/tooling/tests/pw_test.sh"
  local rc=0
  local tmo; tmo="$(_pwtest_row_timeout "$tiers" "$only" "$src")"
  rm -rf "$wt"; mkdir -p "$wt" || { printf '%s\t%s\t2\n' "$tiers" "$only" >> "$resdir/baseline.tsv"; return 0; }
  rsync -a --exclude .git --exclude .cache "$src/" "$wt/" \
    || { rm -rf "$wt"; printf '%s\t%s\t2\n' "$tiers" "$only" >> "$resdir/baseline.tsv"; return 0; }
  _pwtest_timeout "$tmo" bash -c "cd '$wt/tooling/tests' && PWTEST_INNER=1 exec bash '$runner' --tier '$tiers' ${only:+--only '$only'} </dev/null >'$resdir/base.$tag.log' 2>&1" || rc=$?
  rm -rf "$wt"
  printf '%s\t%s\t%s\n' "$tiers" "$only" "$rc" >> "$resdir/baseline.tsv"
  return 0
}

# _pwtest_mut_worker <src-root> <rows-tsv> <start> <end> <base> <cache> <resdir> — one file-group:
# copy the bundle once, run its rows serially on the copy, publish per-row results.
_pwtest_mut_worker() {
  local src="$1" tsv="$2" rng="$3" base="$4" cache="$5" resdir="$6"
  local wt="$base/wt.$rng" id file old new tiers only n=0
  mkdir -p "$wt" "$resdir"
  if ! rsync -a --exclude .git --exclude .cache "$src/" "$wt/"; then
    printf 'copyfail\t%s\n' "$rng" >> "$resdir/results.tsv"; return 1
  fi
  local start="${rng%-*}" end="${rng#*-}"
  while IFS=$'\t' read -r id file old new tiers only; do
    n=$((n+1)); [ "$n" -lt "$start" ] && continue; [ "$n" -gt "$end" ] && break
    [ -n "$tiers" ] || tiers=T0
    id="${id%%|*}"
    local _brc; _brc="$(awk -F'\t' -v t="$tiers" -v o="$only" '$1==t && $2==o{print $3; exit}' "$resdir/baseline.tsv" 2>/dev/null)"
    _pwtest_run_row "$wt" "$id" "$file" "$old" "$new" "$tiers" "$only" "$resdir" "$wt/tooling/tests/pw_test.sh" "" \
      "$resdir/base.$(_pwtest_sel_tag "$tiers" "$only").log" "${_brc:-0}"
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
  local tmo="${PWTEST_MUT_TIMEOUT:-}"
  [ -n "$tmo" ] || tmo="${PWTEST_MUT_TIMEOUT_MAX:-900}"
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

  local wbase="$PWTEST_ROOT/mut-workers" resdir="$PWTEST_ROOT/mut-results"
  mkdir -p "$wbase" "$resdir"

  # --- baseline: the tree must be green before a failure can be blamed on a mutation ---
  # One unmutated child per distinct (tier, only) selection the rows use. A red baseline
  # means the tree or its environment is already broken: every row of that selection would
  # then "fail" for a reason the mutation did not cause, and the sweep would report false
  # catches. The rows of a red selection are reported as baseline-red instead.
  : > "$resdir/baseline.tsv"
  local pairs; pairs="$(awk -F'\t' '{print $5"\t"$6}' "$rows" | sort -u)"
  local _bpidx=0 _bpt _bpo _bpj=0
  while IFS=$'\t' read -r _bpt _bpo; do
    [ -n "$_bpt" ] || continue
    _bpidx=$((_bpidx+1))
    ( _pwtest_mut_baseline "$PW_HOME" "$_bpt" "$_bpo" "$wbase" "$resdir" ) &
    _bpj=$((_bpj+1))
    # portable barrier (no `wait -n` — the bundle still runs on bash 3.2)
    if [ "$_bpj" -ge "$jobs" ]; then wait; _bpj=0; fi
  done <<< "$pairs"
  wait
  local _bred; _bred="$(awk -F'\t' '$3 != 0 {c++} END{print c+0}' "$resdir/baseline.tsv")"
  [ "$_bred" -gt 0 ] && pwtest_note "MUT baseline: $_bred selection(s) are RED in the unmutated tree — rows in them are attributed by the baseline diff (a catch needs a NEW failing assertion) — see $resdir/base.*.log"

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
      _pwt_mutable_push "$(pwtest_script "$file")|$_bak/$id.orig"
      local _brc; _brc="$(awk -F'\t' -v t="$tiers" -v o="$only" '$1==t && $2==o{print $3; exit}' "$resdir/baseline.tsv" 2>/dev/null)"
      _pwtest_run_row "$PW_HOME" "$id" "$file" "$old" "$new" "$tiers" "$only" "$_bak" "$runner" "" \
        "$resdir/base.$(_pwtest_sel_tag "$tiers" "$only").log" "${_brc:-0}"
      _pwt_mutable_pop "$(pwtest_script "$file")|$_bak/$id.orig"
      case "$MUT_STATUS" in
        caught)   caught=$((caught+1)); pwtest_ok "mutation caught: $id" ;;
        hung)     hung=$((hung+1)); hung_ids="$hung_ids $id"
                  pwtest_bad "$id" "HUNG — child exceeded its watchdog (killed; tree restored) — see child log: $_bak/$id.child.log" ;;
        died)     pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log in kept dir"; cp "$_bak/$id.child.log" "$PWTEST_ROOT/mut-$id.child.log" ;;
        drift)    pwtest_bad "$id drift" "old pattern not in $file — update mutations.tsv" ;;
        applyfail) pwtest_bad "$id" "apply failed" ;;
        baselinered) pwtest_bad "$id" "BASELINE-RED — the child failed only on assertions the unmutated tree already failed; the mutation changed nothing — see $resdir/base.*.log" ;;
        *)        pwtest_bad "$id" "VACUOUS: reverted $file on --tier $tiers and everything stayed green" ;;
      esac
      printf 'MUT %s/%s %s rc=%s %ss\n' "$n" "$total" "$id" "$MUT_RC" "$((SECONDS-_rowel))" >&2
    done < "$TOOL/tests/expectations/mutations.tsv"
  else
    # --- parallel path (F5): one disposable bundle-copy per file-group ---
    pwtest_note "MUT parallel: $nrows rows on $jobs workers (disposable bundle copies)"
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

      # A watchdog kill is not a verdict: the child may simply have lost a race for the
      # host. Re-run that row alone (no sweep contention) with a longer watchdog before
      # the sweep calls it hung, so every row ends with a real caught/vacuous verdict.
      if [ "$st" = hung ]; then
        # the row's own derived watchdog, doubled — the re-run has no sweep contention
        local row_tmo rtmo
        row_tmo="$(_pwtest_row_timeout "$tiers" "$only" "$PW_HOME" 1)"
        rtmo=$(( row_tmo * 2 )); [ "$rtmo" -gt 1800 ] && rtmo=1800
        _pwtest_mut_retry "$PW_HOME" "$id" "$file" "$old" "$new" "$tiers" "$only" "$rtmo" "$wbase" "$resdir"
        rt="$MUT_STATUS"
        if [ "$rt" != hung ]; then
          st="$rt"; el="$MUT_ELAPSED"
          printf 'MUT %s/%s %s %s %ss (re-run alone after a watchdog kill)\n' "$n" "$total" "$id" "$st" "$el" >&2
        fi
      fi
      case "$st" in
        caught)   caught=$((caught+1)); pwtest_ok "mutation caught: $id" ;;
        hung)     hung=$((hung+1)); hung_ids="$hung_ids $id"
                  pwtest_bad "$id" "HUNG — child exceeded ${tmo}s twice (killed; tree restored) — see child log: $_bak/$id.child.log" ;;
        died)     pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log: $_bak/$id.child.log" ;;
        drift)    pwtest_bad "$id drift" "old pattern not in $file — update mutations.tsv" ;;
        applyfail) pwtest_bad "$id" "apply failed" ;;
        baselinered) pwtest_bad "$id" "BASELINE-RED — the child failed only on assertions the unmutated tree already failed; the mutation changed nothing — see $resdir/base.*.log" ;;
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
