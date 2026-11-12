"""Compile the locked iOS Swift renderer against fault-injecting graphics APIs.

This verifies production control flow and ARC, not Apple drivers or SDK imports.
Run with swiftc on PATH (or BILISAIL_SWIFTC) for the executable cases.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_apple_texture_handoff import ROOT, package_root


class IOSVideoOutputContractTest(unittest.TestCase):
    def test_per_frame_allocation_is_recoverable_and_corevideo_owns_textures(self):
        source = package_root("media_kit_video")
        gles = source / "ios/media_kit_video/Sources/media_kit_video/plugin/gles"
        helpers = (gles / "OpenGLESHelpers.swift").read_text(encoding="utf-8")
        frame = (gles / "TextureGLESContext.swift").read_text(encoding="utf-8")
        self.assertIn("kCVPixelBufferIOSurfacePropertiesKey", helpers)
        self.assertIn("kCVPixelBufferOpenGLESCompatibilityKey", helpers)
        self.assertNotIn("glDeleteTextures(", helpers)
        self.assertNotIn("exit(1)", frame)
        self.assertIn("init?(", frame)


class IOSVideoOutputExecutionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = os.environ.get("BILISAIL_SWIFTC") or shutil.which("swiftc")
        if not compiler:
            raise unittest.SkipTest("swiftc unavailable; iOS Swift fault injection not executed")
        source = package_root("media_kit_video")
        plugin = source / "ios/media_kit_video/Sources/media_kit_video/plugin"
        common = source / "common/darwin/Classes/plugin"
        paths = [
            common / "SwappableObjectManager.swift",
            plugin / "gles/OpenGLESHelpers.swift",
            plugin / "gles/TextureGLESContext.swift",
            plugin / "TextureHW.swift",
            common / "TextureSWContext.swift",
            common / "TextureSW.swift",
        ]
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        output = Path(cls.directory.name)
        # Only unavailable imports are removed. The complete production classes,
        # including render(), allocation, failure branches and deinit, execute.
        cls.production = "\n".join(
            "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                      if not line.strip().startswith("import "))
            for path in paths
        )
        cls.harness = (ROOT / "tool/native_tests/ios_video_output_test.swift").read_text(encoding="utf-8")
        cls.compiler = compiler
        combined = output / "main.swift"
        combined.write_text(cls.harness.replace("// PRODUCTION_CLASSES", cls.production), encoding="utf-8")
        cls.executable = output / ("ios_video_output.exe" if os.name == "nt" else "ios_video_output")
        result = subprocess.run(
            [compiler, "-swift-version", "5", "-O", str(combined), "-o", str(cls.executable)],
            capture_output=True, text=True, timeout=120,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def run_case(self, name):
        result = subprocess.run([str(self.executable), name], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_thousands_of_frames_keep_retained_images_and_release_gl_resources(self):
        self.run_case("frames")

    def test_pixel_buffer_allocation_failure_keeps_the_previous_frame_and_recovers(self):
        self.run_case("pixel")

    def test_texture_creation_failure_keeps_the_previous_frame_and_recovers(self):
        self.run_case("texture")

    def test_incomplete_framebuffer_keeps_the_previous_frame_and_recovers(self):
        self.run_case("framebuffer")

    def test_invalid_dimensions_do_not_allocate_or_trap(self):
        self.run_case("dimensions")

    def test_context_activation_failure_keeps_the_previous_frame_and_recovers(self):
        self.run_case("context")

    def test_mpv_render_failure_does_not_publish_an_incomplete_frame(self):
        self.run_case("render")

    def test_explicit_dispose_frees_the_context_while_a_frame_is_retained(self):
        self.run_case("dispose")

    def test_native_callbacks_do_not_accumulate_on_the_platform_queue(self):
        self.run_case("callbacks")

    def test_software_context_has_the_same_explicit_disposal_contract(self):
        self.run_case("software")

    def test_software_allocation_failure_keeps_a_complete_frame(self):
        self.run_case("software-pixel")

    def test_software_render_failure_keeps_a_complete_frame(self):
        self.run_case("software-render")

    def test_mpv_parameters_typecheck_with_real_c_headers(self):
        headers = os.environ.get("BILISAIL_MPV_HEADERS")
        if not headers:
            self.skipTest("Set BILISAIL_MPV_HEADERS to the verified mpv header directory")
        # Keep only graphics substitutes, then import mpv's real C declarations.
        # This catches mistakes hidden by the executable mock's Swift signatures.
        graphics = self.harness[:self.harness.index('let MPV_RENDER_API_TYPE_OPENGL =')]
        source = Path(self.directory.name) / "c_abi.swift"
        source.write_text(
            graphics + "\nenum MPVHelpers { static func checkError(_ status: CInt) {} }\n" + self.production,
            encoding="utf-8",
        )
        result = subprocess.run(
            [self.compiler, "-swift-version", "5", "-typecheck", "-I", headers,
             "-import-objc-header", str(Path(headers) / "mpv/render_gl.h"), str(source)],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
