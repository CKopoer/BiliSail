"""Synthetic Apple report fixtures; never use account data or real crash reports."""

import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

import macos_crash_diagnostics as diagnostics


class CrashDiagnosticsTest(unittest.TestCase):
    def ips(self, **overrides):
        report = {
            "pid": 42,
            "procName": "BiliSail",
            "procLaunch": "2026-10-31 07:00:00.000 +0000",
            "captureTime": "2026-10-31 07:00:07.000 +0000",
            "procPath": "/Users/private/BiliSail.app/Contents/MacOS/BiliSail",
            "asi": {
                "private": ["Cookie: private; https://example.invalid/?token=private"]
            },
            "exception": {
                "type": "EXC_BAD_ACCESS",
                "signal": "SIGSEGV",
                "subtype": "KERN_INVALID_ADDRESS at 0x0000000000000000",
            },
            "faultingThread": 1,
            "threads": [
                {
                    "queue": "private",
                    "frames": [
                        {
                            "imageIndex": 0,
                            "imageOffset": 12,
                            "symbol": "main",
                            "symbolLocation": 4,
                        }
                    ],
                },
                {
                    "triggered": True,
                    "frames": [
                        {
                            "imageIndex": 1,
                            "imageOffset": 128,
                            "symbol": "flutter::Shell::OnPlatformViewDestroyed()",
                            "symbolLocation": 8,
                        }
                    ],
                },
            ],
            "usedImages": [
                {
                    "name": "BiliSail",
                    "arch": "x86_64",
                    "uuid": "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "path": "/Users/private/BiliSail",
                    "base": 4096,
                },
                {
                    "name": "FlutterMacOS",
                    "arch": "x86_64",
                    "path": "/Users/private/FlutterMacOS",
                    "base": 8192,
                },
            ],
        }
        report.update(overrides)
        return (
            json.dumps(
                {"bug_type": "309", "name": "BiliSail", "incident_id": "private"}
            )
            + "\n"
            + json.dumps(report)
        )

    def test_ips_keeps_only_owned_process_and_symbolic_stacks(self):
        result = diagnostics.parse_report(self.ips(), 42, 1793430000)
        self.assertEqual(
            result["exception"], {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"}
        )
        self.assertEqual(result["faultingThread"], 1)
        self.assertEqual(
            result["threads"][1]["frames"][0]["symbol"],
            "flutter::Shell::OnPlatformViewDestroyed()",
        )
        self.assertEqual(result["threads"][1]["frames"][0]["imageOffset"], 128)
        self.assertNotRegex(
            json.dumps(result), r"private|/Users|Cookie|token|incident|procPath|queue"
        )

    def test_wrong_pid_name_and_old_launch_are_rejected(self):
        for overrides in (
            {"pid": 99},
            {"procName": "OtherApp"},
            {"procLaunch": "2025-01-01 00:00:00.000 +0000"},
        ):
            with self.subTest(overrides=overrides):
                self.assertIsNone(
                    diagnostics.parse_report(self.ips(**overrides), 42, 1793430000)
                )

    def test_timestamp_normalizes_apple_and_powershell_precision(self):
        for value in (
            "2026-10-31 07:00:00.000 +0000",
            "2026-10-31T07:00:00.0000000+00:00",
            "2026-10-31T07:00:00Z",
        ):
            with self.subTest(value=value):
                self.assertEqual(diagnostics.timestamp(value), 1793430000)
        self.assertIsNone(diagnostics.timestamp(None))
        self.assertIsNone(diagnostics.timestamp("2026-10-31 07:00:00"))
        self.assertIsNone(diagnostics.parse_report("Process: Other [42]", 42, 0))
        self.assertIsNotNone(
            diagnostics.parse_report("\ufeff" + self.ips(), 42, 1793430000)
        )

    def test_worker_identity_is_explicit_and_does_not_match_other_processes(self):
        raw = self.ips(procName="pwsh")
        self.assertIsNone(diagnostics.parse_report(raw, 42, 1793430000))
        self.assertIsNotNone(diagnostics.parse_report(raw, 42, 1793430000, "pwsh"))
        self.assertIsNone(diagnostics.parse_report(raw, 42, 1793430000, "OtherApp"))
        sample = (
            "Process: pwsh [42]\n  99 Thread_123\n + 99 main (in pwsh) + 1 [0x1000]\n"
        )
        self.assertIsNone(diagnostics.parse_sample(sample, 42))
        self.assertIsNotNone(diagnostics.parse_sample(sample, 42, "pwsh"))
        self.assertIsNone(diagnostics.parse_sample(sample, 42, "OtherApp"))
        self.assertEqual(
            diagnostics.collect_crash([], 42, 0, 0, "OtherApp"),
            {"status": "unavailable"},
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pwsh-current.ips").write_text(raw, encoding="utf-8")
            self.assertEqual(
                diagnostics.collect_crash([root], 42, 1793430000, 0, "pwsh")["status"],
                "collected",
            )

    def test_malformed_or_other_report_type_is_rejected(self):
        for raw in ("private", "{}", self.ips().replace('"309"', '"288"', 1)):
            with self.subTest(raw=raw[:20]):
                self.assertIsNone(diagnostics.parse_report(raw, 42, 1793430000))

    def test_unsafe_symbol_and_module_do_not_escape(self):
        result = diagnostics.parse_report(
            self.ips(
                threads=[
                    {
                        "triggered": True,
                        "frames": [
                            {
                                "imageIndex": 0,
                                "imageOffset": 1,
                                "symbol": "https://example.invalid/?token=private",
                            }
                        ],
                    }
                ],
                usedImages=[
                    {"name": "/Users/private/library", "path": "/Users/private/library"}
                ],
            ),
            42,
            1793430000,
        )
        self.assertEqual(result["threads"][0]["frames"][0]["symbol"], None)
        self.assertNotRegex(json.dumps(result), r"private|Users|token|https")

    def test_thread_and_frame_counts_are_bounded_and_crashed_thread_is_kept(self):
        frame = {"imageIndex": 0, "imageOffset": 1, "symbol": "main"}
        result = diagnostics.parse_report(
            self.ips(
                faultingThread=99,
                threads=[{"frames": [frame] * 200} for _ in range(100)],
            ),
            42,
            1793430000,
        )
        self.assertLessEqual(len(result["threads"]), 32)
        self.assertIn(99, [thread["index"] for thread in result["threads"]])
        self.assertTrue(
            all(len(thread["frames"]) <= 96 for thread in result["threads"])
        )

    def test_legacy_crash_report_is_sanitized(self):
        raw = """Process: BiliSail [42]
Path: /Users/private/BiliSail.app/Contents/MacOS/BiliSail
Date/Time: 2026-10-31 07:00:07.000 +0000
Exception Type: EXC_BAD_ACCESS (SIGSEGV)
Crashed Thread: 0
Application Specific Information: Cookie: private
Thread 0 Crashed:: Dispatch queue: private
0   FlutterMacOS  0x0000000100000080 flutter::Shell::OnPlatformViewDestroyed() + 8
1   BiliSail      0x000000010000000c main + 4
Thread 1:
0   libsystem_kernel.dylib 0x0000000100000000 mach_msg_trap + 10
Binary Images:
0x100000000 - 0x10000ffff FlutterMacOS x86_64 <01234567-89AB-CDEF-0123-456789ABCDEF> /Users/private/FlutterMacOS
"""
        result = diagnostics.parse_report(raw, 42, 1793430000)
        self.assertEqual(result["format"], "crash")
        self.assertEqual(result["threads"][0]["frames"][0]["image"], "FlutterMacOS")
        self.assertNotIn("private", json.dumps(result))

    def test_sample_keeps_backtrace_without_paths_or_arguments(self):
        raw = """Sampling process 42 for 1 second
Process: BiliSail [42]
Path: /Users/private/BiliSail.app
Call graph:
    99 Thread_123 DispatchQueue_1: private
    + 99 start (in dyld) + 123 [0x1000]
    + ! 99 -[NSApplication run] (in AppKit) + 42 [0x2000]
    + ! : 99 flutter::Shell::RunEngine() (in FlutterMacOS) + 8 [0x3000]
Binary Images:
private https://example.invalid/?token=private
"""
        result = diagnostics.parse_sample(raw, 42)
        self.assertEqual(result["format"], "sample")
        self.assertEqual(
            [frame["image"] for frame in result["threads"][0]["frames"]],
            ["dyld", "AppKit", "FlutterMacOS"],
        )
        self.assertNotRegex(json.dumps(result), r"private|/Users|DispatchQueue|token")
        self.assertIsNone(diagnostics.parse_sample(raw, 43))
        self.assertIsNone(diagnostics.parse_sample("Process: BiliSail [42]\n", 42))

    def test_sample_retains_unsymbolicated_release_frames(self):
        raw = """Process: BiliSail [42]
    99 Thread_123
    + ! 99 ??? (in FlutterMacOS) load address 0x1000 + 0x80 [0x1080]
    + ! : 99 ??? (in App) load address 0x2000 + 256 [0x2100]
    + 5 Cookie=private (in App) unrecognized private suffix [0x2200]
"""
        frames = diagnostics.parse_sample(raw, 42)["threads"][0]["frames"]
        self.assertEqual(
            [frame["image"] for frame in frames], ["FlutterMacOS", "App", "App"]
        )
        self.assertEqual(frames[0]["imageBase"], 4096)
        self.assertEqual(frames[0]["imageOffset"], 128)
        self.assertEqual(frames[1]["imageOffset"], 256)
        self.assertEqual(frames[0]["samples"], 99)
        self.assertEqual(frames[0]["depth"], 2)
        self.assertNotIn("private", json.dumps(frames))

    def test_collector_filters_size_age_pid_and_ignores_malformed_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "BiliSail-old.ips").write_text(self.ips(pid=99), encoding="utf-8")
            (root / "BiliSail-broken.ips").write_text("broken", encoding="utf-8")
            (root / "BiliSail-current.ips").write_text(self.ips(), encoding="utf-8")
            result = diagnostics.collect_crash([root], 42, 1793430000, wait_seconds=0)
            self.assertEqual(result["status"], "collected")
            self.assertNotIn("private", json.dumps(result))
            with patch.object(diagnostics, "MAX_REPORT_BYTES", 1):
                self.assertEqual(
                    diagnostics.collect_crash([root], 42, 1793430000, wait_seconds=0)[
                        "status"
                    ],
                    "not_found",
                )

    def test_missing_report_has_explicit_status_and_bounded_wait(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(
                diagnostics.time, "monotonic", side_effect=[0, 0, 2]
            ), patch.object(diagnostics.time, "sleep") as sleep:
                result = diagnostics.collect_crash(
                    [Path(directory)], 42, 0, wait_seconds=1
                )
            self.assertEqual(result, {"status": "not_found"})
            self.assertEqual(sleep.call_count, 1)

    def test_malformed_field_types_cannot_export_arbitrary_data(self):
        for overrides in (
            {"exception": {"type": []}},
            {"procLaunch": "private"},
            {"threads": "private"},
            {"usedImages": "private"},
        ):
            with self.subTest(overrides=overrides):
                result = diagnostics.parse_report(self.ips(**overrides), 42, 1793430000)
                self.assertNotIn("private", json.dumps(result))
        for symbol in (
            "Cookie=private",
            "Authorization: private",
            "token=private",
            "x" * 1025,
        ):
            self.assertIsNone(diagnostics._symbol(symbol))

    def test_sample_tool_timeout_and_failure_have_fixed_status(self):
        for error, expected in (
            (OSError("private"), "unavailable"),
            (subprocess.TimeoutExpired("private", 8), "timed_out"),
        ):
            with self.subTest(expected=expected), patch.object(
                diagnostics.subprocess, "run", side_effect=error
            ):
                self.assertEqual(diagnostics.collect_sample(42), {"status": expected})
        with patch.object(
            diagnostics.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 1, b"private", b"private"),
        ):
            self.assertEqual(diagnostics.collect_sample(42), {"status": "unavailable"})
        sample = b"Process: BiliSail [42]\n  99 Thread_123\n + 99 main (in BiliSail) + 1 [0x1000]\n"
        with patch.object(
            diagnostics.subprocess,
            "run",
            return_value=subprocess.CompletedProcess([], 0, sample, b"private"),
        ):
            self.assertEqual(
                diagnostics.collect_sample(42)["threads"][0]["frames"][0]["symbol"],
                "main",
            )

    def test_cli_writes_only_sanitized_json_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "startup.crash.json"
            args = [
                "collector",
                "--pid",
                "42",
                "--started",
                "2026-10-31T07:00:00Z",
                "--phase",
                "startup",
                "--mode",
                "crash",
                "--output",
                str(output),
            ]
            with patch.object(sys, "argv", args), patch.object(
                diagnostics, "collect_crash", return_value={"status": "not_found"}
            ):
                self.assertEqual(diagnostics.main(), 0)
            self.assertEqual(json.loads(output.read_text())["status"], "not_found")
            self.assertFalse(output.with_suffix(".json.new").exists())
            with patch.object(sys, "argv", args), patch.object(
                diagnostics, "collect_crash", side_effect=OSError("private")
            ):
                self.assertEqual(diagnostics.main(), 0)
            self.assertEqual(
                json.loads(output.read_text())["status"], "collector_error"
            )
            self.assertNotIn("private", output.read_text())


if __name__ == "__main__":
    unittest.main()
