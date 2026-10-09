# shellcheck shell=bash
# Request-review: deterministic selection, forge metadata, frame rendering, prose validation,
# and the read-only guarantee — against a strict per-endpoint forge fixture. Private projects;
# no shared fixture is touched.

RR_SHIP="$(pwtest_script pw-ship.sh)"
RR_FRAME="$PW_REVIEW_REQUEST_TEMPLATE_FILE"                 # harness-seeded default frame (temp root)
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

# Conflict + failure + empty projects reuse the same PLAN shape.
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
PY

RR_ENV=( "PATH=$PWTEST_TESTSDIR/bin:$PATH" "PW_PROJECTS_DIR=$PW_PROJECTS_DIR" "PW_REPOS=$PW_REPOS"
         "PW_CONFIG_FILE=$ROOT/rr-forge-config.sh" "PW_REVIEW_REQUEST_TEMPLATE_FILE=$RR_FRAME"
         "PWTEST_REVIEW_FORGE_DIR=$RR_ROOT/forges" )
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
grep -q '^\*\*Summary:\*\*' "$PWTEST_OUT" && pwtest_bad 'summary not faked without prose' 'summary rendered without prose' || pwtest_ok 'summary not faked without prose'

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
