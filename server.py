#!/usr/bin/env python3
import http.server
import socketserver
import os
import signal
import sys

# KYTESTORE_BIND / KYTESTORE_PORT: use 127.0.0.1:9080 behind Caddy; 0.0.0.0:80 for standalone.
PORT = int(os.environ.get("KYTESTORE_PORT", "9080"))
BIND = os.environ.get("KYTESTORE_BIND", "127.0.0.1")
DIRECTORY = "/root/innovic.cn"

class KyteStoreHandler(http.server.SimpleHTTPRequestHandler):
    # Python 3.6 has no directory= on SimpleHTTPRequestHandler; cwd is set in main().
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def log_message(self, format, *args):
        sys.stdout.write("[%s] %s\n" % (self.log_date_time_string(), format % args))
        sys.stdout.flush()

    def do_GET(self):
        if self.path == '/':
            self.path = '/index.html'
        return http.server.SimpleHTTPRequestHandler.do_GET(self)

def signal_handler(sig, frame):
    print("\n[KyteStore Server] Shutting down...")
    sys.exit(0)

def main():
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    os.chdir(DIRECTORY)

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer((BIND, PORT), KyteStoreHandler) as httpd:
        print("[KyteStore Server] Serving on %s:%d" % (BIND, PORT))
        print("[KyteStore Server] Document root: %s" % DIRECTORY)
        sys.stdout.flush()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[KyteStore Server] Received interrupt, stopping...")
            httpd.shutdown()

if __name__ == "__main__":
    main()
