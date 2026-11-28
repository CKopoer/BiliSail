"""Stage the iOS audio_service pod with background-only Now Playing metadata."""

import hashlib
from pathlib import Path
import shutil

from media_kit_sources import ROOT, apply_patches, package_source

IMPLEMENTATION = Path("darwin/audio_service/Sources/audio_service/AudioServicePlugin.m")
SOURCE_HASH = "fed592f28065dcdcf1819754c83a34f046f7583a897cd53365d845a8d4920b22"


def prepare(repo: Path, source: Path) -> Path:
    link = repo / "ios/.symlinks/plugins/audio_service"
    destination = repo / "build/apple-plugins/ios/audio_service"
    if not link.is_symlink() or link.resolve() not in (source, destination):
        raise RuntimeError(f"Unexpected Flutter audio_service symlink: {link}")
    if destination.resolve() != destination or source == destination:
        raise RuntimeError(f"Unsafe audio_service staging path: {destination}")
    upstream = (source / IMPLEMENTATION).read_text(encoding="utf-8")
    if hashlib.sha256(upstream.encode()).hexdigest() != SOURCE_HASH:
        raise RuntimeError("Review the iOS Now Playing patch for the new audio_service source")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source / "darwin", destination / "darwin")
    shutil.copyfile(source / "LICENSE", destination / "LICENSE")
    apply_patches(destination, ["now-playing"], ROOT / "ios/patches/audio_service")
    link.unlink()
    link.symlink_to(destination, target_is_directory=True)
    return destination


if __name__ == "__main__":
    prepare(ROOT, package_source("audio_service"))
