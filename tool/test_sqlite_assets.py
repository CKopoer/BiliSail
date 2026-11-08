"""HTTP and filesystem regressions for the SQLite native asset preflight."""

from contextlib import contextmanager
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("sqlite_assets", ROOT / "tool/prepare-sqlite-assets.py")
staging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(staging)
GATEWAY_ERROR = b"<html><body><h1>504 Gateway Time-out</h1>\nThe server didn't respond in time.\n</body></html>\n"
PAYLOAD = b"controlled native binary fixture"
DIGEST = hashlib.sha256(PAYLOAD).hexdigest()
TAG = "sqlite3-3.7.0"
PRIMARY = f"/simolus3/sqlite3.dart/releases/download/{TAG}/libsqlite3.x64.linux.so"
METADATA = f"/repos/simolus3/sqlite3.dart/releases/tags/{TAG}"
ASSET = "/repos/simolus3/sqlite3.dart/releases/assets/1234"


def fixture(repo):
    package = repo / "cache with spaces/sqlite3"
    (package / "lib/src/hook").mkdir(parents=True)
    manifest = f"const String? releaseTag = '{TAG}';\n" + "\n".join(
        f"  '{filename}': '{DIGEST}'," for filename, _ in staging.TARGETS.values()
    )
    (package / "lib/src/hook/asset_hashes.dart").write_text(manifest, encoding="utf-8")
    config = repo / ".dart_tool/package_config.json"
    config.parent.mkdir()
    config.write_text(json.dumps({"packages": [{"name": "sqlite3", "rootUri": package.as_uri()}]}))
    return staging.asset_spec(repo, "linux-x64")[2]


def metadata(digest=DIGEST, name="libsqlite3.x64.linux.so"):
    return json.dumps({"tag_name": TAG, "assets": [{
        "name": name, "state": "uploaded", "id": 1234, "digest": f"sha256:{digest}"
    }]}).encode()


