"""Local Range fixture and a native fault restricted to the development worker."""
import argparse
import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--port', type=int, default=18764)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    fixtures = Path(__file__).resolve().parents[2] / 'test' / 'fixtures' / 'media'
    report = {}
    package = 'dev.bilisail.bilisail.test'

    def adb(*command):
        return subprocess.check_output(['adb', '-s', args.device, *command], text=True).strip()

    def process(name):
        value = adb('shell', 'pidof', name)
        if not re.fullmatch(r'[1-9][0-9]*', value):
            raise RuntimeError('Expected exactly one test process')
        return int(value)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_HEAD(self):
            self.do_GET(head=True)

        def do_GET(self, head=False):
            if self.path not in ('/video.mp4', '/audio.m4a'):
                self.send_error(404)
                return
            data = (fixtures / self.path[1:]).read_bytes()
            start, end = 0, len(data) - 1
            requested = self.headers.get('Range')
            if requested:
                match = re.fullmatch(r'bytes=([0-9]+)-([0-9]*)', requested)
                if not match:
                    self.send_error(416)
                    return
                start = int(match[1])
                end = min(end, int(match[2])) if match[2] else end
                if start > end:
                    self.send_error(416)
                    return
            self.send_response(206 if requested else 200)
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            if requested:
                self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
            self.end_headers()
            if not head:
                try:
                    self.wfile.write(data[start:end + 1])
                except (BrokenPipeError, ConnectionResetError):
                    pass

        def do_POST(self):
            if self.path not in ('/playing', '/reopened'):
                self.send_error(404)
                return
            data = json.loads(self.rfile.read(min(int(self.headers['Content-Length']), 1024)))
            ui_pid = process(package)
            if data.get('pid') != ui_pid:
                raise RuntimeError('UI PID mismatch')
            worker = process(package + ':fvp_player')
            if worker == ui_pid:
                raise RuntimeError('Worker is not isolated')
            report[self.path[1:]] = {'uiPid': ui_pid, 'workerPid': worker}
            Path(args.output).write_text(json.dumps(report, indent=2), encoding='utf-8')
            screenshot = subprocess.check_output(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'])
            Path(args.output).with_name('fvp-process-' + self.path[1:] + '.png').write_bytes(screenshot)
            self.send_response(200)
            self.send_header('Content-Length', '0')
            self.end_headers()
            if self.path == '/playing':
                # run-as requires the signed, debuggable development fixture.
                # No production package or main/UI process is signalled.
                adb('shell', 'run-as', package, 'kill', '-11', str(worker))
            elif report['playing']['uiPid'] != ui_pid or report['playing']['workerPid'] == worker:
                raise RuntimeError('Reopen did not retain UI and replace worker')

    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
