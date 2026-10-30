"""Regenerate: uv run --with pillow==12.3.0 --with resvg-py==0.5.0 python tool/generate_app_icons.py."""
import json
from pathlib import Path

from PIL import Image
import resvg_py

root = Path(__file__).resolve().parent.parent
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
