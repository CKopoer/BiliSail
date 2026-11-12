"""Execute the production Apple worker/output lifecycle with controlled render stalls."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_apple_texture_handoff import ROOT, package_root


class AppleVideoLifecycleContractTest(unittest.TestCase):
    def test_channel_reply_waits_for_explicit_native_output_disposal(self):
        common = package_root("media_kit_video") / "common/darwin/Classes/plugin"
        plugin = (common / "MediaKitVideoPlugin.swift").read_text(encoding="utf-8")
        handler = plugin[plugin.index("  private func handleDisposeMethodCall("):]
        handler = handler[:handler.index("  private func handleEnterNativeFullscreenMethodCall(")]
        self.assertIn("completion:", handler)
        protocol = (common / "ResizableTextureProtocol.swift").read_text(encoding="utf-8")
        self.assertIn("func dispose()", protocol)


class AppleVideoLifecycleExecutionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = os.environ.get("BILISAIL_SWIFTC") or shutil.which("swiftc")
        if not compiler:
            raise unittest.SkipTest("swiftc unavailable; native lifecycle execution not run")
        common = package_root("media_kit_video") / "common/darwin/Classes/plugin"
        paths = [common / name for name in (
            "Worker.swift", "VideoOutputConfiguration.swift", "ResizableTextureProtocol.swift",
            "SafeResizableTexture.swift", "VideoOutput.swift", "VideoOutputManager.swift",
            "UtilsProtocol.swift", "MediaKitVideoPlugin.swift",
        )]
        production = "\n".join(
            "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                      if not line.strip().startswith("import "))
            for path in paths
        )
        # Select the actual iOS registrar branch while using stand-in Flutter
        # declarations. The real MethodChannel handler is compiled and run.
        production = production.replace("#if canImport(Flutter)", "#if true")
        fixture = (ROOT / "tool/native_tests/apple_video_lifecycle_test.swift").read_text(encoding="utf-8")
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        source = Path(cls.directory.name) / "main.swift"
        source.write_text(fixture.replace("// PRODUCTION_CLASSES", production), encoding="utf-8")
        cls.executable = Path(cls.directory.name) / ("lifecycle.exe" if os.name == "nt" else "lifecycle")
        result = subprocess.run(
            [compiler, "-swift-version", "5", "-O", str(source), "-o", str(cls.executable)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_case(self, scenario):
        result = subprocess.run([str(self.executable), scenario], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_dispose_waits_for_an_inflight_render(self):
        self.run_case("barrier")

    def test_flutter_retention_does_not_keep_the_mpv_context_alive_after_dispose(self):
        self.run_case("retained")

    def test_ten_thousand_updates_coalesce_while_the_renderer_is_busy(self):
        self.run_case("coalesce")

    def test_repeated_dispose_and_late_updates_are_safe(self):
        self.run_case("repeat")

    def test_close_during_texture_initialization_waits_and_prevents_registration(self):
        self.run_case("initialize")

    def test_the_caller_can_free_mpv_immediately_after_the_disposal_reply(self):
        self.run_case("native-free")


if __name__ == "__main__":
    unittest.main()
