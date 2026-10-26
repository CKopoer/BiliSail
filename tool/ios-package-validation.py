"""Inspect the delivered IPA; optionally sign a disposable BiliMux copy on macOS.

This checks structure and Info.plist binding, not Apple certificate trust or
compatibility with a particular third-party signer. Never modifies the IPA.
"""

import argparse
import hashlib
import plistlib
from pathlib import Path, PurePosixPath
import struct
import subprocess
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def slices(data):
    if data[:4] == b"\xcf\xfa\xed\xfe":
        return [data]
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        wide = data[3] == 0xBF
        count = struct.unpack_from(">I", data, 4)[0]
        require(0 < count <= 16, "Invalid fat architecture count")
        result = []
        for i in range(count):
            offset, size = struct.unpack_from(">QQ" if wide else ">II", data,
                                              8 + i * (32 if wide else 20) + 8)
            require(size > 0 and offset + size <= len(data), "Invalid fat slice")
            result.extend(slices(data[offset:offset + size]))
        require(len(result) == count, "Unsupported Mach-O slice")
        return result
    return []


def inspect_macho(data):
    require(len(data) >= 32 and data[:4] == b"\xcf\xfa\xed\xfe", "Expected Mach-O 64")
    header = struct.unpack_from("<8I", data)
    require(header[1] == 0x100000C, "Non-arm64 architecture")
    require(header[3] in (2, 6), "Expected executable or dynamic library")
    end = 32 + header[5]
    require(end <= len(data), "Truncated load commands")
    offset, platform, signature, embedded = 32, None, None, False
    for _ in range(header[4]):
        require(offset + 8 <= end, "Truncated load command")
        command, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and offset + size <= end, "Invalid load command size")
        if command == 0x32:  # LC_BUILD_VERSION
            require(size >= 24, "Truncated build version")
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS (arm64 device)
            platform = 2
        elif command in (0x24, 0x2F, 0x30):
            platform = -1
        elif command == 0x1D:
            require(size >= 16, "Truncated code signature command")
            start, length = struct.unpack_from("<II", data, offset + 8)
            require(start + length <= len(data), "Truncated signature")
            signature = data[start:start + length]
        elif command == 0x19:
            require(size >= 72, "Truncated segment")
            count = struct.unpack_from("<I", data, offset + 64)[0]
            require(72 + count * 80 <= size, "Truncated sections")
            for i in range(count):
                section = offset + 72 + i * 80
                if data[section:section + 16].rstrip(b"\0") == b"__info_plist":
                    embedded = True
        offset += size
    require(offset == end, "Load command size mismatch")
    require(platform == 2, f"Expected iPhoneOS platform, got {platform}")
    return signature, embedded


def verify_info_slot(signature, info):
    require(signature is not None and len(signature) >= 12, "Missing signature")
    magic, length, count = struct.unpack_from(">III", signature)
    require(magic == 0xFADE0CC0 and length <= len(signature), "Invalid signature blob")
    require(12 + count * 8 <= length, "Truncated signature index")
    checked = 0
    for i in range(count):
        kind, offset = struct.unpack_from(">II", signature, 12 + i * 8)
        if kind != 0 and not 0x1000 <= kind <= 0x1005:
            continue
        require(offset + 40 <= length, "Truncated CodeDirectory")
        cd = signature[offset:length]
        magic, size, _, _, hashes, _, special = struct.unpack_from(">7I", cd)
        hash_size, hash_type = struct.unpack_from("BB", cd, 36)
        require(magic == 0xFADE0C02 and size <= len(cd), "Invalid CodeDirectory")
        require(special >= 1 and hashes >= hash_size and hashes <= size,
                "Info.plist is not bound in CodeDirectory slot -1")
        algorithms = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}
        require(hash_type in algorithms, "Unsupported signature hash")
        digest = hashlib.new(algorithms[hash_type], info).digest()
        expected_size = 20 if hash_type == 3 else len(digest)
        require(hash_size == expected_size, "Invalid signature hash size")
        require(cd[hashes - hash_size:hashes] == digest[:hash_size],
                "Info.plist hash mismatch in CodeDirectory slot -1")
        checked += 1
    require(checked > 0, "No CodeDirectory")
    return checked


