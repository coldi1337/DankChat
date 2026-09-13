import json
import sys
for line in sys.stdin:
    request = json.loads(line)
    result = {'ok': True, 'requestId': request['requestId']}
    provider = request.get('provider', '')
    action = request.get('action')
    if action == 'status':
        result.update(authorized=True, authState='authorized')
    elif action == 'chats':
        result['chats'] = [dict(key=provider + str(i), id=str(i), provider=provider, account='', name='Synthetic chat ' + str(i), preview='Sample preview', timestamp=i, unread=i % 4, pinned=i % 7 == 0) for i in range(120)]
    elif action == 'messages':
        result['messages'] = [dict(id=str(i), text='Synthetic message https://example.org ' + str(i), sender='Test', out=i % 2 == 0, time='12:00', timestamp=i, mediaType='', mediaPath='') for i in range(80)]
    print(json.dumps(result), flush=True)
