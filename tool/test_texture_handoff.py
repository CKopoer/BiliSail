"""Verify the pinned fvp build-copy patch without building an application."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parent.parent
PATCH = ROOT / "windows/patches/fvp/apply.cmake"


class TextureHandoffPatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        config = ROOT / ".dart_tool/package_config.json"
        packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
        fvp = next(package for package in packages if package["name"] == "fvp")
        uri = urljoin(config.as_uri(), fvp["rootUri"])
        cls.source = Path(url2pathname(urlparse(uri).path)) / "windows"

    def prepare(self, source, output):
        return subprocess.run(
            ["cmake", f"-DBILISAIL_FVP_TEST_SOURCE={source}",
             f"-DBILISAIL_FVP_TEST_OUTPUT={output}", "-P", str(PATCH)],
            capture_output=True, text=True, check=False,
        )

    def test_verified_copy_replaces_only_the_renderer(self):
        original = (self.source / "fvp_plugin.cpp").read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.prepare(self.source, output)
            self.assertEqual(result.returncode, 0, result.stderr)
            patched = (output / "fvp_plugin.cpp").read_text(encoding="utf-8")
            self.assertIn('#include "texture_player.inc"', patched)
            self.assertIn('#include "d3d11_texture_snapshot.h"', patched)
            self.assertNotIn("ctx->CopyResource", patched)
            self.assertIn("texture_registrar_->UnregisterTexture(", patched)
            self.assertEqual(original, (self.source / "fvp_plugin.cpp").read_bytes())

    def test_changed_dependency_fails_before_producing_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            original = (self.source / "fvp_plugin.cpp").read_bytes()
            (source / "fvp_plugin.cpp").write_bytes(original + b"\n// drift\n")
            output = Path(directory) / "output"
            result = self.prepare(source, output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Review the fvp texture patch", result.stderr)
            self.assertFalse(output.exists())

    def test_lf_and_crlf_checkouts_produce_the_same_source(self):
        original = (self.source / "fvp_plugin.cpp").read_bytes().replace(b"\r\n", b"\n")
        with tempfile.TemporaryDirectory() as directory:
            results = []
            for name, data in [("lf", original), ("crlf", original.replace(b"\n", b"\r\n"))]:
                source = Path(directory) / name
                source.mkdir()
                (source / "fvp_plugin.cpp").write_bytes(data)
                output = source / "output"
                result = self.prepare(source, output)
                self.assertEqual(result.returncode, 0, result.stderr)
                results.append((output / "fvp_plugin.cpp").read_bytes())
            self.assertEqual(*results)


if __name__ == "__main__":
    unittest.main()
