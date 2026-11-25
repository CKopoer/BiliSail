"""Check the packaged libmpv's IEC 61937 output against the original DD+ payload."""

import argparse
import ctypes
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time


def capture(library, source, destination):
    handle_type = ctypes.c_void_p
    string = ctypes.c_char_p
    with os.add_dll_directory(str(library.parent)):
        dll = ctypes.CDLL(str(library))
    for name, arguments, result in (
        ("mpv_create", [], handle_type),
        ("mpv_initialize", [handle_type], ctypes.c_int),
        ("mpv_set_option_string", [handle_type, string, string], ctypes.c_int),
        ("mpv_set_property_string", [handle_type, string, string], ctypes.c_int),
        ("mpv_command", [handle_type, ctypes.POINTER(string)], ctypes.c_int),
        ("mpv_get_property_string", [handle_type, string], handle_type),
        ("mpv_free", [handle_type], None),
        ("mpv_terminate_destroy", [handle_type], None),
    ):
        function = getattr(dll, name)
        function.argtypes = arguments
        function.restype = result
    handle = dll.mpv_create()
    if not handle:
        raise RuntimeError("mpv_create failed")

    def property_value(name):
        pointer = dll.mpv_get_property_string(handle, name)
        if not pointer:
            return None
        try:
            return ctypes.string_at(pointer)
        finally:
            dll.mpv_free(pointer)

    def await_format(encoded):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            value = property_value(b"audio-out-params/format")
            if value and value.startswith(b"spdif-") == encoded:
                return
            time.sleep(0.025)
        raise RuntimeError("Timed out switching between decoded and encoded audio")

    try:
        # ao_pcm preserves encoded samples when invoked without a WAV header.
        options = {
            "config": "no", "video": "no", "pause": "yes",
            "ao": "pcm", "ao-pcm-waveheader": "no",
            "ao-pcm-file": str(destination), "idle": "yes",
        }
        for name, value in options.items():
            if dll.mpv_set_option_string(handle, name.encode(), value.encode()) < 0:
                raise RuntimeError(f"libmpv rejected {name}")
        if dll.mpv_initialize(handle) < 0:
            raise RuntimeError("mpv_initialize failed")
        command = (string * 3)(b"loadfile", str(source).encode(), None)
        if dll.mpv_command(handle, command) < 0:
            raise RuntimeError("libmpv could not open the fixture")
        # Exercise the application's actual file-local option after demux.
        await_format(False)
        for mode in (b"eac3", b"", b"eac3"):
            position = property_value(b"time-pos")
            if dll.mpv_set_property_string(handle, b"file-local-options/audio-spdif", mode) < 0:
                raise RuntimeError("libmpv rejected a DD+ route change")
            if not position or dll.mpv_set_property_string(handle, b"time-pos", position) < 0:
                raise RuntimeError("Could not restore the playback clock after switching audio")
            await_format(bool(mode))
        if dll.mpv_set_property_string(handle, b"pause", b"no") < 0:
            raise RuntimeError("Could not start encoded playback")
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if (property_value(b"idle-active") == b"yes"
                    and destination.is_file() and destination.stat().st_size > 0):
                return
            time.sleep(0.05)
        raise RuntimeError("libmpv did not finish writing the encoded carrier")
    finally:
        dll.mpv_terminate_destroy(handle)


def unpack(carrier):
    burst_size = 24576
    if not carrier or len(carrier) % burst_size:
        raise ValueError("Incomplete E-AC-3 IEC 61937 burst")
    payload = bytearray()
    for offset in range(0, len(carrier), burst_size):
        sync1, sync2, data_type, size = struct.unpack_from("<4H", carrier, offset)
        if (sync1, sync2, data_type & 31) != (0xf872, 0x4e1f, 0x15):
            raise ValueError(f"Invalid E-AC-3 preamble at byte {offset}")
        if size == 0 or size % 2 or size > burst_size - 8:
            raise ValueError(f"Invalid E-AC-3 payload length {size}")
        chunk = carrier[offset + 8:offset + 8 + size]
        native = bytearray(size)
        native[::2], native[1::2] = chunk[1::2], chunk[::2]
        payload.extend(native)
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    original = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(args.source), "-map", "0:a:0",
        "-c:a", "copy", "-f", "eac3", "pipe:1",
    ])
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / "ddp.iec61937"
        capture(args.library.resolve(strict=True), args.source.resolve(strict=True), output)
        carrier = output.read_bytes()
    payload = unpack(carrier)
    if payload != original:
        raise ValueError("IEC 61937 payload differs from the original E-AC-3 frames")
    print(f"{len(carrier) // 24576} E-AC-3 bursts, {len(payload)} original bytes, "
          f"SHA-256 {hashlib.sha256(payload).hexdigest()}")
