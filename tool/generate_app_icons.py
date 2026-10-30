"""Regenerate: uv run --with pillow==12.3.0 --with resvg-py==0.5.0 python tool/generate_app_icons.py."""
import io
import json
import struct
from pathlib import Path

from PIL import Image
import resvg_py

root = Path(__file__).resolve().parent.parent


def save_dock_icon(image, path):
    # Include small 1x representations as well as Retina variants; Pillow's
    # built-in ICNS writer omits the 16/32/64px 1x entries.
    chunks = []
    for kind, size in {
        b"icp4": 16, b"icp5": 32, b"icp6": 64,
        b"ic07": 128, b"ic08": 256, b"ic09": 512, b"ic10": 1024,
        b"ic11": 32, b"ic12": 64, b"ic13": 256, b"ic14": 512,
    }.items():
        stream = io.BytesIO()
        image.resize((size, size), Image.Resampling.LANCZOS).save(stream, format="PNG")
        data = stream.getvalue()
        chunks.append(kind + struct.pack(">I", 8 + len(data)) + data)
    payload = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", 8 + len(payload)) + payload)


with Image.open(root / "assets/branding/app_icon.png") as image:
    image = image.convert("RGBA")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            root / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png")
    image.save(root / "windows/runner/resources/app_icon.ico", format="ICO",
               sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    # iOS App Store icons must be opaque; composite on the brand's white base.
    opaque = Image.new("RGB", image.size, "white")
    opaque.paste(image, mask=image.getchannel("A"))
    icon_dir = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for entry in contents["images"]:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
        opaque.resize((size, size), Image.Resampling.LANCZOS).save(
            icon_dir / entry["filename"])
    image.resize((256, 256), Image.Resampling.LANCZOS).save(
        root / "linux/packaging/dev.bilisail.bilisail.png")

# Render the alternate from its vector source, with brand pink and safe margins.
svg = (root / "assets/branding/bilibili_source.svg").read_text(encoding="utf-8")
svg = svg.replace('viewBox="0 0 24 24"',
                  'width="1254" height="1254" fill="#FB7299" viewBox="-1 -1 26 26"')
(root / "assets/branding/bilibili_pink.svg").write_text(svg, encoding="utf-8")
(root / "assets/branding/bilibili_pink.png").write_bytes(
    resvg_py.svg_to_bytes(svg_string=svg))
with Image.open(root / "assets/branding/bilibili_pink.png") as original:
    image = original.convert("RGBA")
    # Dock overrides bypass the installed app-icon presentation. Give the
    # alternate its own padded, multi-resolution canvas; keep other OS assets.
    dock = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    dock.alpha_composite(image.resize((820, 820), Image.Resampling.LANCZOS), (102, 102))
    save_dock_icon(dock, root / "assets/branding/bilibili_pink_macos.icns")
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                          "xxhdpi": 144, "xxxhdpi": 192}.items():
        image.resize((size, size), Image.Resampling.LANCZOS).save(
            root / f"android/app/src/main/res/mipmap-{density}/ic_launcher_bilibili.png")
    image.save(root / "windows/runner/resources/bilibili_icon.ico", format="ICO",
               sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    icon_dir = root / "ios/Runner/Assets.xcassets/BilibiliIcon.appiconset"
    icon_dir.mkdir(exist_ok=True)
    contents = json.loads((root / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json")
                         .read_text(encoding="utf-8"))
    (icon_dir / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    for entry in contents["images"]:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
        opaque = Image.new("RGB", image.size, "white")
        opaque.paste(image, mask=image.getchannel("A"))
        opaque.resize((size, size), Image.Resampling.LANCZOS).save(
            icon_dir / entry["filename"])
