# Source-only ship attempt records and owned MR description delivery.
# Python stdlib handles JSON/Unicode/atomic files; the entity supplies WIB and forge mappings.
pw_ship_history() {
  python3 - "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid
from urllib.parse import quote, unquote, urlsplit

class HistoryError(Exception):
    pass

class HistoryParser(argparse.ArgumentParser):
    def error(self, message):
        raise HistoryError('usage: ' + message)

def need(condition, message):
    if not condition:
        raise HistoryError(message)

def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

def safe_path(path, directory=False):
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        # macOS owns these filesystem aliases; user-controlled links remain forbidden.
        system_alias = str(part) in ('/var', '/tmp') and str(part.resolve()) == '/private' + str(part)
        need(not part.is_symlink() or (system_alias and part.lstat().st_uid == 0), 'unsafe symlink in history/input path')
    if path.exists():
        need(path.is_dir() if directory else path.is_file(), 'unexpected history/input file type')
    return path.resolve()

def read_json(path):
    return json.loads(safe_path(path).read_bytes().decode('utf-8'))

def atomic_json(path, value):
    # ponytail: one whole JSON archive per MR; segment records if history size makes rewrites expensive.
    safe_path(path)
    fd, temporary = tempfile.mkstemp(prefix='.history-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def identity(url, mappings):
    parsed = urlsplit(url)
    need(parsed.scheme in ('http', 'https') and not parsed.username and not parsed.password,
         'MR URL must be http(s) without credentials')
    host = parsed.netloc.lower()
    need(re.fullmatch(r'[a-z0-9][a-z0-9.-]*(?::[0-9]+)?', host), 'invalid MR hostname')
    need(not parsed.query and not parsed.fragment, 'MR URL must not contain query or fragment')
    path = unquote(parsed.path).rstrip('/')
    match = re.fullmatch(r'/(.+)/-/merge_requests/([1-9][0-9]*)', path)
    forge = 'gitlab'
    if not match:
        match = re.fullmatch(r'/([^/]+/[^/]+)/pull/([1-9][0-9]*)', path)
        forge = 'github'
    need(match is not None, 'unrecognized MR/PR URL')
    repo, number = match.groups()
    need(all(re.fullmatch(r'[A-Za-z0-9_.-]+', part) and part not in ('.', '..') for part in repo.split('/')),
         'unsafe repository identity')
    if forge == 'github':
        repo = repo.lower()
    known = (host, forge) in (('github.com', 'github'), ('gitlab.com', 'gitlab'))
    for mapping in mappings.splitlines():
        if '=' in mapping:
            configured_host, configured_forge = mapping.split('=', 1)
            if configured_host.lower() == host:
                need(configured_forge == forge, 'MR URL conflicts with configured forge')
                known = True
    need(known, 'MR hostname requires a matching configured forge registry entry')
    return {'forge': forge, 'host': host, 'repo': repo, 'number': int(number)}

def api(mr, body=None):
    github = mr['forge'] == 'github'
    endpoint = ('repos/' + mr['repo'] + '/pulls/' if github else
                'projects/' + quote(mr['repo'], safe='') + '/merge_requests/') + str(mr['number'])
    command = ['gh' if github else 'glab', 'api', endpoint, '--hostname', mr['host']]
    incoming = None
    if body is not None:
        command += ['--method', 'PATCH' if github else 'PUT', '--input', '-', '-H', 'Content-Type: application/json']
        incoming = json.dumps({'body' if github else 'description': body}, ensure_ascii=False)
    result = subprocess.run(command, input=incoming, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=90)
    need(result.returncode == 0, 'description update pending: forge request failed')
    response = json.loads(result.stdout)
    need(isinstance(response, dict), 'invalid forge response')
    if body is not None:
        return response
    need(str(response.get('number' if github else 'iid')) == str(mr['number']), 'forge response belongs to another MR')
    field = 'body' if github else 'description'
    text = response.get(field)
    if text is None:
        text = ''
    need(isinstance(text, str), 'invalid remote description')
    head = response.get('head', {}).get('sha') if github else response.get('sha')
    need(isinstance(head, str) and re.fullmatch(r'[0-9a-f]{7,64}', head), 'missing MR head SHA')
    raw_state = response.get('state')
    state = 'merged' if response.get('merged') is True else {'opened': 'open', 'open': 'open',
             'merged': 'merged', 'closed': 'closed'}.get(raw_state)
    need(state is not None, 'unknown remote MR state')
    return {'body': text, 'head': head, 'state': state}

def regions(body):
    found = {}
    for name in ('mr-summary', 'review-changes'):
        start = '<!-- pw-' + name + ':start -->'
        end = '<!-- pw-' + name + ':end -->'
        ns, ne = body.count(start), body.count(end)
        need((ns, ne) in ((0, 0), (1, 1)), 'description conflict: malformed/duplicate markers')
        if ns:
            begin = body.index(start)
            finish = body.index(end) + len(end)
            need(begin < finish - len(end), 'description conflict: reversed markers')
            # Markers are standalone, so literal marker text inside prose/code cannot adopt ownership.
            need((begin == 0 or body[begin - 1] == '\n') and body[begin + len(start):].startswith(('\n', '\r\n')),
                 'description conflict: inline marker')
            need(body[finish - len(end) - 1:finish - len(end)] == '\n', 'description conflict: inline end marker')
            need(finish == len(body) or body[finish:].startswith(('\n', '\r\n')), 'description conflict: inline end marker suffix')
            found[name] = (begin, finish, body[begin:finish])
    ordered = sorted(found.values())
    need(all(a[1] <= b[0] for a, b in zip(ordered, ordered[1:])), 'description conflict: nested markers')
    for marker in re.finditer(r'<!--\s*pw-(?:mr-summary|review-changes)', body):
        need(any(body.startswith(token, marker.start()) for token in (
             '<!-- pw-mr-summary:start -->', '<!-- pw-mr-summary:end -->',
             '<!-- pw-review-changes:start -->', '<!-- pw-review-changes:end -->')),
             'description conflict: malformed marker token')
    if 'mr-summary' in found:
        summary = found['mr-summary'][2]
        headings = re.findall(r'^## ([^\r\n]+)\r?$', summary, re.M)
        need(headings == ['What & why', 'High-level changes', 'Low-level changes', 'Verification', 'Notes for the reviewer'],
             'summary requires all five ordered sections, including reviewer notes')
    return found

def clean_lines(value, label):
    need(isinstance(value, list) and value and all(isinstance(line, str) and line.strip() for line in value),
         label + ' must be a nonempty string list')
    for line in value:
        need('\n' not in line and '\r' not in line and '\x00' not in line and '<!--' not in line,
             'unsafe marker/multiline input in ' + label)
        # The collapsible wrapper uses <details> as a structural delimiter; content that could
        # forge one (or a close tag) would make the stored presentation ambiguous on readback.
        need(not re.search(r'</?details', line), 'structural wrapper delimiters are not allowed in ' + label)
        need(not re.search(r'(?:#note_|discussion_r|/comments/)', line), 'comment references belong in local tracking, not the MR block')
    return value

def payload(value):
    need(isinstance(value, dict), 'checkpoint must be a JSON object')
    need(set(value) <= {'before', 'after', 'summary', 'commits', 'verification', 'head', 'summary_body', 'tasks', 'comments'},
         'unknown checkpoint field')
    for name in ('tasks', 'comments'):
        need(isinstance(value.get(name, []), list) and all(isinstance(item, str) and item and '\x00' not in item for item in value.get(name, [])),
             'invalid local ' + name + ' metadata')
    for field in ('before', 'after', 'summary'):
        clean_lines(value.get(field), field)
    need(isinstance(value.get('head'), str) and re.fullmatch(r'[0-9a-f]{7,64}', value['head']), 'checkpoint requires final published head')
    commits = value.get('commits')
    need(isinstance(commits, list), 'commits must be a list (empty for no commits)')
    seen = set()
    for commit in commits:
        need(isinstance(commit, dict) and set(commit) == {'sha', 'subject', 'published'}, 'invalid commit entry')
        need(isinstance(commit['sha'], str) and re.fullmatch(r'[0-9a-f]{7,64}', commit['sha']) and commit['sha'] not in seen,
             'invalid/duplicate commit SHA')
        clean_lines([commit['subject']], 'commit subject')
        need(isinstance(commit['published'], bool), 'commit publication flag must be boolean')
        seen.add(commit['sha'])
    verification = value.get('verification')
    need(isinstance(verification, list) and verification, 'verification must disclose actual results/skips')
    for check in verification:
        need(isinstance(check, dict) and set(check) == {'head', 'text'}, 'invalid verification entry')
        need(isinstance(check['head'], str) and re.fullmatch(r'[0-9a-f]{7,64}', check['head']), 'verification requires matching head')
        clean_lines([check['text']], 'verification')
    summary = value.get('summary_body')
    need(isinstance(summary, str), 'checkpoint requires current summary_body')
    section = regions(summary)
    need(set(section) == {'mr-summary'} and section['mr-summary'][2] == summary.strip(), 'summary_body must contain only its owned summary region')
    return value

def render(attempt):
    data = payload(attempt['checkpoint'])
    text = '### ' + attempt['timestamp'] + '\n<!-- pw-review-attempt:' + attempt['key'] + ' -->\n#### Changes\n'
    for field in ('before', 'after', 'summary'):
        text += '##### ' + field.title() + '\n' + ''.join('- ' + line + '\n' for line in data[field]) + '\n'
    text += '#### Commits\n'
    for commit in data['commits']:
        text += '- `' + commit['sha'] + '` - ' + commit['subject'] + ('' if commit['published'] else ' (local only; not pushed)') + '\n'
    if not data['commits']:
        text += '- None. Published head remains `' + data['head'] + '`.\n'
    text += '\n#### Verification\n'
    text += ''.join('- ' + check['text'] + ' (head `' + check['head'] + '`).\n' for check in data['verification'])
    return text + '\n'

# The wrapper is presentation-only: the attempt's persisted datetime is displayed with the
# date/time separator (legacy undashed instants gain it in the label), while the enclosed
# frozen block bytes never change. Escaping keeps the label safe as HTML text.
def display_timestamp(timestamp):
    match = re.fullmatch(r'([0-9]{1,2} [A-Za-z]+ [0-9]{4}) ([0-9]{2}\.[0-9]{2} WIB)', timestamp)
    if match:
        return match.group(1) + ' - ' + match.group(2)
    return timestamp

def wrapper_label(attempt):
    label = display_timestamp(attempt['timestamp'])
    return label.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def wrapped(attempt):
    return ('<details>\n<summary>Review attempt: ' + wrapper_label(attempt) + '</summary>\n\n'
            + attempt['block'] + '</details>\n\n')

def _entry_key(entry, block, state, message):
    markers = re.findall(r'<!-- pw-review-attempt:([0-9a-f]{32}) -->', block)
    need(len(markers) == 1, 'description conflict: duplicate/invalid attempt key')
    attempt = next((a for a in state['attempts'] if a['key'] == markers[0]), None)
    need(attempt and attempt['frozen'], 'description conflict: unknown or unfrozen attempt')
    need(block == attempt['block'], message)
    return markers[0], attempt

# Ordered attempt keys present in the file's ## Review changes region. Accepts BOTH the legacy
# unwrapped frozen blocks and the collapsible <details> wrappers during transition; each entry
# must match a stored frozen attempt byte-exactly, one attempt per wrapper, with the wrapper
# label equal to that attempt's displayed persisted datetime. Anything else — nested, duplicated,
# malformed, unknown, or externally edited — is a conflict rather than a guessed boundary.
def history_keys(region, state):
    if region is None:
        return []
    inner = region[2].split('-->', 1)[1].rsplit('<!--', 1)[0]
    need(inner.startswith('\n## Review changes\n'), 'description conflict: invalid history heading')
    inner = inner[len('\n## Review changes\n'):]
    if not inner.strip():
        return []
    keys = []
    while True:
        inner = inner.lstrip('\r\n')
        if not inner:
            return keys
        if inner.startswith('<details>'):
            end = inner.find('</details>')
            need(end != -1, 'description conflict: unbalanced details wrapper')
            entry = inner[:end + len('</details>')]
            inner = inner[end + len('</details>'):]
            wrapper = re.fullmatch(r'<details>\n<summary>Review attempt: ([^\r\n<]*)</summary>\n\n(.*)</details>',
                                   entry, re.S)
            need(wrapper is not None, 'description conflict: malformed details wrapper')
            label, block = wrapper.groups()
            key, attempt = _entry_key(entry, block, state, 'description conflict: frozen attempt was edited or is unknown')
            need(label == wrapper_label(attempt), 'description conflict: wrapper label does not match the attempt datetime')
            keys.append(key)
        elif inner.startswith('### '):
            nxt = inner.find('\n### ', 1)
            entry = inner if nxt == -1 else inner[:nxt + 1]
            inner = '' if nxt == -1 else inner[nxt + 1:]
            key, _attempt = _entry_key(entry, entry, state, 'description conflict: frozen attempt was edited or is unknown')
            keys.append(key)
        else:
            need(False, 'description conflict: unrecognized history content')

def compose(remote, state, selected, limit, unit):
    body = remote['body']
    spans = regions(body)
    existing = history_keys(spans.get('review-changes'), state)
    need(not (set(existing) & set(state['pruned'])), 'description conflict: pruned attempt resurrected')
    expected = {a['key'] for a in state['attempts'] if a['delivered'] and a['key'] not in state['pruned']}
    need(expected <= set(existing), 'description conflict: retained delivered history was removed')
    summary_pending = False
    candidate_summary = selected['checkpoint']['summary_body'].strip()
    summary_span = spans.get('mr-summary')
    if summary_span:
        observed = summary_span[2]
        approved = [state['last_summary']]
        if state.get('planned'):
            approved.append(state['planned']['summary'])
        need(observed in approved, 'description conflict: owned summary edited or ownership snapshot missing')
        if selected['checkpoint']['head'] == remote['head']:
            body = body[:summary_span[0]] + candidate_summary + body[summary_span[1]:]
        else:
            summary_pending = state.get('last_summary_head') != remote['head']
            candidate_summary = observed
    else:
        summary_pending = True
        candidate_summary = None
    # Remove only the owned history; all outside bytes survive as the prefix before the final region.
    spans = regions(body)
    history = spans.get('review-changes')
    outside = body[:history[0]] + body[history[1]:] if history else body
    keep = set(existing) | {selected['key']}
    keep -= set(state['pruned'])
    attempts = sorted((a for a in state['attempts'] if a['key'] in keep), key=lambda a: a['sequence'], reverse=True)
    pruned = []
    def build():
        return outside + ('' if outside.endswith('\n\n') or not outside else '\n' if outside.endswith('\n') else '\n\n') + \
               '<!-- pw-review-changes:start -->\n## Review changes\n' + ''.join(wrapped(a) for a in attempts) + '<!-- pw-review-changes:end -->'
    proposed = build()
    size = lambda text: len(text.encode('utf-8')) if unit == 'utf8' else len(text)
    while size(proposed) > limit and len(attempts) > 1:
        pruned.append(attempts.pop()['key'])
        proposed = build()
    need(size(proposed) <= limit, 'description capacity exceeded: newest block and protected text do not fit')
    return proposed, candidate_summary, pruned, summary_pending

def validate_state(state, mr):
    need(isinstance(state, dict) and type(state.get('version')) is int and state.get('version') == 1 and state.get('mr') == mr, 'malformed/mismatched history record')
    need(isinstance(state.get('attempts'), list) and isinstance(state.get('pruned'), list), 'malformed attempt archive')
    need(state.get('last_summary') is None or isinstance(state['last_summary'], str), 'malformed ownership snapshot')
    need(type(state.get('initial_pending', False)) is bool and (state.get('initial_body') is None or isinstance(state['initial_body'], str)),
         'malformed initial snapshot recovery')
    keys, sequences = set(), set()
    for attempt in state['attempts']:
        need(isinstance(attempt, dict) and re.fullmatch(r'[0-9a-f]{32}', attempt.get('key', '')), 'malformed attempt key')
        need(attempt['key'] not in keys and type(attempt.get('sequence')) is int and attempt['sequence'] > 0 and attempt['sequence'] not in sequences,
             'duplicate attempt identity/order')
        keys.add(attempt['key']); sequences.add(attempt['sequence'])
        need(isinstance(attempt.get('invocation'), str) and re.fullmatch(r'[A-Za-z0-9_-]{1,96}', attempt['invocation']), 'malformed invocation identity')
        filename = digest(json.dumps(mr, sort_keys=True))
        need(attempt['key'] == digest(attempt['invocation'] + '|' + filename)[:32], 'attempt key does not match invocation/MR identity')
        need(isinstance(attempt.get('timestamp'), str) and re.fullmatch(r'[0-9]{1,2} [A-Za-z]+ [0-9]{4}(?: -)? [0-9]{2}\.[0-9]{2} WIB', attempt['timestamp']),
             'malformed attempt timestamp')
        need(isinstance(attempt.get('before_head'), str) and re.fullmatch(r'[0-9a-f]{7,64}', attempt['before_head']) and isinstance(attempt.get('before_body'), str),
             'malformed before snapshot')
        need(type(attempt.get('frozen')) is bool and type(attempt.get('delivered')) is bool, 'malformed attempt state')
        need(not attempt['delivered'] or attempt['frozen'], 'unfrozen attempt cannot be acknowledged')
        if attempt.get('checkpoint') is not None:
            payload(attempt['checkpoint'])
        if attempt['frozen']:
            need(attempt.get('block') == render(attempt), 'malformed frozen block')
    need(all(key in keys for key in state['pruned']), 'malformed retention tombstone')
    planned = state.get('planned')
    if planned is not None:
        need(isinstance(planned, dict) and planned.get('attempt') in keys and isinstance(planned.get('head'), str)
             and re.fullmatch(r'[0-9a-f]{7,64}', planned['head']), 'malformed tentative delivery')
        need(isinstance(planned.get('history'), str) and isinstance(planned.get('pruned'), list)
             and all(key in keys for key in planned['pruned']) and type(planned.get('summary_pending')) is bool,
             'malformed tentative projection')
        need(planned.get('summary') is None or isinstance(planned['summary'], str), 'malformed tentative summary')
    return state

def run():
    project, timestamp, mappings, registered, *arguments = sys.argv[1:]
    parser = HistoryParser(prog='pw-ship history')
    parser.add_argument('operation', choices=['invocation', 'init', 'begin', 'checkpoint', 'freeze', 'deliver', 'pending'])
    parser.add_argument('url', nargs='?')
    parser.add_argument('--invocation')
    parser.add_argument('--attempt')
    parser.add_argument('--file')
    parser.add_argument('--reviewed', action='store_true')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--unit', choices=['utf8', 'chars'])
    parser.add_argument('--limit-source')
    args = parser.parse_args(arguments)
    need(not args.reviewed or args.operation == 'init', '--reviewed applies only to an explicitly owner-requested ownership repair')
    if args.operation == 'invocation':
        print(uuid.uuid4().hex)
        return
    root = safe_path(project, directory=True)
    directory = safe_path(root / '.ship-history', directory=True)
    if args.operation == 'pending':
        if directory.exists():
            for path in sorted(directory.glob('*.json')):
                state = read_json(path)
                mr = state.get('mr') if isinstance(state, dict) else None
                need(isinstance(mr, dict), 'malformed history identity')
                need(path.stem == digest(json.dumps(mr, sort_keys=True)), 'mismatched history filename')
                validate_state(state, mr)
                if state.get('initial_pending'):
                    print(json.dumps({'mr': mr, 'initial_snapshot_pending': True}, sort_keys=True))
                for attempt in state['attempts']:
                    if attempt['key'] not in state['pruned'] and (not attempt['delivered'] or attempt.get('summary_pending')):
                        print(json.dumps({'mr': mr, 'attempt': attempt['key'], 'frozen': attempt['frozen'],
                                          'description_delivered': attempt['delivered'], 'summary_pending': attempt.get('summary_pending', False)}, sort_keys=True))
        return
    mr = identity(args.url or '', mappings)
    directory.mkdir(mode=0o700, exist_ok=True)
    filename = digest(json.dumps(mr, sort_keys=True))
    path = directory / (filename + '.json')
    need(registered == 'yes' or path.exists(), 'MR URL is not registered in this project')
    locks = safe_path(root.parent / '.ship-history-locks', directory=True)
    locks.mkdir(mode=0o700, exist_ok=True)
    lock = locks / (filename + '.lock')
    safe_path(lock, directory=True)
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        raise HistoryError('history locked: retry after the writer exits; remove a stale lock only after confirming no writer is active')
    owner = uuid.uuid4().hex
    owner_path = lock / 'owner.json'
    try:
        atomic_json(owner_path, {'pid': os.getpid(), 'token': owner})
        state = validate_state(read_json(path), mr) if path.exists() else {
            'version': 1, 'mr': mr, 'attempts': [], 'last_summary': None, 'last_summary_head': None, 'pruned': [], 'planned': None}
        if args.operation == 'init':
            source = safe_path(args.file).read_bytes().decode('utf-8') if args.file else state.get('initial_body')
            need(isinstance(source, str) and 'mr-summary' in regions(source), 'init requires its marked creation body or retained initial payload')
            need(not state['attempts'] or args.reviewed, 'existing attempts require an explicitly owner-reviewed ownership repair')
            need(state['last_summary'] in (None, regions(source)['mr-summary'][2]) or args.reviewed, 'description conflict: initial summary changed')
            state['initial_body'] = source
            state['initial_pending'] = True
            atomic_json(path, state)
            remote = api(mr)
            need(remote['state'] == 'open', 'MR is closed/merged; no description write')
            need(remote['body'] == source, 'initial description readback differs from the creation file')
            spans = regions(remote['body'])
            need('mr-summary' in spans, 'initial ownership requires a marked summary')
            observed = spans['mr-summary'][2]
            history_keys(spans.get('review-changes'), state)
            if args.reviewed:
                expected = {a['key'] for a in state['attempts'] if a['delivered'] and a['key'] not in state['pruned']}
                need(expected <= set(history_keys(spans.get('review-changes'), state)), 'ownership repair cannot erase retained attempt history')
            state['last_summary'] = observed
            state['last_summary_head'] = remote['head']
            state['initial_pending'] = False
            if args.reviewed:
                for attempt in state['attempts']:
                    attempt['summary_pending'] = False
        elif args.operation == 'begin':
            need(not state.get('initial_pending'), 'initial ownership snapshot is pending; recover it before review work')
            need(args.invocation and re.fullmatch(r'[A-Za-z0-9_-]{1,96}', args.invocation), 'begin requires a persisted invocation ID')
            key = digest(args.invocation + '|' + filename)[:32]
            existing = next((a for a in state['attempts'] if a['key'] == key), None)
            if existing:
                print(json.dumps(existing, sort_keys=True))
                return
            need(not any(not a['frozen'] for a in state['attempts']), 'another invocation is active for this MR; resume it first')
            remote = api(mr)
            need(remote['state'] == 'open', 'MR is closed/merged; no new attempt')
            regions(remote['body'])
            need(re.fullmatch(r'[0-9]{1,2} [A-Za-z]+ [0-9]{4}(?: -)? [0-9]{2}\.[0-9]{2} WIB', timestamp), 'missing valid WIB event timestamp')
            existing = {'key': key, 'invocation': args.invocation, 'sequence': max([a['sequence'] for a in state['attempts']] or [0]) + 1,
                        'timestamp': timestamp, 'before_head': remote['head'], 'before_body': remote['body'],
                        'checkpoint': None, 'frozen': False, 'delivered': False, 'block': None}
            state['attempts'].append(existing)
        else:
            need(args.attempt and re.fullmatch(r'[0-9a-f]{32}', args.attempt), 'operation requires a recorded attempt key')
            selected = next((a for a in state['attempts'] if a['key'] == args.attempt), None)
            need(selected is not None, 'unknown attempt key')
            if args.operation == 'checkpoint':
                data = payload(read_json(args.file or ''))
                allowed_heads = {selected['before_head'], data['head']} | {commit['sha'] for commit in data['commits']}
                need(all(check['head'] in allowed_heads for check in data['verification']), 'verification head is unrelated to this attempt')
                need(not selected['frozen'] or data == selected['checkpoint'], 'frozen attempt cannot be changed')
                selected['checkpoint'] = data
            elif args.operation == 'freeze':
                need(selected['checkpoint'] is not None, 'freeze requires actual checkpoint evidence')
                selected['block'] = render(selected)
                selected['frozen'] = True
            elif args.operation == 'deliver':
                need(selected['frozen'], 'delivery requires a frozen attempt')
                if selected['key'] in state['pruned']:
                    print('attempt archived locally; pruned remote block will not be restored')
                    return
                need(args.limit and args.limit > 0 and args.unit and args.limit_source,
                     'delivery requires documented --limit, --unit and --limit-source; unknown capacity is not pruning permission')
                need(not state.get('planned') or state['planned'].get('attempt') == selected['key'],
                     'recover the outstanding description write before delivering another attempt')
                for retry in range(3):
                    remote = api(mr)
                    need(remote['state'] == 'open', 'MR is closed/merged; pending record retained without write')
                    planned = state.get('planned')
                    spans = regions(remote['body'])
                    if planned and remote['head'] == planned['head'] and spans.get('review-changes', (None, None, None))[2] == planned['history'] \
                            and spans.get('mr-summary', (None, None, None))[2] == planned['summary']:
                        state['pruned'] = list(dict.fromkeys(state['pruned'] + planned['pruned']))
                        state['last_summary'] = planned['summary']
                        state['last_summary_head'] = planned['head'] if not planned['summary_pending'] else state.get('last_summary_head')
                        selected['delivered'] = selected['key'] not in state['pruned']
                        selected['summary_pending'] = planned['summary_pending']
                        state['capacity'] = {name: planned[name] for name in ('limit', 'unit', 'source')}
                        state['planned'] = None
                        atomic_json(path, state)
                        print('attempt archived locally by retention' if not selected['delivered'] else 'remote success recovered; no duplicate description write')
                        return
                    proposed, summary, pruned, summary_pending = compose(remote, state, selected, args.limit, args.unit)
                    if proposed != remote['body']:
                        latest = api(mr)
                        if latest != remote:
                            continue
                        state['planned'] = {'attempt': selected['key'], 'head': remote['head'], 'summary': summary,
                                            'history': regions(proposed)['review-changes'][2], 'summary_pending': summary_pending,
                                            'body_digest': digest(proposed), 'pruned': pruned,
                                            'limit': args.limit, 'unit': args.unit, 'source': args.limit_source}
                        atomic_json(path, state)
                        api(mr, proposed)
                        landed = api(mr)
                        need(landed['body'] == proposed and landed['head'] == remote['head'],
                             'description update pending: readback differs or head advanced')
                    selected['summary_pending'] = summary_pending
                    state['last_summary'] = summary
                    if not summary_pending:
                        state['last_summary_head'] = remote['head']
                    state['pruned'] = list(dict.fromkeys(state['pruned'] + pruned))
                    selected['delivered'] = selected['key'] not in state['pruned']
                    state['capacity'] = {'limit': args.limit, 'unit': args.unit, 'source': args.limit_source}
                    state['planned'] = None
                    atomic_json(path, state)
                    print('attempt archived locally by retention' if not selected['delivered'] else
                          'history delivered; summary refresh pending' if summary_pending else 'description delivered and readback verified')
                    return
                raise HistoryError('description update pending: remote changed on every bounded retry')
        atomic_json(path, state)
        if args.operation == 'begin':
            print(json.dumps(existing, sort_keys=True))
        else:
            print(args.operation + ': recorded')
    finally:
        if owner_path.is_file() and not owner_path.is_symlink() and read_json(owner_path).get('token') == owner:
            owner_path.unlink()
            lock.rmdir()

try:
    run()
except (HistoryError, OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError, subprocess.SubprocessError) as error:
    print('pw-ship history: ' + str(error) + ' → fix: inspect the pending record/ownership or forge configuration, then retry safely', file=sys.stderr)
    sys.exit(2)
PY
}


# Request-review message generation — the read-only half of /pw-ship request-review. The shell
# resolves the project's candidate tasks, the effective frame file, and the effective generation
# prompt files; this helper queries each unique MR's forge metadata once (read-only, bounded
# timeout), applies the selection rules, reads + validates only the enabled prompts (when this
# run authors prose, never for a direct --prose supply), validates optional caller-supplied
# prose, and renders the recap plus one copyable message through the frame placeholders. Nothing
# here writes project state or performs forge writes.
# argv: <projectdir> <frame-file> <candidates-tsv> <all|explicit> <selector-ids> <to-names>
#       <summary:0|1> <mr-summary:0|1> <note:0|1> <no-reviewers:0|1> <prose-file|-> <mappings>
#       <summary-prompt-file|-> <note-prompt-file|-> <summary-prompt-source> <note-prompt-source>
pw_ship_request_review() {
  python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, unquote, urlsplit

class ReviewError(Exception):
    pass

def need(condition, message):
    if not condition:
        raise ReviewError(message)

# ---------------- forge identity + one-shot read-only queries ----------------

def identity(url, mappings):
    parsed = urlsplit(url)
    need(parsed.scheme in ('http', 'https') and not parsed.username and not parsed.password,
         'MR URL must be http(s) without credentials: ' + url)
    host = parsed.netloc.lower()
    need(re.fullmatch(r'[a-z0-9][a-z0-9.-]*(?::[0-9]+)?', host), 'invalid MR hostname in ' + url)
    path = unquote(parsed.path).rstrip('/')
    match = re.fullmatch(r'/(.+)/-/merge_requests/([1-9][0-9]*)', path)
    forge = 'gitlab'
    if not match:
        match = re.fullmatch(r'/([^/]+/[^/]+)/pull/([1-9][0-9]*)', path)
        forge = 'github'
    need(match is not None, 'unrecognized MR/PR URL: ' + url)
    repo, number = match.groups()
    need(all(re.fullmatch(r'[A-Za-z0-9_.-]+', part) and part not in ('.', '..') for part in repo.split('/')),
         'unsafe repository identity in ' + url)
    if forge == 'github':
        repo = repo.lower()
    known = (host, forge) in (('github.com', 'github'), ('gitlab.com', 'gitlab'))
    for mapping in mappings.splitlines():
        if '=' in mapping:
            configured_host, configured_forge = mapping.split('=', 1)
            if configured_host.lower() == host:
                need(configured_forge == forge, 'MR URL conflicts with the configured forge for ' + host)
                known = True
    need(known, 'MR host ' + host + ' has no matching configured forge registry entry')
    return {'forge': forge, 'host': host, 'repo': repo, 'number': int(number)}

def forge_get(mr, endpoint):
    binary = 'gh' if mr['forge'] == 'github' else 'glab'
    try:
        result = subprocess.run([binary, 'api', endpoint, '--hostname', mr['host']],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    except subprocess.SubprocessError:
        return None
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except ValueError:
        return None

def metadata(mr, want_description):
    if mr['forge'] == 'github':
        endpoint = 'repos/' + mr['repo'] + '/pulls/' + str(mr['number'])
    else:
        endpoint = 'projects/' + quote(mr['repo'], safe='') + '/merge_requests/' + str(mr['number'])
    data = forge_get(mr, endpoint)
    if not isinstance(data, dict):
        return None
    if mr['forge'] == 'github':
        raw_state = data.get('state')
        if data.get('merged') is True:
            state = 'merged'
        elif raw_state == 'open':
            state = 'open'
        elif raw_state == 'closed':
            state = 'closed'
        else:
            state = None
        base = data.get('base') if isinstance(data.get('base'), dict) else {}
        head_block = data.get('head') if isinstance(data.get('head'), dict) else {}
        target = base.get('ref')
        head = head_block.get('sha')
        raw_reviewers = data.get('requested_reviewers') or []
        reviewers = [r.get('login') for r in raw_reviewers if isinstance(r, dict) and r.get('login')]
        description = data.get('body')
    else:
        raw_state = data.get('state')
        if data.get('merged') is True or raw_state == 'merged':
            state = 'merged'
        elif raw_state in ('opened', 'open', ''):
            state = 'open'
        elif raw_state in ('closed', 'locked'):
            state = 'closed'
        else:
            state = None
        target = data.get('target_branch')
        head = data.get('sha')
        raw_reviewers = data.get('reviewers') or []
        reviewers = [r.get('name') or r.get('username') for r in raw_reviewers if isinstance(r, dict) and (r.get('name') or r.get('username'))]
        description = data.get('description')
    if state is None:
        return None
    raw_title = data.get('title')
    title = raw_title if isinstance(raw_title, str) else ''
    draft = bool(data.get('draft') or data.get('work_in_progress')) or title.lower().startswith(('draft:', 'wip:'))
    return {'title': title,
            'state': state,
            'draft': draft,
            'target': target if isinstance(target, str) else '',
            'head': head if isinstance(head, str) and re.fullmatch(r'[0-9a-f]{7,64}', head or '') else '',
            'reviewers': [r for r in reviewers if r],
            'description': description if isinstance(description, str) else ''}

CI_MAP = {'success': 'passed', 'failed': 'failed', 'canceled': 'canceled', 'cancelled': 'canceled',
          'skipped': 'skipped', 'running': 'running', 'created': 'pending', 'pending': 'pending',
          'manual': 'pending', 'scheduled': 'pending', 'preparing': 'pending',
          'waiting_for_resource': 'pending'}

def build_status(mr, head):
    if not head:
        return 'unavailable'
    if mr['forge'] == 'github':
        data = forge_get(mr, 'repos/' + mr['repo'] + '/commits/' + head + '/check-runs')
        runs = data.get('check_runs') if isinstance(data, dict) else None
        if not isinstance(runs, list) or not runs:
            return 'unavailable'
        if any(not isinstance(r, dict) or r.get('status') != 'completed' for r in runs):
            running = any(isinstance(r, dict) and r.get('status') == 'in_progress' for r in runs)
            return 'running' if running else 'pending'
        conclusions = [r.get('conclusion') or '' for r in runs if isinstance(r, dict)]
        if any(c in ('failure', 'timed_out', 'action_required', 'startup_failure') for c in conclusions):
            return 'failed'
        if any(c == 'cancelled' for c in conclusions):
            return 'canceled'
        if any(c == 'success' for c in conclusions):
            return 'passed'
        if any(c in ('skipped', 'neutral') for c in conclusions):
            return 'skipped'
        return 'unknown'
    endpoint = ('projects/' + quote(mr['repo'], safe='') + '/merge_requests/'
                + str(mr['number']) + '/pipelines')
    data = forge_get(mr, endpoint)
    if not isinstance(data, list):
        return 'unavailable'
    statuses = [p.get('status') for p in data if isinstance(p, dict) and p.get('sha') == head and p.get('status')]
    if not statuses:
        return 'unavailable'
    chosen = next((s for s in statuses if s != 'skipped'), 'skipped')
    return CI_MAP.get(chosen, 'unknown')

# ---------------- optional AI prose validation --------------------------------

def sentences(text):
    return [part for part in re.split(r'(?<=[.!?])\s+', text.strip()) if part]

def word_count(text):
    return len(text.split())

def single_line(text, label):
    need('\n' not in text and '\r' not in text, label + ' must be a single line')
    return text.strip()

def validate_prose(path, selected_urls, want):
    resolved = os.path.abspath(path)
    need(not os.path.islink(resolved) and os.path.isfile(resolved),
         'prose file must be a plain existing file: ' + resolved)
    try:
        data = json.loads(Path(resolved).read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise ReviewError('prose file is not valid JSON (' + str(error) + ')')
    need(isinstance(data, dict), 'prose file must contain a JSON object')
    fields = {'summary', 'mr_summaries', 'note', 'omit'}
    need(set(data) <= fields, 'unknown prose field(s): ' + ', '.join(sorted(set(data) - fields)))
    omit = data.get('omit', [])
    need(isinstance(omit, list) and all(o in ('summary', 'mr_summary', 'note') for o in omit),
         "omit must list 'summary', 'mr_summary' and/or 'note'")
    result = {'summary': '', 'mr_summaries': {}, 'note': [], 'omitted': []}
    if want['summary']:
        if 'summary' in omit:
            result['omitted'].append('summary')
        else:
            text = data.get('summary')
            need(isinstance(text, str) and text.strip(), 'enabled --summary needs a nonempty "summary" string')
            text = single_line(text, 'summary')
            need(len(sentences(text)) <= 2 and word_count(text) <= 50,
                 'summary exceeds its limit (2 sentences and 50 words max)')
            result['summary'] = text
    if want['mr_summary']:
        if 'mr_summary' in omit:
            result['omitted'].append('mr_summary')
        else:
            table = data.get('mr_summaries')
            need(isinstance(table, dict), 'enabled --mr-summary needs an "mr_summaries" object keyed by MR URL')
            need(set(table) == set(selected_urls),
                 'mr_summaries keys must be exactly the selected MR URLs (got: '
                 + ', '.join(sorted(table)) + ')')
            for url in selected_urls:
                text = table[url]
                need(isinstance(text, str) and text.strip(), 'missing summary for ' + url)
                text = single_line(text, 'summary for ' + url)
                need(len(sentences(text)) <= 2 and word_count(text) <= 35,
                     'summary for ' + url + ' exceeds its limit (2 sentences and 35 words max)')
                result['mr_summaries'][url] = text
    if want['note']:
        if 'note' in omit:
            result['omitted'].append('note')
        else:
            bullets = data.get('note')
            need(isinstance(bullets, list) and bullets, 'enabled --note needs a nonempty "note" bullet list')
            need(len(bullets) <= 3, 'note allows at most 3 bullets')
            cleaned = []
            total = 0
            for bullet in bullets:
                need(isinstance(bullet, str) and bullet.strip(), 'note bullets must be nonempty strings')
                bullet = single_line(bullet, 'note bullet')
                total += word_count(bullet)
                cleaned.append(bullet)
            need(total <= 60, 'note exceeds its limit (60 words max)')
            result['note'] = cleaned
    return result

# ---------------- rendering ---------------------------------------------------

TOKENS = ('{{TO_BLOCK}}', '{{SUMMARY_BLOCK}}', '{{MR_BLOCKS}}', '{{NOTE_BLOCK}}', '{{PROJECT}}')

def render_frame(text, values):
    for token in TOKENS[:4]:
        need(text.count(token) == 1, 'frame must contain ' + token + ' exactly once')
    need(text.count('{{PROJECT}}') <= 1, 'frame may use {{PROJECT}} at most once')
    found = re.findall(r'\{\{[A-Za-z0-9_]+\}\}', text)
    unknown = sorted(set(found) - set(TOKENS))
    need(not unknown, 'unknown frame placeholder(s): ' + ', '.join(unknown))
    need(text.count('{{') == len(found) and text.count('}}') == len(found),
         'malformed {{…}} placeholder syntax in the frame')
    sentinel = '\x00'
    pattern = re.compile(r'\{\{(?:TO_BLOCK|SUMMARY_BLOCK|MR_BLOCKS|NOTE_BLOCK|PROJECT)\}\}')

    def replace(match):
        value = values[match.group(0)[2:-2]]
        return value if value else sentinel

    substituted = pattern.sub(replace, text)
    lines = []
    for line in substituted.split('\n'):
        if sentinel in line and line.strip(' \t\r' + sentinel) == '':
            continue
        lines.append(line.replace(sentinel, ''))
    collapsed = []
    for line in lines:
        if line.strip() == '' and collapsed and collapsed[-1].strip() == '':
            continue
        collapsed.append(line)
    return '\n'.join(collapsed).strip('\n') + '\n'

def order_entries(entries):
    by_task = {}
    for entry in entries:
        for task in entry['tasks']:
            by_task[task] = entry

    def depth(entry, trail):
        parent = by_task.get(entry['stack_parent'])
        if parent is None or parent is entry or id(parent) in trail:
            return 0
        return 1 + depth(parent, trail | {id(entry)})

    group_order = {}
    ordered = sorted(entries, key=lambda e: e['order'])
    for entry in ordered:
        unit = entry['landing_unit']
        if unit:
            group = 'lu:' + unit
        else:
            root = entry
            trail = {id(entry)}
            while True:
                parent = by_task.get(root['stack_parent'])
                if parent is None or parent is root or id(parent) in trail:
                    break
                root = parent
                trail.add(id(root))
            group = ('chain:' + root['tasks'][0]) if root is not entry else ('task:' + entry['tasks'][0])
        entry['_group'] = group
        if group not in group_order:
            group_order[group] = len(group_order)
    return sorted(entries, key=lambda e: (group_order.get(e['_group'], 0), depth(e, frozenset()), e['order']))

def fence_for(text):
    longest = max((len(m.group(0)) for m in re.finditer(r'`+', text)), default=0)
    return '`' * max(3, longest + 1)

def task_result_excerpt(project, task, limit=800):
    path = os.path.join(project, 'task', task + '.md')
    try:
        text = Path(path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return '(unavailable)'
    match = re.search(r'^## Result\s*$([\s\S]*?)(?=^## |\Z)', text, re.M)
    if not match:
        return '(no Result section)'
    excerpt = match.group(1).strip().replace('\r', '')
    if not excerpt:
        return '(empty Result section)'
    return excerpt[:limit] + ('…' if len(excerpt) > limit else '')

def recap(slug, entries, excluded):
    tasks_selected = sum(len(e['tasks']) for e in entries)
    lines = ['request-review ' + slug + ': ' + str(len(entries)) + ' unique open MR(s) for ' + str(tasks_selected) + ' task(s)',
             'selection recap:']
    for entry in entries:
        extra = ''
        if len(entry['tasks']) > 1:
            extra += '; also ' + ', '.join(entry['tasks'][1:])
        if entry['draft']:
            extra += '; draft'
        lines.append('  include ' + entry['tasks'][0] + ' -> ' + entry['url'] + ' (' + entry['state'] + extra + ')')
    for task, reason in excluded:
        lines.append('  exclude ' + task + ': ' + reason)
    if not entries and not excluded:
        lines.append('  (no tasks with recorded MRs)')
    return '\n'.join(lines)

# ---------------- generation prompts + supplementary evidence -----------------

PROMPT_MAX_BYTES = 16384
PER_MR_EVIDENCE_BUDGET = 12000
AGGREGATE_EVIDENCE_BUDGET = 48000

def read_prompt(path, kind):
    # File-health validation only (mirrors pw_review_prompt_error): presence, regular readable
    # file, nonempty, UTF-8, <= 16 KiB. Custom instructions are never judged semantically.
    if not path or path == '-':
        return None, 'prompt path is empty'
    if not os.path.isfile(path):
        return None, 'file not found: ' + path
    if not os.access(path, os.R_OK):
        return None, 'not readable: ' + path
    try:
        raw = Path(path).read_bytes()
    except OSError as error:
        return None, 'not readable (' + str(error) + '): ' + path
    if not raw.strip():
        return None, 'file is empty: ' + path
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        return None, 'not valid UTF-8 text: ' + path
    if len(raw) > PROMPT_MAX_BYTES:
        return None, ('file exceeds the ' + str(PROMPT_MAX_BYTES) + '-byte prompt limit ('
                      + str(len(raw)) + ' bytes): ' + path)
    return text, None

def diff_excerpt(ident, base, head):
    # Bounded read-only diff of the MR's own delta (target...head — for a stacked MR the target
    # is the parent branch, so inherited parent changes never enter the excerpt). Only consulted
    # when the description cannot explain the change; a failed read is a limitation, not a stop.
    if ident['forge'] == 'github':
        endpoint = 'repos/' + ident['repo'] + '/compare/' + quote(base, safe='') + '...' + head
    else:
        endpoint = ('projects/' + quote(ident['repo'], safe='') + '/repository/compare?from='
                    + quote(base, safe='') + '&to=' + quote(head, safe=''))
    data = forge_get(ident, endpoint)
    if not isinstance(data, dict):
        return None
    files = []
    if ident['forge'] == 'github':
        raw = data.get('files')
        if not isinstance(raw, list) or not raw:
            return None
        for item in raw[:12]:
            if not isinstance(item, dict) or not isinstance(item.get('filename'), str):
                continue
            name = item['filename']
            status = item.get('status') or ''
            additions = item.get('additions')
            deletions = item.get('deletions')
            patch = item.get('patch') if isinstance(item.get('patch'), str) else ''
            files.append((name, status, additions, deletions, '\n'.join(patch.splitlines()[:14])))
    else:
        raw = data.get('diffs')
        if not isinstance(raw, list) or not raw:
            return None
        for item in raw[:12]:
            if not isinstance(item, dict):
                continue
            name = item.get('new_path') or item.get('old_path')
            if not isinstance(name, str):
                continue
            if item.get('new_file'):
                status = 'new'
            elif item.get('deleted_file'):
                status = 'deleted'
            elif item.get('renamed_file'):
                status = 'renamed'
            else:
                status = 'modified'
            patch = item.get('diff') if isinstance(item.get('diff'), str) else ''
            files.append((name, status, None, None, '\n'.join(patch.splitlines()[:14])))
    if not files:
        return None
    lines = ['diff excerpt (target -> head, truncated):']
    for name, status, additions, deletions, patch in files:
        label = name + (' (' + status + ')' if status and status != 'modified' else '')
        if additions is not None:
            label += ' +' + str(additions) + '/-' + str(deletions)
        lines.append('--- ' + label)
        if patch:
            lines.append(patch)
    return '\n'.join(lines)

def build_message(slug, tonames, entries, prose, no_reviewers):
    counts = {}
    for entry in entries:
        counts[entry['title']] = counts.get(entry['title'], 0) + 1
    mr_lines = []
    for entry in entries:
        title = entry['title']
        if counts[title] > 1:
            title += ' (' + entry['repo'] + ')'
        lines = ['- ' + title,
                 '  - Link : ' + entry['url'],
                 '  - Branch Target : ' + (entry['target'] or 'unavailable'),
                 '  - CI Status : ' + entry['ci']]
        if entry['reviewers'] and not no_reviewers:
            lines.append('  - Assigned Reviewer : ' + ', '.join(entry['reviewers']))
        if prose['mr_summaries'].get(entry['url']):
            lines.append('  - Summary : ' + prose['mr_summaries'][entry['url']])
        if entry['draft']:
            lines.append('  - Draft : early feedback requested')
        if entry['landing_unit']:
            lines.append('  - Landing unit : ' + entry['landing_unit'])
        if entry['stack_parent']:
            lines.append('  - Stacked on : ' + entry['stacked_on'])
        mr_lines.append('\n'.join(lines))
    values = {'TO_BLOCK': 'Hi ' + (tonames or 'team') + ',',
              'SUMMARY_BLOCK': ('**Summary:** ' + prose['summary']) if prose['summary'] else '',
              'MR_BLOCKS': '\n'.join(mr_lines),
              'NOTE_BLOCK': ('**Review hints:**\n' + '\n'.join('- ' + b for b in prose['note'])) if prose['note'] else '',
              'PROJECT': slug}
    return values

def evidence_packet(project, entries):
    # Supplementary evidence for the prose pass: current MR descriptions (any prose flag,
    # including note-only), task-result excerpts, and — only when the description cannot
    # explain the change and the MR records a target and head — a bounded diff of that MR's
    # own delta. Budgets: 12,000 characters per MR (description + excerpts + diff, in that
    # order) and 48,000 characters aggregate; identity/head lines always survive and every
    # trim is labeled. A truncated or unavailable description is a limitation, never proof
    # that no relevant detail exists.
    chunks = []
    for entry in entries:
        head_lines = ['MR: ' + entry['url'],
                      'title: ' + entry['title'],
                      'head: ' + (entry['head'] or 'unavailable'),
                      'state=' + entry['state'] + (' | draft' if entry['draft'] else '')]
        parts = []
        description = entry['description'].strip().replace('\r', '')
        parts.append('description (truncated):')
        if description:
            shown = description[:2000] + ('…' if len(description) > 2000 else '')
        else:
            shown = '(unavailable)'
        parts.append(shown)
        for task in entry['tasks']:
            parts.append('task ' + task + ' result: ' + task_result_excerpt(project, task))
        if not description and entry['target'] and entry['head']:
            excerpt = diff_excerpt(entry['_ident'], entry['target'], entry['head'])
            if excerpt:
                parts.append(excerpt)
        assembled = []
        used = 0
        budget_hit = False
        for part in parts:
            if used + len(part) > PER_MR_EVIDENCE_BUDGET:
                remaining = PER_MR_EVIDENCE_BUDGET - used
                if remaining > 40:
                    assembled.append(part[:remaining] + '…(per-MR evidence budget reached)')
                budget_hit = True
                break
            assembled.append(part)
            used += len(part)
        if budget_hit:
            assembled.append('(per-MR supplementary evidence budget reached; remaining sources truncated)')
        chunks.append('\n'.join(head_lines + assembled))
    kept = []
    total = 0
    aggregate_hit = False
    for chunk in chunks:
        if total + len(chunk) > AGGREGATE_EVIDENCE_BUDGET:
            remaining = AGGREGATE_EVIDENCE_BUDGET - total
            if remaining > 80:
                kept.append(chunk[:remaining] + '\n(aggregate evidence budget reached)')
            aggregate_hit = True
            break
        kept.append(chunk)
        total += len(chunk)
    lines = ['----- pw-review-evidence (for the optional prose pass; NOT part of the message) -----']
    lines.extend(kept)
    if aggregate_hit:
        lines.append('(aggregate evidence budget reached; remaining MRs truncated)')
    lines.append('----- end pw-review-evidence -----')
    return '\n'.join(lines)

def run():
    argv = sys.argv[1:]
    need(len(argv) == 16, 'internal usage: request-review helper needs 16 arguments')
    (project, frame_path, candidates_path, mode, ids, tonames, summary_flag, mr_summary_flag,
     note_flag, no_reviewers, prose_path, mappings, summary_prompt, note_prompt,
     summary_prompt_source, note_prompt_source) = argv
    project = os.path.abspath(project)
    want = {'summary': summary_flag == '1', 'mr_summary': mr_summary_flag == '1', 'note': note_flag == '1'}
    ai_requested = any(want.values())
    no_reviewers = no_reviewers == '1'

    # Frame read (validated once per invocation; the shell already checked it, re-check here
    # so a direct helper call cannot render a half-broken frame).
    try:
        frame_text = Path(frame_path).read_text(encoding='utf-8')
    except OSError as error:
        raise ReviewError('frame file is not readable (' + str(error) + ')')
    need(frame_text.strip(), 'frame file is empty: ' + frame_path)
    render_frame(frame_text, {token[2:-2]: 'x' for token in TOKENS})  # structural validation pass

    # Candidate rows from the shell (PLAN order): task, url, conflict, title, landing_unit,
    # stack_parent, parent_url, parent_branch.
    columns = ('task', 'url', 'conflict', 'title', 'landing_unit', 'stack_parent', 'parent_url', 'parent_branch')
    rows = []
    try:
        raw = Path(candidates_path).read_text(encoding='utf-8')
    except OSError as error:
        raise ReviewError('candidate list is not readable (' + str(error) + ')')
    for line in raw.splitlines():
        if not line.strip():
            continue
        fields = line.split('\t')
        need(len(fields) == len(columns), 'malformed candidate record')
        rows.append(dict(zip(columns, fields)))

    if mode == 'explicit':
        wanted = ids.split()
        need(wanted, 'explicit selection needs at least one task id')
        by_task = {row['task']: row for row in rows}
        selected = []
        seen = set()
        for task in wanted:
            row = by_task.get(task)
            need(row is not None, 'task ' + task + ' does not exist in this project plan → fix: check the task id (/pw-status shows the plan)')
            need(not row['conflict'], 'recorded MR links conflict for ' + task
                 + ' (task Result and dashboard disagree) → fix: correct the task Result or the dashboard row')
            need(row['url'], 'task ' + task + ' has no recorded MR → fix: remove it from the selection or ship it first (/pw-ship)')
            if task not in seen:
                seen.add(task)
                selected.append(row)
    elif mode == 'all':
        conflicts = [row['task'] for row in rows if row['conflict']]
        need(not conflicts, 'recorded MR links conflict for: ' + ', '.join(conflicts)
             + ' → fix: correct the task Result or the dashboard row, then re-run')
        selected = [row for row in rows if row['url']]
    else:
        need(False, 'internal usage: unknown selection mode')

    excluded = []
    if mode == 'all':
        for row in rows:
            if not row['url']:
                excluded.append((row['task'], 'no recorded MR'))
    else:
        # Nothing to exclude pre-metadata in explicit mode: a selected task without an MR has
        # already stopped the run above.
        pass

    # Query each unique MR once; several tasks sharing one MR emit one entry.
    failures = []
    seen_ids = set()
    entries = []
    for row in selected:
        ident = identity(row['url'], mappings)
        key = ident['forge'] + '|' + ident['host'] + '|' + ident['repo'] + '|' + str(ident['number'])
        if key in seen_ids:
            next(e for e in entries if e['_key'] == key)['tasks'].append(row['task'])
            continue
        meta = metadata(ident, ai_requested)
        if meta is None:
            failures.append(row['task'] + ' (' + row['url'] + ')')
            continue
        seen_ids.add(key)
        entry = {'_key': key, '_ident': ident, 'url': row['url'], 'repo': ident['repo'], 'tasks': [row['task']],
                 'order': len(entries), 'landing_unit': row['landing_unit'],
                 'stack_parent': row['stack_parent'], 'title': meta['title'] or row['title'],
                 'state': meta['state'], 'draft': meta['draft'], 'target': meta['target'],
                 'head': meta['head'], 'reviewers': meta['reviewers'],
                 'description': meta['description']}
        if row['stack_parent']:
            if row['parent_url'].startswith('http'):
                entry['stacked_on'] = row['parent_url']
            elif row['parent_branch']:
                entry['stacked_on'] = 'branch ' + row['parent_branch']
            else:
                entry['stacked_on'] = 'not recorded'
        entries.append(entry)
    need(not failures, 'MR lookup failed for: ' + '; '.join(failures)
         + ' → fix: check the forge CLI authentication/host configuration and re-run')

    included = []
    for entry in entries:
        if entry['state'] in ('merged', 'closed'):
            if mode == 'explicit':
                need(False, 'task(s) ' + ', '.join(entry['tasks']) + ': MR ' + entry['url'] + ' is '
                     + entry['state'] + ' → fix: remove the task(s) from the selection')
            for task in entry['tasks']:
                excluded.append((task, 'MR ' + entry['state']))
            continue
        included.append(entry)
    entries = included

    # Stable order: landing-unit groups and stack chains (parent-first) in first-seen order.
    entries = order_entries(entries)
    for entry in entries:
        entry['ci'] = build_status(entry['_ident'], entry['head'])

    # Optional prose: validate before anything is rendered into the message. A direct --prose
    # supply triggers no prompt reads; the generation pass reads only the enabled prompts, once
    # each, and treats an invalid prompt as an omission of its affected sections with a
    # diagnostic outside the copyable message (the deterministic message always survives).
    prose = {'summary': '', 'mr_summaries': {}, 'note': [], 'omitted': []}
    prose_note = ''
    generation = ''
    heads_line = 'observed heads: ' + '; '.join(
        e['url'] + ' ' + (e['head'] or 'unavailable') for e in entries)
    if ai_requested:
        if prose_path and prose_path != '-':
            prose = validate_prose(prose_path, [entry['url'] for entry in entries], want)
            included_sections = [s for s in ('summary', 'mr_summary', 'note') if want[s] and s not in prose['omitted']]
            if included_sections:
                prose_note = 'prose included: ' + ', '.join(included_sections)
            if prose['omitted']:
                prose_note += ('\n' if prose_note else '') + 'prose omitted by the prose pass: ' + ', '.join(prose['omitted'])
            prose_note += ('\n' if prose_note else '') + heads_line
        else:
            prompt_texts = {}
            failures = []
            if want['summary'] or want['mr_summary']:
                text, err = read_prompt(summary_prompt, 'summary')
                if err:
                    for section in ('summary', 'mr_summary'):
                        if want[section]:
                            failures.append((section, 'summary', summary_prompt, summary_prompt_source, err))
                else:
                    prompt_texts['summary'] = (summary_prompt, summary_prompt_source, text)
            if want['note']:
                text, err = read_prompt(note_prompt, 'note')
                if err:
                    failures.append(('note', 'note', note_prompt, note_prompt_source, err))
                else:
                    prompt_texts['note'] = (note_prompt, note_prompt_source, text)
            for section, kind, path, source, err in failures:
                if source == 'default' and err.startswith('file not found'):
                    fix = 'run /pw-doctor --fix (seeds the missing default ' + kind + ' prompt)'
                else:
                    fix = 'create the file or correct the setting in pw.config.sh'
                prose_note += ((prose_note and prose_note + '\n') or '') + 'prose section ' + section \
                    + ' omitted: ' + kind + ' prompt ' + err + ' (' + path + ', ' + source + ') → fix: ' + fix
                prose['omitted'].append(section)
            pending = [s for s in ('summary', 'mr_summary', 'note') if want[s] and s not in prose['omitted']]
            if pending:
                requested = ', '.join(pending)
                prose_note += ((prose_note and prose_note + '\n') or '') \
                    + ('prose requested but not supplied: ' + requested + '\n'
                       'limits: summary <= 2 sentences/50 words; mr_summary <= 2 sentences/35 words per MR; note <= 3 bullets/60 words total\n'
                       '→ next: author the requested sections from the evidence packet and prompt below, write JSON '
                       '{"summary": "...", "mr_summaries": {"<MR url>": "..."}, "note": ["..."]}, and re-run with --prose <file>; '
                       'declare a section omitted with "omit": ["..."] only after one failed shortening pass')
                context = []
                if 'summary' in prompt_texts:
                    path, source, text = prompt_texts['summary']
                    context.append('----- pw-generation-prompt: summary (path: ' + path + '; source: ' + source + ') -----')
                    context.append(text.rstrip('\n'))
                    context.append('----- end pw-generation-prompt -----')
                if 'note' in prompt_texts:
                    path, source, text = prompt_texts['note']
                    context.append('----- pw-generation-prompt: note (path: ' + path + '; source: ' + source + ') -----')
                    context.append(text.rstrip('\n'))
                    context.append('----- end pw-generation-prompt -----')
                generation = '\n'.join(context)

    print(recap(project.rsplit('/', 1)[-1], entries, excluded))
    if not entries:
        print()
        print('no open MRs remain in the selection — no review request generated')
        return
    values = build_message(project.rsplit('/', 1)[-1], tonames, entries, prose, no_reviewers)
    message = render_frame(frame_text, values)
    fence = fence_for(message)
    print()
    print('copyable message:')
    print(fence + 'markdown')
    sys.stdout.write(message if message.endswith('\n') else message + '\n')
    print(fence)
    if prose_note:
        print()
        print(prose_note)
    if ai_requested and (not prose_path or prose_path == '-'):
        if generation:
            print()
            print(evidence_packet(project, entries))
            print()
            print(generation)
        print()
        print(heads_line)

try:
    run()
except ReviewError as error:
    message = str(error)
    if '→ fix:' not in message:
        message += ' → fix: re-run after correcting the reported selection, frame, or prose input'
    print('pw-ship request-review: ' + message, file=sys.stderr)
    sys.exit(2)
except (OSError, ValueError, TypeError, KeyError) as error:
    print('pw-ship request-review: ' + str(error)
          + ' → fix: inspect the selection/evidence and re-run', file=sys.stderr)
    sys.exit(2)
PY
}
