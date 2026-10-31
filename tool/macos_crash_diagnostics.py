"""Export only owned-process backtraces, never raw Apple reports or app output.

Apple's IPS schema: https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report
"""

from __future__ import annotations

import argparse
from datetime import datetime
from itertools import islice
import json
import os
from pathlib import Path
import re
import subprocess
import time

MAX_REPORT_BYTES = 8 * 1024 * 1024
MAX_THREADS = 32
MAX_FRAMES = 96
SIGNALS = {
    "SIGSEGV",
    "SIGBUS",
    "SIGABRT",
    "SIGILL",
    "SIGFPE",
    "SIGTRAP",
    "SIGKILL",
    "SIGSYS",
    "SIGTERM",
    "SIGQUIT",
}
EXCEPTIONS = {
    "EXC_BAD_ACCESS",
    "EXC_BAD_INSTRUCTION",
    "EXC_ARITHMETIC",
    "EXC_EMULATION",
    "EXC_SOFTWARE",
    "EXC_BREAKPOINT",
    "EXC_SYSCALL",
    "EXC_MACH_SYSCALL",
    "EXC_RPC_ALERT",
    "EXC_CRASH",
    "EXC_RESOURCE",
    "EXC_GUARD",
    "EXC_CORPSE_NOTIFY",
}


