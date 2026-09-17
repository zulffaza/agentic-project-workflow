# shellcheck shell=bash
# cases/pw-context-fetch.t.sh — offline-safe walking of INDEX (no rows added; completion rc).
pwtest_rc 0 "fetch F2" "$(pwtest_script pw-context-fetch.sh)" "$S2"
pwtest_re "complete|context|nothing" "summary line"
pwtest_rc 2 "unknown project" "$(pwtest_script pw-context-fetch.sh)" nope-xyz
pwtest_fix "unknown actionable"
