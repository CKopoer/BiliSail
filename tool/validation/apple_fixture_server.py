"""Serve local Apple playback fixtures, requiring production headers on DASH reads."""
import http.server
import re
import sys
from pathlib import Path


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if not self.path.startswith("/dash/"):
            return super().do_GET()
        name = self.path.removeprefix("/dash/")
        if name not in {"video.mp4", "joc.m4a"} or self.headers.get("Referer") != "https://fixture.example/":
            return self.send_error(403)
        data = Path(self.directory, name).read_bytes()
        match = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
        start = int(match[1]) if match else 0
        end = min(int(match[2]) if match and match[2] else len(data) - 1, len(data) - 1)
        if start > end:
            return self.send_error(416)
        self.send_response(206 if match else 200)
        self.send_header("Accept-Ranges", "bytes")
        if match:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        try:
            self.wfile.write(data[start:end + 1])
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    from functools import partial
    with http.server.ThreadingHTTPServer(("127.0.0.1", 18085), partial(Handler, directory=sys.argv[1])) as server:
        server.serve_forever()
