"""Own wacli sync and a private loopback receiver for live delivery receipts."""
import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import secrets
import signal
import subprocess
import threading
import sys
from accounts import validate_id
from receipts import record


def peer_uid(address, destination, table='/proc/net/tcp'):
    """Owner of the local TCP socket that connected from `address`, or None.

    wacli only accepts the webhook secret as a command-line argument, which other
    local users can read. Accept receipts only from processes of this user.
    """
    host, port = address[:2]
    if host != '127.0.0.1':
        return None
    wanted = '0100007F:%04X' % port
    remote = '0100007F:%04X' % destination[1]
    try:
        with open(table) as rows:
            next(rows, None)
            for row in rows:
                fields = row.split()
                if len(fields) > 7 and fields[1] == wanted and fields[2] == remote and fields[3] == '01':
                    return int(fields[7])
    except (OSError, ValueError):
        return None
    return None


def main():
    os.umask(0o077)
    configured = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    state = (configured if configured.is_absolute() else Path.home() / '.local/state') / 'dankchat/whatsapp'
    account = validate_id(sys.argv[1] if len(sys.argv) > 1 else '')
    if account:
        state = state / account
    store = state / 'store'
    if not (store / 'session.db').is_file():
        return 0
    helper = state / 'helper'; helper.mkdir(parents=True, exist_ok=True, mode=0o700)
    secret = secrets.token_hex(32)
    class Handler(BaseHTTPRequestHandler):
        # Applies while reading the request line and headers, too.
        timeout = 3
        def log_message(self, *args):
            pass
        def do_POST(self):
            try:
                if peer_uid(self.client_address, self.connection.getsockname()) != os.getuid():
                    self.send_response(403); self.end_headers(); return
                length = int(self.headers.get('Content-Length', '0'))
                if self.path != '/receipt' or not 0 < length <= 262144:
                    raise ValueError()
                accepted = record(helper / 'receipts.sqlite', self.rfile.read(length), self.headers.get('X-Wacli-Signature', ''), secret)
                self.send_response(204 if accepted else 403)
            except Exception:
                self.send_response(400)
            self.end_headers()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    command = [str(Path.home() / '.local/bin/wacli'), '--store', str(store), '--lock-wait', '30s', 'sync', '--follow',
        '--max-reconnect', '10m', '--stale-threshold', '2m', '--presence-mode', 'quiet', '--max-db-size', '1GB', '--refresh-groups',
        '--webhook', f'http://127.0.0.1:{server.server_port}/receipt', '--webhook-allow-private', '--webhook-events', 'receipt,chat_presence', '--webhook-secret', secret]
    child = None
    def stop(*args):
        if child and child.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                child.terminate()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        child = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return child.wait()
    finally:
        stop()
        if child and child.poll() is None:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait()
        server.shutdown(); server.server_close()

if __name__ == '__main__':
    raise SystemExit(main())