def validate_ipa(path, signing_probe=False):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP paths")
        for name in names:
            parts = PurePosixPath(name)
            require(not parts.is_absolute() and ".." not in parts.parts, "Unsafe ZIP path")
        root = "Payload/Runner.app/"
        require(root + "Info.plist" in names and root + "Runner" in names, "Invalid Payload")
        info = plistlib.loads(archive.read(root + "Info.plist"))
        require(info.get("CFBundleIdentifier") == "dev.bilisail.bilisail", "Wrong application ID")
        require(info.get("MinimumOSVersion") == "15.0", "Unexpected minimum iOS version")
        count = 0
        for name in names:
            if name.endswith("/"):
                continue
            with archive.open(name) as stream:
                magic = stream.read(4)
            if magic not in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
                continue
            binary_slices = slices(archive.read(name))
            for data in binary_slices:
                signature, embedded = inspect_macho(data)
            count += 1
            print(f"iPhoneOS arm64: {name} ({len(binary_slices)} slice(s))")
        require(count > 0, "No Mach-O files")
        framework = root + "Frameworks/BiliMux.framework/"
        raw_info = archive.read(framework + "Info.plist")
        metadata = plistlib.loads(raw_info)
        require(raw_info.startswith(b"bplist00"), "BiliMux must ship a processed binary Info.plist")
        for key, value in {"CFBundleExecutable": "BiliMux", "CFBundleIdentifier": "dev.bilisail.mux",
                           "CFBundlePackageType": "FMWK", "CFBundleInfoDictionaryVersion": "6.0",
                           "MinimumOSVersion": "15.0", "CFBundleSupportedPlatforms": ["iPhoneOS"]}.items():
            require(metadata.get(key) == value, f"Invalid BiliMux {key}")
        for data in slices(archive.read(framework + "BiliMux")):
            signature, embedded = inspect_macho(data)
            require(not embedded, "Framework must use its external Info.plist, not __info_plist")
            if signature is not None:
                verify_info_slot(signature, raw_info)
        if signing_probe:
            with tempfile.TemporaryDirectory(prefix="bilisail-ios-signing-") as work:
                bundle = Path(work) / "BiliMux.framework"
                for name in names:
                    if name.startswith(framework) and not name.endswith("/"):
                        target = bundle / name[len(framework):]
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(archive.read(name))
                (bundle / "BiliMux").chmod(0o755)
                subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(bundle)], check=True)
                subprocess.run(["codesign", "--verify", "--strict", "--verbose=2", str(bundle)], check=True)
                signed_info = (bundle / "Info.plist").read_bytes()
                require(signed_info == raw_info, "Signing changed Info.plist bytes")
                for data in slices((bundle / "BiliMux").read_bytes()):
                    signature, _ = inspect_macho(data)
                    verify_info_slot(signature, signed_info)
                print("Disposable BiliMux ad-hoc signature and Info.plist slot -1 verified")
        print(f"IPA structure validated: {count} Mach-O files; device re-signing remains unverified")


def compare_legacy(path):
    """A/B the exact released binary, without altering the downloaded IPA."""
    require(hashlib.sha256(path.read_bytes()).hexdigest() ==
            "e7e1ece6f97a73e406824046873361842500d465f355055cffe6d0f9686f056a",
            "Legacy IPA checksum mismatch")
    prefix = "Payload/Runner.app/Frameworks/BiliMux.framework/"
    with zipfile.ZipFile(path) as archive, tempfile.TemporaryDirectory() as work:
        original = archive.read(prefix + "BiliMux")
        original_info = archive.read(prefix + "Info.plist")
        for label in ("original-xml", "processed-binary"):
            bundle = Path(work) / label / "BiliMux.framework"
            bundle.mkdir(parents=True)
            for name in archive.namelist():
                if not name.startswith(prefix) or name.endswith("/"):
                    continue
                relative = PurePosixPath(name[len(prefix):])
                require(".." not in relative.parts, "Unsafe legacy ZIP path")
                target = bundle / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
            require((bundle / "BiliMux").read_bytes() == original, "A/B binary differs")
            (bundle / "BiliMux").chmod(0o755)
            info_path = bundle / "Info.plist"
            if label == "processed-binary":
                metadata = plistlib.loads(original_info)
                metadata["CFBundleInfoDictionaryVersion"] = "6.0"
                info_path.write_bytes(plistlib.dumps(metadata))
                subprocess.run(["plutil", "-convert", "binary1", str(info_path)], check=True)
            info = info_path.read_bytes()
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(bundle)], check=True)
            subprocess.run(["codesign", "--verify", "--strict", "--verbose=2", str(bundle)], check=True)
            require(info_path.read_bytes() == info, "Signing changed plist bytes")
            for data in slices((bundle / "BiliMux").read_bytes()):
                signature, _ = inspect_macho(data)
                verify_info_slot(signature, info)
            print(f"Legacy BiliMux A/B: {label} Apple ad-hoc and Info.plist slot -1 PASS", flush=True)
    print("Apple A/B does not reproduce or certify third-party signer behavior", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--signing-probe", action="store_true")
    parser.add_argument("--compare-legacy", action="store_true")
    args = parser.parse_args()
    if args.compare_legacy:
        compare_legacy(args.ipa)
    else:
        validate_ipa(args.ipa, args.signing_probe)
