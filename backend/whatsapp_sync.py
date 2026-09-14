"""Own wacli sync and a private loopback receiver for live delivery receipts."""
import contextlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import secrets
import signal
import subprocess
import threading
from receipts import record


def main():
    os.umask(0o077)
    configured = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    state = (configured if configured.is_absolute() else Path.home() / '.local/state') / 'dankchat/whatsapp'
    store = state / 'store'
    if not (store / 'session.db').is_file():
        return 0
    helper = state / 'helper'; helper.mkdir(parents=True, exist_ok=True, mode=0o700)
    secret = secrets.token_hex(32)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            self.connection.settimeout(3)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if self.path != '/receipt' or not 0 < length <= 262144:
                    raise ValueError()
                accepted = record(helper / 'receipts.sqlite', self.rfile.read(length), self.headers.get('X-Wacli-Signature', ''), secret)
                self.send_response(204 if accepted else 403)
            except Exception:
                self.send_response(400)
            self.end_headers()
    server = HTTPServer(('127.0.0.1', 0), Handler)
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
