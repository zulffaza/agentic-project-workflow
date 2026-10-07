"""Strict persisted forge API fixture, enabled only by PWTEST_HISTORY_FORGE_DIR."""
import hashlib
import json
import os
from pathlib import Path
import sys

try:
    forge, *args = sys.argv[1:]
    if args[:2] == ['mr' if forge == 'glab' else 'pr', 'create']:
        root = Path(os.environ['PWTEST_HISTORY_FORGE_DIR'])
        candidates = [(p, json.loads(p.read_text())) for p in root.glob('*.json')]
        candidates = [(p, item) for p, item in candidates if item.get('creation_url')]
        if len(candidates) != 1:
            raise ValueError('expected one configured creation target')
        path, state = candidates[0]
        field, option = ('description', '--description') if forge == 'glab' else ('body', '--body')
        state['response'][field] = args[args.index(option) + 1]
        state['creates'] = state.get('creates', 0) + 1
        path.write_text(json.dumps(state, ensure_ascii=False))
        if forge == 'glab':
            print(json.dumps(dict(state['response'], web_url=state['creation_url']), separators=(',', ':')))
        else:
            print(state['creation_url'])
        sys.exit(0)
    if len(args) not in (4, 8) or args[0] != 'api' or args[2] != '--hostname':
        raise ValueError('unexpected arguments')
    endpoint, host = args[1], args[3]
    writing = len(args) == 8
    if writing and args[4:] != ['--method', 'PUT' if forge == 'glab' else 'PATCH', '--input', '-']:
        raise ValueError('unexpected write arguments')
    root = Path(os.environ['PWTEST_HISTORY_FORGE_DIR'])
    key = hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest()
    path = root / (key + '.json')
    state = json.loads(path.read_text())
    state['reads'] = state.get('reads', 0) + (not writing)
    mode = state.get('mode')
    if (mode == 'fetch-fail' and not writing) or (mode == 'write-fail' and writing):
        raise ValueError('injected request failure')
    field = 'description' if forge == 'glab' else 'body'
    state['response'].setdefault('iid' if forge == 'glab' else 'number', int(endpoint.rsplit('/', 1)[1]))
    if not writing and state.get('race_at') == state['reads']:
        state['response'][field] += state.get('race_text', '\nReviewer added a checklist.\n')
    if not writing and mode == 'always-race':
        state['response'][field] += '\nReviewer edit ' + str(state['reads']) + '\n'
    if writing:
        payload = json.load(sys.stdin)
        if set(payload) != {field} or not isinstance(payload[field], str):
            raise ValueError('unexpected payload')
        state['writes'] = state.get('writes', 0) + 1
        if mode != 'write-noop':
            state['response'][field] = payload[field]
        if mode == 'head-change-on-write':
            if forge == 'glab': state['response']['sha'] = 'f666666'
            else: state['response']['head']['sha'] = 'f666666'
            state['mode'] = None
        if mode == 'success-before-error':
            state['mode'] = None
            path.write_text(json.dumps(state, ensure_ascii=False))
            raise ValueError('injected crash after remote success')
    path.write_text(json.dumps(state, ensure_ascii=False))
    print(json.dumps(state['response'], ensure_ascii=False))
except (ValueError, OSError, KeyError) as error:
    print('history-shim: ' + str(error), file=sys.stderr)
    sys.exit(42)
