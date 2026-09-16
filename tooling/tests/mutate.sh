# shellcheck shell=bash
# mutate.sh — meta-test (plan 16 §3): revert a documented fix, the harness MUST fail.
# expectations/mutations.tsv columns (TAB): id \t file(tooling/…) \t OLD \t NEW \t tiers \t only
# Applied via python3 exact-string replace in the working tree; always restored (trap).

pwtest_run_mutations() {
  local filter="$1" runner="$2"
  local id file old new tiers only rc n=0 caught=0 _orig
  local _bak="${PWTEST_KEEP_DIR:-$PWTEST_ROOT/mut}"; mkdir -p "$_bak"
  command -v python3 >/dev/null 2>&1 || { echo "mutate: python3 required" >&2; return 2; }
  while IFS=$'\t' read -r id file old new tiers only; do
    case "$id" in ''|'#'*) continue ;; esac
    if [ -n "$filter" ] && [ "$filter" != all ]; then
      printf '%s' "$id" | grep -qE -- "$filter" || continue
    fi
    [ -n "$tiers" ] || tiers=T0
    n=$((n+1)); id="${id%%|*}"
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
    ( cd "$TOOL/tests" && PWTEST_INNER=1 bash "$runner" --tier "$tiers" ${only:+--only "$only"} </dev/null >"$_bak/$id.child.log" 2>&1 ) || sub_rc=$?
    cp "$_orig" "$TOOL/$file"; rm -f "$_orig"
    _pwt_mutable_pop "$TOOL/$file|$_orig"
    if [ "$sub_rc" -gt 0 ] && [ "$sub_rc" -le 1 ]; then
      caught=$((caught+1)); pwtest_ok "mutation caught: $id"
    elif [ "$sub_rc" = 2 ]; then
      pwtest_bad "$id" "child runner died (fixture/setup issue, rc=2) — see child log in kept dir"; cp "$_bak/$id.child.log" "$PWTEST_ROOT/mut-$id.child.log"
    else
      pwtest_bad "$id" "VACUOUS: reverted $file on --tier $tiers and everything stayed green"
    fi
  done < "$TOOL/tests/expectations/mutations.tsv"
  printf '\nmutate: %d mutations, %d caught, %d vacuous/drift\n' "$n" "$caught" "$((n-caught))" >&2
  [ "$n" -gt 0 ] && [ "$caught" -eq "$n" ]
}
