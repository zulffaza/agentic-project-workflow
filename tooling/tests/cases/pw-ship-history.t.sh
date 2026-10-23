# shellcheck shell=bash
# Independent stateful API fixtures; no network, pushes, or thread replies.
HH_PROJECT=history-runtime
mkdir -p "$PW_PROJECTS_DIR/$HH_PROJECT"
cat > "$ROOT/history-forge-config.sh" <<'CONFIG'
PW_FORGE_HOSTS=("gitlab.test=gitlab" "github.test=github" "gitlab.example.com=gitlab")
CONFIG
pwtest_rc 0 'history runtime scenarios execute with strict forge fixtures' python3 - "$(pwtest_script pw-ship.sh)" "$PW_PROJECTS_DIR/$HH_PROJECT" "$ROOT" "$ROOT/history-forge-config.sh" <<'PY'
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys

script, project, scratch, configuration = sys.argv[1:]
project = Path(project)
scratch = Path(scratch) / 'history-forges'
scratch.mkdir()
checks = 0
def check(label, condition):
    global checks
    if not condition:
        print('FAIL\t' + label)
        raise AssertionError(label)
    checks += 1
    print('PASS\t' + label)

def summary(head, behavior='Reject empty IDs.'):
    return ('<!-- pw-mr-summary:start -->\n## What & why\n' + behavior +
            '\n## High-level changes\n- ' + behavior + '\n## Low-level changes\n- Validator changed.\n'
            '## Verification\n- Tests passed at ' + head + '.\n## Notes for the reviewer\n- Check validation.\n<!-- pw-mr-summary:end -->')

