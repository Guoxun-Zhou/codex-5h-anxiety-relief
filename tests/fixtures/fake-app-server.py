import json
import sys

for line in sys.stdin:
    message = json.loads(line)
    method = message.get('method')
    if method == 'initialized':
        continue
    print(json.dumps({'method': 'test/notification', 'params': {}}), flush=True)
    if method == 'initialize':
        result = {'userAgent': 'fake'}
    elif method == 'account/read':
        result = {'account': {'type': 'chatgpt', 'email': 'fixture@example.invalid'}}
    elif method == 'account/rateLimits/read':
        result = {'rateLimitsByLimitId': {
            'other': {'primary': {'usedPercent': 0, 'windowDurationMins': 60}},
            'codex': {'primary': {'usedPercent': 0, 'windowDurationMins': 300, 'resetsAt': 20000},
                      'secondary': {'usedPercent': 20}}
        }}
    else:
        raise RuntimeError('Unexpected method')
    print(json.dumps({'id': message['id'], 'result': result}), flush=True)
