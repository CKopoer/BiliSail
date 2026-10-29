"""Regression coverage for build-local CocoaPods staging."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "apple_media_kit", Path(__file__).with_name("prepare-media-kit-apple.py")
)
staging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(staging)


class AppleStagingTests(unittest.TestCase):
    def fixture(self, repo: Path, platform: str) -> tuple[Path, Path]:
        source = repo / "pub-cache/media_kit_video"
        (source / platform).mkdir(parents=True)
        (source / "common/mpv/include/mpv").mkdir(parents=True)
        (source / "common/mpv/include/mpv/client.h").write_text("int binding();")
        (source / "common/mpv/include/media_kit_mpv.h").write_text('#include "mpv/client.h"\n')
        (source / "common/mpv/media_kit_mpv.c").write_text("int binding() { return 0; }")
        (source / "common/plugin.swift").write_text("class Plugin {}")
        (source / platform / "plugin.swift").symlink_to(Path("../common/plugin.swift"))
        (source / "LICENSE").write_text("MIT")
        podspec = source / platform / "media_kit_video.podspec"
        podspec.write_text(
            "s.source_files = '../common/mpv/media_kit_mpv.c', '../common/mpv/include/**/*.h'\n"
            "s.header_mappings_dir = '../common/mpv/include'\n",
            encoding="utf-8",
        )
        relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
        link = repo / platform / relative / "plugins/media_kit_video"
        link.parent.mkdir(parents=True)
        link.symlink_to(source, target_is_directory=True)
        return source, link

    def test_both_platforms_stage_real_c_files_without_changing_pub_source(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory).resolve()
                source, link = self.fixture(repo, platform)
                original = (source / platform / "media_kit_video.podspec").read_text()
                checksum = staging.hashlib.sha256(original.encode()).hexdigest()
                with patch.dict(staging.PODSPEC_HASHES, {platform: checksum}):
                    destination = staging.prepare(repo, platform)
                    self.assertEqual(link.resolve(), destination)
                    podroot = destination / platform
                    self.assertTrue((podroot / "media_kit_mpv/media_kit_mpv.c").is_file())
                    self.assertTrue((podroot / "media_kit_mpv/include/media_kit_mpv.h").is_file())
                    self.assertTrue((podroot / "media_kit_mpv/include/client.h").is_file())
                    self.assertFalse((podroot / "media_kit_mpv/include/mpv").exists())
                    wrapper = (podroot / "media_kit_mpv/include/media_kit_mpv.h").read_text()
                    self.assertEqual(wrapper, '#include "client.h"\n')
                    self.assertEqual((podroot / "plugin.swift").read_text(), "class Plugin {}")
                    self.assertNotIn("../common/mpv", (podroot / "media_kit_video.podspec").read_text())
                    self.assertEqual((source / platform / "media_kit_video.podspec").read_text(), original)
                    # Repeated pod install starts from the original, not its patched copy.
                    self.assertEqual(staging.prepare(repo, platform), destination)
                    self.assertEqual(link.resolve(), destination)

    def test_changed_upstream_is_rejected_before_repointing_the_plugin(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            source, link = self.fixture(repo, "ios")
            with self.assertRaisesRegex(RuntimeError, "changed source"):
                staging.prepare(repo, "ios")
            self.assertEqual(link.resolve(), source.resolve())
            self.assertFalse((repo / "build/apple-plugins").exists())


if __name__ == "__main__":
    unittest.main()
