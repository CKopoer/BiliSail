"""Exercise the bundled AppImage output path without linuxdeploy or FUSE."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("linux-appimage.sh")


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux AppImage tooling")
class AppImageOutputTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="bilisail appimage ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.image = self.root / "verified image"
        self.appdir = self.root / "AppDir"
        self.appdir.mkdir()
        self.tools = self.root / "output tools"
        self.output = self.root / "result.AppImage"
        self.calls = self.root / "calls"
        self.image.write_text('''#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$CALLS"
[[ "$#" == 1 && "$1" == --appimage-extract ]] || exit 90
[[ "$SCENARIO" != extraction-failure ]] || exit 7
[[ "$SCENARIO" != missing-plugin ]] || exit 0
tools=squashfs-root/plugins/linuxdeploy-plugin-appimage/usr/bin
mkdir -p "$tools"
cat > "$tools/linuxdeploy-plugin-appimage" <<'PLUGIN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$CALLS"
[[ "$#" == 2 && "$1" == --appdir && "$2" == "$EXPECTED_APPDIR" ]] || exit 91
[[ "$SCENARIO" != plugin-failure ]] || exit 8
printf 'packaged fixture\\n' > "$LDAI_OUTPUT"
PLUGIN
printf '#!/bin/sh\\nexit 0\\n' > "$tools/appimagetool"
chmod +x "$tools/"*
''', encoding="utf-8")
        self.image.chmod(0o755)

    def run_output(self, scenario="success"):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; build_appimage_from_appdir "$2" "$3" "$4"',
             "appimage-test", str(SCRIPT), str(self.image), str(self.appdir), str(self.tools)],
            env=dict(os.environ, CALLS=str(self.calls), LDAI_OUTPUT=str(self.output),
                     SCENARIO=scenario, EXPECTED_APPDIR=str(self.appdir)),
            capture_output=True, text=True, timeout=10,
        )

    def test_calls_only_extraction_and_the_output_plugin(self):
        result = self.run_output()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "packaged fixture\n")
        self.assertEqual(self.calls.read_text().splitlines(),
                         ["--appimage-extract", f"--appdir {self.appdir}"])

    def test_extraction_failure_stops_before_packaging(self):
        result = self.run_output("extraction-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(self.calls.read_text().splitlines(), ["--appimage-extract"])

    def test_missing_bundled_plugin_is_rejected(self):
        result = self.run_output("missing-plugin")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing its AppImage output tools", result.stderr)
        self.assertFalse(self.output.exists())

    def test_plugin_failure_is_propagated(self):
        result = self.run_output("plugin-failure")
        self.assertEqual(result.returncode, 8, result.stderr)
        self.assertFalse(self.output.exists())

    def test_existing_tools_are_not_reused_or_overwritten(self):
        self.tools.mkdir()
        result = self.run_output()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
