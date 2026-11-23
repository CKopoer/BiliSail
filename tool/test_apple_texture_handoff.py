"""Offline regression for media_kit Apple renderer handoff."""

import atexit
from functools import cache
import os
from pathlib import Path
import tempfile
import unittest

from media_kit_sources import ROOT, package_source, stage


@cache
def package_root(name):
    if override := os.environ.get("BILISAIL_MEDIA_TEST_SOURCE"):
        return Path(override).resolve(strict=True)
    temp = tempfile.TemporaryDirectory()
    atexit.register(temp.cleanup)
    destination = Path(temp.name) / name
    stage(package_source(name), destination, ["ios", "macos"])
    return destination


class AppleTextureStagingTest(unittest.TestCase):
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
