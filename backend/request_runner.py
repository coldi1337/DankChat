"""Keep local clipboard work and provider reads responsive during transfers."""
import asyncio
from collections import deque
from contextlib import AsyncExitStack
import time

LOCAL = {'clipboard_image', 'discard_clipboard'}
VOICE = {'voice', 'voice_start', 'voice_stop', 'voice_discard'}
TRANSFERS = {'download', 'file', 'voice', 'send'}
LIFECYCLE = {'login', 'logout', 'cancel_login', 'password'}
ACTIONS = LOCAL | VOICE | TRANSFERS | LIFECYCLE | {'configure', 'status', 'chats', 'messages', 'presence', 'context', 'reaction', 'delete', 'read', 'acknowledge', 'export', 'pin', 'diagnostics', 'app_info', 'check_updates', 'accounts', 'add_account', 'rename_account', 'storage_info', 'clean_storage', 'browse', 'edit', 'notify'}


class RequestRunner:
    def __init__(self):
        self.control = {name: asyncio.Lock() for name in ('telegram', 'whatsapp', '')}
        self.transfer = {name: asyncio.Lock() for name in ('telegram', 'whatsapp', '')}
        self.download = {name: asyncio.Semaphore(1 if name == 'whatsapp' else 2) for name in self.control}
        self.messages = {name: asyncio.Semaphore(2) for name in self.control}
        self.presence = {name: asyncio.Lock() for name in self.control}
        self.clipboard = asyncio.Lock()
        self.voice = asyncio.Lock()
        self.diagnostics = deque(maxlen=50)

    async def run(self, request, dispatch):
        action, provider = request.get('action'), request.get('provider', '')
        provider = provider if provider in ('telegram', 'whatsapp') else ''
        service = provider
        target = request.get('chat')
        account = request.get('account', target.get('account', '') if isinstance(target, dict) else '')
        from accounts import validate_id
        validate_id(account)
        if account:
            provider += ':' + account
        if provider not in self.control:
            self.control[provider] = asyncio.Lock(); self.transfer[provider] = asyncio.Lock()
            self.download[provider] = asyncio.Semaphore(1 if service == 'whatsapp' else 2)
            self.messages[provider] = asyncio.Semaphore(2); self.presence[provider] = asyncio.Lock()
        started = time.monotonic()
        outcome = 'ok'
        timeout = 210 if action == 'download' else 150 if action in TRANSFERS else 90
        async def execute():
            async with AsyncExitStack() as stack:
                if action in LOCAL:
                    await asyncio.wait_for(stack.enter_async_context(self.clipboard), 30)
                elif action in VOICE:
                    await asyncio.wait_for(stack.enter_async_context(self.voice), 30)
                if action == 'download':
                    await asyncio.wait_for(stack.enter_async_context(self.download[provider]), 30)
                elif action in {'messages', 'context', 'browse'}:
                    await asyncio.wait_for(stack.enter_async_context(self.messages[provider]), 30)
                elif action == 'presence':
                    await asyncio.wait_for(stack.enter_async_context(self.presence[provider]), 30)
                elif action in TRANSFERS:
                    await asyncio.wait_for(stack.enter_async_context(self.transfer[provider]), 30)
                elif action not in LOCAL | VOICE:
                    await asyncio.wait_for(stack.enter_async_context(self.control[provider]), 30)
                    if action in LIFECYCLE:
                        await asyncio.wait_for(stack.enter_async_context(self.transfer[provider]), 30)
                        for _ in range(1 if service == 'whatsapp' else 2):
                            await asyncio.wait_for(stack.enter_async_context(self.download[provider]), 30)
                        for _ in range(2):
                            await asyncio.wait_for(stack.enter_async_context(self.messages[provider]), 30)
                        await asyncio.wait_for(stack.enter_async_context(self.presence[provider]), 30)
                return await asyncio.wait_for(dispatch(request), timeout)
        try:
            result = await execute()
            if not result.get('ok'):
                outcome = 'rejected'
            return result
        except BaseException as exc:
            outcome = 'timeout' if isinstance(exc, asyncio.TimeoutError) else 'cancelled' if isinstance(exc, asyncio.CancelledError) else 'error'
            raise
        finally:
            self.diagnostics.append({'provider': service, 'action': action if action in ACTIONS else 'unknown',
                'outcome': outcome, 'durationMs': round((time.monotonic() - started) * 1000)})
