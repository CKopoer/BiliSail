"""Loopback-only TLS fixture: close TCP inside one encrypted media record.

The caller supplies synthetic media and a temporary self-signed certificate.
Only the first response of the selected track is truncated; Range retries get
the remaining original bytes. stdout contains ports and byte offsets only.
"""

import json
import re
import socketserver
import ssl
import sys
import threading
from pathlib import Path


def main():
    directory = Path(sys.argv[1])
    affected = sys.argv[2]
    media = {
        "/video": (directory / "video.mp4").read_bytes(),
        "/audio": (directory / "audio.m4a").read_bytes(),
    }
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(directory / "cert.pem", directory / "key.pem")
    lock = threading.Lock()
    interrupted = False

    def emit(value):
        with lock:
            print(json.dumps(value), flush=True)

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            nonlocal interrupted
            incoming, outgoing = ssl.MemoryBIO(), ssl.MemoryBIO()
            tls = context.wrap_bio(incoming, outgoing, server_side=True)
            self.request.settimeout(10)

            def flush():
                data = outgoing.read()
                if data:
                    self.request.sendall(data)

            def receive():
                data = self.request.recv(65536)
                if not data:
                    raise ConnectionError("Fixture client disconnected")
                incoming.write(data)

            try:
                while True:
                    try:
                        tls.do_handshake()
                        flush()
                        break
                    except ssl.SSLWantReadError:
                        flush()
                        receive()
                request = b""
                while b"\r\n\r\n" not in request:
                    try:
                        request += tls.read(65536)
                    except ssl.SSLWantReadError:
                        receive()
                    if len(request) > 16384:
                        raise ValueError("Fixture request exceeds budget")
                path = request.split(b" ")[1].decode("ascii")
                data = media[path]
                match = re.search(rb"Range: bytes=(\d+)", request, re.IGNORECASE)
                start = int(match[1]) if match else 0
                with lock:
                    truncate = path == f"/{affected}" and not interrupted
                    interrupted |= truncate
                emit({"track": path[1:], "offset": start, "truncated": truncate})
                if start >= len(data):
                    tls.write(b"HTTP/1.1 416 Range Not Satisfiable\r\n\r\n")
                    flush()
                    return
                headers = (
                    "HTTP/1.1 206 Partial Content\r\n"
                    f"Content-Length: {len(data) - start}\r\n"
                    f"Content-Range: bytes {start}-{len(data) - 1}/{len(data)}\r\n"
                    "Accept-Ranges: bytes\r\n\r\n"
                ).encode("ascii")
                tls.write(headers)
                flush()
                if truncate:
                    tls.write(data[start : start + 256 * 1024])
                    # The final TLS record is incomplete, even though TCP EOF
                    # is immediately observable. No artificial SDK events.
                    self.request.sendall(outgoing.read()[:-8])
                else:
                    for offset in range(start, len(data), 65536):
                        tls.write(data[offset : offset + 65536])
                        flush()
            except (OSError, ValueError, KeyError):
                # Player disposal cancels outstanding requests.
                pass

    with socketserver.ThreadingTCPServer(("127.0.0.1", 0), Handler) as server:
        server.daemon_threads = True
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        emit({"port": server.server_address[1]})
        try:
            sys.stdin.read()
        finally:
            server.shutdown()
            worker.join(timeout=2)


if __name__ == "__main__":
    main()
