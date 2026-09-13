import json
import sys
import base64
from pathlib import Path
media = Path(__file__).with_name('synthetic.png')
media.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaPj/HwAEggJ/59habAAAAABJRU5ErkJggg=='))
downloaded = set()
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
        result['messages'] = [dict(id=str(i), text='Synthetic message https://example.org ' + str(i), sender='Test', out=i % 2 == 0, time='12:00', timestamp=i, mediaType='image' if i >= 78 else '', mediaPath=str(media) if (request['chat']['key'], str(i)) in downloaded else '') for i in range(80)]
    elif action == 'context':
        result['messages'] = [dict(id=request['messageId'], text='Synthetic original', sender='Test', out=False, timestamp=0, mediaType='', mediaPath='')]
    elif action == 'download':
        key = (request['chat']['key'], str(request['messageId']))
        if key in downloaded:
            result.update(ok=False, error='Duplicate download')
        downloaded.add(key)
    print(json.dumps(result), flush=True)
