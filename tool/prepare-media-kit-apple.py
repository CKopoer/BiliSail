"""Stage the pinned CocoaPods plugin without changing the Pub checkout."""

import argparse
import hashlib
from pathlib import Path
import shutil


PODSPEC_HASHES = {
    "ios": "93cdfd347e6b85a2af3e115969629b940b64819462307407af6c2b73ac97a62f",
    "macos": "c811ae717625eef4621160ba53c572317dfd8ef9e58e5887be19ce67f372736f",
}


def prepare(repo: Path, platform: str) -> Path:
    repo = repo.resolve()
    relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
    link = repo / platform / relative / "plugins/media_kit_video"
    if not link.is_symlink():
        raise RuntimeError(f"Expected Flutter's generated plugin symlink: {link}")
    source = link.resolve(strict=True)
    destination = repo / "build/apple-plugins" / platform / "media_kit_video"
    # A repeated pod install must still start from the immutable Pub source.
    marker = destination / "bilisail-source.txt"
    if source == destination:
        source = Path(marker.read_text(encoding="utf-8").strip()).resolve(strict=True)
    podspec = source / platform / "media_kit_video.podspec"
    text = podspec.read_text(encoding="utf-8")
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if digest != PODSPEC_HASHES[platform]:
        raise RuntimeError(f"Review media-kit CocoaPods patch for changed source: {digest}")
    bindings = source / "common/mpv"
    if not (bindings / "include/media_kit_mpv.h").is_file():
        raise RuntimeError("media-kit shared C bindings are missing")
    # Only this fixed child of build/ may be replaced. Never follow a stale link.
    if destination.is_symlink() or not destination.resolve().is_relative_to(repo / "build"):
        raise RuntimeError(f"Unsafe Apple plugin staging path: {destination}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for directory in (platform, "common"):
        shutil.copytree(source / directory, destination / directory, symlinks=True)
    shutil.copyfile(source / "LICENSE", destination / "LICENSE")
    shutil.copytree(bindings, destination / platform / "media_kit_mpv")
    # CocoaPods matches files below the pod root; ../common is never enumerated.
    patched = text.replace("../common/mpv/", "media_kit_mpv/")
    (destination / platform / podspec.name).write_text(patched, encoding="utf-8")
    marker.write_text(str(source) + "\n", encoding="utf-8")
    link.unlink()
    link.symlink_to(destination, target_is_directory=True)
    print(f"Prepared {platform} media-kit CocoaPods C bindings in {destination}")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=PODSPEC_HASHES)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    prepare(args.repo, args.platform)
