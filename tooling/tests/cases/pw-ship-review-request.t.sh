# shellcheck shell=bash
# Request-review: deterministic selection, forge metadata, frame rendering, prose validation,
# and the read-only guarantee — against a strict per-endpoint forge fixture. Private projects;
# no shared fixture is touched.

RR_SHIP="$(pwtest_script pw-ship.sh)"
# The harness seeds a frame at $PWTEST_ROOT/user-templates/review-request.md and exports its
# path; an earlier case that sources pw-common can reset the export to empty, so fall back to
# the harness seed location directly instead of trusting the clobbered variable.
RR_FRAME="${PW_REVIEW_REQUEST_TEMPLATE_FILE:-$PWTEST_ROOT/user-templates/review-request.md}"
RR_ROOT="$ROOT/review-request"; mkdir -p "$RR_ROOT/forges"

cat > "$ROOT/rr-forge-config.sh" <<'CONFIG'
PW_FORGE_HOSTS=("gitlab.example.com=gitlab")
CONFIG

rr_project() {  # <slug> — minimal PLAN (ten rows) plus task files
  local slug="$1" p="$PW_PROJECTS_DIR/$1"
  mkdir -p "$p/task"
  cat > "$p/task/PLAN.md" <<'PLAN'
# PLAN
- **Status:** approved-for-execution

## Task table
| ID | Title | Repo | depends_on | Group | Execute with | SP | Status | Time | Result |
|----|-------|------|------------|-------|--------------|----|--------|------|--------|
| T01 | Handle repeated checkout requests | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T02 | Retry delayed checkout events | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T03 | Harden the sentinel path | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T04 | Audit legacy flags | api | — | G1 | kilotest/test-model | 1 | accepted | — | — |
| T05 | Closed spike | api | — | G1 | kilotest/test-model | 1 | todo | — | — |
| T06 | Wire checkout telemetry | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T07 | Rebase checkout schema | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T08 | Retry worker backoff | worker | — | G1 | kilotest/test-model | 1 | done | — | — |
| T09 | Rate-limit partner callbacks | app | — | G1 | kilotest/test-model | 1 | done | — | — |
| T10 | Nightly regression sweep | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T11 | Split checkout adapters | api | — | G1 | kilotest/test-model | 1 | done | — | — |
| T12 | Propagate adapter move | api | T11 | G1 | kilotest/test-model | 1 | done | — | — |
PLAN
}
rr_task() {  # <slug> <id> <title> <mr>
  printf '# %s: %s\n\n## Result\n- **MR:** %s\n' "$2" "$3" "$4" > "$PW_PROJECTS_DIR/$1/task/$2.md"
}

rr_project rr-review
rr_task rr-review T01 "Handle repeated checkout requests" "https://gitlab.example.com/pwtest/api/-/merge_requests/11"
rr_task rr-review T02 "Retry delayed checkout events"       "https://gitlab.example.com/pwtest/api/-/merge_requests/12"
rr_task rr-review T03 "Harden the sentinel path"            "(none)"
rr_task rr-review T04 "Audit legacy flags"                  "https://gitlab.example.com/pwtest/api/-/merge_requests/13"
rr_task rr-review T05 "Closed spike"                        "https://gitlab.example.com/pwtest/api/-/merge_requests/14"
rr_task rr-review T06 "Wire checkout telemetry"             "https://gitlab.example.com/pwtest/api/-/merge_requests/11"
rr_task rr-review T07 "Rebase checkout schema"              "(none)"
rr_task rr-review T08 "Retry worker backoff"                "https://gitlab.example.com/pwtest/checkout-worker/-/merge_requests/15"
rr_task rr-review T09 "Rate-limit partner callbacks"        "https://github.com/octo/app/pull/21"
rr_task rr-review T10 "Nightly regression sweep"            "https://gitlab.example.com/pwtest/api/-/merge_requests/18"
rr_task rr-review T11 "Split checkout adapters"             "https://gitlab.example.com/pwtest/api/-/merge_requests/22"
printf -- '- **Landing unit:** checkout-wave\n' >> "$PW_PROJECTS_DIR/rr-review/task/T11.md"
rr_task rr-review T12 "Propagate adapter move"              "https://gitlab.example.com/pwtest/api/-/merge_requests/23"
printf -- '- **Stacked on:** T11\n- **Landing unit:** checkout-wave\n' >> "$PW_PROJECTS_DIR/rr-review/task/T12.md"

