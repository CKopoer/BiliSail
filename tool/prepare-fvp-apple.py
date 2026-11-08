"""Stage the pinned fvp CocoaPods renderer without changing the Pub checkout."""

import argparse
import hashlib
from pathlib import Path
import shutil


SOURCE_SHA256 = "67f70166e224384973bd890cbdd157aeeb3efb716b50f719e47d4d51ef56493e"


def patch_source(text: str) -> str:
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    if digest != SOURCE_SHA256:
        raise RuntimeError(f"Review fvp Apple texture patch for changed source: {digest}")
    start = text.index("@interface MetalTexture")
    end = text.index("class TexturePlayer final")
    text = text[:start] + '#include "metal_texture.inc"\n\n' + text[end:]
    text = text.replace(
        "texId_ = [texReg registerTexture:mtex_];",
        "texId_ = [texReg registerTexture:mtex_];\n"
        "        [mtex_ bindRegistry:texReg textureId:texId_];",
    ).replace(
        "            renderVideo();\n",
        "            renderVideo();\n            ++mtex_->revision;\n",
    ).replace(
        "        setRenderCallback(nullptr);\n",
        "        setRenderCallback(nullptr);\n        [mtex_ invalidate];\n",
    )
    return text


def prepare(repo: Path, platform: str) -> Path:
    repo = repo.resolve()
    relative = ".symlinks" if platform == "ios" else "Flutter/ephemeral/.symlinks"
    link = repo / platform / relative / "plugins/fvp"
    if not link.is_symlink():
        raise RuntimeError(f"Expected Flutter's generated fvp plugin symlink: {link}")
    source = link.resolve(strict=True)
    destination = repo / "build/apple-plugins" / platform / "fvp"
    marker = destination / "bilisail-source.txt"
    if source == destination:
        source = Path(marker.read_text(encoding="utf-8").strip()).resolve(strict=True)
    patched = patch_source((source / "darwin/Classes/FvpPlugin.mm").read_text(encoding="utf-8"))
    podspec = (source / "darwin/fvp.podspec").read_text(encoding="utf-8")
    pattern = "s.source_files     = 'Classes/**/*'"
    if podspec.count(pattern) != 1:
        raise RuntimeError("Review fvp Apple source-file registration")
    # The .inc is included by FvpPlugin.mm, never compiled or exported as a header.
    podspec = podspec.replace(pattern, "s.source_files     = 'Classes/**/*.{h,m,mm,c,cc,cpp}'")
    if destination.is_symlink() or not destination.resolve().is_relative_to(repo / "build"):
        raise RuntimeError(f"Unsafe fvp staging path: {destination}")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    for directory in ("darwin", "lib"):
        shutil.copytree(source / directory, destination / directory, symlinks=True)
    for name in ("LICENSE", "pubspec.yaml"):
        shutil.copyfile(source / name, destination / name)
    for relative_path, content in (
        ("darwin/Classes/FvpPlugin.mm", patched),
        ("darwin/fvp.podspec", podspec),
    ):
        target = destination / relative_path
        if not target.resolve().is_relative_to(destination):
            raise RuntimeError(f"Staged source escaped its build directory: {target}")
        # macOS command-line tools can still provide Python 3.9, whose
        # Path.write_text does not accept the newline argument.
        with target.open("w", encoding="utf-8", newline="\n") as output:
            output.write(content)
    shutil.copyfile(repo / "native/fvp/apple/metal_texture.inc",
                    destination / "darwin/Classes/metal_texture.inc")
    marker.write_text(str(source) + "\n", encoding="utf-8")
    link.unlink()
    link.symlink_to(destination, target_is_directory=True)
    print(f"Prepared {platform} fvp completed immutable Metal snapshots in {destination}")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("ios", "macos"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    prepare(args.repo, args.platform)
