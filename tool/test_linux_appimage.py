"""Exercise the Linux GTK launcher and the bundled AppImage output path."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("linux-appimage.sh")
PACKAGING = SCRIPT.parents[1] / "linux" / "packaging"


class DisplayBackendTests(unittest.TestCase):
    def test_flatpak_exposes_wayland_with_x11_fallback(self):
        manifest = json.loads((PACKAGING / "dev.bilisail.bilisail.json").read_text())
        args = manifest["finish-args"]
        self.assertIn("--socket=wayland", args)
        self.assertIn("--socket=fallback-x11", args)
        self.assertNotIn("--socket=x11", args)
        self.assertFalse(any(arg.startswith("--env=GDK_BACKEND=") for arg in args))

    @unittest.skipUnless(sys.platform.startswith("linux"), "Flatpak launcher")
    def test_flatpak_cursor_search_preserves_overrides_and_finds_host_themes(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            launcher = (PACKAGING / "flatpak-launcher").read_text()
            # Redirect only the final exec from the sandbox to the test AppRun.
            launcher = launcher.replace("exec /app/AppRun", 'exec "$TEST_APPRUN"')
            program = app / "AppRun"
            program.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$XCURSOR_PATH" "$XCURSOR_THEME" "$XCURSOR_SIZE" "$@"\n'
            )
            program.chmod(0o755)
            for override in (None, "/custom cursors:/other"):
                with self.subTest(override=override):
                    env = dict(os.environ, TEST_APPRUN=str(program), HOME="/home/test",
                               XDG_DATA_HOME="/sandbox/data", XCURSOR_THEME="Breeze", XCURSOR_SIZE="48")
                    env.pop("XCURSOR_PATH", None)
                    if override:
                        env["XCURSOR_PATH"] = override
                    path, theme, size, arg = subprocess.check_output(
                        ["sh", "-c", launcher, "bilisail", "one argument"], env=env, text=True,
                    ).splitlines()
                    expected = (override.split(":") if override else []) + [
                        "/run/host/user-share/icons", "/run/host/share/icons",
                        "/sandbox/data/icons", "/home/test/.icons", "/app/share/icons",
                        "/usr/share/icons", "/usr/share/pixmaps",
                    ]
                    self.assertEqual(path.split(":"), expected)
                    self.assertEqual((theme, size, arg), ("Breeze", "48", "one argument"))

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux GTK launcher")
    def test_apprun_finds_host_cursor_themes_before_gtk_hook(self):
        with tempfile.TemporaryDirectory(prefix="bilisail cursors ") as temp:
            root = Path(temp)
            launcher = root / "AppRun"
            shutil.copyfile(PACKAGING / "AppRun", launcher)
            hooks = root / "apprun-hooks"
            hooks.mkdir()
            (hooks / "gtk.sh").write_text('export XDG_DATA_DIRS="$APPDIR/usr/share:/usr/share"\n')
            program = root / "usr/bin/bilisail"
            program.parent.mkdir(parents=True)
            program.write_text('#!/bin/sh\nprintf "%s\\n" "$XCURSOR_PATH" "$XCURSOR_THEME" "$XCURSOR_SIZE"\n')
            program.chmod(0o755)
            defaults = "/home/test/.local/share/icons:/home/test/.icons:/usr/local/share/icons:/usr/share/icons"
            legacy = ":/usr/share/pixmaps:/home/test/.cursors:/usr/share/cursors/xorg-x11"
            for home, dirs, override, expected in [
                ("", "", "", defaults + legacy),
                ("relative", "", "", defaults + legacy),
                ("/user data/", "/nix/profile/share::relative:/usr/share/:/nix/profile/share", "",
                 "/user data/icons:/home/test/.icons:/nix/profile/share/icons:/usr/share/icons" + legacy),
                ("", "/extra", "/custom icons:/run/host/share/icons", "/custom icons:/run/host/share/icons"),
            ]:
                with self.subTest(home=home, dirs=dirs, override=override):
                    env = dict(os.environ, HOME="/home/test", XDG_DATA_HOME=home,
                               XDG_DATA_DIRS=dirs, XCURSOR_PATH=override, XCURSOR_THEME="Breeze", XCURSOR_SIZE="48")
                    result = subprocess.check_output(["bash", launcher], env=env, text=True)
                    self.assertEqual(result.splitlines(), [expected, "Breeze", "48"])

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux GTK launcher")
    def test_gtk_hook_preserves_backend_selection(self):
        with tempfile.TemporaryDirectory(prefix="bilisail display ") as temp:
            root = Path(temp)
            launcher = root / "AppRun"
            shutil.copyfile(PACKAGING / "AppRun", launcher)
            hooks = root / "apprun-hooks"
            hooks.mkdir()
            (hooks / "gtk.sh").write_text("export GDK_BACKEND=x11\nexport GTK_DATA_PREFIX=test\n")
            program = root / "usr/bin/bilisail"
            program.parent.mkdir(parents=True)
            program.write_text('#!/bin/sh\nprintf "%s\\n" "$GDK_BACKEND" "$GTK_DATA_PREFIX" "$@"\n')
            program.chmod(0o755)
            for backend in (None, "x11", "wayland"):
                with self.subTest(backend=backend):
                    env = os.environ.copy()
                    env.pop("GDK_BACKEND", None)
                    if backend:
                        env["GDK_BACKEND"] = backend
                    result = subprocess.check_output(
                        ["bash", launcher, "one argument"], env=env, text=True,
                    )
                    self.assertEqual(
                        result.splitlines(), [backend or "wayland,x11", "test", "one argument"]
                    )


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
