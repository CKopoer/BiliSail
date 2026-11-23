"""Apply BiliSail's native lifecycle fixes to build-local Predidit sources."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname


ROOT = Path(__file__).resolve().parents[1]
PATCHES = ROOT / "tool/media-kit-patches"


def package_source(name):
    config = ROOT / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text(encoding="utf-8"))["packages"]
    entry = next(p for p in packages if p["name"] == name)
    uri = urlparse(urljoin(config.as_uri(), entry["rootUri"]))
    return Path(url2pathname(uri.path)).resolve(strict=True)


def apply_patches(destination, platforms):
    # Run outside any enclosing Git worktree so patch paths are relative
    # to the copied plugin, even in CocoaPods' build directory.
    env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(destination.parent.resolve()))
    for platform in platforms:
        patch = PATCHES / f"{platform}.patch"
        subprocess.run(["git", "-c", "core.autocrlf=false", "apply",
                        "--ignore-space-change", "--whitespace=nowarn", str(patch)],
                       cwd=destination, env=env, check=True, timeout=30)


def stage(source, destination, platforms):
    destination.mkdir(parents=True, exist_ok=True)
    for directory in ("common", *platforms):
        shutil.copytree(source / directory, destination / directory, dirs_exist_ok=True,
                        symlinks=True)
    shutil.copyfile(source / "LICENSE", destination / "LICENSE")
    common = ["mpv-client"]
    if {"macos", "ios"}.intersection(platforms):
        common.append("darwin")
    apply_patches(destination, [*common, *platforms])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("windows", "linux"))
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    stage(package_source("media_kit_video"), args.destination.resolve(), [args.platform])

    shutil.copyfile(package_source("media_kit") / "hook/native_bundles.json",
                    args.destination / "native_bundles.json")
