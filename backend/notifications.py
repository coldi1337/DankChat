"""Desktop notifications, separate from messenger read receipts and sending."""
import asyncio
import html
import shutil


async def deliver(title, body, sound=False):
    binary = shutil.which('notify-send')
    if not binary:
        return False
    command = [binary, '--app-name=DankChat', '--icon=internet-chat', '--hint=boolean:suppress-sound:' + ('false' if sound else 'true')]
    if sound:
        command.append('--hint=string:sound-name:message-new-instant')
    command += ['--', title[:160], html.escape(body[:300])]
    process = await asyncio.create_subprocess_exec(*command, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
    try:
        return await asyncio.wait_for(process.wait(), 5) == 0
    finally:
        if process.returncode is None:
            process.kill(); await process.wait()
