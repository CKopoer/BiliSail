import unittest

from analyze_android_rate_switches import analyze


def fixture():
    observations = [dict(monoUs=t * 1000, frameDrops=d, avsyncSeconds=av)
                    for t, d, av in [(0, 0, 0), (100, 0, 0), (500, 2, 0),
                                     (700, 2, .02), (750, 12, .4),
                                     (1200, 22, 0), (1500, 22, 0)]]
    return [dict(type='phase-start', stage='hold', monoUs=0, frameDrops=0),
            dict(type='phase-end', stage='hold', monoUs=1500000, frameDrops=22),
            dict(type='hold-observations', stage='hold', observations=observations,
                 touches=[dict(action='down', cycle=1, monoUs=100000),
                          dict(action='up', cycle=1, monoUs=700000)])]


class SwitchAttributionTest(unittest.TestCase):
    def test_release_drops_are_separated_from_sustained_hold(self):
        row = analyze(fixture())[0]
        self.assertEqual((row['heldDrops'], row['releaseWindowDrops'], row['otherDrops']), (2, 20, 0))
        self.assertAlmostEqual(row['cycles'][0]['releasePeakAvsyncMs'], 400)
        self.assertIn('native speed was not captured', row['rateObservation'])

    def test_native_rate_must_be_present_before_claiming_native_confirmation(self):
        events = fixture()
        for sample in events[-1]['observations']:
            sample['nativeRate'] = 1.0
        self.assertEqual(analyze(events)[0]['rateObservation'], 'native-speed')

    def test_missing_release_and_counter_resets_are_not_successes(self):
        events = fixture()
        events[-1]['touches'].pop()
        with self.assertRaisesRegex(ValueError, 'missing pointer-up'):
            analyze(events)
        events = fixture()
        events[-1]['observations'][2]['frameDrops'] = 30
        events[-1]['touches'][1]['monoUs'] = 500000
        with self.assertRaisesRegex(ValueError, 'counter reset'):
            analyze(events)

    def test_release_window_cannot_overlap_the_next_hold(self):
        events = fixture()
        record = events[-1]
        record['touches'] += [dict(action='down', cycle=2, monoUs=800000),
                              dict(action='up', cycle=2, monoUs=1200000)]
        rows = analyze(events)
        self.assertEqual(rows[0]['releaseWindowDrops'], 10)
        self.assertEqual(rows[0]['heldDrops'], 12)


if __name__ == '__main__':
    unittest.main()
