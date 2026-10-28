#!/usr/bin/env bash
# ============================================================================
# change_record.sh — validate one change requirement/evidence record.
#
#   tests/change_record.sh check --mode draft    --record FILE [--evidence FILE]
#   tests/change_record.sh check --mode complete --record FILE [--evidence FILE]
#
# Test support, not a user command. The repository suite validates this checker
# and its fixtures; a maintainer points it at the actual local change record when
# auditing a delivery (see docs/testing.md §Change records).
#
# Record format: "# change-record v1", then TAB-separated rows:
#   id  requirement  implementation  verification  evidence  scope  note
#
# Evidence format: "# evidence-record v1", then TAB-separated rows:
#   id  command  identity  selection  result  exit
#
# Exit 0 = valid. Exit 1 = invalid record/evidence. Exit 2 = bad invocation.
# ============================================================================
set -u

usage() {
  cat <<'EOF'
usage: change_record.sh check [--mode draft|complete] --record FILE [--evidence FILE]

  --mode draft      allow pending implementation/verification states
  --mode complete   reject pending states; require final dispositions

Record columns (TAB): id, requirement, implementation, verification, evidence, scope, note
  implementation: pending | delivered | partial | not-delivered
  verification:   pending | passed | failed | blocked | not-run | not-applicable
  evidence:       - or comma-separated E<n> ids
  scope:          accepted | narrowed | dropped

Evidence columns (TAB): id, command, identity, selection, result, exit
EOF
}

MODE="draft"
RECORD=""
EVIDENCE=""
CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    check) CMD="check"; shift ;;
    --mode) [ $# -ge 2 ] || { echo "change_record: --mode needs a value" >&2; exit 2; }; MODE="$2"; shift 2 ;;
    --record) [ $# -ge 2 ] || { echo "change_record: --record needs a value" >&2; exit 2; }; RECORD="$2"; shift 2 ;;
    --evidence) [ $# -ge 2 ] || { echo "change_record: --evidence needs a value" >&2; exit 2; }; EVIDENCE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "change_record: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "$CMD" = check ] || { echo "change_record: the check command is required" >&2; usage >&2; exit 2; }
case "$MODE" in draft|complete) ;; *) echo "change_record: --mode must be draft or complete" >&2; exit 2 ;; esac
[ -n "$RECORD" ] || { echo "change_record: --record is required" >&2; exit 2; }
[ -f "$RECORD" ] || { echo "change_record: record not found: $RECORD" >&2; exit 2; }
if [ -n "$EVIDENCE" ] && [ ! -f "$EVIDENCE" ]; then
  echo "change_record: evidence index not found: $EVIDENCE" >&2
  exit 2
fi

awk -v mode="$MODE" -v evfile="$EVIDENCE" '
function err(msg) { printf "change-record: %s: %s\n", where, msg > "/dev/stderr"; bad = 1 }
function valid_id(s) { return s ~ /^R[1-9][0-9]*$/ }
function valid_ev(s) { return s ~ /^E[1-9][0-9]*$/ }

