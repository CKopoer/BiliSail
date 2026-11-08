"""Verify that an APK contains the MDK SDK selected by the native asset lock."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname
import zipfile


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def load_image_sha256(data):
    """Hash ELF runtime segments, allowing AGP to strip nonloaded debug sections."""
    data = bytearray(data)
    if data[:4] != b"\x7fELF" or data[5] != 1:
        raise ValueError("Expected a little-endian Android ELF library")
    if data[4] == 2:
        offset = struct.unpack_from("<Q", data, 32)[0]
        size, count = struct.unpack_from("<HH", data, 54)
        data[40:48] = bytes(8)  # Section table location changes when stripped.
        data[58:64] = bytes(6)
        header = "<IIQQQQQQ"
    elif data[4] == 1:
        offset = struct.unpack_from("<I", data, 28)[0]
        size, count = struct.unpack_from("<HH", data, 42)
        data[32:36] = bytes(4)
        data[46:52] = bytes(6)
        header = "<IIIIIIII"
    else:
        raise ValueError("Unsupported ELF class")
    digest = hashlib.sha256()
    loads = 0
    for index in range(count):
        values = struct.unpack_from(header, data, offset + size * index)
        if values[0] != 1:  # PT_LOAD
            continue
        if data[4] == 2:
            _, flags, start, address, _, length, memory, _ = values
        else:
            _, start, address, _, length, memory, flags, _ = values
        if start + length > len(data) or length > memory:
            raise ValueError("Invalid ELF load segment")
        digest.update(struct.pack("<QQQQ", address, flags, length, memory))
        digest.update(data[start:start + length])
        loads += 1
    if not loads:
        raise ValueError("ELF contains no load segments")
    return digest.hexdigest()


def verify(apk, root):
    lock = json.loads((root / "native/fvp/assets.lock.json").read_text("utf-8"))
    expected = lock["assets"]["android"]["sha256"]
    config_path = root / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text("utf-8"))
    package = next(p for p in config["packages"] if p["name"] == "fvp")
    uri = urlparse(urljoin(config_path.as_uri(), package["rootUri"]))
    if uri.scheme != "file":
        raise ValueError("fvp must resolve to a local package")
    android = Path(url2pathname(uri.path)) / "android"
    sdk = android / "mdk-sdk"
    stamp = (sdk / ".fvp-deps.sha256").read_text("utf-8").strip()
    if stamp != expected or sha256(android / lock["assets"]["android"]["archive"]) != expected:
        raise ValueError("Android MDK SDK does not match native/fvp/assets.lock.json")
    libraries = {}
    with zipfile.ZipFile(apk) as archive:
        for name in archive.namelist():
            parts = name.split("/")
            if len(parts) != 3 or parts[0] != "lib" or parts[2] != "libmdk.so":
                continue
            abi = parts[1]
            packaged = archive.read(name)
            actual = load_image_sha256(packaged)
            if actual != load_image_sha256((sdk / "lib" / abi / "libmdk.so").read_bytes()):
                raise ValueError(f"APK contains a stale or different MDK library: {abi}")
            libraries[abi] = {"sha256": hashlib.sha256(packaged).hexdigest(), "loadImageSha256": actual}
    if not libraries:
        raise ValueError("APK contains no MDK library")
    return {"sdkVersion": lock["version"], "archiveSha256": expected, "libraries": libraries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    print(json.dumps(verify(args.apk, args.root.resolve()), indent=2))


if __name__ == "__main__":
    main()