@contextmanager
def http_fixture(routes, authorization_calls=None):
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            calls.append((self.path, self.headers.get("Accept")))
            if authorization_calls is not None:
                authorization_calls.append((self.path, self.headers.get("Authorization")))
            route = routes[self.path]
            response = route.pop(0) if isinstance(route, list) else route
            status, data = response[:2]
            self.send_response(status)
            for key, value in (response[2] if len(response) == 3 else {}).items():
                self.send_header(key, value)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def open_local(request, timeout):
        # Only this test adapter maps the public HTTPS endpoints to a local
        # HTTP server. Production keeps normal HTTPS/TLS verification.
        url = f"http://127.0.0.1:{server.server_port}{urlparse(request.full_url).path}"
        local_request = Request(url, headers=request.headers)
        for key, value in request.unredirected_hdrs.items():
            local_request.add_unredirected_header(key, value)
        return urlopen(local_request, timeout=timeout)

    try:
        with patch.object(staging, "urlopen", side_effect=open_local), patch.object(staging.time, "sleep"):
            yield calls
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class SQLiteAssetsTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {"BILISAIL_GITHUB_TOKEN": ""})
        environment.start()
        self.addCleanup(environment.stop)

    def test_ci_mismatch_was_the_exact_504_error_page(self):
        self.assertEqual(len(GATEWAY_ERROR), 92)
        self.assertEqual(hashlib.sha256(GATEWAY_ERROR).hexdigest(),
                         "bef140a1a96994029153dca8c00b1750b9a5a764fb9db2dc68d7bb40e8a29e8a")

    def test_504_uses_official_api_and_publishes_only_the_verified_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {PRIMARY: (504, GATEWAY_ERROR), METADATA: (200, metadata()), ASSET: (200, PAYLOAD)}
            with http_fixture(routes) as calls:
                self.assertEqual(staging.prepare(repo, "linux-x64"), destination)
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual([path for path, _ in calls], [PRIMARY, METADATA, ASSET])
            self.assertEqual(calls[-1][1], "application/octet-stream")
            self.assertFalse(list(destination.parent.glob("*.part")))

    def test_success_and_verified_cache_do_not_need_api_or_network(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            with http_fixture({PRIMARY: (200, PAYLOAD)}) as calls:
                staging.prepare(repo, "linux-x64")
                staging.prepare(repo, "linux-x64")
            self.assertEqual(len(calls), 1)
            self.assertEqual(destination.read_bytes(), PAYLOAD)

    def test_200_with_corrupt_bytes_stops_without_retry_or_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            with http_fixture({PRIMARY: (200, GATEWAY_ERROR)}) as calls:
                with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(len(calls), 1)
            self.assertFalse(destination.exists())
            self.assertFalse(list(destination.parent.glob("*.part")))

    def test_api_digest_must_match_the_immutable_package_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {PRIMARY: (504, GATEWAY_ERROR), METADATA: (200, metadata("0" * 64))}
            with http_fixture(routes) as calls:
                with self.assertRaisesRegex(RuntimeError, "digest does not match"):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(len(calls), 2)
            self.assertFalse(destination.exists())

    def test_repeated_504_is_bounded_and_never_creates_a_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {PRIMARY: (504, GATEWAY_ERROR), METADATA: (200, metadata()), ASSET: (504, GATEWAY_ERROR)}
            with http_fixture(routes) as calls:
                with self.assertRaisesRegex(RuntimeError, "3 attempts.*HTTP 504"):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(sum(path in (PRIMARY, ASSET) for path, _ in calls), 3)
            self.assertEqual(sum(path == METADATA for path, _ in calls), 1)
            self.assertFalse(destination.exists())

    def test_api_gateway_failure_returns_to_the_release_download(self):
        # The failed CI stayed on the API after a connection error, then spent
        # its remaining attempts on 502/503 metadata responses.
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {
                PRIMARY: [(504, GATEWAY_ERROR), (200, PAYLOAD)],
                METADATA: (502, b"bad gateway"),
            }
            with http_fixture(routes) as calls:
                staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual([path for path, _ in calls], [PRIMARY, METADATA, PRIMARY])

    def test_transient_api_asset_failure_reuses_metadata_and_recovers(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {
                PRIMARY: (503, b"unavailable"),
                METADATA: (200, metadata()),
                ASSET: [(504, GATEWAY_ERROR), (200, PAYLOAD)],
            }
            with patch.dict(os.environ, {"BILISAIL_GITHUB_TOKEN": "controlled-test-token"}):
                with http_fixture(routes) as calls:
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual([path for path, _ in calls], [METADATA, ASSET, PRIMARY, ASSET])

    def test_exhausted_metadata_errors_name_the_failed_phase(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            routes = {PRIMARY: (504, GATEWAY_ERROR), METADATA: (503, b"unavailable")}
            with patch.dict(os.environ, {"BILISAIL_GITHUB_TOKEN": "controlled-test-token"}):
                with http_fixture(routes) as calls:
                    with self.assertRaisesRegex(RuntimeError, "Release API metadata.*3 attempts.*503"):
                        staging.prepare(repo, "linux-x64")
            self.assertEqual(len(calls), 3)
            self.assertFalse(destination.exists())

    def test_ci_uses_authenticated_api_and_drops_token_on_asset_redirect(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            authorization = []
            routes = {
                METADATA: (200, metadata()),
                ASSET: (302, b"", {"Location": "/cdn-binary"}),
                "/cdn-binary": (200, PAYLOAD),
            }
            with patch.dict(os.environ, {"BILISAIL_GITHUB_TOKEN": "controlled-test-token"}):
                with http_fixture(routes, authorization) as calls:
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual([path for path, _ in calls], [METADATA, ASSET, "/cdn-binary"])
            self.assertEqual(authorization, [
                (METADATA, "Bearer controlled-test-token"),
                (ASSET, "Bearer controlled-test-token"),
                ("/cdn-binary", None),
            ])

    def test_authenticated_api_failure_uses_anonymous_release_download(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            authorization = []
            routes = {METADATA: (503, b"unavailable"), PRIMARY: (200, PAYLOAD)}
            with patch.dict(os.environ, {"BILISAIL_GITHUB_TOKEN": "controlled-test-token"}):
                with http_fixture(routes, authorization):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual(authorization, [
                (METADATA, "Bearer controlled-test-token"), (PRIMARY, None),
            ])

    def test_404_stops_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            fixture(repo)
            with http_fixture({PRIMARY: (404, b"not found")}) as calls:
                with self.assertRaisesRegex(RuntimeError, "HTTP 404"):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(len(calls), 1)

    def test_connection_failure_switches_to_api(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            original = staging.request
            attempts = []

            def connect(url, deadline, accept):
                attempts.append(url)
                if len(attempts) == 1:
                    raise URLError("controlled connection failure")
                return original(url, deadline, accept)

            with http_fixture({METADATA: (200, metadata()), ASSET: (200, PAYLOAD)}):
                with patch.object(staging, "request", side_effect=connect):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)
            self.assertEqual(len(attempts), 3)

    def test_deadline_prevents_new_network_requests(self):
        with patch.object(staging.time, "monotonic", return_value=121):
            with patch.object(staging, "urlopen") as open_request:
                with self.assertRaises(TimeoutError):
                    staging.request("https://github.com/unused", 120, "application/octet-stream")
        open_request.assert_not_called()

    def test_oversize_response_does_not_publish_or_leave_partial_files(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            with http_fixture({PRIMARY: (200, PAYLOAD)}):
                with patch.object(staging, "MAX_BYTES", len(PAYLOAD) - 1):
                    with self.assertRaisesRegex(RuntimeError, "size limit"):
                        staging.prepare(repo, "linux-x64")
            self.assertFalse(destination.exists())
            self.assertFalse(list(destination.parent.glob("*.part")))

    def test_invalid_cached_binary_is_replaced_only_after_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            destination = fixture(repo)
            destination.parent.mkdir(parents=True)
            destination.write_bytes(b"invalid old cache")
            with http_fixture({PRIMARY: (200, GATEWAY_ERROR)}):
                with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                    staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), b"invalid old cache")
            with http_fixture({PRIMARY: (200, PAYLOAD)}):
                staging.prepare(repo, "linux-x64")
            self.assertEqual(destination.read_bytes(), PAYLOAD)

    def test_manifest_drives_all_seven_targets_and_shared_hook_cache_names(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            fixture(repo)
            for target, (_, name) in staging.TARGETS.items():
                with self.subTest(target=target):
                    tag, digest, path = staging.asset_spec(repo, target)
                    self.assertEqual((tag, digest, path.name), (TAG, DIGEST, name))
                    self.assertEqual(path.parent.name, f"download-{DIGEST[:8]}")


if __name__ == "__main__":
    unittest.main()