# Conflict + failure + empty + diff/budget projects reuse the same PLAN shape.
rr_project rr-conflict
rr_task rr-conflict T01 "Conflicting links" "https://gitlab.example.com/pwtest/api/-/merge_requests/11"
cat > "$PW_PROJECTS_DIR/rr-conflict/README.md" <<'README'
# Dashboard
## Merge requests
| Task | Repo | MR | State |
|------|------|----|-------|
| T01 | api | [MR 16](https://gitlab.example.com/pwtest/api/-/merge_requests/16) | open |
README
rr_project rr-fail
rr_task rr-fail T01 "Lookup fails" "https://gitlab.example.com/pwtest/api/-/merge_requests/19"
rr_project rr-empty
rr_task rr-empty T01 "No MR yet" "(none)"
rr_project rr-diff
rr_task rr-diff T01 "Undescribed change" "https://gitlab.example.com/pwtest/api/-/merge_requests/24"
rr_project rr-ghdiff
rr_task rr-ghdiff T01 "Undescribed PR" "https://github.com/octo/app/pull/25"
rr_project rr-budget
for _n in 1 2 3 4 5; do
  rr_task rr-budget "T0$_n" "Budget change $_n" "https://gitlab.example.com/pwtest/api/-/merge_requests/3$_n"
done

python3 - "$RR_ROOT/forges" <<'PY'
import hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
def fix(forge, host, endpoint, response=None, fail=False):
    key = hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest()
    (root / (key + '.json')).write_text(json.dumps({'response': response if response is not None else {}, 'fail': fail}))
gl = 'gitlab.example.com'
api = 'projects/pwtest%2Fapi/merge_requests/'
fix('glab', gl, api + '11', {'title': 'Handle repeated checkout requests', 'state': 'opened', 'draft': False,
    'target_branch': 'main', 'sha': 'aaaa1111', 'reviewers': [{'name': 'Andi'}, {'name': 'Sari'}],
    'description': 'Rejects repeated checkout requests and bounds the retry queue.'})
fix('glab', gl, api + '11/pipelines', [{'sha': 'bbbb2222', 'status': 'failed'},
                                       {'sha': 'aaaa1111', 'status': 'success'}])
fix('glab', gl, api + '12', {'title': 'Retry delayed checkout events', 'state': 'opened', 'draft': True,
    'target_branch': 'main', 'sha': 'cccc3333', 'reviewers': [], 'description': 'Retries delayed events.'})
fix('glab', gl, api + '12/pipelines', [{'sha': 'cccc3333', 'status': 'running'}])
fix('glab', gl, api + '13', {'title': 'Audit legacy flags', 'state': 'merged', 'sha': 'dddd4444'})
fix('glab', gl, api + '14', {'title': 'Closed spike', 'state': 'closed', 'sha': 'eeee5555'})
fix('glab', gl, 'projects/pwtest%2Fcheckout-worker/merge_requests/15',
    {'title': 'Handle repeated checkout requests', 'state': 'opened', 'draft': False,
     'target_branch': 'develop', 'sha': 'ffff6666', 'reviewers': [{'username': 'budi'}],
     'description': 'Worker backoff.'})
fix('glab', gl, 'projects/pwtest%2Fcheckout-worker/merge_requests/15/pipelines', fail=True)
fix('glab', gl, api + '16', {'title': 'Rebase checkout schema', 'state': 'opened', 'sha': 'aabbccdd', 'target_branch': 'main'})
fix('glab', gl, api + '18', {'title': 'Nightly regression sweep', 'state': 'opened', 'draft': False,
    'target_branch': 'main', 'sha': '18181818', 'reviewers': [], 'description': 'Nightly sweep.'})
fix('glab', gl, api + '18/pipelines', [{'sha': '18181818', 'status': 'created'}])
fix('glab', gl, api + '22', {'title': 'Split checkout adapters', 'state': 'opened', 'draft': False,
    'target_branch': 'main', 'sha': '22222222', 'reviewers': [{'name': 'Nia'}], 'description': 'Splits adapters.'})
fix('glab', gl, api + '22/pipelines', [{'sha': '22222222', 'status': 'success'}])
fix('glab', gl, api + '23', {'title': 'Propagate adapter move', 'state': 'opened', 'draft': False,
    'target_branch': 'agent/pwtest/T11-split', 'sha': '23232323', 'reviewers': [],
    'description': 'Moves callers onto the split adapters.'})
fix('glab', gl, api + '23/pipelines', [{'sha': '23232323', 'status': 'running'}])
fix('glab', gl, api + '19', fail=True)
fix('gh', 'github.com', 'repos/octo/app/pulls/21', {'title': 'Rate-limit partner callbacks', 'state': 'open',
    'draft': False, 'base': {'ref': 'main'}, 'head': {'sha': '21212121'},
    'requested_reviewers': [{'login': 'octo-reviewer'}], 'body': 'Token bucket for partner callbacks.'})
fix('gh', 'github.com', 'repos/octo/app/commits/21212121/check-runs',
    {'check_runs': [{'status': 'completed', 'conclusion': 'failure'},
                    {'status': 'completed', 'conclusion': 'success'}]})
# diff-retrieval fixtures: undescribed MRs whose target...head delta explains the change
fix('glab', gl, api + '24', {'title': 'Undescribed change', 'state': 'opened', 'draft': False,
    'target_branch': 'main', 'sha': '24242424', 'reviewers': []})
fix('glab', gl, 'projects/pwtest%2Fapi/repository/compare?from=main&to=24242424',
    {'diffs': [{'old_path': 'checkout/handler.py', 'new_path': 'checkout/handler.py', 'new_file': False,
                'deleted_file': False, 'renamed_file': False,
                'diff': '@@ -1,2 +1,2 @@\n-def handle(events):\n+def handle(events):\n+    events = dedupe(events)\n'}]})
fix('gh', 'github.com', 'repos/octo/app/pulls/25', {'title': 'Undescribed PR', 'state': 'open',
    'draft': False, 'base': {'ref': 'main'}, 'head': {'sha': '25252525'}, 'requested_reviewers': []})
fix('gh', 'github.com', 'repos/octo/app/compare/main...25252525',
    {'files': [{'filename': 'rate/token_bucket.py', 'status': 'modified', 'additions': 2, 'deletions': 1,
                'patch': '@@ -1,2 +1,3 @@\n-def refill(now):\n+def refill(now):\n+    now = monotonic(now)\n'}]})
# budget fixtures: undescribed MRs with oversized diffs exercise the per-MR and aggregate caps
def bigdiff():
    files = []
    for i in range(12):
        lines = []
        for j in range(14):
            lines.append('+    %s  # file %d line %d' % ('x' * 72, i, j))
        files.append({'old_path': 'f%d.py' % i, 'new_path': 'f%d.py' % i, 'new_file': False,
                      'deleted_file': False, 'renamed_file': False, 'diff': '\n'.join(lines)})
    return {'diffs': files}
for n in range(1, 6):
    num = str(n)
    fix('glab', gl, api + '3' + num, {'title': 'Budget change ' + num, 'state': 'opened', 'draft': False,
        'target_branch': 'main', 'sha': '3030303' + num, 'reviewers': []})
    fix('glab', gl, 'projects/pwtest%2Fapi/repository/compare?from=main&to=3030303' + num, bigdiff())
PY

RR_ENV=( "PATH=$PWTEST_TESTSDIR/bin:$PATH" "PW_PROJECTS_DIR=$PW_PROJECTS_DIR" "PW_REPOS=$PW_REPOS"
         "PW_CONFIG_FILE=$ROOT/rr-forge-config.sh" "PW_REVIEW_REQUEST_TEMPLATE_FILE=$RR_FRAME"
         "PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE=$RR_ROOT/prompt-summary.md"
         "PW_REVIEW_REQUEST_NOTE_PROMPT_FILE=$RR_ROOT/prompt-note.md"
         "PWTEST_REVIEW_FORGE_DIR=$RR_ROOT/forges" )
cat > "$RR_ROOT/prompt-summary.md" <<'PROMPT'
Write a summary from the evidence. (test summary prompt)
PROMPT
cat > "$RR_ROOT/prompt-note.md" <<'PROMPT'
Write reviewer hints from the evidence. (test note prompt)
PROMPT
rr() {  # <want-rc> <label> <slug> [args…]
  local want="$1" label="$2" slug="$3"; shift 3
  pwtest_rc "$want" "$label" env "${RR_ENV[@]}" bash "$RR_SHIP" request-review "$slug" "$@"
}
rr_frame() {  # <want-rc> <label> <frame-file> <slug> [args…]
  local want="$1" label="$2" frame="$3" slug="$4"; shift 4
  pwtest_rc "$want" "$label" env "${RR_ENV[@]}" "PW_REVIEW_REQUEST_TEMPLATE_FILE=$frame" \
    bash "$RR_SHIP" request-review "$slug" "$@"
}
rr_message() {  # extract the fenced message from the last run into $RR_ROOT/message.md
  python3 - "$PWTEST_OUT" "$RR_ROOT/message.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
match = re.search(r'^(`+)markdown\n(.*?)\n\1$', text, re.M | re.S)
if not match:
    sys.exit(1)
open(sys.argv[2], 'w', encoding='utf-8').write(match.group(2) + '\n')
PY
}
rr_diff_message() {  # <label> <expected-file>
  if rr_message && diff -u "$2" "$RR_ROOT/message.md" >"$RR_ROOT/message.diff" 2>&1; then
    pwtest_ok "$1"
  else
    pwtest_bad "$1" "$(head -3 "$RR_ROOT/message.diff" 2>/dev/null | tr '\n' ' ')"
  fi
}
rr_ordered() {  # <label> <first-substring> <second-substring>
  if python3 - "$PWTEST_OUT" "$2" "$3" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
a, b = sys.argv[2], sys.argv[3]
sys.exit(0 if a in text and b in text and text.index(a) < text.index(b) else 1)
PY
  then pwtest_ok "$1"; else pwtest_bad "$1" "ordering not found in output"; fi
}
rr_calls() { wc -l < "$RR_ROOT/forges/calls.log" 2>/dev/null | tr -d ' '; }

# --- default generation: every unique open MR once, exclusions in the recap ------------------
cat > "$RR_ROOT/expected-all.md" <<'MSG'
Hi team,

Please review these MRs for rr-review:

- Handle repeated checkout requests (pwtest/api)
  - Link : https://gitlab.example.com/pwtest/api/-/merge_requests/11
  - Branch Target : main
  - CI Status : passed
  - Assigned Reviewer : Andi, Sari
- Retry delayed checkout events
  - Link : https://gitlab.example.com/pwtest/api/-/merge_requests/12
  - Branch Target : main
  - CI Status : running
  - Draft : early feedback requested
- Handle repeated checkout requests (pwtest/checkout-worker)
  - Link : https://gitlab.example.com/pwtest/checkout-worker/-/merge_requests/15
  - Branch Target : develop
  - CI Status : unavailable
  - Assigned Reviewer : budi
- Rate-limit partner callbacks
  - Link : https://github.com/octo/app/pull/21
  - Branch Target : main
  - CI Status : failed
  - Assigned Reviewer : octo-reviewer
- Nightly regression sweep
  - Link : https://gitlab.example.com/pwtest/api/-/merge_requests/18
  - Branch Target : main
  - CI Status : pending
- Split checkout adapters
  - Link : https://gitlab.example.com/pwtest/api/-/merge_requests/22
  - Branch Target : main
  - CI Status : passed
  - Assigned Reviewer : Nia
  - Landing unit : checkout-wave
- Propagate adapter move
  - Link : https://gitlab.example.com/pwtest/api/-/merge_requests/23
  - Branch Target : agent/pwtest/T11-split
  - CI Status : running
  - Landing unit : checkout-wave
  - Stacked on : https://gitlab.example.com/pwtest/api/-/merge_requests/22

Thanks!
MSG
rr 0 'all: every unique open recorded MR is requested once' rr-review all
rr_diff_message 'all: deterministic title-led message with repo disambiguation' "$RR_ROOT/expected-all.md"
pwtest_re 'request-review rr-review: 7 unique open MR\(s\) for 8 task\(s\)' 'all: recap counts unique MRs and tasks'
pwtest_re 'include T01 -> .*/merge_requests/11 \(open; also T06\)' 'all: shared MR maps both tasks once'
pwtest_re 'exclude T03: no recorded MR' 'all: task without an MR is excluded with the reason'
pwtest_re 'exclude T04: MR merged' 'all: merged MR excluded with the reason'
pwtest_re 'exclude T05: MR closed' 'all: closed MR excluded with the reason'
grep -q 'pw-review-evidence' "$PWTEST_OUT" && pwtest_bad 'default run gathers no AI evidence' 'evidence packet present' || pwtest_ok 'default run gathers no AI evidence'
grep -q 'prose requested' "$PWTEST_OUT" && pwtest_bad 'default run requests no prose' 'prose diagnostics present' || pwtest_ok 'default run requests no prose'
# stale pipeline for another sha must not masquerade as the head result (11 -> passed, not failed)
pwtest_re 'CI Status : passed' 'head-specific CI status wins over a stale pipeline'

# --- explicit selection ----------------------------------------------------------------------
rr 0 'explicit selection limits the requested set' rr-review T01
grep -qE 'merge_requests/(12|15|18)|pull/21' "$PWTEST_OUT" && pwtest_bad 'explicit selection excludes unselected MRs' 'unselected MR leaked' || pwtest_ok 'explicit selection excludes unselected open MRs'
rr 0 '--no-reviewers omits assignment fields' rr-review all --no-reviewers
grep -q 'Assigned Reviewer' "$PWTEST_OUT" && pwtest_bad '--no-reviewers omits assignments' 'reviewer field rendered' || pwtest_ok '--no-reviewers omits assignment fields'
rr 0 'landing-unit and stack grouping render' rr-review T12 T11
rr_ordered 'stacked child renders after its parent' 'Split checkout adapters' 'Propagate adapter move'
pwtest_re 'Landing unit : checkout-wave' 'landing unit field rendered'
pwtest_re 'Stacked on : https://gitlab.example.com/pwtest/api/-/merge_requests/22' 'stack parent link shown as context'
pwtest_re 'Branch Target : agent/pwtest/T11-split' 'stacked child keeps its inherited target'
rr 0 'comma-separated task ids are accepted' rr-review T01,T02
pwtest_re 'include T02' 'comma selector includes the second task'
rr 0 'greeting renders supplied names literally' rr-review T01 --to 'Andi, Sari'
pwtest_re '^Hi Andi, Sari,$' 'greeting uses the --to segment verbatim'

# --- optional AI prose -----------------------------------------------------------------------
rr 0 'AI flags without prose keep the deterministic message' rr-review T01 --summary --note
pwtest_re 'prose requested but not supplied: summary, note' 'pending sections are named outside the message'
pwtest_re 'pw-review-evidence' 'bounded evidence packet is emitted for the prose pass'
pwtest_re 'description \(truncated\)' 'evidence includes the current MR description'
pwtest_re 'task T01 result' 'evidence includes task/result excerpts'
pwtest_re 'pw-generation-prompt: summary \(path: .*prompt-summary\.md; source: custom\)' 'summary prompt context names its path and source'
pwtest_re 'test summary prompt' 'summary prompt text is emitted outside the message'
pwtest_re 'pw-generation-prompt: note \(path: .*prompt-note\.md; source: custom\)' 'note prompt context names its path and source'
pwtest_re 'test note prompt' 'note prompt text is emitted outside the message'
pwtest_re 'observed heads: https://gitlab.example.com/pwtest/api/-/merge_requests/11 aaaa1111' 'first call exposes observed heads'
grep -q '^\*\*Summary:\*\*' "$PWTEST_OUT" && pwtest_bad 'summary not faked without prose' 'summary rendered without prose' || pwtest_ok 'summary not faked without prose'
rr 0 'per-MR summary mode shares the summary prompt' rr-review T01 --mr-summary
pwtest_re 'pw-generation-prompt: summary' 'per-MR summary mode uses the shared summary prompt'
grep -q 'pw-generation-prompt: note' "$PWTEST_OUT" && pwtest_bad 'disabled note prompt is not read' 'note context leaked' || pwtest_ok 'disabled note prompt is not read'
rr 0 'note-only reads only the note prompt and still gets descriptions' rr-review T01 --note
pwtest_re 'pw-generation-prompt: note' 'note context present for the note flag'
grep -q 'pw-generation-prompt: summary' "$PWTEST_OUT" && pwtest_bad 'disabled summary prompt is not read' 'summary context leaked' || pwtest_ok 'disabled summary prompt is not read'
pwtest_re 'description \(truncated\)' 'note-only evidence includes the current description'
pwtest_re 'Rejects repeated checkout requests and bounds the retry queue\.' 'note-only evidence carries the actual description text'

cat > "$RR_ROOT/prose-ok.json" <<'JSON'
{"summary": "Checkout hardening and retry work waits for review. The changes are small and independent.",
 "mr_summaries": {"https://gitlab.example.com/pwtest/api/-/merge_requests/11": "Rejects repeated checkout requests and bounds the retry queue."},
 "note": ["Check the retry backoff edge cases.", "Confirm the queue bound is enforced."]}
JSON
rr 0 'validated prose is inserted into the enabled sections' rr-review T01 --summary --mr-summary --note --prose "$RR_ROOT/prose-ok.json"
pwtest_re '^\*\*Summary:\*\* Checkout hardening' 'global summary section inserted'
pwtest_re 'Summary : Rejects repeated checkout requests' 'per-MR summary stays inside its MR block'
pwtest_re '^\*\*Review hints:\*\*' 'reviewer-hint heading inserted'
pwtest_re 'prose included: summary, mr_summary, note' 'inclusion diagnostic stays outside the message'
pwtest_re 'observed heads: https://gitlab.example.com/pwtest/api/-/merge_requests/11 aaaa1111' 'prose run exposes observed heads for the second call'
grep -q 'pw-generation-prompt' "$PWTEST_OUT" && pwtest_bad 'direct prose supply triggers no prompt reads' 'prompt context leaked into a prose run' || pwtest_ok 'direct prose supply triggers no prompt reads'
rr_ordered 'global summary before MR blocks, hints after them' '**Summary:**' '**Review hints:**'

cat > "$RR_ROOT/prose-long.json" <<'JSON'
{"summary": "One sentence here. Two sentences here. Three sentences here."}
JSON
rr 2 'over-limit prose is refused before rendering' rr-review T01 --summary --prose "$RR_ROOT/prose-long.json"
pwtest_err 'exceeds its limit' 'over-limit error names the limit'
cat > "$RR_ROOT/prose-membership.json" <<'JSON'
{"mr_summaries": {"https://gitlab.example.com/pwtest/api/-/merge_requests/999": "Not a selected MR."}}
JSON
rr 2 'wrong summary membership is refused' rr-review T01 --mr-summary --prose "$RR_ROOT/prose-membership.json"
pwtest_err 'keys must be exactly the selected MR URLs' 'membership error names the rule'
cat > "$RR_ROOT/prose-omit.json" <<'JSON'
{"omit": ["summary"]}
JSON
rr 0 'explicit omit survives with an outside diagnostic' rr-review T01 --summary --prose "$RR_ROOT/prose-omit.json"
pwtest_re 'prose omitted by the prose pass: summary' 'omit is reported outside the message'
grep -q '^\*\*Summary:\*\*' "$PWTEST_OUT" && pwtest_bad 'omitted section leaves no heading' 'heading still rendered' || pwtest_ok 'omitted section leaves no heading'

# --- prompt health: invalid enabled prompts omit their sections, never stop the message ------
: > "$RR_ROOT/prompt-empty.md"
rr_env_prompt() {  # <var-name> <file> <slug> [args…]
  local var="$1" file="$2" slug="$3"; shift 3
  pwtest_rc 0 "prompt health: ${var##*_}" env "${RR_ENV[@]}" "$var=$file" \
    bash "$RR_SHIP" request-review "$slug" "$@"
}
rr_env_prompt PW_REVIEW_REQUEST_NOTE_PROMPT_FILE "$RR_ROOT/prompt-empty.md" rr-review T01 --note
pwtest_re 'prose section note omitted: note prompt file is empty' 'empty prompt omits only its section'
grep -q '^\*\*Review hints:\*\*' "$PWTEST_OUT" && pwtest_bad 'omitted note leaves no heading' 'hint heading rendered' || pwtest_ok 'omitted note leaves no heading'
python3 -c "open('$RR_ROOT/prompt-big.md', 'w').write('x' * 20000)"
rr_env_prompt PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE "$RR_ROOT/prompt-big.md" rr-review T01 --summary
pwtest_re 'prose section summary omitted: summary prompt file exceeds the 16384-byte prompt limit' 'oversized prompt omits its section with the size limit'
printf '\xff\xfe\x00\x01not utf8\n' > "$RR_ROOT/prompt-utf8.md"
rr_env_prompt PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE "$RR_ROOT/prompt-utf8.md" rr-review T01 --summary
pwtest_re 'not valid UTF-8 text' 'invalid UTF-8 prompt omits its section'
rr_env_prompt PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE "$RR_ROOT/absent-custom-prompt.md" rr-review T01 --summary
pwtest_re "prose section summary omitted: summary prompt file not found: $RR_ROOT/absent-custom-prompt.md \(.*, custom\)" 'missing custom prompt is named with its correction'
[ ! -e "$RR_ROOT/absent-custom-prompt.md" ] && pwtest_ok 'request-review never creates a prompt file' || pwtest_bad 'request-review never creates a prompt file' 'file was created'
rr_env_prompt PW_REVIEW_REQUEST_NOTE_PROMPT_FILE "$RR_ROOT/absent-custom-prompt.md" rr-review T01 --summary
grep -q 'note prompt' "$PWTEST_OUT" && pwtest_bad 'disabled note prompt is not read even when missing' 'note diagnostic leaked' || pwtest_ok 'disabled note prompt is not read even when missing'
# a summary-prompt failure affects both summary modes
rr_env_prompt PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE "$RR_ROOT/prompt-empty.md" rr-review T01 --summary --mr-summary
pwtest_re 'prose section summary omitted' 'both summary modes omit on the shared prompt failure'
pwtest_re 'prose section mr_summary omitted' 'per-MR summary omitted by the summary prompt failure'
grep -q 'pw-generation-prompt: summary' "$PWTEST_OUT" && pwtest_bad 'invalid prompt emits no context' 'prompt context leaked' || pwtest_ok 'invalid prompt emits no generation context'

# --- missing defaults resolve under the bundle's user/ and direct the user to doctor ----------
RR_BARE="$RR_ROOT/bare-bundle"; mkdir -p "$RR_BARE/tooling"
cp -R "$TOOL/scripts" "$TOOL/templates" "$TOOL/prompts" "$RR_BARE/tooling/"
RR_BARE_SHIP="$RR_BARE/tooling/scripts/entities/pw-ship.sh"
rr_bare() {  # <want-rc> <label> <slug> [args…] — bare bundle: no user/ defaults exist
  local want="$1" label="$2" slug="$3"; shift 3
  pwtest_rc "$want" "$label" env "${RR_ENV[@]}" \
    "PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE=" "PW_REVIEW_REQUEST_NOTE_PROMPT_FILE=" \
    bash "$RR_BARE_SHIP" request-review "$slug" "$@"
}
rr_bare 0 'missing default prompts omit with a doctor fix line' rr-review T01 --summary --note
pwtest_re 'prose section summary omitted: summary prompt file not found: .*user/prompts/review-request-summary\.md \(.*, default\)' 'missing default summary prompt names its path'
pwtest_re '→ fix: run /pw-doctor --fix' 'missing default prompt directs to doctor repair'
pwtest_re 'prose section note omitted: note prompt file not found' 'missing default note prompt named'
grep -q 'copyable message' "$PWTEST_OUT" && pwtest_ok 'deterministic message survives prompt failures' || pwtest_bad 'deterministic message survives prompt failures' 'no message rendered'

# --- supplementary evidence: conditional diffs and budgets -----------------------------------
rr 0 'diff excerpt fills an unavailable description' rr-diff T01 --summary
pwtest_re 'description \(truncated\)' 'evidence still labels the unavailable description'
pwtest_re '\(unavailable\)' 'unavailable description is a labeled limitation'
pwtest_re 'diff excerpt \(target -> head, truncated\)' 'diff excerpt rendered for a description gap'
pwtest_re 'checkout/handler\.py' 'gitlab diff names the changed file'
pwtest_re 'def handle\(events\)' 'gitlab diff carries patch content'
rr 0 'github compare excerpt fills a missing body' rr-ghdiff T01 --summary
pwtest_re 'rate/token_bucket\.py \+2/-1' 'github diff names the file with counts'
grep -q 'diff excerpt' "$PWTEST_OUT" && pwtest_ok 'github compare endpoint resolved through the same reader' || pwtest_bad 'github compare endpoint resolved' 'no diff excerpt'
rr 0 'supplementary evidence stays within the per-MR and aggregate budgets' rr-budget all --note
pwtest_re 'per-MR supplementary evidence budget reached' 'per-MR budget is labeled when hit'
pwtest_re 'aggregate evidence budget reached' 'aggregate budget is labeled when hit'
pwtest_re '^MR: https://gitlab.example.com/pwtest/api/-/merge_requests/31' 'first MR identity survives budget trimming'
: > "$RR_ROOT/forges/calls.log"
rr 0 'a described MR triggers no diff retrieval' rr-review T01 --summary
grep -q 'diff excerpt' "$PWTEST_OUT" && pwtest_bad 'no diff read when the description explains the change' 'diff excerpt present' || pwtest_ok 'no diff read when the description explains the change'
grep -q 'repository/compare' "$RR_ROOT/forges/calls.log" && pwtest_bad 'no compare call when the description explains the change' 'compare endpoint called' || pwtest_ok 'no compare call when the description explains the change'

# --- prompt text stays text (never sourced/executed) and disabled reads stay absent -----------
cat > "$RR_ROOT/prompt-shell.md" <<'PROMPT'
$(touch $ROOT/pwned) `echo hi` $((1+1)) summary prompt with shell syntax
PROMPT
rr_env_prompt PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE "$RR_ROOT/prompt-shell.md" rr-review T01 --summary
pwtest_re 'shell syntax' 'prompt text with shell syntax renders literally'
[ ! -e "$RR_ROOT/pwned" ] && pwtest_ok 'prompt text is never executed' || pwtest_bad 'prompt text is never executed' 'command executed from prompt'

# --- head comparison support: both calls expose the same per-MR heads ------------------------
rr 0 'head comparison: first call heads' rr-review T01 --summary
head_one="$(grep -o 'observed heads: .*' "$PWTEST_OUT" | head -1)"
rr 0 'head comparison: prose call heads' rr-review T01 --summary --prose "$RR_ROOT/prose-ok.json"
head_two="$(grep -o 'observed heads: .*' "$PWTEST_OUT" | head -1)"
pwtest_eq 'both calls expose identical observed heads' "$head_one" "$head_two"

# --- stop conditions -------------------------------------------------------------------------
rr 2 'merged MR stops an explicit selection' rr-review T04
pwtest_err 'is merged' 'merged stop names the state'
rr 2 'closed MR stops an explicit selection' rr-review T05
pwtest_err 'is closed' 'closed stop names the state'
rr 2 'task without an MR stops an explicit selection' rr-review T03
pwtest_err 'no recorded MR' 'missing-MR stop is actionable'
rr 2 'unknown task id is refused' rr-review T99
rr 2 'conflicting recorded links stop before a message' rr-conflict all
pwtest_err 'conflict' 'conflict stop identifies the affected candidate'
rr 2 'forge query failure stops before a message' rr-fail T01
pwtest_err 'MR lookup failed' 'lookup failure names the affected candidate'
rr 0 'empty selection is explained without a message' rr-empty all
pwtest_re 'no open MRs remain' 'empty selection is explained'
grep -q 'copyable message' "$PWTEST_OUT" && pwtest_bad 'empty selection emits no message' 'message emitted' || pwtest_ok 'empty selection emits no message'

# --- argument contract -----------------------------------------------------------------------
rr 2 'ship-mode switches are rejected' rr-review T01 --skip-build-check
rr 2 'comment-mode operator tokens are rejected' rr-review comments
rr 2 'all cannot combine with task ids' rr-review all T01
rr 2 'repeated switches are rejected' rr-review T01 --summary --summary
rr 2 'trailing prose after a switch is rejected' rr-review T01 --summary extra
rr 2 'unknown flags are rejected' rr-review T01 --bogus
rr 2 'invalid selector tokens are rejected' rr-review T01 bogus

# --- frame file: custom order, invalid frames, missing paths ---------------------------------
cat > "$RR_ROOT/frame-note-first.md" <<'FRAME'
{{TO_BLOCK}}

{{NOTE_BLOCK}}

Please review these MRs for {{PROJECT}}:

{{SUMMARY_BLOCK}}

{{MR_BLOCKS}}

Thanks!
FRAME
cat > "$RR_ROOT/prose-note.json" <<'JSON'
{"note": ["Check the retry backoff edge cases."]}
JSON
rr_frame 0 'custom frame block order renders' "$RR_ROOT/frame-note-first.md" rr-review T01 --note --prose "$RR_ROOT/prose-note.json"
rr_ordered 'custom frame moves the hint block before the request line' 'Review hints:' 'Please review these MRs for rr-review'
cat > "$RR_ROOT/frame-missing-block.md" <<'FRAME'
{{TO_BLOCK}}

Please review these MRs for {{PROJECT}}:

{{SUMMARY_BLOCK}}

{{NOTE_BLOCK}}
FRAME
cat > "$RR_ROOT/frame-dup.md" <<'FRAME'
{{TO_BLOCK}}

{{MR_BLOCKS}}

{{MR_BLOCKS}}

{{SUMMARY_BLOCK}}

{{NOTE_BLOCK}}
FRAME
cat > "$RR_ROOT/frame-unknown.md" <<'FRAME'
{{TO_BLOCK}}

{{MR_BLOCKS}}

{{SUMMARY_BLOCK}}

{{NOTE_BLOCK}}

{{BOGUS}}
FRAME
: > "$RR_ROOT/frame-empty.md"
calls_before="$(rr_calls)"
rr_frame 2 'frame without MR_BLOCKS is refused' "$RR_ROOT/frame-missing-block.md" rr-review T01
pwtest_err 'MR_BLOCKS.*exactly once' 'missing block is named'
rr_frame 2 'duplicate block placeholder is refused' "$RR_ROOT/frame-dup.md" rr-review T01
rr_frame 2 'unknown placeholder is refused' "$RR_ROOT/frame-unknown.md" rr-review T01
pwtest_err 'unknown placeholder' 'unknown token is named'
rr_frame 2 'empty frame file is refused' "$RR_ROOT/frame-empty.md" rr-review T01
pwtest_err 'file is empty' 'empty frame is named'
rr_frame 2 'missing custom frame path is refused, never created' "$RR_ROOT/absent-frame.md" rr-review T01
pwtest_err 'configured review-frame template missing' 'missing custom path is named'
[ ! -e "$RR_ROOT/absent-frame.md" ] && pwtest_ok 'missing custom frame is never materialized' || pwtest_bad 'missing custom frame is never materialized' 'file was created'
pwtest_eq 'frame validation precedes any forge query' "$calls_before" "$(rr_calls)"

# --- read-only guarantees --------------------------------------------------------------------
if grep -qv '^GET' "$RR_ROOT/forges/calls.log" 2>/dev/null; then
  pwtest_bad 'no forge writes are attempted' "$(grep -v '^GET' "$RR_ROOT/forges/calls.log" | head -2 | tr '\n' ' ')"
else
  pwtest_ok 'no forge writes are attempted'
fi
RR_BEFORE="$(find "$PW_PROJECTS_DIR/rr-review" -type f -exec cksum {} + | sort | cksum)"
rr 0 'state comparison run' rr-review all
RR_AFTER="$(find "$PW_PROJECTS_DIR/rr-review" -type f -exec cksum {} + | sort | cksum)"
pwtest_eq 'generation changes no project file' "$RR_BEFORE" "$RR_AFTER"

# --- frame health primitives (shared by bootstrap and doctor) --------------------------------
RR_SEED_DEST="$RR_ROOT/seeded/review-request.md"
pwtest_rc 0 'frame seeding creates the default user file' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_seed "$2"' _ "$PW_HOME/tooling/scripts/lib/pw-common.sh" "$RR_SEED_DEST"
pwtest_grep_file '\{\{MR_BLOCKS\}\}' 'seeded frame carries the block placeholders' "$RR_SEED_DEST"
printf 'custom user frame\n' > "$RR_SEED_DEST"
pwtest_rc 1 'frame seeding refuses an existing destination' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_seed "$2"' _ "$PW_HOME/tooling/scripts/lib/pw-common.sh" "$RR_SEED_DEST"
pwtest_eq 'customized bytes survive a reseed attempt' 'custom user frame' "$(cat "$RR_SEED_DEST")"
RR_DOCTOR="$(pwtest_script pw-doctor.sh)"
pwtest_rc 1 'doctor reports a missing custom frame' \
  env "${RR_ENV[@]}" "PW_REVIEW_REQUEST_TEMPLATE_FILE=$RR_ROOT/absent-doctor.md" bash "$RR_DOCTOR"
pwtest_re 'review frame' 'doctor names the review-frame finding'
[ ! -e "$RR_ROOT/absent-doctor.md" ] && pwtest_ok 'doctor never creates a custom frame path' || pwtest_bad 'doctor never creates a custom frame path' 'file was created'

# --- prompt seeds, migration, and path resolution ---------------------------------------------
RR_LIB="$PW_HOME/tooling/scripts/lib/pw-common.sh"
pwtest_rc 0 'prompt seeding creates the summary default' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_prompt_seed summary "$2"' _ "$RR_LIB" "$RR_ROOT/pseeded-summary.md"
pwtest_grep_file 'length limit' 'seeded summary prompt carries its contract' "$RR_ROOT/pseeded-summary.md"
printf 'my summary style\n' > "$RR_ROOT/pseeded-summary.md"
pwtest_rc 1 'prompt seeding refuses an existing destination' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_prompt_seed summary "$2"' _ "$RR_LIB" "$RR_ROOT/pseeded-summary.md"
pwtest_eq 'customized prompt bytes survive a reseed attempt' 'my summary style' "$(cat "$RR_ROOT/pseeded-summary.md")"
pwtest_rc 0 'prompt health rejects an empty file' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; [ -n "$(pw_review_prompt_error "$2")" ]' _ "$RR_LIB" "$RR_ROOT/prompt-empty.md"
pwtest_rc 0 'prompt health rejects an oversized file' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; [ -n "$(pw_review_prompt_error "$2")" ]' _ "$RR_LIB" "$RR_ROOT/prompt-big.md"
# default resolution: unset/empty selects user/templates + user/prompts under PW_HOME
rr_defaults() { PW_HOME="$RR_BARE" bash -c 'unset PW_REVIEW_REQUEST_TEMPLATE_FILE PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE PW_REVIEW_REQUEST_NOTE_PROMPT_FILE
. "$1"; printf "%s|%s\n" "$(pw_review_template_path)" "$(pw_review_prompt_path summary)"' _ "$RR_LIB"; }
pwtest_eq 'unset settings resolve to the editable defaults' \
  "$RR_BARE/user/templates/review-request.md|$RR_BARE/user/prompts/review-request-summary.md" "$(rr_defaults)"
rr_rels() { env PW_HOME="$RR_BARE" PW_REVIEW_REQUEST_SUMMARY_PROMPT_FILE="user/prompts/team.md" \
  PW_REVIEW_REQUEST_NOTE_PROMPT_FILE="prompts/team-notes.md" PW_REVIEW_REQUEST_TEMPLATE_FILE="user/templates/team-frame.md" \
  bash -c '. "$1"; printf "%s|%s|%s\n" "$(pw_review_template_path)" "$(pw_review_prompt_path summary)" "$(pw_review_prompt_path note)"' _ "$RR_LIB"; }
pwtest_eq 'relative configured paths resolve under PW_HOME' \
  "$RR_BARE/user/templates/team-frame.md|$RR_BARE/user/prompts/team.md|$RR_BARE/prompts/team-notes.md" "$(rr_rels)"
# migration: legacy content survives byte-for-byte; the new default wins when both exist
RR_MIG_NEW="$RR_ROOT/migrated/templates/review-request.md"
RR_MIG_LEG="$RR_ROOT/legacy/review-request.md"
mkdir -p "$RR_ROOT/migrated/templates" "$RR_ROOT/legacy"
printf 'legacy customized frame bytes\n' > "$RR_MIG_LEG"
pwtest_rc 0 'legacy template migrates byte-for-byte' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_migrate "$2" "$3"' _ "$RR_LIB" "$RR_MIG_NEW" "$RR_MIG_LEG"
pwtest_eq 'migrated frame keeps the legacy customization' 'legacy customized frame bytes' "$(cat "$RR_MIG_NEW")"
[ -f "$RR_MIG_LEG" ] && pwtest_ok 'legacy file is kept for rollback' || pwtest_bad 'legacy file is kept for rollback' 'legacy deleted'
printf 'new default wins\n' > "$RR_MIG_NEW"
pwtest_rc 0 'an existing new default wins without overwrites' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_migrate "$2" "$3"' _ "$RR_LIB" "$RR_MIG_NEW" "$RR_MIG_LEG"
pwtest_eq 'new default preserved when both files exist' 'new default wins' "$(cat "$RR_MIG_NEW")"
pwtest_eq 'legacy preserved when both files exist' 'legacy customized frame bytes' "$(cat "$RR_MIG_LEG")"
mkdir -p "$RR_ROOT/unreadable"; printf 'x\n' > "$RR_ROOT/unreadable/legacy.md"; chmod 000 "$RR_ROOT/unreadable/legacy.md"
pwtest_rc 1 'an unreadable legacy file is a reported migration problem' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_migrate "$2" "$3"' _ "$RR_LIB" "$RR_ROOT/unreadable/new.md" "$RR_ROOT/unreadable/legacy.md"
[ ! -e "$RR_ROOT/unreadable/new.md" ] && pwtest_ok 'migration problem never seeds over the legacy file' || pwtest_bad 'migration problem never seeds over the legacy file' 'new default created'
chmod 644 "$RR_ROOT/unreadable/legacy.md"
pwtest_rc 0 'check-only migration report writes nothing' \
  env PW_HOME="$PW_HOME" bash -c '. "$1"; pw_review_template_migrate "$2" "$3" --report' _ "$RR_LIB" "$RR_ROOT/unreadable/new.md" "$RR_ROOT/unreadable/legacy.md"
[ ! -e "$RR_ROOT/unreadable/new.md" ] && pwtest_ok 'report mode creates nothing' || pwtest_bad 'report mode creates nothing' 'file appeared'
