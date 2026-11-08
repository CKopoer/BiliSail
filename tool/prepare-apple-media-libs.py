"""Build and verify pinned mpv frameworks before CocoaPods evaluates podspecs."""

import argparse
from pathlib import Path
import shutil
import subprocess


def prepare(repo: Path, platform: str) -> Path:
    repo = repo.resolve()
    package = f"media_kit_libs_{platform}_video"
    relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
    link = repo / platform / relative / "plugins" / package
    if not link.is_symlink():
        raise RuntimeError(f"Expected Flutter's generated plugin symlink: {link}")
    source = link.resolve(strict=True)
    destination = repo / "build/apple-plugins" / platform / package
    if destination.is_symlink() or not destination.resolve().is_relative_to(repo / "build"):
        raise RuntimeError(f"Unsafe Apple library staging path: {destination}")
    marker = destination / "bilisail-source.txt"
    if source == destination:
        source = Path(marker.read_text(encoding="utf-8").strip()).resolve(strict=True)
    # Reuse only our own build-local staging, preserving verified make caches.
    if not marker.is_file() or marker.read_text(encoding="utf-8").strip() != str(source):
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(
            source / platform, destination / platform, symlinks=True,
            ignore=shutil.ignore_patterns(".cache", "Frameworks"),
        )
        shutil.copyfile(source / "LICENSE", destination / "LICENSE")
        marker.write_text(str(source) + "\n", encoding="utf-8")
    podroot = destination / platform
    # The upstream podspec ignores system("make")'s result. Running it here with
    # check=True exposes download errors instead of a later missing-Mpv link error.
    # URLs, SHA-256 checks, extraction and framework aliases remain fork-owned.
    subprocess.run(["make"], cwd=podroot, check=True, timeout=600)
    binary = podroot / f"Frameworks/.symlinks/mpv/{platform}/Mpv.framework/Mpv"
    if not binary.is_file():
        raise RuntimeError(f"Pinned mpv framework is missing after make: {binary}")
    if link.resolve() != destination:
        link.unlink()
        link.symlink_to(destination, target_is_directory=True)
    print(f"Verified {platform} mpv framework in {destination}", flush=True)
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("ios", "macos"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    prepare(args.repo, args.platform)