BEGIN {
  if (evfile != "") {
    if ((getline line < evfile) > 0) {
      if (line != "# evidence-record v1") {
        printf "evidence-record: 1: expected header \"# evidence-record v1\"\n" > "/dev/stderr"
        bad = 1
      }
    } else {
      printf "evidence-record: empty evidence index\n" > "/dev/stderr"
      bad = 1
    }
    while ((getline line < evfile) > 0) {
      if (line ~ /^#/ || line == "") continue
      n = split(line, f, "\t")
      if (n != 6) {
        printf "evidence-record: expected 6 tab-separated fields, found %d\n", n > "/dev/stderr"
        bad = 1
        continue
      }
      if (!valid_ev(f[1])) {
        printf "evidence-record: invalid evidence id \"%s\"\n", f[1] > "/dev/stderr"
        bad = 1
        continue
      }
      if (f[1] in seen_ev) {
        printf "evidence-record: duplicate evidence id %s\n", f[1] > "/dev/stderr"
        bad = 1
      }
      seen_ev[f[1]] = 1
      if (f[2] == "" || f[3] == "" || f[4] == "" || f[5] == "") {
        printf "evidence-record: %s needs command, identity, selection and result\n", f[1] > "/dev/stderr"
        bad = 1
      }
      if (f[6] !~ /^([0-9]+|-)$/) {
        printf "evidence-record: %s exit must be an integer or -\n", f[1] > "/dev/stderr"
        bad = 1
      }
      if (f[6] == "-" && f[5] != "pending") {
        printf "evidence-record: %s uses exit - but result is not pending\n", f[1] > "/dev/stderr"
        bad = 1
      }
      if (f[6] != "-" && f[5] == "pending") {
        printf "evidence-record: %s is pending but carries exit %s\n", f[1], f[6] > "/dev/stderr"
        bad = 1
      }
      if (f[6] == "-" || f[5] == "pending") pending_ev[f[1]] = 1
    }
    close(evfile)
  }
}

$0 ~ /^#/ {
  if ($0 == "# change-record v1") header = 1
  next
}
$0 == "" { next }

{
  where = "line " NR
  n = split($0, f, "\t")
  if (n != 7) { err("expected 7 tab-separated fields, found " n); next }
  id = f[1]; req = f[2]; impl = f[3]; ver = f[4]; ev = f[5]; scope = f[6]; note = f[7]

  rows++
  expected = "R" rows
  if (!valid_id(id)) { err("invalid requirement id \"" id "\" (expected R<n>)"); next }
  if (id in seen_req) { err("duplicate requirement id " id); next }
  seen_req[id] = 1
  if (id != expected) { err("requirement ids must be contiguous from R1 (expected " expected ", found " id ")"); next }
  if (req == "") { err("requirement text is empty"); next }

  if (impl != "pending" && impl != "delivered" && impl != "partial" && impl != "not-delivered") {
    err("implementation must be pending, delivered, partial or not-delivered (found \"" impl "\")")
  }
  if (ver != "pending" && ver != "passed" && ver != "failed" && ver != "blocked" && ver != "not-run" && ver != "not-applicable") {
    err("verification must be pending, passed, failed, blocked, not-run or not-applicable (found \"" ver "\")")
  }
  if (scope != "accepted" && scope != "narrowed" && scope != "dropped") {
    err("scope must be accepted, narrowed or dropped (found \"" scope "\")")
  }
  if (mode == "complete") {
    if (impl == "pending") err("complete mode requires a final implementation state")
    if (ver == "pending") err("complete mode requires a final verification state")
  }
  if (ev == "-") {
    if (ver == "passed") err("passed verification needs at least one evidence id")
  } else {
    m = split(ev, evs, ",")
    for (i = 1; i <= m; i++) {
      if (!valid_ev(evs[i])) { err("invalid evidence id \"" evs[i] "\""); continue }
      refs[evs[i]] = 1
      if (ver == "passed" && (evs[i] in pending_ev)) {
        err("passed verification references pending evidence " evs[i])
      }
    }
  }
  if ((ver == "failed" || ver == "blocked" || ver == "not-run" || ver == "not-applicable") && note == "") {
    err(ver " verification needs a note (reason, blocker or follow-up)")
  }
  if ((scope == "narrowed" || scope == "dropped") && note == "") {
    err(scope " scope needs a note naming the decision and what is excluded")
  }
}

END {
  if (!header) {
    printf "change-record: missing header \"# change-record v1\"\n" > "/dev/stderr"
    bad = 1
  }
  if (rows == 0) {
    printf "change-record: no requirement rows\n" > "/dev/stderr"
    bad = 1
  }
  if (evfile != "") {
    for (e in refs) {
      if (!(e in seen_ev)) {
        printf "change-record: evidence id %s is not defined in %s\n", e, evfile > "/dev/stderr"
        bad = 1
      }
    }
  }
  if (bad) exit 1
  printf "change-record: ok (%d requirements, mode %s)\n", rows, mode
}
' "$RECORD"
