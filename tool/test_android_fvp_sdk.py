import hashlib
import json
from pathlib import Path
import tempfile
import struct
import unittest
import zipfile

from verify_android_fvp_sdk import load_image_sha256, verify


def elf(payload=b"native code", debug=True):
    length = 120 + len(payload)
    data = bytearray(length)
    data[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HHIQQQIHHHHHH", data, 16, 3, 183, 1, 0, 64,
                     length if debug else 0, 0, 64, 56, 1, 64 if debug else 0,
                     1 if debug else 0, 0)
    struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, 0, 0, length, length, 4096)
    data[120:] = payload
    return bytes(data) + (bytes(64) if debug else b"")


class AndroidFvpSdkTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sdk = self.root / "fvp/android/mdk-sdk"
        self.library = elf()
        self.sdk.joinpath("lib/arm64-v8a").mkdir(parents=True)
        self.sdk.joinpath("lib/arm64-v8a/libmdk.so").write_bytes(self.library)
        archive = self.root / "fvp/android/mdk-sdk-android.7z"
        archive.write_bytes(b"verified SDK archive fixture")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.sdk.joinpath(".fvp-deps.sha256").write_text(digest)
        self.root.joinpath("native/fvp").mkdir(parents=True)
        self.root.joinpath("native/fvp/assets.lock.json").write_text(json.dumps({
            "version": "0.39.0",
            "assets": {"android": {"archive": archive.name, "sha256": digest}},
        }))
        self.root.joinpath(".dart_tool").mkdir()
        self.root.joinpath(".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": "fvp", "rootUri": "../fvp"}],
        }))
        self.apk = self.root / "test.apk"
        self.write_apk(self.library)

    def write_apk(self, library):
        with zipfile.ZipFile(self.apk, "w") as archive:
            if library is not None:
                archive.writestr("lib/arm64-v8a/libmdk.so", library)

    def test_matching_archive_sdk_and_apk(self):
        result = verify(self.apk, self.root)
        self.assertEqual(result["libraries"]["arm64-v8a"]["sha256"], hashlib.sha256(self.library).hexdigest())

    def test_android_debug_stripping_is_allowed(self):
        self.write_apk(elf(debug=False))
        verify(self.apk, self.root)

    def test_changed_executable_code_is_rejected(self):
        self.write_apk(elf(b"other code", debug=False))
        with self.assertRaisesRegex(ValueError, "stale or different"):
            verify(self.apk, self.root)

    def test_invalid_elf_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "ELF"):
            load_image_sha256(b"not an ELF library")

    def test_unpinned_cache_is_rejected(self):
        self.sdk.joinpath(".fvp-deps.sha256").write_text("0" * 64)
        with self.assertRaisesRegex(ValueError, "does not match"):
            verify(self.apk, self.root)

    def test_changed_archive_is_rejected(self):
        self.root.joinpath("fvp/android/mdk-sdk-android.7z").write_bytes(b"other release")
        with self.assertRaisesRegex(ValueError, "does not match"):
            verify(self.apk, self.root)

    def test_stale_packaged_library_is_rejected(self):
        self.write_apk(elf(b"previous native build"))
        with self.assertRaisesRegex(ValueError, "stale or different"):
            verify(self.apk, self.root)

    def test_missing_library_is_rejected(self):
        self.write_apk(None)
        with self.assertRaisesRegex(ValueError, "no MDK"):
            verify(self.apk, self.root)


if __name__ == "__main__":
    unittest.main()
