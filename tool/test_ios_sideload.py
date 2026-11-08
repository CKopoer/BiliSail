"""Cover re-signing inputs, native failures, and the actual IPA boundary."""

import importlib.util
import io
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "ios_sideload", Path(__file__).with_name("ios-sideload.py")
)
sideload = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sideload)


def macho(signed=True, cpu=0x0100000C):
    command = struct.pack("<4I", 0x1D, 16, 48, 12) if signed else b""
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 6, int(signed), len(command), 0, 0)
    return header + command + (struct.pack(">3I", 0xFADE0CC0, 12, 0) if signed else b"")


def fat():
    # The released 1.2.8 Avutil has exactly one unsigned arm64 slice at 0x8000.
    thin = macho(False)
    header = struct.pack(">7I", 0xCAFEBABE, 1, 0x0100000C, 0, 32768, len(thin), 15)
    return header.ljust(32768, b"\0") + thin


class IosSideloadTests(unittest.TestCase):
    def check(self, data):
        sideload.validate_macho(io.BytesIO(data), len(data), "Avutil")

    def fixture(self, directory):
        app = Path(directory) / "Payload/Runner.app"
        framework = app / "Frameworks/Avutil.framework"
        framework.mkdir(parents=True)
        for bundle, name in ((app, "Runner"), (framework, "Avutil")):
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": name}))
            (bundle / name).write_bytes(macho(False) if bundle == app else fat())
        (app / "resource.txt").write_bytes(b"keep this resource")
        dylib = app / "Frameworks/extra.dylib"
        dylib.write_bytes(macho(False))
        return app, framework, dylib

    def test_single_slice_fat_and_unsigned_thin_are_rejected(self):
        self.check(macho())
        for data, error in ((fat(), "thin arm64"), (macho(False), "LC_CODE_SIGNATURE"),
                            (macho(cpu=0x01000007), "arm64 executable")):
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                self.check(data)

    def test_malformed_headers_and_signature_ranges_are_rejected(self):
        valid = macho()
        for data in (valid[:24], valid[:40], valid[:-1],
                     valid[:36] + struct.pack("<I", 0) + valid[40:],
                     valid[:40] + struct.pack("<I", 0xFFFFFFFF) + valid[44:],
                     valid[:48] + b"bad signature"):
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.check(data)

    def test_staging_thins_before_signing_and_seals_app_last(self):
        with tempfile.TemporaryDirectory() as directory:
            app, framework, dylib = self.fixture(directory)
            calls = []

            def native(*args):
                calls.append(args)
                if args[0] == "lipo":
                    self.assertEqual(args[2:5], ("-thin", "arm64", "-output"))
                    Path(args[-1]).write_bytes(macho(False))
                elif "--sign" in args:
                    target = Path(args[-1])
                    binary = sideload.bundle_executable(target) if target.is_dir() else target
                    self.assertEqual(binary.read_bytes()[:4], sideload.THIN_ARM64)
                    binary.write_bytes(macho())

            with patch.object(sideload, "run", side_effect=native):
                sideload.prepare(app)
            self.assertEqual(calls[0][0], "lipo")
            self.assertEqual(calls[-2][-1], str(app.resolve()))
            self.assertEqual(
                calls[-1], ("codesign", "--verify", "--deep", "--strict", str(app.resolve())),
            )
            self.assertIn(str(framework.resolve()), [call[-1] for call in calls])
            self.assertIn(str(dylib.resolve()), [call[-1] for call in calls])
            self.assertEqual((app / "resource.txt").read_bytes(), b"keep this resource")
            self.assertEqual(list(app.rglob("*.thin")), [])
            package = Path(directory) / "test.ipa"
            with zipfile.ZipFile(package, "w") as archive:
                for path in app.rglob("*"):
                    if path.is_file():
                        archive.write(path, path.relative_to(directory).as_posix())
            sideload.validate_ipa(package)
            # Validate the ZIP contents, even if the staged .app was correct.
            with zipfile.ZipFile(package, "a") as archive:
                archive.writestr("Payload/Runner.app/Frameworks/late.dylib", fat())
            with self.assertRaisesRegex(ValueError, "late.dylib.*thin arm64"):
                sideload.validate_ipa(package)

    def test_native_failures_and_noop_signing_stop_packaging(self):
        for failed_command in ("lipo", "codesign", "verify", "noop"):
            with self.subTest(command=failed_command), tempfile.TemporaryDirectory() as directory:
                app, _, _ = self.fixture(directory)

                def native(*args):
                    if args[0] == failed_command or (
                        failed_command == "verify" and "--verify" in args
                    ):
                        raise subprocess.CalledProcessError(1, args)
                    if args[0] == "lipo":
                        Path(args[-1]).write_bytes(macho(False))
                    elif "--sign" in args and failed_command != "noop":
                        target = Path(args[-1])
                        binary = sideload.bundle_executable(target) if target.is_dir() else target
                        binary.write_bytes(macho())

                with patch.object(sideload, "run", side_effect=native):
                    with self.assertRaises((subprocess.CalledProcessError, ValueError)):
                        sideload.prepare(app)
                self.assertEqual(list(app.rglob("*.thin")), [])

    def test_bad_thinning_does_not_replace_the_original_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            app, framework, _ = self.fixture(directory)

            def wrong_architecture(*args):
                self.assertEqual(args[0], "lipo")
                Path(args[-1]).write_bytes(macho(cpu=0x01000007))

            with patch.object(sideload, "run", side_effect=wrong_architecture):
                with self.assertRaisesRegex(ValueError, "arm64 executable"):
                    sideload.prepare(app)
            self.assertEqual((framework / "Avutil").read_bytes(), fat())
            self.assertEqual(list(app.rglob("*.thin")), [])

    def test_ipa_requires_the_main_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / "test.ipa"
            with zipfile.ZipFile(package, "w") as archive:
                archive.writestr(
                    "Payload/Runner.app/Info.plist",
                    plistlib.dumps({"CFBundleExecutable": "Runner"}),
                )
                archive.writestr("Payload/Runner.app/Frameworks/Avutil.framework/Avutil", macho())
            with self.assertRaisesRegex(ValueError, "missing.*executable"):
                sideload.validate_ipa(package)


if __name__ == "__main__":
    unittest.main()
