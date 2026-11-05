"""Exercise HTTP Range semantics without Android, credentials or large media."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request


class RangeServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = pathlib.Path(cls.temp.name)
        cls.data = bytes(range(256)) * 512
        (cls.root / 'http-video-4k60.mp4').write_bytes(cls.data)
        (cls.root / 'http-audio.m4a').write_bytes(cls.data)
        config = cls.root / 'config.json'
        config.write_text(json.dumps([{'name': 'http-test', 'seconds': 5}]))
        cls.output = cls.root / 'run'
        cls.process = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name('android_4k60_collector.py')),
            '--device', 'unused', '--output', str(cls.output), '--config', str(config), '--port', '0'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            state = cls.output / 'server.json'
            if state.exists():
                cls.base = 'http://127.0.0.1:' + str(json.loads(state.read_text())['port'])
                break
            time.sleep(.05)
        else:
            raise RuntimeError('Range server did not start')

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.temp.cleanup()

    def test_head_advertises_exact_resource_size(self):
        request = urllib.request.Request(self.base + '/media/fast/video.mp4', method='HEAD')
        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers['Accept-Ranges'], 'bytes')
            self.assertEqual(int(response.headers['Content-Length']), len(self.data))
            self.assertEqual(response.read(), b'')

    def test_seek_and_suffix_ranges_return_exact_bytes(self):
        for header, expected_start, expected in [('bytes=4096-8191', 4096, self.data[4096:8192]),
                                                ('bytes=-1024', len(self.data)-1024, self.data[-1024:])]:
            request = urllib.request.Request(self.base + '/media/fast/video.mp4', headers={'Range': header})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 206)
                self.assertEqual(response.headers['Content-Range'],
                    f'bytes {expected_start}-{expected_start+len(expected)-1}/{len(self.data)}')
                self.assertEqual(response.read(), expected)

    def test_unsatisfiable_range_and_unknown_paths(self):
        request = urllib.request.Request(self.base + '/media/fast/video.mp4', headers={'Range': 'bytes=9999999-'})
        with self.assertRaises(urllib.error.HTTPError) as raised:
            urllib.request.urlopen(request)
        self.assertEqual(raised.exception.code, 416)
        self.assertEqual(raised.exception.headers['Content-Range'], f'bytes */{len(self.data)}')
        with self.assertRaises(urllib.error.HTTPError) as raised:
            urllib.request.urlopen(self.base + '/media/fast/../../config.json')
        self.assertEqual(raised.exception.code, 404)


if __name__ == '__main__':
    unittest.main()
