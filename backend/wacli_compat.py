"""Check the command surface we use, rather than pinning one exact release."""
import asyncio
import re

MINIMUM = (0, 17, 1)
REQUIRED = {
    ('sync',): ('--follow', '--webhook-events', '--webhook-secret', '--presence-mode', '--refresh-groups', '--max-db-size', '--max-reconnect', '--stale-threshold', '--webhook-allow-private'),
    ('send', 'file'): ('--to', '--file', '--reply-to', '--post-send-wait'),
    ('send', 'text'): ('--to', '--message', '--reply-to'),
    ('send', 'voice'): ('--to', '--file'),
    ('send', 'react'): ('--to', '--id'),
    ('messages', 'delete'): ('--chat', '--id'),
    ('messages', 'edit'): ('--chat', '--id', '--message'),
    ('chats', 'mark-read'): ('--chat',),
    ('media', 'download'): ('--chat', '--id', '--read-only', '--output'),
}


def supported_version(output):
    match = re.fullmatch(r'wacli v?(\d+)\.(\d+)\.(\d+)(?:[-+][\w.-]+)?', output.strip())
    return bool(match and tuple(map(int, match.groups())) >= MINIMUM)


async def check(binary):
    async def run(*args):
        process = await asyncio.create_subprocess_exec(str(binary), *args,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            stdout, _ = await asyncio.wait_for(process.communicate(), 8)
            return process.returncode, stdout.decode(errors='replace')
        finally:
            if process.returncode is None:
                process.kill(); await process.wait()
    code, version = await run('--version')
    if code or not supported_version(version):
        raise ValueError('DankChat requires wacli 0.17.1 or newer with a compatible command interface.')
    for command, flags in REQUIRED.items():
        code, output = await run(*command, '--help')
        if code or any(not re.search(r'(?<!\S)' + re.escape(flag) + r'(?=[\s=,]|$)', output) for flag in flags):
            raise ValueError('This wacli build is missing commands required by DankChat. Install the recommended release from the README.')
    return version.strip()