for forge, host, url, endpoint in [
    ('glab', 'gitlab.test', 'https://gitlab.test/a/b/-/merge_requests/42', 'projects/a%2Fb/merge_requests/42'),
    ('gh', 'github.test', 'https://github.test/a/b/pull/42', 'repos/a/b/pulls/42')]:
    field = 'description' if forge == 'glab' else 'body'
    native = {'state': 'opened', 'sha': 'a111111'} if forge == 'glab' else {'state': 'open', 'head': {'sha': 'a111111'}}
    outside = '\n\n## Reviewer checklist\n- Preserve café and emoji 🧪.\n'
    native[field] = summary('a111111') + outside
    native['private_token'] = 'glpat-SENTINEL'
    fixture = scratch / (hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest() + '.json')
    fixture.write_text(json.dumps({'response': native, 'reads': 0, 'writes': 0}, ensure_ascii=False))
    (project / 'task').mkdir(exist_ok=True)
    (project / 'task' / 'T01.md').write_text('# Task\n## Result\n- **MR:** ' + url + '\n')
    env = dict(os.environ, PWTEST_HISTORY_FORGE_DIR=str(scratch), PW_CONFIG_FILE=configuration)
    def state():
        return json.loads(fixture.read_text())
    def edit(**changes):
        item = state(); item.update(changes); fixture.write_text(json.dumps(item, ensure_ascii=False))
    def head(sha):
        item = state()
        if forge == 'glab': item['response']['sha'] = sha
        else: item['response']['head']['sha'] = sha
        fixture.write_text(json.dumps(item, ensure_ascii=False))
    def call(op, *args, rc=0, env_extra=None):
        run_env = dict(env)
        if env_extra:
            run_env.update(env_extra)
        rest = list(args)
        mr = None
        if rest and not rest[0].startswith('--'):
            mr = rest.pop(0)
        argv = ['bash', script, 'history', '--project', project.name, '--operation', op]
        if mr is not None:
            argv += ['--mr', mr]
        if rest:
            argv += ['--options'] + rest
        result = subprocess.run(argv, env=run_env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd='/')
        if result.returncode != rc:
            print(result.stderr, file=sys.stderr)
        check(forge + ' ' + op + ' rc=' + str(rc), result.returncode == rc)
        if rc:
            check(forge + ' actionable failure ' + op, '→ fix:' in result.stderr)
        return result
    # D01: published-body readback and the scoped repair preview (dry run, no writes).
    verified = call('verify', url)
    check(forge + ' forge response fields are allowlisted (no credential echo)',
          'glpat-SENTINEL' not in (verified.stdout + verified.stderr))
    original = dict(state()['response'])
    res = state()
    res['response'][field] = summary('a111111') + chr(92) + 'n' + chr(92) + 'n' + outside
    fixture.write_text(json.dumps(res, ensure_ascii=False))
    call('verify', url, rc=2)
    writes_before = state()['writes']
    preview = call('repair-preview', url)
    check(forge + ' repair preview is a dry run', state()['writes'] == writes_before)
    check(forge + ' repair preview names the literal suffix', 'literal' in preview.stdout)
    res = state()
    res['response'] = original
    fixture.write_text(json.dumps(res, ensure_ascii=False))
    # D03: capacity discovery, the documented 403 fallback, and reuse of the persisted policy.
    if forge == 'glab':
        doc = 'https://docs.gitlab.com/api/merge_requests/'
        capdir = project / '.ship-history' / 'capacity'
        if capdir.exists():
            for item in capdir.glob('*.json'):
                item.unlink()
        first = call('capacity', url, env_extra={'PWTEST_SETTINGS_403': '1'})
        check('glab capacity falls back on settings 403', 'settings-403' in first.stdout and doc in first.stdout)
        check('glab capacity policy persisted', any(capdir.glob('*.json')))
        reused = call('capacity', url, env_extra={'PWTEST_SETTINGS_JSON': '{"max_merge_request_description_length": 5000}'})
        check('glab capacity policy reused (no re-probe)', '1048576' in reused.stdout)
        for item in capdir.glob('*.json'):
            item.unlink()
        learned = call('capacity', url, env_extra={'PWTEST_SETTINGS_JSON': '{"max_merge_request_description_length": 5000}'})
        check('glab capacity uses the instance limit', '5000' in learned.stdout and 'instance-settings' in learned.stdout)
    def archive():
        records = [json.loads(p.read_text()) for p in (project / '.ship-history').glob('*.json')]
        return next(r for r in records if r['mr']['host'] == host and r['mr']['number'] == int(url.rsplit('/', 1)[1]))
    def evidence(sha, commits=None, text='Reject blank IDs.'):
        return {'before': ['Empty IDs are rejected.', 'Blank IDs reach downstream.'],
                'after': [text], 'summary': ['Validate blank IDs.', 'Keep error codes.'],
                'commits': commits if commits is not None else [{'sha': sha, 'subject': 'Reject blank IDs', 'published': True}],
                'verification': [{'head': sha, 'text': 'Local tests: 44 passed, 0 failed'},
                                 {'head': sha, 'text': 'Pipeline: passed for current head'}],
                'head': sha, 'summary_body': summary(sha, text), 'tasks': ['T01', 'T02'], 'comments': ['inline:101', 'general:102']}
    def put(key, data, rc=0):
        file = scratch / 'payload.json'; file.write_text(json.dumps(data, ensure_ascii=False))
        return call('checkpoint', url, '--attempt', key, '--file', str(file), rc=rc)
    def begin(name):
        return json.loads(call('begin', url, '--invocation', name).stdout)['key']
    def deliver(key, limit=100000, rc=0):
        return call('deliver', url, '--attempt', key, '--limit', str(limit), '--unit', 'utf8',
                    '--limit-source', 'offline fixture capacity', rc=rc)
    creation_body = scratch / (forge + '-creation.md'); creation_body.write_text(native[field], encoding='utf-8')
    edit(mode='fetch-fail'); call('init', url, '--file', str(creation_body), rc=2)
    check(forge + ' failed initial readback is discoverable without a review attempt', 'initial_snapshot_pending' in call('pending').stdout and not archive()['attempts'])
    creation_body.unlink(); edit(mode=None); call('init', url)
    check(forge + ' creation body survives lost temporary source', archive()['initial_body'] == native[field])
    # D02: ownership-proven delimiter recovery. Only the exact saved summary interior may be
    # re-wrapped; a repeated/edited interior stops without writing.
    saved = archive()['last_summary']
    interior = saved[saved.index('-->') + 3:saved.rindex('<!-- pw-mr-summary:end')].strip('\n')
    broken = native[field].replace('<!-- pw-mr-summary:start -->\n', '').replace('\n<!-- pw-mr-summary:end -->', '')
    res = state(); res['response'][field] = broken; fixture.write_text(json.dumps(res, ensure_ascii=False))
    before = state()['writes']
    rp = call('recover-preview', url)
    check(forge + ' recovery preview is a dry run', state()['writes'] == before)
    check(forge + ' recovery preview names both missing delimiters', 'start@' in rp.stdout and 'end@' in rp.stdout)
    ra = call('recover', url, '--apply')
    body = state()['response'][field]
    check(forge + ' recovery restores both markers with raw readback evidence',
          body.count('<!-- pw-mr-summary:start -->') == 1 and body.count('<!-- pw-mr-summary:end -->') == 1
          and 'restored missing delimiter' in ra.stdout)
    check(forge + ' recovery preserves every outside byte', body.endswith(outside.lstrip('\n')) and 'café' in body)
    check(forge + ' recovery reuses the saved summary interior', interior in body)
    res = state(); res['response'][field] = interior + '\n\n' + interior + '\n' + outside
    fixture.write_text(json.dumps(res, ensure_ascii=False))
    before = state()['writes']
    amb = call('recover-preview', url)
    check(forge + ' ambiguous duplicate interior is refused without writing',
          state()['writes'] == before and ('occur' in amb.stdout) and 'nothing was written' in amb.stdout)
    res = state(); res['response'][field] = native[field]; fixture.write_text(json.dumps(res, ensure_ascii=False))
    key1 = begin('invocation-1')
    check(forge + ' invocation/MR idempotent', begin('invocation-1') == key1)
    call('begin', url, '--invocation', 'other-active', rc=2)
    data1 = evidence('b222222')
    data1['commits'].append({'sha': 'c333333', 'subject': 'Fix CI formatting', 'published': True})
    data1['head'] = 'c333333'; data1['summary_body'] = summary('c333333', 'Reject blank IDs.')
    data1['verification'].append({'head': 'c333333', 'text': 'Final pipeline passed after CI repair'})
    put(key1, data1)
    call('freeze', url, '--attempt', key1)
    frozen1 = archive()['attempts'][0]['block']
    head('c333333')
    deliver(key1)
    body1 = state()['response'][field]
    check(forge + ' one block for many comments/commits/CI repairs', body1.count('<!-- pw-review-attempt:') == 1)
    check(forge + ' before after summary bullet groups', all('##### ' + name + '\n- ' in body1 for name in ['Before', 'After', 'Summary']))
    check(forge + ' commit list includes both commits', '- `b222222`' in body1 and '- `c333333`' in body1)
    check(forge + ' verification includes CI without standalone CI heading', 'Final pipeline passed' in body1 and '\n#### CI' not in body1)
    check(forge + ' first delivery refreshes owned current summary', 'Reject blank IDs.' in body1.split('<!-- pw-mr-summary:end -->')[0])
    check(forge + ' no request or comment references', 'Request:' not in body1 and 'inline:101' not in body1)
    check(forge + ' notes within summary and history last', body1.index('## Notes for the reviewer') < body1.index('<!-- pw-mr-summary:end -->') < body1.index('## Review changes') and body1.endswith('<!-- pw-review-changes:end -->'))
    check(forge + ' outside Unicode bytes preserved', outside in body1)
    def display(ts):
        parts = ts.rsplit(' WIB', 1)[0].split(' ')
        return ts if ' - ' in ts else ' '.join(parts[:3]) + ' - ' + ' '.join(parts[3:]) + ' WIB'
    label1 = archive()['attempts'][0]['timestamp']
    check(forge + ' one collapsed wrapper per attempt with the persisted datetime', body1.count('<details>') == 1 and body1.count('</details>') == 1 and '<summary>Review attempt: ' + display(label1) + '</summary>' in body1)
    check(forge + ' frozen block bytes stay inside the wrapper', '<summary>Review attempt: ' + display(label1) + '</summary>\n\n' + frozen1 + '</details>' in body1)
    writes = state()['writes']; deliver(key1)
    check(forge + ' completed retry makes no write', state()['writes'] == writes and state()['response'][field] == body1)
    changed = dict(data1, summary=['rewrite frozen attempt'])
    put(key1, changed, rc=2)

    # New invocation refreshes current summary but never old block bytes.
    key2 = begin('invocation-2')
    put(key2, evidence('d444444', text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key2); head('d444444'); deliver(key2)
    body2 = state()['response'][field]
    check(forge + ' newest-first order', body2.index(key2) < body2.index(key1))
    check(forge + ' prior block byte immutable', frozen1 in body2)
    check(forge + ' current summary replaces obsolete behavior', 'Preserve valid ID bytes.' in body2.split('<!-- pw-mr-summary:end -->')[0] and 'Reject blank IDs.' not in body2.split('<!-- pw-mr-summary:end -->')[0])
    # Legacy unwrapped presentation (both attempts, newest first) converts on the next
    # authorized delivery without changing the enclosed frozen bytes; the wrapped retry is stable.
    current = state()['response'][field]
    start = '<!-- pw-review-changes:start -->'; end = '<!-- pw-review-changes:end -->'
    legacy_region = start + '\n## Review changes\n' + archive()['attempts'][1]['block'] + frozen1 + end
    item = state(); item['response'][field] = current[:current.index(start)] + legacy_region
    fixture.write_text(json.dumps(item, ensure_ascii=False))
    deliver(key2)
    converted = state()['response'][field]
    check(forge + ' legacy unwrapped history converts during authorized delivery', converted.count('<details>') == 2 and '<summary>Review attempt: ' + display(label1) + '</summary>\n\n' + frozen1 + '</details>' in converted)
    labels = re.findall(r'<summary>Review attempt: ([^<]*)</summary>', converted)
    check(forge + ' one wrapper per attempt with persisted labels', len(labels) == 2 and all(re.fullmatch(r'[0-9]{1,2} [A-Za-z]+ [0-9]{4} - [0-9]{2}\.[0-9]{2} WIB', label) for label in labels))
    writes = state()['writes']; deliver(key2)
    check(forge + ' wrapped history retry makes no write', state()['writes'] == writes)
    call('pending')
    check(forge + ' no pending after successful deliveries', not any(not a['delivered'] for a in archive()['attempts']))

    # Failure before write and success-before-acknowledgement retain the exact frozen key.
    key3 = begin('invocation-3'); put(key3, evidence('d444444', commits=[], text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key3)
    edit(mode='write-fail'); deliver(key3, rc=2)
    check(forge + ' failed write keeps remote bytes', state()['response'][field] == body2)
    check(forge + ' failed write remains pending', not archive()['attempts'][2]['delivered'])
    edit(mode='success-before-error'); deliver(key3, rc=2)
    writes = state()['writes']; deliver(key3)
    check(forge + ' remote-success recovery avoids duplicate write', state()['writes'] == writes)
    check(forge + ' answer/verification-only commit list', '- None. Published head remains `d444444`.' in state()['response'][field])

    # Recheck-before-write rebases an outside human edit.
    key4 = begin('invocation-4'); put(key4, evidence('d444444', commits=[], text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key4)
    edit(race_at=state()['reads'] + 2, race_text='\nHuman addition during delivery.\n')
    deliver(key4)
    check(forge + ' outside concurrent edit survives', 'Human addition during delivery.' in state()['response'][field])

    # Retention drops whole oldest blocks and preserves the complete local archive.
    key5 = begin('invocation-5'); put(key5, evidence('d444444', commits=[], text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key5)
    newest = archive()['attempts'][-1]['block']
    limit = len(summary('d444444', 'Preserve valid ID bytes.').encode()) + len(outside.encode()) + len(newest.encode()) + 400
    edit(mode='success-before-error'); deliver(key5, limit=limit, rc=2)
    writes = state()['writes']; deliver(key5, limit=limit)
    check(forge + ' pruning survives crash after remote success without rewrite', state()['writes'] == writes)
    kept = state()['response'][field]
    check(forge + ' retention keeps newest full block', newest in kept)
    check(forge + ' retention removes oldest blocks', key1 not in kept and archive()['pruned'])
    check(forge + ' full local archive retained', len(archive()['attempts']) == 5 and archive()['attempts'][0]['block'] == frozen1)
    call('deliver', url, '--attempt', key5, '--limit', str(len(kept)), '--unit', 'chars', '--limit-source', 'fixture chars')
    deliver(key5, limit=len(kept), rc=2)
    check(forge + ' exact UTF8 capacity accepts boundary', len(kept.encode()) > len(kept))
    deliver(key5, limit=len(kept.encode()))
    writes = state()['writes']; deliver(key1)
    check(forge + ' pruned retry never resurrects', state()['writes'] == writes and key1 not in state()['response'][field])
    key6 = begin('invocation-6'); put(key6, evidence('d444444', commits=[], text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key6)
    before_capacity = state()['response'][field]; deliver(key6, limit=1, rc=2)
    check(forge + ' capacity failure does not publish truncation', state()['response'][field] == before_capacity)
    edit(mode='write-noop'); deliver(key6, rc=2)
    check(forge + ' ok response without landed text remains pending', not archive()['attempts'][-1]['delivered'])
    edit(mode=None); deliver(key6)

    # A pre-upgrade attempt persists an undashed datetime: its frozen bytes stay untouched while
    # the wrapper label displays the separator; the wrapped retry is byte-stable.
    legacy_bin = scratch / 'legacy-bin'; legacy_bin.mkdir(exist_ok=True)
    legacy_date = legacy_bin / 'date'
    legacy_date.write_text('#!/usr/bin/env bash\nprintf \'7 October 2026 09.00\\n\'\n')
    legacy_date.chmod(0o755)
    legacy_key = json.loads(call('begin', url, '--invocation', 'invocation-legacy',
                                 env_extra={'PATH': str(legacy_bin) + ':' + os.environ['PATH']}).stdout)['key']
    put(legacy_key, evidence('e555555', text='Legacy undashed attempt.'))
    call('freeze', url, '--attempt', legacy_key)
    check(forge + ' legacy attempt persists its undashed timestamp', archive()['attempts'][-1]['timestamp'] == '7 October 2026 09.00 WIB')
    deliver(legacy_key)
    legacy_body = state()['response'][field]
    check(forge + ' legacy frozen bytes keep the undashed heading', '### 7 October 2026 09.00 WIB' in legacy_body)
    check(forge + ' legacy wrapper label displays the separator', '<summary>Review attempt: 7 October 2026 - 09.00 WIB</summary>' in legacy_body)
    writes = state()['writes']; deliver(legacy_key)
    check(forge + ' legacy wrapper retry is byte-stable', state()['writes'] == writes)

    # Closed MR and unknown API outcome never turn into a successful delivery.
    key7 = begin('invocation-7'); put(key7, evidence('d444444', commits=[], text='Preserve valid ID bytes.'))
    call('freeze', url, '--attempt', key7)
    item = state(); item['response']['state'] = 'closed'; fixture.write_text(json.dumps(item))
    writes = state()['writes']; deliver(key7, rc=2)
    check(forge + ' closed MR makes no write', state()['writes'] == writes)
    item = state(); item['response']['state'] = 'opened' if forge == 'glab' else 'open'; fixture.write_text(json.dumps(item))
    edit(mode='fetch-fail'); deliver(key7, rc=2)
    edit(mode='always-race'); reads = state()['reads']; deliver(key7, rc=2)
    check(forge + ' bounded retry limit', state()['reads'] - reads == 6)
    edit(mode=None)
    # Active/frozen evidence is safe against malformed paths and marker injection.
    key8 = begin('invocation-8')
    bad = evidence('d444444'); bad['summary'] = ['<!-- pw-review-changes:end -->']
    put(key8, bad, rc=2)
    link = scratch / 'payload-link.json'; link.unlink(missing_ok=True); link.symlink_to(scratch / 'payload.json')
    call('checkpoint', url, '--attempt', key8, '--file', str(link), rc=2)
    unsafe_url = url.replace('/a/b/', '/a/../b/')
    (project / 'task' / 'T99.md').write_text('# Task\n## Result\n- **MR:** ' + unsafe_url + '\n')
    if forge == 'glab':
        unsafe_endpoint = 'projects/a%2F..%2Fb/merge_requests/42'
        unsafe_fixture = scratch / (hashlib.sha256((forge + '|' + host + '|' + unsafe_endpoint).encode()).hexdigest() + '.json')
        unsafe_fixture.write_text(json.dumps({'response': state()['response'], 'reads': 0, 'writes': 0}))
    traversal = call('begin', unsafe_url, '--invocation', 'traversal', rc=2)
    if forge == 'glab':
        check('repository traversal rejected before an otherwise valid forge lookup', 'unsafe repository identity' in traversal.stderr)
    (project / 'task' / 'T99.md').unlink()
    call('deliver', url, '--attempt', '../../escape', rc=2)
    unrelated = evidence('d444444'); unrelated['verification'][0]['head'] = '0000000'
    put(key8, unrelated, rc=2)
    put(key8, evidence('d444444', commits=[]))
    call('freeze', url, '--attempt', key8)
    original = state()['response'][field]
    item = state(); item['response'][field] = original.replace('## Notes for the reviewer\n', '## Notes for the reviewer\nHuman changed owned content.\n', 1)
    fixture.write_text(json.dumps(item)); deliver(key8, rc=2)
    item = state(); item['response'][field] = original.replace('#### Changes\n', '#### Changes\nHuman edited history.\n', 1)
    fixture.write_text(json.dumps(item)); deliver(key8, rc=2)
    item = state(); item['response'][field] = original + '\n<!-- pw-review-changes:start -->\n'
    fixture.write_text(json.dumps(item)); deliver(key8, rc=2)
    item = state(); item['response'][field] = original + '\n<!-- pw-review-changes:broken\n'
    fixture.write_text(json.dumps(item)); deliver(key8, rc=2)
    item = state(); item['response'][field] = original; fixture.write_text(json.dumps(item))
    id_field = 'iid' if forge == 'glab' else 'number'
    item = state(); item['response'][id_field] = 99; fixture.write_text(json.dumps(item)); deliver(key8, rc=2)
    item = state(); item['response'][id_field] = 42; fixture.write_text(json.dumps(item))
    edit(mode='head-change-on-write'); deliver(key8, rc=2)
    check(forge + ' head advancing during write is not acknowledged', not archive()['attempts'][-1]['delivered'])
    result = deliver(key8)
    check(forge + ' advanced head recovery does not certify stale summary', 'summary refresh pending' in result.stdout)
    unregistered = call('begin', url.rsplit('/', 1)[0] + '/99', '--invocation', 'unregistered', rc=2)
    check(forge + ' unregistered MR cannot trigger a query', 'not registered in this project' in unregistered.stderr)
    unknown_host = call('begin', url.replace(host, 'unknown.test'), '--invocation', 'unknown-host', rc=2)
    check(forge + ' unknown host cannot receive forge credentials', 'configured forge registry' in unknown_host.stderr)

    # Legacy summaries are not adopted by headings; partial delivery remains visible in pending.
    url = url.rsplit('/', 1)[0] + '/43'; endpoint = endpoint.rsplit('/', 1)[0] + '/43'
    (project / 'task' / 'T03.md').write_text('# Legacy task\n## Result\n- **MR:** (none)\n')
    (project / 'README.md').write_text('# Dashboard\n## Merge requests\n| Task | Repo | MR | State |\n|---|---|---|---|\n| T03 | a/b | [MR](' + url + ') | open |\n')
    fixture = scratch / (hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest() + '.json')
    native = {'state': 'opened', 'sha': 'f666666'} if forge == 'glab' else {'state': 'open', 'head': {'sha': 'f666666'}}
    native[field] = '## What & why\nLegacy author summary and reviewer notes.\n'
    fixture.write_text(json.dumps({'response': native, 'reads': 0, 'writes': 0}))
    legacy_key = begin('legacy-call'); put(legacy_key, evidence('f666666', commits=[])); call('freeze', url, '--attempt', legacy_key)
    partial = deliver(legacy_key)
    check(forge + ' legacy ownership remains unchanged', state()['response'][field].startswith(native[field]))
    check(forge + ' legacy partial delivery says summary pending', 'summary refresh pending' in partial.stdout)
    pending = call('pending')
    check(forge + ' delivered history with pending summary remains discoverable', legacy_key in pending.stdout and '"summary_pending": true' in pending.stdout)
    # Capacity now resolves from the persisted host policy, so this re-delivery proceeds instead
    # of failing on missing --limit flags (D03 changes that contract deliberately).
    call('deliver', url, '--attempt', legacy_key)
    record_path = next(p for p in (project / '.ship-history').glob('*.json') if json.loads(p.read_text())['mr']['host'] == host and json.loads(p.read_text())['mr']['number'] == 43)
    lock = project.parent / '.ship-history-locks' / (record_path.stem + '.lock'); lock.mkdir()
    call('freeze', url, '--attempt', legacy_key, rc=2)
    check(forge + ' competing lock is never removed', lock.exists()); lock.rmdir()
    original_record = record_path.read_bytes()
    record_path.write_text('{malformed'); call('pending', rc=2); record_path.write_bytes(original_record)
    invalid = json.loads(original_record); invalid['version'] = True
    record_path.write_text(json.dumps(invalid)); call('pending', rc=2); record_path.write_bytes(original_record)
    alias = project / '.ship-history' / 'linked.json'; alias.symlink_to(record_path)
    call('pending', rc=2); alias.unlink()
    if os.geteuid() != 0:
        prior_mode = record_path.parent.stat().st_mode & 0o777
        record_path.parent.chmod(0o500)
        try:
            put(legacy_key, archive()['attempts'][0]['checkpoint'], rc=2)
            check(forge + ' failed persistence preserves exact prior record', record_path.read_bytes() == original_record)
        finally:
            record_path.parent.chmod(prior_mode)
    else:
        print('SKIP\tpermission-based persistence failure requires non-root execution')
    legacy_frozen = archive()['attempts'][0]['block']
    history_region = state()['response'][field].split('<!-- pw-review-changes:start -->', 1)[1]
    reviewed = summary('f666666') + '\n\n<!-- pw-review-changes:start -->' + history_region
    item = state(); item['response'][field] = reviewed; fixture.write_text(json.dumps(item))
    reviewed_file = scratch / 'reviewed.md'; reviewed_file.write_text(reviewed)
    call('init', url, '--file', str(reviewed_file), rc=2)
    call('init', url, '--file', str(reviewed_file), '--reviewed')
    check(forge + ' explicitly reviewed ownership repair clears partial state', not archive()['attempts'][0]['summary_pending'])
    check(forge + ' ownership repair never changes frozen history', archive()['attempts'][0]['block'] == legacy_frozen)

    # Delayed older history never rolls the current summary back.
    url = url.rsplit('/', 1)[0] + '/44'; endpoint = endpoint.rsplit('/', 1)[0] + '/44'
    (project / 'task' / 'T04.md').write_text('# Task\n## Result\n- **MR:** ' + url + '\n')
    fixture = scratch / (hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest() + '.json')
    native = {'state': 'opened', 'sha': 'a111111'} if forge == 'glab' else {'state': 'open', 'head': {'sha': 'a111111'}}
    native[field] = summary('a111111') + outside
    fixture.write_text(json.dumps({'response': native, 'reads': 0, 'writes': 0}))
    creation_body.write_text(native[field]); call('init', url, '--file', str(creation_body))
    older = begin('delayed-older'); put(older, evidence('b222222')); call('freeze', url, '--attempt', older); head('b222222')
    newer = begin('delayed-newer'); put(newer, evidence('c333333', text='Newest behavior.')); call('freeze', url, '--attempt', newer); head('c333333')
    deliver(newer); newest_summary = state()['response'][field].split('<!-- pw-mr-summary:end -->')[0]
    deliver(older); final_body = state()['response'][field]
    check(forge + ' delayed attempt inserts in original sequence', final_body.index(newer) < final_body.index(older))
    check(forge + ' delayed history preserves newest summary', final_body.split('<!-- pw-mr-summary:end -->')[0] == newest_summary)
    check(forge + ' current newest-head summary is not incorrectly pending', not archive()['attempts'][0]['summary_pending'])
    # A CRLF creation body and Unicode outside text retain their exact bytes.
    url = url.rsplit('/', 1)[0] + '/45'; endpoint = endpoint.rsplit('/', 1)[0] + '/45'
    (project / 'task' / 'T05.md').write_text('# Task\n## Result\n- **MR:** ' + url + '\n')
    fixture = scratch / (hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest() + '.json')
    native = {'state': 'opened', 'sha': 'a111111'} if forge == 'glab' else {'state': 'open', 'head': {'sha': 'a111111'}}
    crlf_outside = outside.replace('\n', '\r\n')
    native[field] = summary('a111111').replace('\n', '\r\n') + crlf_outside
    fixture.write_text(json.dumps({'response': native, 'reads': 0, 'writes': 0}))
    creation_body.write_bytes(native[field].encode()); call('init', url, '--file', str(creation_body))
    crlf_key = begin('crlf-call'); put(crlf_key, evidence('b222222')); call('freeze', url, '--attempt', crlf_key)
    head('b222222'); deliver(crlf_key)
    check(forge + ' CRLF/Unicode outside content is byte-preserved', crlf_outside in state()['response'][field])
    # Replacement-MR migration: preview, apply, idempotent retry, exact-block requirement.
    frozen_src = None
    src_rec_path = None
    for candidate in sorted((project / '.ship-history').glob('*.json')):
        data = json.loads(candidate.read_text())
        found = next((a for a in data['attempts'] if a['frozen'] and a.get('block')), None)
        if found:
            frozen_src = (data['mr'], found)
            src_rec_path = candidate
            break
    check(forge + ' migration source record available', frozen_src is not None)
    src_mr, frozen = frozen_src
    sep = '/pull/' if forge == 'gh' else '/-/merge_requests/'
    src_url = 'https://' + src_mr['host'] + '/' + src_mr['repo'] + sep + str(src_mr['number'])
    def dst_fixture_for(number, body_text):
        endpoint = ('repos/a/b/pulls/' if forge == 'gh' else 'projects/a%2Fb/merge_requests/') + str(number)
        path = scratch / (hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest() + '.json')
        native_dst = {'state': 'opened', 'sha': 'a111111'} if forge == 'glab' else {'state': 'open', 'head': {'sha': 'a111111'}}
        native_dst[field] = body_text
        path.write_text(json.dumps({'response': native_dst, 'reads': 0, 'writes': 0}, ensure_ascii=False))
        return path
    dst_num = 46 if forge == 'glab' else 56
    edited_num = dst_num + 1
    dst_url = 'https://' + host + '/a/b' + sep + str(dst_num)
    dst_fixture_for(dst_num, summary('a111111') + '\n\n' + frozen['block'])
    (project / 'task' / 'T06.md').write_text('# T06\n## Result\n- **MR:** ' + dst_url + '\n')
    preview = call('migrate', dst_url, '--source', src_url, '--attempts', frozen['key'])
    check(forge + ' migrate preview names the plan', 'migrate-preview' in preview.stdout)
    check(forge + ' migrate preview writes no destination record',
          not any(json.loads(item.read_text())['mr']['number'] == dst_num
                  for item in (project / '.ship-history').glob('*.json')))
    call('migrate', dst_url, '--source', src_url, '--attempts', frozen['key'], '--apply')
    dst_record = next(item for item in (project / '.ship-history').glob('*.json')
                      if json.loads(item.read_text())['mr']['number'] == dst_num)
    copied = next((a for a in json.loads(dst_record.read_text())['attempts'] if a['key'] == frozen['key']), None)
    check(forge + ' migrate copied the frozen attempt', copied is not None and copied.get('source_mr'))
    check(forge + ' migrated attempt starts undelivered', copied['delivered'] is False and copied['block'] == frozen['block'])
    again = call('migrate', dst_url, '--source', src_url, '--attempts', frozen['key'], '--apply')
    check(forge + ' migrate retry is idempotent', 'migrate: 0 attempt(s)' in again.stdout)
    # Archived source: the record is found in a sibling project instead of being called lost.
    archived = project.parent / 'archived-fixture' / '.ship-history'
    archived.mkdir(parents=True, exist_ok=True)
    src_rec_path.rename(archived / src_rec_path.name)
    dst3_num = dst_num + 2
    dst3_url = 'https://' + host + '/a/b' + sep + str(dst3_num)
    dst_fixture_for(dst3_num, summary('a111111') + '\n\n' + frozen['block'])
    (project / 'task' / 'T08.md').write_text('# T08\n## Result\n- **MR:** ' + dst3_url + '\n')
    archived_run = call('migrate', dst3_url, '--source', src_url, '--attempts', frozen['key'], '--apply')
    check(forge + ' migrate finds the record in an archived project', 'archived project' in archived_run.stdout)
    edited = frozen['block'].replace('#### Changes', '#### Changes (edited)')
    dst2_url = 'https://' + host + '/a/b' + sep + str(edited_num)
    dst_fixture_for(edited_num, summary('a111111') + '\n\n' + edited)
    (project / 'task' / 'T07.md').write_text('# T07\n## Result\n- **MR:** ' + dst2_url + '\n')
    call('migrate', dst2_url, '--source', src_url, '--attempts', frozen['key'], rc=2)
    print('PASS\t' + forge + ' all runtime scenarios reached')
print('ASSERTIONS\t' + str(checks))
PY
while IFS=$'\t' read -r HH_STATUS HH_LABEL; do
  case "$HH_STATUS" in PASS) pwtest_ok "$HH_LABEL" ;; SKIP) pwtest_skip "$HH_LABEL" 'requires non-root permissions' ;; esac
done < "$PWTEST_OUT"
pwtest_grep_file '^ASSERTIONS' 'history scenarios have nonempty runtime assertion coverage' "$PWTEST_OUT"
HH_CREATE=history-create-f2
cp -a "$F2" "$PW_PROJECTS_DIR/$HH_CREATE"
pwtest_repo api "branch:agent/$HH_CREATE/T01-thing"
sed -i '' "s|agent/$S2/T01-thing|agent/$HH_CREATE/T01-thing|" "$PW_PROJECTS_DIR/$HH_CREATE/task/T01.md"
cat > "$ROOT/history-create.md" <<'BODY'
<!-- pw-mr-summary:start -->
## What & why
Create a validation change.
## High-level changes
- Reject empty IDs.
## Low-level changes
- Validator changed.
## Verification
- Local tests passed.
## Notes for the reviewer
- Review validation order.
<!-- pw-mr-summary:end -->
BODY
mkdir -p "$ROOT/history-create-forge"
python3 - "$ROOT/history-create-forge" "$ROOT/history-create.md" <<'FIXTURE'
import hashlib, json, sys
from pathlib import Path
key = hashlib.sha256(b'glab|gitlab.example.com|projects/pwtest%2Fapi/merge_requests/42').hexdigest()
Path(sys.argv[1], key + '.json').write_text(json.dumps({'creation_url': 'https://gitlab.example.com/pwtest/api/-/merge_requests/42', 'response': {'state': 'opened', 'sha': 'dead000f', 'description': ''}, 'reads': 0, 'writes': 0}))
FIXTURE
pwtest_rc 0 'real ship exec snapshots marked newly created MR through readback' env PWTEST_HISTORY_FORGE_DIR="$ROOT/history-create-forge" PW_CONFIG_FILE="$ROOT/history-forge-config.sh" PWTEST_FORGE_STATE_FILE=/dev/null "$(pwtest_script pw-ship.sh)" exec --project "$HH_CREATE" --task T01 --file "$ROOT/history-create.md"
pwtest_re 'init: recorded' 'creation integrates initial ownership snapshot'
[ -d "$PW_PROJECTS_DIR/$HH_CREATE/.ship-history" ] && pwtest_ok 'ownership stored under project, not worktree' || pwtest_bad 'ownership store' 'missing'
rm -rf "$PW_PROJECTS_DIR/$HH_CREATE"
rm -rf "$PW_PROJECTS_DIR/$HH_PROJECT"