def _object(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _array(value: object) -> list:
    return value if isinstance(value, list) else []


def _number(value: object) -> int | None:
    return (
        value
        if isinstance(value, int) and not isinstance(value, bool) and 0 <= value < 2**64
        else None
    )


def timestamp(value: object) -> float | None:
    if not isinstance(value, str) or len(value) > 64:
        return None
    try:
        # Apple's offset has no colon; PowerShell can emit seven fractional
        # digits. Normalize both for the Python 3.9 shipped with some Xcodes.
        value = re.sub(r"\s+([+-]\d{4})$", r"\1", value).replace("Z", "+00:00")
        value = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", value)
        value = re.sub(r"\.(\d+)", lambda match: "." + (match[1] + "000000")[:6], value)
        parsed = datetime.fromisoformat(value)
        return parsed.timestamp() if parsed.tzinfo else None
    except ValueError:
        return None


def _symbol(value: object) -> str | None:
    # No paths, URL delimiters, quoted strings, control characters or values
    # from application-specific logging. Keep offsets for rejected symbols.
    if (
        isinstance(value, str)
        and not re.search(
            r"(?:cookie|authorization|bearer|token|session)\s*[:=]", value, re.I
        )
        and re.fullmatch(r"[A-Za-z0-9_.$@:+<>,~*?&()\[\] \-=|!#{}%^]{1,1024}", value)
    ):
        return value
    return None


def _image(value: object) -> str:
    if isinstance(value, str):
        name = value.rsplit("/", 1)[-1]
        if re.fullmatch(r"[A-Za-z0-9_.+-]{1,128}", name):
            return name
    return "unknown"


def _exception(value: object) -> dict:
    value = _object(value)
    return {
        "type": value.get("type") if value.get("type") in EXCEPTIONS else None,
        "signal": value.get("signal") if value.get("signal") in SIGNALS else None,
    }


def _ips(report: dict, pid: int, started: float) -> dict | None:
    launched = timestamp(report.get("procLaunch"))
    if (
        report.get("pid") != pid
        or report.get("procName") != "BiliSail"
        or launched is None
        or launched < started - 2
    ):
        return None
    images = _array(report.get("usedImages"))
    threads = _array(report.get("threads"))
    faulting = _number(report.get("faultingThread"))
    if faulting is None or faulting >= len(threads):
        faulting = next(
            (
                index
                for index, thread in enumerate(threads)
                if _object(thread).get("triggered") is True
            ),
            None,
        )
    selected = list(range(min(len(threads), MAX_THREADS)))
    if faulting is not None and faulting not in selected:
        selected[-1] = faulting
    result_threads = []
    for index in selected:
        frames = []
        for value in _array(_object(threads[index]).get("frames"))[:MAX_FRAMES]:
            frame = _object(value)
            image_index = _number(frame.get("imageIndex"))
            image = (
                _object(images[image_index])
                if image_index is not None and image_index < len(images)
                else {}
            )
            frames.append(
                {
                    "image": _image(image.get("name") or image.get("path")),
                    "imageOffset": _number(frame.get("imageOffset")),
                    "imageBase": _number(image.get("base")),
                    "imageUuid": (
                        image.get("uuid")
                        if isinstance(image.get("uuid"), str)
                        and re.fullmatch(
                            r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
                            image["uuid"],
                        )
                        else None
                    ),
                    "imageArch": (
                        image.get("arch")
                        if image.get("arch") in {"x86_64", "x86_64h", "arm64", "arm64e"}
                        else None
                    ),
                    "symbol": _symbol(frame.get("symbol")),
                    "symbolOffset": _number(frame.get("symbolLocation")),
                }
            )
        result_threads.append(
            {"index": index, "crashed": index == faulting, "frames": frames}
        )
    return {
        "format": "ips",
        "exception": _exception(report.get("exception")),
        "faultingThread": faulting,
        "threads": result_threads,
    }


def _legacy(raw: str, pid: int, started: float) -> dict | None:
    process = re.search(r"^Process:\s+BiliSail\s+\[(\d+)\]\s*$", raw, re.M)
    captured = re.search(r"^Date/Time:\s+(.+)$", raw, re.M)
    captured_time = timestamp(captured[1].strip()) if captured else None
    if (
        not process
        or int(process[1]) != pid
        or captured_time is None
        or captured_time < started - 2
    ):
        return None
    exception = re.search(
        r"^Exception Type:\s+(EXC_[A-Z_]+)\s+\((SIG[A-Z]+)\)", raw, re.M
    )
    crashed = re.search(r"^Crashed Thread:\s+(\d+)", raw, re.M)
    faulting = int(crashed[1]) if crashed else None
    threads = []
    current = None
    for line in raw.splitlines():
        header = re.match(r"Thread (\d+)(?: Crashed)?(?:::|:)", line)
        if header:
            index = int(header[1])
            current = {"index": index, "crashed": index == faulting, "frames": []}
            if len(threads) < MAX_THREADS:
                threads.append(current)
            elif index == faulting:
                threads[-1] = current
            continue
        frame = re.match(
            r"\s*\d+\s+(\S+)\s+0x([\da-fA-F]+)\s+(.+?)\s+\+\s+(\d+)\s*$", line
        )
        if frame and current is not None and len(current["frames"]) < MAX_FRAMES:
            current["frames"].append(
                {
                    "image": _image(frame[1]),
                    "address": int(frame[2], 16),
                    "symbol": _symbol(frame[3]),
                    "symbolOffset": int(frame[4]),
                }
            )
    return {
        "format": "crash",
        "exception": _exception(
            {"type": exception[1], "signal": exception[2]} if exception else {}
        ),
        "faultingThread": faulting,
        "threads": threads,
    }


def parse_report(raw: str, pid: int, started: float) -> dict | None:
    raw = raw.lstrip("\ufeff \t\r\n")
    if not raw.lstrip().startswith("{"):
        return _legacy(raw, pid, started)
    try:
        header, end = json.JSONDecoder().raw_decode(raw.lstrip())
        if str(_object(header).get("bug_type")) != "309":
            return None
        report = json.loads(raw.lstrip()[end:].strip())
        return _ips(_object(report), pid, started)
    except (ValueError, TypeError, RecursionError):
        return None


def parse_sample(raw: str, pid: int) -> dict | None:
    if not re.search(rf"^Process:\s+BiliSail\s+\[{pid}\]\s*$", raw, re.M):
        return None
    threads = []
    current = None
    for line in raw.splitlines():
        if re.match(r"\s*\d+\s+Thread_", line):
            current = {"index": len(threads), "frames": []}
            if len(threads) < MAX_THREADS:
                threads.append(current)
            continue
        frame = re.match(
            r"\s*([+!:| ]*)(\d+)\s+(.+?)\s+\(in ([^)]+)\)(.*?)\[0x([\da-fA-F]+)\]\s*$",
            line,
        )
        if frame and current is not None and len(current["frames"]) < MAX_FRAMES:
            offset = re.fullmatch(r"\s*\+\s*(\d+)\s*", frame[5])
            item = {
                "image": _image(frame[4]),
                "symbol": _symbol(frame[3]),
                "symbolOffset": int(offset[1]) if offset else None,
                "address": int(frame[6], 16),
                "samples": _number(int(frame[2])),
                "depth": min(len(re.findall(r"[+!:|]", frame[1])), 256),
            }
            # Release frameworks often have no exported symbol. Apple's sample
            # then uses a load-address suffix instead of a symbol offset.
            loaded = re.fullmatch(
                r"\s*load address 0x([\da-fA-F]+)\s*\+\s*(0x[\da-fA-F]+|\d+)\s*",
                frame[5],
            )
            if loaded:
                item["imageBase"] = int(loaded[1], 16)
                item["imageOffset"] = int(
                    loaded[2], 16 if loaded[2].startswith("0x") else 10
                )
            current["frames"].append(item)
    if not any(thread["frames"] for thread in threads):
        return None
    return {"format": "sample", "threads": threads}


def collect_crash(
    directories: list[Path], pid: int, started: float, wait_seconds: int = 20
) -> dict:
    deadline = time.monotonic() + wait_seconds
    while True:
        candidates = []
        for directory in directories:
            try:
                for path in islice(directory.glob("BiliSail*"), 256):
                    if path.is_symlink():
                        continue
                    stat = path.stat()
                    if (
                        path.suffix in {".ips", ".crash"}
                        and started - 2 <= stat.st_mtime
                        and stat.st_size <= MAX_REPORT_BYTES
                    ):
                        candidates.append((stat.st_mtime, path))
            except OSError:
                continue
        for _, path in sorted(candidates, key=lambda item: item[0], reverse=True)[:64]:
            try:
                with path.open("rb") as stream:
                    raw = stream.read(MAX_REPORT_BYTES + 1)
                if len(raw) <= MAX_REPORT_BYTES:
                    report = parse_report(
                        raw.decode("utf-8", errors="replace"), pid, started
                    )
                    if report is not None:
                        return {"status": "collected", **report}
            except OSError:
                continue
        if time.monotonic() >= deadline:
            return {"status": "not_found"}
        time.sleep(0.5)


def collect_sample(pid: int) -> dict:
    try:
        # Raw output remains in memory and is never written to an artifact/log.
        completed = subprocess.run(
            ["/usr/bin/sample", str(pid), "1", "1", "-file", "/dev/stdout"],
            capture_output=True,
            timeout=8,
            check=False,
        )
        if len(completed.stdout) <= MAX_REPORT_BYTES:
            parsed = parse_sample(
                completed.stdout.decode("utf-8", errors="replace"), pid
            )
            if parsed is not None:
                return {"status": "collected", **parsed}
        return {"status": "unavailable"}
    except subprocess.TimeoutExpired:
        return {"status": "timed_out"}
    except OSError:
        return {"status": "unavailable"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--started", required=True)
    parser.add_argument(
        "--phase",
        choices=["startup", "write", "read-delete", "verify-deleted", "cleanup"],
        required=True,
    )
    parser.add_argument("--mode", choices=["crash", "sample"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    started = timestamp(args.started)
    if args.pid <= 0 or started is None:
        return 1
    try:
        result = (
            collect_sample(args.pid)
            if args.mode == "sample"
            else collect_crash(
                [
                    Path.home() / "Library/Logs/DiagnosticReports",
                    Path("/Library/Logs/DiagnosticReports"),
                ],
                args.pid,
                started,
            )
        )
    except (OSError, ValueError, TypeError, RecursionError):
        result = {"status": "collector_error"}
    result.update({"version": 1, "phase": args.phase, "processId": args.pid})
    try:
        temporary = args.output.with_suffix(args.output.suffix + ".new")
        temporary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, args.output)
    except OSError:
        print("macOS stack diagnostics could not be saved.")
        return 1
    print(f"macOS {args.mode} diagnostics: {result['status']}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
