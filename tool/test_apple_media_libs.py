"""Offline regression for checked, build-local Apple framework preparation."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "apple_media_libs", ROOT / "tool/prepare-apple-media-libs.py"
)
staging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(staging)


class AppleLibraryStagingTests(unittest.TestCase):
    def fixture(self, repo, platform):
        package = f"media_kit_libs_{platform}_video"
        source = repo / "pub-cache" / package
        podroot = source / platform
        podroot.mkdir(parents=True)
        (source / "LICENSE").write_text("MIT", encoding="utf-8")
        (podroot / "Makefile").write_text("all:\n\tfalse\n", encoding="utf-8")
        (podroot / f"{package}.podspec").write_text('system("make")\n', encoding="utf-8")
        # Incomplete outputs in the Pub source must never be reused or modified.
        (podroot / "Frameworks").mkdir()
        (podroot / "Frameworks/sentinel").write_text("keep", encoding="utf-8")
        relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
        link = repo / platform / relative / "plugins" / package
        link.parent.mkdir(parents=True)
        link.symlink_to(source, target_is_directory=True)
        return source, link

    def build(self, command, *, cwd, check, timeout):
        self.assertEqual(command, ["make"])
        self.assertTrue(check)
        self.assertEqual(timeout, 600)
        self.assertIn("build/apple-plugins", cwd.as_posix())
        binary = cwd / f"Frameworks/.symlinks/mpv/{cwd.name}/Mpv.framework/Mpv"
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_bytes(b"controlled framework fixture")

    def test_both_platforms_verify_frameworks_without_writing_to_pub_cache(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory).resolve()
                source, link = self.fixture(repo, platform)
                with patch.object(staging.subprocess, "run", side_effect=self.build) as run:
                    destination = staging.prepare(repo, platform)
                    self.assertEqual(link.resolve(), destination)
                    self.assertFalse((destination / platform / "Frameworks/sentinel").exists())
                    self.assertEqual(staging.prepare(repo, platform), destination)
                    self.assertEqual(run.call_count, 2)
                self.assertEqual((source / platform / "Frameworks/sentinel").read_text(), "keep")
                self.assertFalse((source / platform / "Frameworks/.symlinks").exists())
                self.assertEqual((destination / "LICENSE").read_text(), "MIT")

    def test_make_failure_stops_before_cocoapods_can_continue_with_missing_mpv(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "ios")
            error = subprocess.CalledProcessError(2, ["make"])
            with patch.object(staging.subprocess, "run", side_effect=error):
                with self.assertRaises(subprocess.CalledProcessError):
                    staging.prepare(repo, "ios")
            self.assertEqual(link.resolve(), source)
            # A later attempt reuses its staging directory and can recover.
            with patch.object(staging.subprocess, "run", side_effect=self.build):
                self.assertEqual(staging.prepare(repo, "ios"), link.resolve())

    def test_missing_binary_is_rejected_even_when_make_exits_successfully(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "macos")
            with patch.object(staging.subprocess, "run"):
                with self.assertRaisesRegex(RuntimeError, "framework is missing"):
                    staging.prepare(repo, "macos")
            self.assertEqual(link.resolve(), source)

    @unittest.skipUnless(shutil.which("make"), "requires make")
    def test_real_make_failure_is_propagated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "ios")
            with self.assertRaises(subprocess.CalledProcessError):
                staging.prepare(repo, "ios")
            self.assertEqual(link.resolve(), source)

    @unittest.skipUnless(shutil.which("make"), "requires make")
    def test_real_make_and_framework_alias_are_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "ios")
            (source / "ios/Makefile").write_text(
                "all: Frameworks/.symlinks/mpv/ios/Mpv.framework/Mpv\n"
                "Frameworks/.symlinks/mpv/ios/Mpv.framework/Mpv:\n"
                "\tmkdir -p Frameworks/Mpv.xcframework/ios-arm64/Mpv.framework\n"
                "\techo fixture > Frameworks/Mpv.xcframework/ios-arm64/Mpv.framework/Mpv\n"
                "\tmkdir -p Frameworks/.symlinks/mpv\n"
                "\tln -s ../../Mpv.xcframework/ios-arm64 Frameworks/.symlinks/mpv/ios\n",
                encoding="utf-8",
            )
            destination = staging.prepare(repo, "ios")
            self.assertEqual(staging.prepare(repo, "ios"), destination)
            self.assertEqual(link.resolve(), destination)
            self.assertFalse((source / "ios/Frameworks/.symlinks").exists())

    def test_destination_symlink_cannot_redirect_staging_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "ios")
            destination = repo / "build/apple-plugins/ios" / source.name
            destination.parent.mkdir(parents=True)
            destination.symlink_to(source, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "Unsafe Apple library staging"):
                staging.prepare(repo, "ios")
            self.assertEqual(link.resolve(), source)

    def test_podfiles_check_frameworks_after_generating_plugin_symlinks(self):
        for platform in ("ios", "macos"):
            text = (ROOT / platform / "Podfile").read_text(encoding="utf-8")
            self.assertLess(text.index(f"flutter_install_all_{platform}_pods"),
                            text.index("prepare-apple-media-libs.py"))
            self.assertIn("raise 'Could not prepare the pinned mpv frameworks'", text)


if __name__ == "__main__":
    unittest.main()
