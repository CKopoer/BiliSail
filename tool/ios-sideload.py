"""Prepare staged iOS code for re-signing and inspect the final IPA offline."""

import argparse
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import BinaryIO
import zipfile


THIN_ARM64 = b"\xcf\xfa\xed\xfe"
FAT_MAGICS = {bytes.fromhex(value) for value in (
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}
MACHO_MAGICS = FAT_MAGICS | {
    THIN_ARM64, bytes.fromhex("feedfacf"),
    bytes.fromhex("cefaedfe"), bytes.fromhex("feedface"),
}


def validate_macho(stream: BinaryIO, size: int, label: str,
                   require_signature: bool = True) -> None:
    header = stream.read(32)
    if len(header) != 32 or header[:4] != THIN_ARM64:
        raise ValueError(f"{label}: expected a thin arm64 Mach-O, not a FAT container")
    _, cpu, subtype, filetype, count, command_size, _, _ = struct.unpack("<8I", header)
    if cpu != 0x0100000C or subtype != 0 or filetype not in (2, 6, 8):
        raise ValueError(f"{label}: expected arm64 executable code")
    if command_size > 1024 * 1024 or 32 + command_size > size:
        raise ValueError(f"{label}: invalid Mach-O load-command size")
    commands = stream.read(command_size)
    offset = 0
    signature = None
    for _ in range(count):
        if offset + 8 > len(commands):
            raise ValueError(f"{label}: truncated Mach-O load command")
        command, length = struct.unpack_from("<2I", commands, offset)
        if length < 8 or length % 8 or offset + length > len(commands):
            raise ValueError(f"{label}: invalid Mach-O load command")
        if command == 0x1D:  # LC_CODE_SIGNATURE, linkedit_data_command.
            if length != 16 or signature is not None:
                raise ValueError(f"{label}: invalid code-signature command")
            signature = struct.unpack_from("<2I", commands, offset + 8)
        offset += length
    if offset != command_size:
        raise ValueError(f"{label}: inconsistent Mach-O load commands")
    if not require_signature:
        return
    if signature is None:
        raise ValueError(f"{label}: missing LC_CODE_SIGNATURE")
    start, length = signature
    if start < 32 + command_size or length < 12 or start + length > size:
        raise ValueError(f"{label}: code signature is outside the binary")
    stream.seek(start)
    blob = stream.read(12)
    if len(blob) != 12:
        raise ValueError(f"{label}: truncated code signature")
    magic, blob_size, _ = struct.unpack(">3I", blob)
    if magic != 0xFADE0CC0 or not 12 <= blob_size <= length:
        raise ValueError(f"{label}: invalid embedded signature blob")


def bundle_executable(bundle: Path) -> Path:
    with (bundle / "Info.plist").open("rb") as stream:
        name = plistlib.load(stream).get("CFBundleExecutable")
    if not isinstance(name, str) or not name or name in (".", "..") or "/" in name or "\\" in name:
        raise ValueError(f"{bundle}: invalid CFBundleExecutable")
    binary = bundle / name
    if not binary.is_file():
        raise ValueError(f"{bundle}: missing executable {name}")
    return binary


def run(*arguments: str) -> None:
    subprocess.run(arguments, check=True, timeout=120)


def prepare(app: Path) -> None:
    app = app.resolve(strict=True)
    main = bundle_executable(app)
    binaries = []
    for path in sorted(app.rglob("*")):
        if path.is_file():
            with path.open("rb") as stream:
                magic = stream.read(4)
            if magic in MACHO_MAGICS:
                # Only copied staging files may be replaced, never external assets.
                if path.is_symlink() or not path.resolve().is_relative_to(app):
                    raise ValueError(f"Mach-O escapes the staged application: {path}")
                binaries.append(path)
    bundles = [app] + [path for path in app.rglob("*")
                       if path.is_dir() and path.suffix in (".framework", ".appex", ".app")]
    targets = {bundle_executable(bundle): bundle for bundle in bundles}
    if main not in binaries or any(binary not in binaries for binary in targets):
        raise ValueError("An iOS bundle executable is not Mach-O code")
    for binary in binaries:
        with binary.open("rb") as stream:
            fat = stream.read(4) in FAT_MAGICS
        if fat:
            # lipo -verify_arch accepts a FAT file containing just one slice.
            # Explicit thinning is necessary even when it reports only arm64.
            with tempfile.NamedTemporaryFile(
                dir=binary.parent, suffix=".thin", delete=False,
            ) as stream:
                temporary = Path(stream.name)
            try:
                run("lipo", str(binary), "-thin", "arm64", "-output", str(temporary))
                with temporary.open("rb") as stream:
                    validate_macho(stream, temporary.stat().st_size, str(binary), False)
                shutil.copymode(binary, temporary)
                temporary.replace(binary)
            finally:
                temporary.unlink(missing_ok=True)
        with binary.open("rb") as stream:
            validate_macho(stream, binary.stat().st_size, str(binary), False)
    # Sign code from the inside out, regenerating framework resource seals too.
    # '-' creates an ad-hoc signature without a certificate or Apple account.
    for target in sorted({targets.get(binary, binary) for binary in binaries},
                         key=lambda path: (-len(path.parts), str(path))):
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(target))
    for binary in binaries:
        with binary.open("rb") as stream:
            validate_macho(stream, binary.stat().st_size, str(binary))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    print(f"Prepared {len(binaries)} thin arm64 Mach-O files with ad-hoc signatures")


def validate_ipa(package: Path) -> None:
    prefix = "Payload/Runner.app/"
    count = 0
    with zipfile.ZipFile(package) as archive:
        main_info = plistlib.loads(archive.read(prefix + "Info.plist"))
        main = prefix + main_info["CFBundleExecutable"]
        found_main = False
        for entry in archive.infolist():
            if entry.is_dir() or not entry.filename.startswith(prefix):
                continue
            with archive.open(entry) as stream:
                magic = stream.read(4)
                if magic not in MACHO_MAGICS and entry.filename != main:
                    continue
                stream.seek(0)
                validate_macho(stream, entry.file_size, entry.filename)
                count += 1
                found_main |= entry.filename == main
        if not found_main:
            raise ValueError("IPA is missing its Mach-O application executable")
    print(f"Verified {count} thin arm64 Mach-O signatures in {package.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare-app", type=Path)
    mode.add_argument("--verify-ipa", type=Path)
    args = parser.parse_args()
    if args.prepare_app:
        if sys.platform != "darwin":
            parser.error("iOS code preparation requires macOS lipo and codesign")
        prepare(args.prepare_app)
    else:
        validate_ipa(args.verify_ipa)
