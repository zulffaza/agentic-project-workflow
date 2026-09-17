# shellcheck shell=bash
# cases/pw-doc-summary.t.sh
pwtest_rc 0 "summary plan F2" "$(pwtest_script pw-doc-summary.sh)" plan "$S2"
pwtest_re '^Tasks: 4' "plan mode counts 4 tasks (linked IDs, C4)"
pwtest_re 'SP=7|SP: 7' "SP summed (1+3+2+1)"
pwtest_re 'Repos:' "repos listed (Repo manifest)"
pwtest_re '^Produced by: [a-z-]*$' "Produced by = bare provider token, no template prose ('$' anchor)"
pwtest_rc 0 "summary plan F3 hostile" "$(pwtest_script pw-doc-summary.sh)" plan "$S3"
pwtest_re '^Tasks: 6' "hostile rows (plain+linked ids, quotes) parsed"
pwtest_rc 0 "summary project F2" "$(pwtest_script pw-doc-summary.sh)" project "$S2"
pwtest_re '^Phase: executing' "phase token extracted (not prose)"
pwtest_rc 0 "summary project F3" "$(pwtest_script pw-doc-summary.sh)" project "$S3"
pwtest_rc 0 "summary task F2 T01" "$(pwtest_script pw-doc-summary.sh)" task "$S2" T01
pwtest_re 'Repo: api' "task keys parsed"
pwtest_rc 2 "unknown project" "$(pwtest_script pw-doc-summary.sh)" project nope
pwtest_fix "summary unknown carries fix"
