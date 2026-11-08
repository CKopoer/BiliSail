"""Exercise application SDK verification with the pinned Windows manifests."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parent.parent
CONSUMER = ROOT / "windows/native/media-assets.cmake"


class WindowsMediaAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        config = ROOT / ".dart_tool/package_config.json"
        packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
        package = next(item for item in packages
                       if item["name"] == "media_kit_libs_windows_video")
        uri = urljoin(config.as_uri(), package["rootUri"])
        cls.owner = Path(url2pathname(urlparse(uri).path)) / "windows/native-assets.cmake"

    def configure(self, architecture: str, change: str = "") -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory(prefix="bilisail-media-") as directory:
            source = Path(directory)
            # Use the resolved dependency's filenames and verifier. Only replace
            # the hashes with those of disposable local files; no SDK download,
            # native compiler, or writes to the dependency are needed.
            script = r'''
cmake_minimum_required(VERSION 3.19)
project(media_asset_regression NONE)
set(FLUTTER_TARGET_PLATFORM "windows-@ARCH@")
include("@CONSUMER@")
set(owner "@OWNER@")
include("${owner}")
list(LENGTH MEDIA_KIT_MPV_FILES file_count)
list(LENGTH MEDIA_KIT_MPV_HASHES hash_count)
set(sdk "${CMAKE_CURRENT_SOURCE_DIR}/sdk")
math(EXPR last "${hash_count} - 1")
set(fixture_hashes "")
foreach(index RANGE 0 ${last})
  list(GET MEDIA_KIT_MPV_FILES ${index} name)
  get_filename_component(parent "${sdk}/${name}" DIRECTORY)
  file(MAKE_DIRECTORY "${parent}")
  file(WRITE "${sdk}/${name}" "fixture ${name}")
  file(SHA256 "${sdk}/${name}" hash)
  list(APPEND fixture_hashes "${hash}")
endforeach()
set(fixture_files "${MEDIA_KIT_MPV_FILES}")
@CHANGE@
set(fixture "${CMAKE_CURRENT_SOURCE_DIR}/manifest.cmake")
file(WRITE "${fixture}" "include(\"${owner}\")\nset(MEDIA_KIT_MPV_HASHES \"${fixture_hashes}\")\nset(MEDIA_KIT_MPV_FILES \"${fixture_files}\")\n")
function(bilisail_media_manifest output)
  set(${output} "${fixture}" PARENT_SCOPE)
endfunction()
add_library(media_kit_video_plugin INTERFACE)
set(MEDIA_KIT_MPV_SDK "${sdk}")
bilisail_verify_media_assets()
message(STATUS "Verified ${hash_count} ${FLUTTER_TARGET_PLATFORM} assets")
'''
            script = (script.replace("@ARCH@", architecture)
                      .replace("@CONSUMER@", CONSUMER.as_posix())
                      .replace("@OWNER@", self.owner.as_posix())
                      .replace("@CHANGE@", change))
            (source / "CMakeLists.txt").write_text(script, encoding="utf-8")
            return subprocess.run(
                ["cmake", "-S", str(source), "-B", str(source / "build")],
                capture_output=True, text=True, check=False, timeout=30,
            )

    def assert_rejected(self, architecture: str, change: str, reason: str) -> None:
        result = self.configure(architecture, change)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(reason, result.stderr)

    def test_pinned_arm64_manifest_verifies_its_six_sdk_files(self):
        result = self.configure("arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Verified 6 windows-arm64 assets", result.stdout)

    def test_pinned_x64_manifest_verifies_all_files(self):
        result = self.configure("x64")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_arm64_also_accepts_a_paired_file_list(self):
        result = self.configure("arm64", "list(SUBLIST fixture_files 0 6 fixture_files)")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_library_is_rejected_on_both_architectures(self):
        for architecture in ("x64", "arm64"):
            with self.subTest(architecture=architecture):
                self.assert_rejected(
                    architecture, 'file(REMOVE "${sdk}/libmpv-2.dll")',
                    "Missing media-kit native asset",
                )

    def test_each_sdk_file_is_checked_on_both_architectures(self):
        names = ("libmpv-2.dll", "libmpv.dll.a", "include/mpv/client.h",
                 "include/mpv/render.h", "include/mpv/render_gl.h",
                 "include/mpv/stream_cb.h")
        for architecture in ("x64", "arm64"):
            for name in names:
                with self.subTest(architecture=architecture, name=name):
                    self.assert_rejected(
                        architecture, f'file(APPEND "${{sdk}}/{name}" "changed")',
                        "media-kit native SHA-256 mismatch",
                    )

    def test_x64_provenance_is_still_checked(self):
        self.assert_rejected(
            "x64", 'file(APPEND "${sdk}/provenance/repack.json" "changed")',
            "media-kit native SHA-256 mismatch",
        )

    def test_unexpected_list_mismatches_are_rejected(self):
        for architecture in ("x64", "arm64"):
            for change in (
                "list(REMOVE_AT fixture_hashes 0)",
                "list(APPEND fixture_hashes invalid)",
                "set(fixture_files libmpv-2.dll)",
                "set(fixture_files)\nset(fixture_hashes)",
            ):
                with self.subTest(architecture=architecture, change=change):
                    self.assert_rejected(
                        architecture, change, "Invalid media-kit SDK manifest",
                    )


if __name__ == "__main__":
    unittest.main()
