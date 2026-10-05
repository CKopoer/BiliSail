"""Regenerate launcher assets: uv run --with pillow python tool/generate_uwp_icons.py."""
from pathlib import Path

from PIL import Image

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
