"""Offline wiring checks; AppKit behavior lives in RunnerTests, not these checks."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent.parent


class MacOSImagePickerWiringTest(unittest.TestCase):
    def test_picker_is_compiled_into_the_runner_target(self):
        project = (ROOT / "macos/Runner.xcodeproj/project.pbxproj").read_text(
            encoding="utf-8"
        )
        source = ROOT / "macos/Runner/ImagePicker.swift"
        self.assertTrue(source.is_file())
        build_file = re.search(
            r"([A-F0-9]{24}) /\* ImagePicker.swift in Sources \*/ = "
            r"\{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})",
            project,
        )
        self.assertIsNotNone(build_file)
        build_id, file_id = build_file.groups()
        self.assertRegex(
            project,
            rf"{file_id} /\* ImagePicker.swift \*/ = "
            r"\{isa = PBXFileReference;[^\n]+path = ImagePicker.swift;",
        )
        target = re.search(
            r"33CC10E92044A3C60003C045 /\* Sources \*/ = \{(.*?)\n\t\t\};",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(target)
        self.assertIn(f"{build_id} /* ImagePicker.swift in Sources */", target.group(1))

    def test_channel_uses_engine_scoped_view_and_retires_before_engine(self):
        application = (ROOT / "macos/Runner/MainFlutterWindow.swift").read_text(
            encoding="utf-8"
        )
        registration = application.split(
            "imagePickerChannel = ImagePickerChannel", 1
        )[1].split("desktopWindows =", 1)[0]
        self.assertIn("controller.engine === self.engine", registration)
        self.assertIn("controller.viewIdentifier == viewID", registration)
        self.assertNotIn("NSApp.keyWindow", registration)
        self.assertNotIn("engine.viewController", registration)
        shutdown = application.split("  func shutDown() {", 1)[1].split("\n  }", 1)[0]
        self.assertLess(
            shutdown.index("imagePickerChannel?.shutDown()"),
            shutdown.index("engine.shutDownEngine()"),
        )


if __name__ == "__main__":
    unittest.main()
