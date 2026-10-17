"""Local bridge between Studio and the repo (localhost only).

GET  /<file>          serves files from build/ (manifest.json for tools/studio_sync.luau)
POST /archive/<path>  writes the request body to archive/<path> (exporting Studio scripts)

Run: python tools/dev_server.py   (port 34877)
"""

import os
from http.server import HTTPServer, SimpleHTTPRequestHandler

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
ARCHIVE = os.path.join(ROOT, "archive")
PORT = 34877


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD, **kwargs)

    def do_POST(self):
        if not self.path.startswith("/archive/"):
            self.send_error(404)
            return
        relative = self.path[len("/archive/"):].replace("..", "")
        target = os.path.normpath(os.path.join(ARCHIVE, relative))
        if not target.startswith(ARCHIVE):
            self.send_error(400)
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")


if __name__ == "__main__":
    os.makedirs(BUILD, exist_ok=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
