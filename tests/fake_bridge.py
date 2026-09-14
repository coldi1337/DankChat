import json
import sys
import base64
from pathlib import Path
media = Path(__file__).with_name('synthetic.png')
media.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaPj/HwAEggJ/59habAAAAABJRU5ErkJggg=='))
downloaded = set()
deleted = set()
for line in sys.stdin:
    request = json.loads(line)
    result = {'ok': True, 'requestId': request['requestId']}
    provider = request.get('provider', '')
    action = request.get('action')
    if action == 'status':
        result.update(authorized=True, authState='authorized')
    elif action == 'chats':
        result['chats'] = [dict(key=provider + str(i), id=str(i), provider=provider, account='', name='Synthetic chat ' + str(i), preview='Sample preview', timestamp=i, unread=i % 4, pinned=i % 7 == 0) for i in range(120)]
    elif action == 'presence':
        import time
        result['presence'] = {'activity': 'typing', 'activityExpiresAt': int(time.time()) + 8}
    elif action == 'voice_stop':
        result['path'] = '/tmp/synthetic-voice.ogg'
    elif action == 'messages':
        result['messages'] = [dict(id=str(i), text='Synthetic message https://example.org ' + str(i), sender='Test', out=i % 2 == 0, time='12:00', timestamp=i, mediaType='image' if i >= 77 else '', mediaDownloadable=i != 77, mediaPath=str(media) if (request['chat']['key'], str(i)) in downloaded else '') for i in range(80)]
    elif action == 'delete':
        if request['messageId'] == '1':
            result.update(ok=False, error='Synthetic deletion failure')
        else:
            deleted.add((request['chat']['key'], request['messageId']))
    elif action == 'context':
        result['messages'] = [dict(id=request['messageId'], text='Synthetic original', sender='Test', out=False, timestamp=0, mediaType='', mediaPath='')]
    elif action == 'file' and request.get('path') == '/tmp/test-fail':
        result.update(ok=False, error='Synthetic attachment failure')
    elif action == 'download':
        key = (request['chat']['key'], str(request['messageId']))
        if str(request['messageId']) == '77':
            result.update(ok=False, error='Attempted download without metadata')
        if key in downloaded:
            result.update(ok=False, error='Duplicate download')
        downloaded.add(key)
    if action == 'messages':
        result['messages'] = [row for row in result['messages'] if (request['chat']['key'], row['id']) not in deleted]
    print(json.dumps(result), flush=True)
