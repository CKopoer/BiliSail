"""Attribute video drops to native touch hold/release windows in saved probes."""

import argparse
import json
import pathlib


def analyze(events, release_window_ms=500):
    if not 0 < release_window_ms <= 2000:
        raise ValueError('Release window must be in (0, 2000] milliseconds')
    result = []
    for record in (row for row in events if row['type'] == 'hold-observations'):
        stage = record['stage']
        begin = next(row for row in events if row['type'] == 'phase-start' and row['stage'] == stage)
        end = next(row for row in events if row['type'] == 'phase-end' and row['stage'] == stage)
        observations = sorted((row for row in record['observations']
                               if begin['monoUs'] <= row['monoUs'] <= end['monoUs']),
                              key=lambda row: row['monoUs'])
        touches = sorted(record['touches'], key=lambda row: row['monoUs'])

        def before(time):
            return next((row for row in reversed(observations) if row['monoUs'] <= time), None)

        cycles = []
        for down in (row for row in touches if row['action'] == 'down'):
            up = next((row for row in touches if row['action'] == 'up'
                       and row['cycle'] == down['cycle']), None)
            if up is None:
                raise ValueError(f'{stage}: missing pointer-up for cycle {down["cycle"]}')
            next_down = next((row for row in touches if row['action'] == 'down'
                              and row['monoUs'] > up['monoUs']), None)
            release_end = min(up['monoUs'] + release_window_ms * 1000,
                              next_down['monoUs'] if next_down else end['monoUs'], end['monoUs'])
            first, released, last = before(down['monoUs']), before(up['monoUs']), before(release_end)
            if first is None or released is None or last is None:
                raise ValueError(f'{stage}: missing observations at a touch boundary')
            held_drops = released['frameDrops'] - first['frameDrops']
            release_drops = last['frameDrops'] - released['frameDrops']
            if min(held_drops, release_drops) < 0:
                raise ValueError(f'{stage}: native drop counter reset within a cycle')
            release_samples = [row for row in observations if up['monoUs'] <= row['monoUs'] <= release_end]
            cycles.append({
                'cycle': down['cycle'],
                'actualHoldMs': (up['monoUs'] - down['monoUs']) / 1000,
                'heldDrops': held_drops,
                'releaseWindowDrops': release_drops,
                'releasePeakAvsyncMs': max((abs(row['avsyncSeconds']) * 1000
                    for row in release_samples if row.get('avsyncSeconds') is not None), default=None),
                'nativeRateAvailable': any(row.get('nativeRate') is not None for row in release_samples),
            })
        total = end['frameDrops'] - begin['frameDrops']
        held = sum(row['heldDrops'] for row in cycles)
        release = sum(row['releaseWindowDrops'] for row in cycles)
        result.append({
            'stage': stage, 'releaseWindowMs': release_window_ms, 'cycles': cycles,
            'totalDrops': total, 'heldDrops': held, 'releaseWindowDrops': release,
            'otherDrops': total - held - release,
            'releaseSharePercent': release / total * 100 if total else 0,
            'rateObservation': 'native-speed' if all(row['nativeRateAvailable'] for row in cycles)
                               else 'snapshot-optimistic; native speed was not captured',
        })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', nargs='+', type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    parser.add_argument('--release-window-ms', type=int, default=500)
    args = parser.parse_args()
    rows = []
    for run in args.runs:
        events = [json.loads(line) for line in (run / 'events.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
        rows.extend(dict(run=run.name, **row) for row in analyze(events, args.release_window_ms))
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for row in rows:
        print(f"{row['run']}/{row['stage']}: held={row['heldDrops']}, "
              f"release={row['releaseWindowDrops']}, total={row['totalDrops']}, "
              f"release share={row['releaseSharePercent']:.1f}%")


if __name__ == '__main__':
    main()
