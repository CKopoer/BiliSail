"""Check icon sizes and generated pixels: uv run --with pillow==12.3.0 python tool/check_app_icons.py."""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ICO_SIZES = {(size, size) for size in (16, 24, 32, 48, 64, 128, 256)}
checked = 0


def check_png(path, original, size, opaque=False):
    global checked
    source = original
    if opaque:
        source = Image.new("RGB", original.size, "white")
        source.paste(original, mask=original.getchannel("A"))
    expected = source.resize((size, size), Image.Resampling.LANCZOS)
    with Image.open(ROOT / path) as actual:
        assert actual.size == (size, size), path
        assert actual.mode == expected.mode, (path, actual.mode)
        assert actual.tobytes() == expected.tobytes(), path
    checked += 1


for name, source, android, windows, ios in (
    ("bilisail", "app_icon.png", "ic_launcher", "app_icon.ico", "AppIcon"),
    ("bilibili", "bilibili_pink.png", "ic_launcher_bilibili", "bilibili_icon.ico", "BilibiliIcon"),
):
    with Image.open(ROOT / "assets/branding" / source) as original:
        original = original.convert("RGBA")
        assert original.size == (1254, 1254), source
        assert original.getpixel((0, 0))[3] == 0, source
        for density, size in DENSITIES.items():
            check_png(f"android/app/src/main/res/mipmap-{density}/{android}.png", original, size)
        with Image.open(ROOT / "windows/runner/resources" / windows) as icon:
            assert icon.ico.sizes() == ICO_SIZES, windows
            for size in ICO_SIZES:
                assert icon.ico.getimage(size).size == size, (windows, size)
                checked += 1
        icon_dir = Path(f"ios/Runner/Assets.xcassets/{ios}.appiconset")
        contents = json.loads((ROOT / icon_dir / "Contents.json").read_text(encoding="utf-8"))
        for entry in contents["images"]:
            size = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
            check_png(icon_dir / entry["filename"], original, size, opaque=True)
        if name == "bilisail":
            for size in (16, 32, 64, 128, 256, 512, 1024):
                check_png(f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png", original, size)
            check_png("linux/packaging/dev.bilisail.bilisail.png", original, 256)

source = ROOT / "assets/branding/bilibili_source.svg"
print(f"Icon resources checked: {checked}; both runtime sources: 1254x1254 RGBA")
print(f"Bilibili vector SHA-256: {hashlib.sha256(source.read_bytes()).hexdigest()}")
