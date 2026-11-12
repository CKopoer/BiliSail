"""Controlled native tests; no Flutter app, GPU driver or Apple SDK is required."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_apple_texture_handoff import ROOT, package_root


def function_body(path, signature):
    text = path.read_text(encoding="utf-8")
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end] + "\n"


class NativeTextureHandoffTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = shutil.which("clang++") or shutil.which("g++")
        if not cls.compiler:
            raise unittest.SkipTest("C++ compiler unavailable for controlled native tests")
        cls.media = package_root("media_kit_video")

    def linux_case(self, mutation=None):
        source = self.media / "linux"
        gl = function_body(source / "texture_gl.cc", "gboolean texture_gl_populate_texture(")
        if mutation == "consumer":
            gl = gl.replace("glFinish();", "glFlush();", 1)
        if mutation == "producer":
            index = gl.rindex("glFinish();")
            gl = gl[:index] + gl[index:].replace("glFinish();", "glFlush();", 1)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "linux_texture_gl_body.inc").write_text(gl, encoding="utf-8")
            (output / "linux_video_copy_body.inc").write_text(function_body(
                source / "video_output.cc", "gboolean video_output_copy_pixel_buffer("), encoding="utf-8")
            (output / "linux_texture_sw_body.inc").write_text(function_body(
                source / "texture_sw.cc", "gboolean texture_sw_copy_pixels("), encoding="utf-8")
            executable = output / "linux_texture_handoff.exe"
            compiled = subprocess.run([
                self.compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
                "-I", str(output), str(ROOT / "tool/native_tests/linux_texture_handoff_test.cpp"),
                "-o", str(executable),
            ], capture_output=True, text=True, timeout=45)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            return subprocess.run([str(executable)], capture_output=True, text=True, timeout=15)

    def test_linux_actual_methods_keep_delayed_reads_and_pixel_copies_complete(self):
        result = self.linux_case()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_consumer_completion_is_detected(self):
        result = self.linux_case("consumer")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Delayed Flutter read", result.stderr)

    def test_missing_producer_completion_is_detected(self):
        result = self.linux_case("producer")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Published before producer GPU completion", result.stderr)



if __name__ == "__main__":
    unittest.main()
