"""Offline coverage for WebKitGTK subprocess deployment and relocation."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "linux_webview", Path(__file__).with_name("linux-webview.py")
)
webview = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(webview)


class WebKitDeploymentTests(unittest.TestCase):
    def test_stages_helpers_and_bundle_without_browser(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "system" / webview.WEBKIT_DIRECTORY
            for name in [*webview.REQUIRED_FILES, "WebKitGPUProcess", "MiniBrowser"]:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"ELF fixture")
            appdir = root / "app"
            webview.stage_webkit(appdir, root / "system")
            self.assertEqual(len(webview.validate_webkit(appdir)), 3)
            self.assertFalse((appdir / webview.WEBKIT_DIRECTORY / "MiniBrowser").exists())
            (appdir / webview.WEBKIT_DIRECTORY / "WebKitNetworkProcess").unlink()
            with self.assertRaisesRegex(RuntimeError, "Missing packaged"):
                webview.validate_webkit(appdir)

    def test_missing_source_fails_before_staging(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(RuntimeError, "Missing WebKitGTK"):
                webview.stage_webkit(Path(temporary) / "app", Path(temporary))

    def test_relocation_preserves_offsets_and_rejects_unknown_abi(self):
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / "libwebkit2gtk-4.1.so.0"
            original = b"ELF\0/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1\0tail"
            library.write_bytes(original)
            webview.relocate_webkit_library(library)
            result = library.read_bytes()
            self.assertEqual(len(result), len(original))
            self.assertIn(b"\0usr/lib/x86_64-linux-gnu/webkit2gtk-4.1\0\0tail", result)
            with self.assertRaisesRegex(RuntimeError, "Unexpected WebKitGTK"):
                webview.relocate_webkit_library(library)


if __name__ == "__main__":
    unittest.main()
