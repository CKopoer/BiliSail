import unittest

from analyze_android_video_cadence import gap_statistics


class VideoCadenceTest(unittest.TestCase):
    def test_orders_and_deduplicates_native_submissions(self):
        gaps, result = gap_statistics([3000, 1000, 1000, 2000])
        self.assertEqual(result['submissionCount'], 3)
        self.assertEqual(gaps, [(1000, 2000, 1), (2000, 3000, 1)])

    def test_a_hold_is_visible_even_when_overlay_frames_keep_arriving(self):
        _, result = gap_statistics([0, 16000, 32000, 340000, 356000])
        self.assertEqual(result['maxGapMs'], 308)
        self.assertEqual(result['gapsOver100Ms'], 1)

    def test_empty_or_single_submission_has_no_measurable_interval(self):
        for points in [[], [100]]:
            _, result = gap_statistics(points)
            self.assertIsNone(result['maxGapMs'])
            self.assertEqual(result['gapsOver50Ms'], 0)


if __name__ == '__main__':
    unittest.main()
