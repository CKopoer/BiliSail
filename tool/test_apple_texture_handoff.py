"""Offline regression for media_kit Apple renderer handoff."""

import json
import os
from pathlib import Path
import unittest
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parent.parent


def package_root(name):
    override = os.environ.get("BILISAIL_MEDIA_TEST_SOURCE")
    if name == "media_kit_video" and override:
        return Path(override).resolve()
    config = ROOT / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    package = next(item for item in packages if item["name"] == name)
    return Path(url2pathname(urlparse(urljoin(config.as_uri(), package["rootUri"])).path))


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
