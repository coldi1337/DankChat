import json
import sys
import base64
import threading
output_lock = threading.Lock()
def emit(result):
    with output_lock:
        print(json.dumps(result), flush=True)
delay_next_messages = False
from pathlib import Path
media = Path(__file__).with_name('synthetic.png')
media.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaPj/HwAEggJ/59habAAAAABJRU5ErkJggg=='))
downloaded = set()
deleted = set()
externally_read = set()
read_calls = []
accounts = [{'provider': p, 'id': '', 'label': p.title()} for p in ('telegram', 'whatsapp')]
for line in sys.stdin:
    request = json.loads(line)
    result = {'ok': True, 'requestId': request['requestId']}
    provider = request.get('provider', '')
    action = request.get('action')
    if action == 'test_exit':
        sys.exit(0)
    if action == 'test_slow_next_messages':
        delay_next_messages = True
    if action == 'app_info':
        result.update(version='0.4.0', development=True, revision='synthetic')
    if action == 'check_updates':
        result.update(version='0.4.0', latest='0.4.0', available=False)
    if action == 'configure':
        result['accounts'] = accounts
    if action == 'add_account':
        accounts.append({'provider':provider,'id':'a'*32,'label':request['label']})
        result['accounts'] = accounts
    if action == 'rename_account':
        for row in accounts:
            if row['provider'] == provider and row['id'] == request['account']: row['label'] = request['label']
        result['accounts'] = accounts
    if action == 'read':
        read_calls.append(request['chat']['key']); externally_read.add(request['chat']['key'])
    if action == 'test_read_calls': result['calls'] = read_calls
    if action == 'browse': result.update(messages=[{'id':'older-result','text':'Synthetic match','timestamp':1}],next='')
    if action == 'status':
        result.update(authorized=True, authState='authorized')
    elif action == 'chats':
        account = request.get('account','')
        prefix = provider + (':' + account if account else '')
        result['chats'] = [dict(key=prefix + str(i), id=str(i), provider=provider, account=account, name='Synthetic chat ' + str(i), preview='Sample preview', timestamp=i, unread=0 if prefix + str(i) in externally_read else i % 4, pinned=i % 7 == 0) for i in range(120)]
    elif action == 'test_external_read':
        externally_read.add(request['key'])
        print(json.dumps({'event': 'provider_changed', 'provider': provider}), flush=True)
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
    if action == 'messages' and delay_next_messages:
        delay_next_messages = False
        timer = threading.Timer(1, emit, args=(result,)); timer.daemon = True; timer.start()
    else:
        emit(result)
