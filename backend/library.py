"""Search and media browsing use the provider's history, not only visible rows."""
import asyncio
from model import message


async def telegram_browse(provider, target, query, category, offset):
    from telethon.tl import types
    filters = {'images': types.InputMessagesFilterPhotos, 'videos': types.InputMessagesFilterVideo,
               'files': types.InputMessagesFilterDocument, 'links': types.InputMessagesFilterUrl,
               'audio': types.InputMessagesFilterRoundVoice}
    options = {'limit': 51, 'offset_id': int(offset or 0), 'search': query}
    if category in filters:
        options['filter'] = filters[category]()
    entity = await provider.daemon.client.get_input_entity(int(target['id']))
    if category == 'audio':
        voice = dict(options, filter=types.InputMessagesFilterRoundVoice())
        music = dict(options, filter=types.InputMessagesFilterMusic())
        groups = await asyncio.gather(provider.daemon.client.get_messages(entity, **voice), provider.daemon.client.get_messages(entity, **music))
        rows = sorted({row.id: row for group in groups for row in group}.values(), key=lambda row: row.id, reverse=True)
    else:
        rows = await provider.daemon.client.get_messages(entity, **options)
    results = []
    for row in rows[:50]:
        file = getattr(row, 'file', None)
        kind = 'photo' if getattr(row, 'photo', None) else 'video' if getattr(row, 'video', None) else 'audio' if getattr(row, 'audio', None) or getattr(row, 'voice', None) else 'document' if file else ''
        results.append(message('telegram', {'id': row.id, 'text': row.message or '', 'out': row.out,
            'timestamp': int(row.date.timestamp()), 'is_edited': bool(row.edit_date),
            'media_type': kind, 'filename': getattr(file, 'name', '') or '',
            'file_size': getattr(file, 'size', 0) or 0}))
    return {'ok': True, 'messages': results, 'next': str(rows[49].id) if len(rows) > 50 else ''}
