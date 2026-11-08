"""Offline regression for the build-local fvp Apple renderer and Podfile route."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("fvp_apple", ROOT / "tool/prepare-fvp-apple.py")
staging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(staging)


def package_root(name):
    override = os.environ.get("BILISAIL_MEDIA_TEST_SOURCE")
    if name == "media_kit_video" and override:
        return Path(override).resolve()
    config = ROOT / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    package = next(item for item in packages if item["name"] == name)
    return Path(url2pathname(urlparse(urljoin(config.as_uri(), package["rootUri"])).path))


class AppleTextureStagingTest(unittest.TestCase):
    def fixture(self, repo, platform):
        upstream = package_root("fvp")
        source = repo / "cache/fvp"
        (source / "darwin/Classes").mkdir(parents=True)
        (source / "lib/src").mkdir(parents=True)
        for path in ("darwin/Classes/FvpPlugin.mm", "darwin/fvp.podspec", "LICENSE", "pubspec.yaml"):
            shutil.copyfile(upstream / path, source / path)
        (source / "lib/src/version.h").write_text("#define FVP_VERSION 1\n", encoding="utf-8")
        (repo / "native/fvp/apple").mkdir(parents=True)
        shutil.copyfile(ROOT / "native/fvp/apple/metal_texture.inc", repo / "native/fvp/apple/metal_texture.inc")
        relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
        link = repo / platform / relative / "plugins/fvp"
        link.parent.mkdir(parents=True)
        link.symlink_to(source, target_is_directory=True)
        return source, link

    def test_both_platforms_keep_upstream_immutable_and_repeated_install_safe(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                repo = Path(directory).resolve()
                source, link = self.fixture(repo, platform)
                original = (source / "darwin/Classes/FvpPlugin.mm").read_bytes()
                destination = staging.prepare(repo, platform)
                patched = (destination / "darwin/Classes/FvpPlugin.mm").read_text(encoding="utf-8")
                self.assertIn('#include "metal_texture.inc"', patched)
                self.assertIn("++mtex_->revision", patched)
                self.assertIn("[mtex_ invalidate]", patched)
                self.assertIn("[mtex_ bindRegistry:texReg textureId:texId_]", patched)
                self.assertNotIn("return CVPixelBufferRetain(pixbuf)", patched)
                self.assertTrue((destination / "darwin/Classes/metal_texture.inc").is_file())
                self.assertTrue((destination / "lib/src/version.h").is_file())
                self.assertIn("*.{h,m,mm,c,cc,cpp}", (destination / "darwin/fvp.podspec").read_text())
                self.assertEqual(staging.prepare(repo, platform), destination)
                self.assertEqual(link.resolve(), destination)
                self.assertEqual((source / "darwin/Classes/FvpPlugin.mm").read_bytes(), original)

    def test_dependency_drift_is_rejected_before_repointing_or_deleting(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "ios")
            path = source / "darwin/Classes/FvpPlugin.mm"
            path.write_bytes(path.read_bytes() + b"\n// upstream drift\n")
            with self.assertRaisesRegex(RuntimeError, "changed source"):
                staging.prepare(repo, "ios")
            self.assertEqual(link.resolve(), source)
            self.assertFalse((repo / "build/apple-plugins").exists())

    def test_staging_refuses_a_destination_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            source, link = self.fixture(repo, "macos")
            outside = repo / "preserved"
            outside.mkdir()
            (outside / "sentinel").write_text("keep", encoding="utf-8")
            destination = repo / "build/apple-plugins/macos/fvp"
            destination.parent.mkdir(parents=True)
            destination.symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "Unsafe fvp staging"):
                staging.prepare(repo, "macos")
            self.assertEqual((outside / "sentinel").read_text(), "keep")
            self.assertEqual(link.resolve(), source)

    def test_staging_supports_macos_python39_path_api(self):
        original_write = Path.write_text

        # Python 3.9 does not accept Path.write_text(newline=...).
        def python39_write(path, data, encoding=None, errors=None):
            return original_write(path, data, encoding=encoding, errors=errors)

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory).resolve()
            self.fixture(repo, "macos")
            with patch.object(Path, "write_text", python39_write):
                destination = staging.prepare(repo, "macos")
            self.assertTrue((destination / "darwin/Classes/metal_texture.inc").is_file())

    def test_podfiles_stage_after_flutter_generates_the_symlinks(self):
        for platform in ("ios", "macos"):
            text = (ROOT / platform / "Podfile").read_text(encoding="utf-8")
            self.assertLess(text.index(f"flutter_install_all_{platform}_pods"),
                            text.index("prepare-fvp-apple.py"))
            self.assertIn(f"__dir__), '{platform}')", text)
            self.assertIn("raise 'Could not prepare", text)

    def test_apple_renderers_publish_new_buffers_after_completion(self):
        media = package_root("media_kit_video")
        for platform in ("macos", "ios"):
            text = (media / platform / "media_kit_video/Sources/media_kit_video/plugin/TextureHW.swift").read_text(encoding="utf-8")
            render = text[text.index("  public func render("):]
            self.assertNotIn("nextAvailable", render)
            self.assertLess(render.index("glFinish()"), render.index("frames.publish("))
            self.assertIn("let textureContext = Texture", render)
        software = (media / "common/darwin/Classes/plugin/TextureSW.swift").read_text(encoding="utf-8")
        render = software[software.index("  public func render("):]
        self.assertNotIn("nextAvailable", render)
        self.assertLess(render.index("CVPixelBufferUnlockBaseAddress"), render.index("frames.publish("))


if __name__ == "__main__":
    unittest.main()
