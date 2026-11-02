"""Serve bounded local media and capture the Android test application's screen."""

import argparse
import http.server
import json
from pathlib import Path
import re
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    args.output.mkdir(parents=True, exist_ok=True)
    media = root / 'build/validation/dolby-vision'
    files = {
        '/video.mp4': media / 'video.mp4',
        '/audio.m4a': root / 'test/fixtures/media/audio.m4a',
        '/sdr.mp4': root / 'test/fixtures/media/video.mp4',
        '/reference.png': media / 'reference-playing.png',
    }

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args: object) -> None:
            pass

        def do_HEAD(self) -> None:
            self.serve_media(body=False)

        def do_GET(self) -> None:
            self.serve_media(body=True)

        def serve_media(self, *, body: bool) -> None:
            path = files.get(self.path)
            if path is None:
                self.send_error(404)
                return
            size = path.stat().st_size
            start, end = 0, size - 1
            ranged = self.headers.get('Range')
            if ranged:
                match = re.fullmatch(r'bytes=(\d+)-(\d*)', ranged)
                if not match:
                    self.send_error(416)
                    return
                start = int(match[1])
                if match[2]:
                    end = min(end, int(match[2]))
                if start > end:
                    self.send_error(416)
                    return
            self.send_response(206 if ranged else 200)
            self.send_header('Content-Length', str(end - start + 1))
            self.send_header('Accept-Ranges', 'bytes')
            if ranged:
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.end_headers()
            if body:
                try:
                    with path.open('rb') as stream:
                        stream.seek(start)
                        remaining = end - start + 1
                        while remaining:
                            chunk = stream.read(min(1024 * 1024, remaining))
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                            remaining -= len(chunk)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                    # mpv cancels outstanding reads when changing sources.
                    pass

        def do_POST(self) -> None:
            mode = self.path.removeprefix('/capture/')
            if mode not in {'automatic', 'software', 'sdr', 'sdr-software'}:
                self.send_error(404)
                return
            try:
                focus = subprocess.run(
                    ['adb', '-s', args.device, 'shell', 'dumpsys', 'window'],
                    capture_output=True, text=True, timeout=10, check=True,
                ).stdout
                if not any('mCurrentFocus=' in line and
                           'dev.bilisail.bilisail.test/' in line
                           for line in focus.splitlines()):
                    self.send_error(409, 'The test application is not foreground')
                    return
                screen = subprocess.run(
                    ['adb', '-s', args.device, 'exec-out', 'screencap', '-p'],
                    capture_output=True, timeout=15, check=True,
                ).stdout
                (args.output / f'screen-{mode}.png').write_bytes(screen)
            except (subprocess.SubprocessError, OSError):
                self.send_error(500, 'Android screen capture failed')
                return
            self.send_response(200)
            self.send_header('Content-Length', '0')
            self.end_headers()

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    (args.output / 'server.json').write_text(
        json.dumps({'port': server.server_port}), encoding='utf-8',
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
