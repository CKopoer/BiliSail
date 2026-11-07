"""Loopback controller for the Android local-file playback probe and Perfetto."""
import argparse
import http.server
import json
import pathlib
import re
import statistics
import shlex
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from perfetto_capture import stop_and_wait

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
parser.add_argument('--config', type=pathlib.Path, required=True)
parser.add_argument('--port', type=int, default=18965)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
config = json.loads(args.config.read_text(encoding='utf-8-sig'))
assert isinstance(config, list) and config
assert all(re.fullmatch(r'[a-zA-Z0-9_-]+', x['name']) and 5 <= x.get('seconds', 30) <= 60 for x in config)
assert len({x['name'] for x in config}) == len(config)
lock = threading.Lock()
active = None
vm_base = None
vm_forward = None
isolate_id = None
starts = {}
network_epoch = None
network_lock = threading.Lock()
network_slots = {}
media_limit = threading.BoundedSemaphore(8)


def adb(*parts, timeout=20, check=True):
    result = subprocess.run(['adb', '-s', args.device, *parts], capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'adb {parts[:3]}: {result.stderr[-300:]}')
    return result.stdout.strip()


def save(name, value):
    (args.output / name).write_text(value, encoding='utf-8')


def vm(method, **params):
    if not vm_base:
        return None
    uri = vm_base + method + '?' + urllib.parse.urlencode(params)
    with urllib.request.urlopen(uri, timeout=20) as response:
        return json.load(response)


def counters(stop, stage):
    layers = adb('shell', 'dumpsys SurfaceFlinger --list')
    names = re.findall(r'([0-9a-f]+ SurfaceView\[dev\.bilisail\.bilisail\.test/[^\]]+\]\(BLAST\)#\d+)', layers)
    layer = max(names, key=lambda name: int(name.rsplit('#', 1)[1])) if names else None
    save(f'{stage}.surface-layer.txt', layer or 'Unavailable')
    with (args.output / f'{stage}.gpu.jsonl').open('w', encoding='utf-8') as output:
        while not stop.is_set():
            before = time.time()
            try:
                lines = adb('shell', 'cat /proc/uptime /sys/class/kgsl/kgsl-3d0/gpubusy', timeout=5).splitlines()
                busy, total = map(int, lines[1].split())
                row = {'timeUtcSeconds': time.time(), 'bootSeconds': float(lines[0].split()[0]),
                       'busyUs': busy, 'totalUs': total, 'busyPercent': busy / total * 100 if total else None}
                if layer:
                    raw = adb('shell', 'dumpsys', 'SurfaceFlinger', '--latency', shlex.quote(layer), timeout=5)
                    values = [list(map(int, line.split())) for line in raw.splitlines() if re.fullmatch(r'\d+\s+\d+\s+\d+', line)]
                    row['surfaceTimesNs'] = values
                output.write(json.dumps(row) + '\n')
                output.flush()
            except Exception as error:
                output.write(json.dumps({'error': str(error)}) + '\n')
            stop.wait(max(0, 1 - (time.time() - before)))


def ready(stage, seconds):
    global active
    assert active is None
    prefix = f'/data/misc/perfetto-traces/bilisail-4k60-{stage}'
    config_path = f'/data/local/tmp/bilisail-4k60-{stage}.pbtxt'
    pbtxt = f'''buffers {{ size_kb: 196608 fill_policy: RING_BUFFER }}
duration_ms: {(seconds + 5) * 1000}
data_sources {{ config {{ name: "linux.ftrace" ftrace_config {{
 ftrace_events: "sched/sched_switch"
 ftrace_events: "sched/sched_waking"
 ftrace_events: "power/cpu_frequency"
 ftrace_events: "power/gpu_frequency"
 atrace_categories: "gfx"
 atrace_categories: "view"
 atrace_apps: "dev.bilisail.bilisail.test"
}} }} }}
data_sources {{ config {{ name: "linux.process_stats" process_stats_config {{ scan_all_processes_on_start: true }} }} }}
data_sources {{ config {{ name: "android.surfaceflinger.frametimeline" }} }}
'''
    path = args.output / f'{stage}.pbtxt'
    path.write_text(pbtxt, encoding='utf-8')
    adb('push', str(path), config_path)
    save(f'{stage}.thermal-before.txt', adb('shell', 'dumpsys thermalservice'))
    # Feed config over stdin: Android's traced SELinux domain cannot read shell tmp files.
    result = adb('shell', f'cat {config_path} | perfetto --background --txt -c - -o {prefix}.trace')
    match = re.search(r'(\d+)\s*$', result)
    if not match:
        raise RuntimeError('Perfetto did not return its PID: ' + result)
    stop = threading.Event()
    worker = threading.Thread(target=counters, args=(stop, stage), daemon=True)
    active = (stage, prefix, int(match[1]), stop, worker)
    worker.start()
    save(f'{stage}.trace-start.json', json.dumps({'perfettoPid': int(match[1]),
         'bootSeconds': adb('shell', 'cat /proc/uptime').split()[0], 'hostTime': time.time()}))


