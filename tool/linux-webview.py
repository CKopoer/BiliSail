"""Stage WebKitGTK's out-of-process executables alongside its shared library."""

from pathlib import Path
import hashlib
import json
import shutil
import sys


WEBKIT_DIRECTORY = Path("usr/lib/x86_64-linux-gnu/webkit2gtk-4.1")
REQUIRED_FILES = (
    "WebKitWebProcess",
    "WebKitNetworkProcess",
    "injected-bundle/libwebkit2gtkinjectedbundle.so",
)


def relocate_webkit_library(library: Path, notices: Path | None = None) -> None:
    # Release WebKitGTK ignores WEBKIT_EXEC_PATH (developer builds alone use
    # it). Its helper prefix is a NUL-terminated compile-time string. Retain ELF
    # offsets while making that prefix relative to AppRun's working directory.
    # The injected bundle has its own supported absolute environment override.
    original = b"/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1\0"
    relocated = b"usr/lib/x86_64-linux-gnu/webkit2gtk-4.1\0\0"
    content = library.read_bytes()
    if content.count(original) != 1:
        raise RuntimeError("Unexpected WebKitGTK helper prefix; review distro ABI")
    library.write_bytes(content.replace(original, relocated))
    if notices is None:
        return
    notices.mkdir(parents=True, exist_ok=True)
    (notices / "webkitgtk-relocation.json").write_text(json.dumps({
        "library": library.name,
        "originalSha256": hashlib.sha256(content).hexdigest(),
        "packagedSha256": hashlib.sha256(library.read_bytes()).hexdigest(),
        "change": "Replace the single NUL-terminated helper prefix with an equal-size relative prefix",
        "sourcePackages": "dependencies/packages.tsv",
        "rebuild": "Fetch the recorded Ubuntu source version and apply linux-webview.py after deployment",
    }, indent=2) + "\n", encoding="utf-8")
    shutil.copy2(Path(__file__), notices / "linux-webview.py")


def stage_webkit(appdir: Path, system_root: Path = Path("/")) -> None:
    source = system_root / WEBKIT_DIRECTORY
    for name in REQUIRED_FILES:
        if not (source / name).is_file():
            raise RuntimeError(f"Missing WebKitGTK runtime component: {name}")
    # Keep the distro layout; do not copy MiniBrowser or developer utilities.
    destination = appdir / WEBKIT_DIRECTORY
    destination.mkdir(parents=True, exist_ok=True)
    for process in source.glob("WebKit*Process"):
        shutil.copy2(process, destination / process.name)
    shutil.copytree(source / "injected-bundle", destination / "injected-bundle")


def validate_webkit(appdir: Path) -> list[Path]:
    directory = appdir / WEBKIT_DIRECTORY
    for name in REQUIRED_FILES:
        if not (directory / name).is_file():
            raise RuntimeError(f"Missing packaged WebKitGTK component: {name}")
    return sorted(directory.glob("WebKit*Process"))


if __name__ == "__main__":
    stage_webkit(Path(sys.argv[1]))
