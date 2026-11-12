"""Check production bundle installation after a failed dependency configure."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux CMake install contract")
class LinuxCmakeInstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="bilisail bundle retry ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source/linux"
        self.build = self.root / "build"
        self.env = dict(os.environ)
        self.env.pop("CMAKE_INSTALL_PREFIX", None)
        self.env.pop("DESTDIR", None)
        self.write("linux/CMakeLists.txt", (ROOT / "linux/CMakeLists.txt").read_text())
        # Replace external dependencies, retaining the complete application
        # CMakeLists and its real configure/build/install behavior.
        self.write("linux/cmake/FindPkgConfig.cmake", """
set(PkgConfig_FOUND TRUE)
macro(pkg_check_modules)
endmacro()
""")
        self.write("linux/flutter/CMakeLists.txt", """
add_custom_target(flutter_assemble)
set(FLUTTER_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/libflutter_linux_gtk.so" PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_SOURCE_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${CMAKE_SOURCE_DIR}/assets/" PARENT_SCOPE)
""")
        self.write("linux/flutter/generated_plugins.cmake", """
if(NOT FIXTURE_DEPS_READY)
  message(FATAL_ERROR "Failed to download fixture dependency")
endif()
""")
        self.write("linux/runner/CMakeLists.txt", "add_executable(${BINARY_NAME} main.cc)\n")
        self.write("linux/runner/main.cc", "int main() { return 0; }\n")
        self.write("linux/flutter/libflutter_linux_gtk.so", "fixture library")
        self.write("linux/flutter/icudtl.dat", "fixture data")
        self.write("linux/assets/flutter_assets/AssetManifest.bin", "fixture assets")
        self.write("linux/assets/native_assets/linux/libfixture.so", "fixture native asset")

    def write(self, relative: str, content: str) -> None:
        destination = self.root / "source" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")

    def command(self, *arguments: str | Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["cmake", *map(str, arguments)], env=self.env,
            capture_output=True, text=True, check=False, timeout=60,
        )

    def configure(self, ready: bool, *arguments: str) -> subprocess.CompletedProcess[str]:
        return self.command(
            "-S", self.source, "-B", self.build,
            f"-DCMAKE_MODULE_PATH={self.source / 'cmake'}",
            "-DCMAKE_BUILD_TYPE=Debug",
            f"-DFIXTURE_DEPS_READY={'ON' if ready else 'OFF'}", *arguments,
        )

    def assert_installs_to(self, prefix: Path) -> None:
        cache = (self.build / "CMakeCache.txt").read_text(encoding="utf-8")
        self.assertIn(f"CMAKE_INSTALL_PREFIX:PATH={prefix}\n", cache)
        # Never run install if a regression would target a system directory.
        self.assertTrue(prefix.is_relative_to(self.root))
        result = self.command("--build", self.build, "--target", "install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for relative in ("bilisail", "lib/libflutter_linux_gtk.so", "data/icudtl.dat",
                         "lib/libfixture.so", "data/flutter_assets/AssetManifest.bin"):
            self.assertTrue((prefix / relative).is_file(), relative)

    def test_clean_configure_installs_in_build_bundle(self):
        result = self.configure(True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_installs_to(self.build / "bundle")

    def test_dependency_failure_then_retry_preserves_bundle_destination(self):
        failed = self.configure(False)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Failed to download fixture dependency", failed.stderr)
        recovered = self.configure(True)
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assert_installs_to(self.build / "bundle")
        repeated = self.configure(True)
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assert_installs_to(self.build / "bundle")

    def test_explicit_install_prefix_survives_dependency_retry(self):
        prefix = self.root / "custom install"
        failed = self.configure(False, f"-DCMAKE_INSTALL_PREFIX={prefix}")
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Failed to download fixture dependency", failed.stderr)
        recovered = self.configure(True)
        self.assertEqual(recovered.returncode, 0, recovered.stderr)
        self.assert_installs_to(prefix)


if __name__ == "__main__":
    unittest.main()
