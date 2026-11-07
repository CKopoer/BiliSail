"""Offline regressions for Linux dependency ownership and license collection."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "linux_package_validation", Path(__file__).with_name("linux-package-validation.py")
)
validation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validation)


class DistroOwnershipTests(unittest.TestCase):
    def find_packages(self, output: str, returncode: int = 0) -> list[str]:
        result = subprocess.CompletedProcess(
            ["dpkg-query"], returncode, stdout=output, stderr="query failed"
        )
        with patch.object(validation.subprocess, "run", return_value=result):
            return validation.find_distro_packages([Path("libvulkan.so.1")])

    def test_chrome_private_copy_is_not_a_distro_dependency(self):
        packages = self.find_packages(
            "google-chrome-stable: /opt/google/chrome/libvulkan.so.1\n"
            "libvulkan1:amd64: /usr/lib/x86_64-linux-gnu/libvulkan.so.1\n"
        )
        self.assertEqual(packages, ["libvulkan1:amd64"])

    def test_other_application_under_usr_lib_is_also_excluded(self):
        packages = self.find_packages(
            "chromium: /usr/lib/chromium/libvulkan.so.1\n"
            "libvulkan1:amd64: /lib/x86_64-linux-gnu/libvulkan.so.1\n"
        )
        self.assertEqual(packages, ["libvulkan1:amd64"])

    def test_nested_system_modules_and_multiple_owners_are_retained(self):
        packages = self.find_packages(
            "libvulkan1:amd64, vulkan-helper: /usr/lib/x86_64-linux-gnu/modules/libvulkan.so.1\n"
            "libvulkan1:amd64: /lib/x86_64-linux-gnu/libvulkan.so.1\n"
        )
        self.assertEqual(packages, ["libvulkan1:amd64", "vulkan-helper"])

    def test_unbundled_libraries_and_diversion_records_are_excluded(self):
        packages = self.find_packages(
            "unrelated: /usr/lib/x86_64-linux-gnu/libunrelated.so.1\n"
            "diversion by private-driver from: /usr/lib/x86_64-linux-gnu/libvulkan.so.1\n"
            "libvulkan1:amd64: /usr/lib/x86_64-linux-gnu/libvulkan.so.1\n"
        )
        self.assertEqual(packages, ["libvulkan1:amd64"])

    def test_no_system_owner_still_fails(self):
        with self.assertRaisesRegex(RuntimeError, "No distro dependency"):
            self.find_packages("chrome: /opt/google/chrome/libvulkan.so.1\n", 1)

    def test_query_errors_are_not_treated_as_missing_matches(self):
        with self.assertRaisesRegex(RuntimeError, "query failed"):
            self.find_packages("", 2)


class DistroNoticeTests(unittest.TestCase):
    def test_matching_system_notice_and_versions_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            docs = root / "docs"
            (docs / "libvulkan1").mkdir(parents=True)
            (docs / "libvulkan1/copyright").write_text("Vulkan license", encoding="utf-8")
            notices = root / "notices"
            with patch.object(validation, "run", return_value="libvulkan1:amd64\t1\tvulkan-loader\t1\n"):
                validation.write_distro_notices(["libvulkan1:amd64"], notices, docs)
            self.assertEqual(
                (notices / "libvulkan1_amd64.copyright").read_text(encoding="utf-8"),
                "Vulkan license",
            )
            self.assertIn("vulkan-loader", (notices / "packages.tsv").read_text(encoding="utf-8"))

    def test_missing_real_distro_license_is_still_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(validation, "run", return_value="libvulkan1:amd64\t1\tvulkan-loader\t1\n"):
                with self.assertRaisesRegex(RuntimeError, "Distro license text missing: libvulkan1"):
                    validation.write_distro_notices(
                        ["libvulkan1:amd64"], root / "notices", root / "docs"
                    )


class PackageValidationTests(unittest.TestCase):
    def validate(self, root: Path, dependencies: str = "", version: str = "1.2.1",
                 repository: str = "https://github.com/CKopoer/mpv"):
        binary = root / "usr/bin/bilisail"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"\x7fELFtest")
        library = root / "usr/lib/libmpv.so.2"
        library.parent.mkdir(parents=True)
        library.write_bytes(b"\x7fELFtest")
        metadata = root / "usr/bin/data/flutter_assets/version.json"
        metadata.parent.mkdir(parents=True)
        metadata.write_text(
            json.dumps({"version": version, "build_number": "3"}), encoding="utf-8"
        )
        source = root / "usr/bin/data/licenses/mpv/SOURCE.json"
        source.parent.mkdir(parents=True)
        source.write_text(json.dumps({"repository": repository}), encoding="utf-8")
        with (
            patch.object(validation.sys, "argv", ["validate", str(root), "1.2.1+3"]),
            patch.object(validation, "run", return_value=dependencies),
            patch.object(validation, "find_distro_packages", return_value=["libavcodec60"]),
            patch.object(validation, "write_distro_notices"),
        ):
            validation.main()

    def test_complete_package_with_matching_version_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.validate(root)
            notice = json.loads((root / "usr/share/doc/bilisail/native-mpv.json").read_text(encoding="utf-8"))
            self.assertEqual(notice["source"]["repository"], "https://github.com/CKopoer/mpv")
            self.assertEqual(len(notice["libraries"]), 1)

    def test_unmaintained_mpv_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "maintained personal fork"):
                self.validate(Path(directory), repository="https://example.test/mpv")

    def test_missing_runtime_dependency_still_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "Unresolved dependencies"):
                self.validate(Path(directory), dependencies="libmissing.so.1 => not found")

    def test_stale_application_version_still_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "Linux version metadata mismatch"):
                self.validate(Path(directory), version="1.2.0")

    def test_missing_mpv_still_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(validation.sys, "argv", ["validate", directory, "1.2.1+3"]):
                with self.assertRaisesRegex(RuntimeError, "must include.*libmpv"):
                    validation.main()


if __name__ == "__main__":
    unittest.main()
