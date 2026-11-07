"""A still-running trace writer must never be reported as ready to copy."""
import unittest
from unittest.mock import Mock, patch

from perfetto_capture import stop_and_wait


class TraceShutdownTest(unittest.TestCase):
    def test_waits_for_writer_exit(self):
        adb = Mock(side_effect=['', '42 (perfetto) S 1', '42 (perfetto) R 1', ''])
        with patch('perfetto_capture.time.sleep') as sleep:
            stop_and_wait(adb, 42)
        self.assertEqual(sleep.call_count, 2)
        self.assertEqual(adb.call_args.args, ('shell', 'cat', '/proc/42/stat'))

    def test_zombie_has_already_closed_output(self):
        adb = Mock(side_effect=['', '42 (perfetto) Z 1'])
        stop_and_wait(adb, 42)

    def test_running_writer_at_deadline_is_a_failure(self):
        adb = Mock(return_value='42 (perfetto) S 1')
        with self.assertRaises(TimeoutError):
            stop_and_wait(adb, 42, timeout=0)


if __name__ == '__main__':
    unittest.main()