def finish(stage):
    global active
    assert active and active[0] == stage
    _, prefix, trace_pid, stop, worker = active
    stop.set()
    worker.join(timeout=6)
    stop_and_wait(adb, trace_pid)
    adb('pull', prefix + '.trace', str(args.output / f'{stage}.perfetto-trace'), timeout=30)
    save(f'{stage}.thermal-after.txt', adb('shell', 'dumpsys thermalservice'))
    with (args.output / f'{stage}.png').open('wb') as screenshot:
        subprocess.run(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'],
                       stdout=screenshot, stderr=subprocess.PIPE, check=True, timeout=15)
    save(f'{stage}.meminfo.txt', adb('shell', 'dumpsys meminfo dev.bilisail.bilisail.test'))
    save(f'{stage}.codec.txt', adb('shell', 'dumpsys media.codec', check=False))
    if vm_base and isolate_id and stage in starts and starts[stage][1] is not None:
        begin, end = starts[stage]
        try:
            result = vm('getCpuSamples', isolateId=isolate_id, timeOriginMicros=begin, timeExtentMicros=end-begin)
            save(f'{stage}.dart-cpu.json', json.dumps(result))
        except Exception as error:
            save(f'{stage}.dart-cpu-error.txt', str(error))
    adb('shell', f'rm -f /data/local/tmp/bilisail-4k60-{stage}.pbtxt {prefix}.trace', check=False)
    active = None


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, value, status=200):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/config':
            self.reply(config)
        else:
            match = re.fullmatch(r'/media/(fast|slow|stall)/(video|audio)\.mp4', self.path)
            if match:
                self.media(match[1], match[2], head=False)
            else:
                self.reply({'error': 'unknown path'}, 404)

    def do_HEAD(self):
        match = re.fullmatch(r'/media/(fast|slow|stall)/(video|audio)\.mp4', self.path)
        if match:
            self.media(match[1], match[2], head=True)
        else:
            self.reply({'error': 'unknown path'}, 404)

    def media(self, profile, track, head):
        # Fixed public fixtures only; no general file-serving or user paths.
        path = args.output.parent / ('http-video-4k60.mp4' if track == 'video' else 'http-audio.m4a')
        if not path.exists() or not media_limit.acquire(timeout=2):
            self.reply({'error': 'fixture unavailable'}, 503)
            return
        sent = 0
        started = time.monotonic()
        start, end = 0, path.stat().st_size - 1
        range_header = self.headers.get('Range')
        complete = False
        try:
            if range_header:
                match = re.fullmatch(r'bytes=(\d*)-(\d*)', range_header)
                if not match or not any(match.groups()):
                    self.send_error(416)
                    return
                if not match[1]:
                    start = max(0, end + 1 - int(match[2]))
                else:
                    start = int(match[1])
                    end = min(end, int(match[2])) if match[2] else end
                if start > end:
                    self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{path.stat().st_size}')
                    self.end_headers()
                    return
            time.sleep(.12 if profile == 'slow' else .05)
            self.send_response(206 if range_header else 200)
            self.send_header('Content-Type', 'video/mp4' if track == 'video' else 'audio/mp4')
            self.send_header('Accept-Ranges', 'bytes')
            self.send_header('Content-Length', str(end - start + 1))
            self.send_header('Connection', 'close')
            if range_header:
                self.send_header('Content-Range', f'bytes {start}-{end}/{path.stat().st_size}')
            self.end_headers()
            if head:
                complete = True
                return
            rate = (2 if profile == 'slow' else 32) * 1_000_000 / 8
            with path.open('rb') as source:
                source.seek(start)
                while sent <= end - start:
                    chunk = source.read(min(32768, end - start + 1 - sent))
                    if not chunk:
                        break
                    if profile == 'stall' and network_epoch is not None:
                        until = network_epoch + 20 - time.monotonic()
                        if network_epoch + 8 <= time.monotonic() and until > 0:
                            time.sleep(until)
                    with network_lock:
                        slot = max(time.monotonic(), network_slots.get(profile, 0))
                        network_slots[profile] = slot + len(chunk) / rate
                    time.sleep(max(0, slot - time.monotonic()))
                    if profile == 'slow' and sent // 32768 % 7 == 0:
                        time.sleep(.015)
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
                complete = sent == end - start + 1
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass
        finally:
            with lock, (args.output / 'http-requests.jsonl').open('a', encoding='utf-8') as output:
                output.write(json.dumps({'profile': profile, 'track': track, 'rangeStart': start,
                    'rangeEnd': end, 'rangeRequested': bool(range_header), 'head': head,
                    'headerChecks': {name: self.headers.get(name) == value
                                     for name, value in config[0].get('verifyRequestHeaders', {}).items()},
                    'bytesSent': sent, 'durationSeconds': time.monotonic()-started,
                    'complete': complete}) + '\n')
            media_limit.release()

    def do_POST(self):
        global vm_base, vm_forward, isolate_id, network_epoch
        try:
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            if self.path == '/event':
                with lock, (args.output / 'events.jsonl').open('a', encoding='utf-8') as file:
                    file.write(json.dumps(data) + '\n')
                kind, stage = data['type'], data.get('stage')
                if kind == 'bootstrap' and data.get('vmUri'):
                    uri = urllib.parse.urlparse(data['vmUri'])
                    vm_forward = adb('forward', 'tcp:0', f'tcp:{uri.port}')
                    vm_base = f'http://127.0.0.1:{vm_forward}{uri.path}'
                    save('vm-forward.json', json.dumps({'port': vm_forward}))
                    result = vm('getVM')
                    isolates = result.get('result', {}).get('isolates', [])
                    isolate_id = next((x['id'] for x in isolates if x['name'] == 'main'), None)
                    profiler = vm('setFlag', name='profiler', value='true')
                    save('vm-status.json', json.dumps({'available': True, 'mainIsolate': isolate_id, 'profiler': profiler}))
                elif kind == 'phase-start':
                    starts[stage] = [data['monoUs'], None]
                    network_epoch = time.monotonic()
                elif kind == 'phase-end':
                    starts[stage][1] = data['monoUs']
                self.reply({'ok': True})
            elif self.path == '/ready':
                ready(data['stage'], data['seconds'])
                self.reply({'ok': True})
            elif self.path == '/startup':
                stage, phase = data['stage'], data['phase']
                scenario = next(x for x in config if x['name'] == stage)
                if phase not in ('opened', 'resumed'):
                    raise ValueError('Invalid startup phase')
                screenshot = args.output / f'{stage}-{phase}.png'
                with screenshot.open('wb') as file:
                    subprocess.run(['adb', '-s', args.device, 'exec-out', 'screencap', '-p'],
                                   stdout=file, check=True, timeout=15)
                # Only explicitly selected, known nonblack fixtures use this
                # assertion. A naturally black scene is valid video content.
                pixels = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(screenshot),
                    '-vf', 'crop=iw/3:ih/3:iw/3:ih/3,scale=64:64,format=gray',
                    '-f', 'rawvideo', '-'], capture_output=True, check=True, timeout=15).stdout
                if len(pixels) != 64 * 64:
                    raise ValueError('Startup screenshot could not be sampled')
                stats = {'mean': statistics.mean(pixels), 'stddev': statistics.pstdev(pixels)}
                save(f'{stage}-{phase}-pixels.json', json.dumps(stats))
                if scenario.get('verifyStartupPixels') and (stats['mean'] < 10 or stats['stddev'] < 8):
                    raise ValueError('Known nonblack fixture has no visible video')
                self.reply(stats)
            elif self.path == '/finish':
                finish(data['stage'])
                self.reply({'ok': True})
            elif self.path == '/abort':
                if active and active[0] == data['stage']:
                    finish(data['stage'])
                self.reply({'ok': True})
            elif self.path == '/touch':
                action, x, y = data['action'], data['x'], data['y']
                if action not in ('DOWN', 'UP') or not all(
                        isinstance(v, int) and 0 <= v <= 8192 for v in (x, y)):
                    raise ValueError('Invalid fixture touch')
                adb('shell', 'input', 'touchscreen', 'motionevent', action, str(x), str(y))
                self.reply({'ok': True})
            else:
                self.reply({'error': 'unknown path'}, 404)
        except Exception as error:
            with (args.output / 'collector-errors.log').open('a', encoding='utf-8') as file:
                file.write(str(error) + '\n')
            self.reply({'error': str(error)}, 500)


server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
save('server.json', json.dumps({'port': server.server_address[1]}))
server.serve_forever()
