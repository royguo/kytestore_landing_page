#!/usr/bin/env python3
import http.server
import socketserver
import os
import signal
import sys

PORT = 80
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
    with socketserver.TCPServer(("", PORT), KyteStoreHandler) as httpd:
        print("[KyteStore Server] Serving on port %d" % PORT)
        print("[KyteStore Server] Document root: %s" % DIRECTORY)
        sys.stdout.flush()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[KyteStore Server] Received interrupt, stopping...")
            httpd.shutdown()

if __name__ == "__main__":
    main()
