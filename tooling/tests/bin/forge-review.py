"""Strict request-review forge API fixture, enabled only by PWTEST_REVIEW_FORGE_DIR.

Serves one JSON response per (forge, host, endpoint) key and appends every call to
calls.log (method, host, endpoint). Any write method fails loudly: request-review is a
read-only generator, and a write reaching this shim is a contract violation.
"""
import hashlib
import json
import os
from pathlib import Path
import sys

try:
    forge, *args = sys.argv[1:]
    if not args or args[0] != 'api':
        raise ValueError('unexpected invocation')
    endpoint = args[1] if len(args) > 1 else ''
    host = args[args.index('--hostname') + 1] if '--hostname' in args else ''
    method = args[args.index('--method') + 1] if '--method' in args else 'GET'
    root = Path(os.environ['PWTEST_REVIEW_FORGE_DIR'])
    with (root / 'calls.log').open('a', encoding='utf-8') as stream:
        stream.write(method + '\t' + host + '\t' + endpoint + '\n')
    if method != 'GET':
        raise ValueError('request-review must not perform forge writes')
    key = hashlib.sha256((forge + '|' + host + '|' + endpoint).encode()).hexdigest()
    path = root / (key + '.json')
    if not path.is_file():
        raise ValueError('unknown review endpoint: ' + endpoint)
    state = json.loads(path.read_text(encoding='utf-8'))
    if state.get('fail'):
        raise ValueError('injected endpoint failure: ' + endpoint)
    print(json.dumps(state['response'], ensure_ascii=False))
except (ValueError, OSError, KeyError) as error:
    print('review-shim: ' + str(error), file=sys.stderr)
    sys.exit(42)
