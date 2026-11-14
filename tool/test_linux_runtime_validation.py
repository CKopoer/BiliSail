"""Exercise the Runtime shell checker without installing Flatpak or Flutter."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("linux-runtime-validation.sh")


class RuntimeValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="runtime check ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.binary = self.root / "usr/bin/bilisail"
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b"\x7fELFfixture")
        self.library = self.root / "usr/bin/lib/libexample.so"
        self.library.parent.mkdir()
        self.library.write_bytes(b"\x7fELFfixture")
        webkit = self.root / "usr/lib/x86_64-linux-gnu/webkit2gtk-4.1"
        self.helpers = [webkit / "WebKitWebProcess", webkit / "WebKitNetworkProcess",
                        webkit / "injected-bundle/libwebkit2gtkinjectedbundle.so"]
        for helper in self.helpers:
            helper.parent.mkdir(parents=True, exist_ok=True)
            helper.write_bytes(b"\x7fELFfixture")
        commands = self.root / "commands"
        commands.mkdir()
        ldd = commands / "ldd"
        ldd.write_text('''#!/bin/sh
printf '%s\\n' "$1" >> "$CHECKED_FILES"
if [ "$1" = "$FAIL_BINARY" ]; then
  printf '%s\\n' "$LDD_MESSAGE" >&2
  exit "$LDD_STATUS"
fi
printf 'libc.so.6 => /usr/lib/libc.so.6\\n'
''')
        ldd.chmod(0o755)
        self.checked = self.root / "checked"
        self.env = dict(
            os.environ, PATH=f"{commands}:{os.environ['PATH']}",
            CHECKED_FILES=str(self.checked), FAIL_BINARY="", LDD_STATUS="0",
            LDD_MESSAGE="",
        )

    def check(self, binary=None, status=0, message=""):
        self.env.update(FAIL_BINARY=str(binary or ""), LDD_STATUS=str(status),
                        LDD_MESSAGE=message)
        return subprocess.run(
            ["sh", "-s", "--", str(self.root)], env=self.env,
            input=SCRIPT.read_text(), capture_output=True, text=True, timeout=10,
        )

    def test_checks_executable_and_libraries_with_spaces_in_paths(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(self.checked.read_text().splitlines()),
                         {str(self.binary), str(self.library), *map(str, self.helpers)})
        self.assertIn("checks passed", result.stdout)

    def test_nonzero_ldd_prints_captured_error_and_fails(self):
        result = self.check(self.library, 1, "loader diagnostic")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(self.library), result.stderr)
        self.assertIn("ldd exit 1", result.stderr)
        self.assertIn("loader diagnostic", result.stderr)
        self.assertNotIn("checks passed", result.stdout)

    def test_missing_webkit_helper_fails(self):
        self.helpers[0].unlink()
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing WebKitGTK component", result.stderr)

    def test_webkit_helper_dependencies_are_checked(self):
        result = self.check(self.helpers[1], 0, "libmissing.so => not found")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(self.helpers[1]), result.stderr)

    def test_non_elf_webkit_helper_is_rejected(self):
        self.helpers[0].write_text("corrupt helper")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Executable is not ELF", result.stderr)

    def test_missing_dependency_with_zero_ldd_status_still_fails(self):
        result = self.check(self.library, 0, "libmissing.so => not found")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("libmissing.so => not found", result.stderr)

    def test_main_executable_errors_are_visible(self):
        result = self.check(self.binary, 1, "executable loader failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(self.binary), result.stderr)
        self.assertIn("executable loader failure", result.stderr)
        self.assertIn(str(self.library), self.checked.read_text().splitlines())

    def test_missing_executable_fails(self):
        self.binary.unlink()
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing executable", result.stderr)

    def test_sound_schema_is_not_passed_to_ldd(self):
        schema = self.root / "usr/share/glib-2.0/schemas/org.gnome.desktop.sound.gschema.xml"
        schema.parent.mkdir(parents=True)
        schema.write_text("<schemalist/>")
        result = self.check(schema, 1, "not a dynamic executable")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(str(schema), self.checked.read_text().splitlines())

    def test_non_elf_executable_is_not_silently_skipped(self):
        self.binary.write_text("not an executable")
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Executable is not ELF", result.stderr)


if __name__ == "__main__":
    unittest.main()
