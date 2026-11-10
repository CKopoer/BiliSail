"""Exercise the production MDK selector and Windows archive staging offline."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "native/fvp"


class WindowsFvpSdkTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="bilisail-fvp-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.source = self.root / "native"
        self.source.mkdir()
        for name in ("resolve.cmake", "configure.cmake", "assets.lock.json"):
            shutil.copyfile(SOURCE / name, self.source / name)
        self.lock = json.loads((self.source / "assets.lock.json").read_text())
        self.curl = shutil.which("curl.exe") or shutil.which("curl")
        self.assertIsNotNone(self.curl, "curl is required for offline file:// staging")

    def run_cmake(self, body):
        script = self.root / "test.cmake"
        script.write_text(
            'cmake_minimum_required(VERSION 3.19)\n' + body,
            encoding="utf-8",
        )
        return subprocess.run(
            ["cmake", "-P", str(script)], cwd=self.root,
            capture_output=True, text=True, check=False, timeout=30,
        )

    def save_lock(self):
        (self.source / "assets.lock.json").write_text(json.dumps(self.lock))

    def stage(self, architecture="arm64"):
        return self.run_cmake(f'''
set(WIN32 TRUE)
set(FLUTTER_TARGET_PLATFORM "windows-{architecture}")
set(CMAKE_BINARY_DIR "{self.root.as_posix()}/build")
set(_bilisail_fvp_curl "{Path(self.curl).as_posix()}")
include("{self.source.as_posix()}/configure.cmake")
file(WRITE "{self.root.as_posix()}/selected.txt"
  "${{FVP_DEPS_URL}}\n${{FVP_DEPS_SHA256}}\n")
''')

    def fixture_asset(self, architecture, data):
        origin = self.root / "origin"
        origin.mkdir(exist_ok=True)
        archive = origin / f"sdk-{architecture}.7z"
        archive.write_bytes(data)
        sha = hashlib.sha256(data).hexdigest()
        self.lock["assets"][f"windows-{architecture}"] = {
            "baseUrl": origin.as_uri(), "archive": archive.name, "sha256": sha,
        }
        self.save_lock()
        alias = "mdk-sdk-windows.7z" if architecture == "arm64" else "mdk-sdk-windows-x64.7z"
        target = self.root / "build/fvp-deps" / sha / alias
        return archive, target

    def test_only_arm64_uses_refreshed_release(self):
        for platform in ("windows-arm64", "windows-x64", "linux-x64"):
            with self.subTest(platform=platform):
                result = self.run_cmake(f'''
include("{self.source.as_posix()}/resolve.cmake")
bilisail_fvp_asset("{platform}" base archive hash)
message(STATUS "SELECTED=${{base}}/${{archive}};${{hash}}")
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                version = "0.40.1" if platform == "windows-arm64" else "0.39.0"
                self.assertIn(f"/download/v{version}/", result.stdout)
                asset = self.lock["assets"][platform]
                self.assertIn(f'{asset["archive"]};{asset["sha256"]}', result.stdout)

    def test_both_windows_architectures_stage_verified_bytes_under_fvp_alias(self):
        for architecture in ("arm64", "x64"):
            with self.subTest(architecture=architecture):
                data = f"new SDK {architecture}".encode()
                _, target = self.fixture_asset(architecture, data)
                result = self.stage(architecture)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(target.read_bytes(), data)
                url, sha = (self.root / "selected.txt").read_text().splitlines()
                self.assertEqual(url, f"file:///{target.parent.as_posix()}")
                self.assertEqual(sha, hashlib.sha256(data).hexdigest())

    def test_valid_cache_is_reused_without_downloading(self):
        archive, target = self.fixture_asset("arm64", b"SDK")
        target.parent.mkdir(parents=True)
        target.write_bytes(archive.read_bytes())
        archive.unlink()
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), b"SDK")

    def test_corrupt_cache_is_replaced(self):
        _, target = self.fixture_asset("arm64", b"SDK")
        target.parent.mkdir(parents=True)
        target.write_bytes(b"corrupt")
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), b"SDK")

    def test_sdk_upgrade_does_not_resume_an_older_partial_archive(self):
        _, old_target = self.fixture_asset("arm64", b"old SDK")
        old_target.parent.mkdir(parents=True)
        old_target.write_bytes(b"old SDK")
        old_target.with_suffix(".7z.part").write_bytes(b"old partial")
        _, new_target = self.fixture_asset("arm64", b"new SDK")
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(new_target.read_bytes(), b"new SDK")
        self.assertEqual(old_target.read_bytes(), b"old SDK")
        self.assertNotEqual(old_target.parent, new_target.parent)

    def test_download_hash_mismatch_is_rejected(self):
        archive, target = self.fixture_asset("arm64", b"SDK")
        archive.write_bytes(b"unexpected release")
        result = self.stage()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("SHA-256 does not match the lock", result.stderr)
        self.assertFalse(target.exists())

        # A rejected download must not poison subsequent configure attempts.
        archive.write_bytes(b"SDK")
        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), b"SDK")

    def test_corrupt_partial_download_is_discarded_after_hash_rejection(self):
        _, target = self.fixture_asset("arm64", b"SDK")
        target.parent.mkdir(parents=True)
        partial = target.with_suffix(".7z.part")
        partial.write_bytes(b"bad")

        result = self.stage()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("SHA-256 does not match the lock", result.stderr)
        self.assertFalse(partial.exists())

        result = self.stage()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), b"SDK")

    def test_invalid_hash_is_rejected_before_download(self):
        _, target = self.fixture_asset("arm64", b"SDK")
        self.lock["assets"]["windows-arm64"]["sha256"] = "bad"
        self.save_lock()
        result = self.stage()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Invalid pinned fvp SDK SHA-256", result.stderr)
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
