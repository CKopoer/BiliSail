"""Measure native video submission gaps, independently of Flutter overlay frames."""

import argparse
import csv
import io
import json
import pathlib
import subprocess


def gap_statistics(points):
    times = sorted(set(points))
    gaps = [(a, b, (b - a) / 1000) for a, b in zip(times, times[1:])]
    return gaps, {
        'submissionCount': len(times),
        'maxGapMs': max((row[2] for row in gaps), default=None),
        'gapsOver50Ms': sum(row[2] > 50 for row in gaps),
        'gapsOver100Ms': sum(row[2] > 100 for row in gaps),
    }


def analyze(run, binary, completed_only=False):
    events = [json.loads(line) for line in (run / 'events.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
    result = []
    for begin in (row for row in events if row['type'] == 'phase-start'):
        stage = begin['stage']
        end = next((row for row in events if row['type'] == 'phase-end' and row.get('stage') == stage), None)
        trace = run / f'{stage}.perfetto-trace'
        if end is None or not trace.exists():
            if completed_only:
                continue
            raise ValueError(f'Incomplete stage: {stage}')
        sql = f'''
WITH clock AS (
 SELECT AVG(ts-clock_value) AS offset FROM clock_snapshot WHERE clock_id=3
), points AS (
 SELECT t.tid,t.name,(s.ts+s.dur-clock.offset)/1000.0 AS mono_us
 FROM slice s JOIN thread_track tr ON s.track_id=tr.id
 JOIN thread t USING(utid) JOIN process p USING(upid) CROSS JOIN clock
 WHERE p.pid={begin['pid']} AND s.name='eglSwapBuffers' AND s.dur>0
 AND s.ts+s.dur>={begin['monoUs']}*1000+clock.offset
 AND s.ts+s.dur<={end['monoUs']}*1000+clock.offset
), busiest AS (SELECT tid FROM points GROUP BY tid ORDER BY COUNT(*) DESC LIMIT 1)
SELECT tid,name,mono_us FROM points WHERE tid=(SELECT tid FROM busiest) ORDER BY mono_us;
'''
        query = run / f'{stage}.cadence.sql'
        query.write_text(sql, encoding='utf-8')
        proc = subprocess.run([str(binary), 'query', '--format', 'csv', '-f', str(query), str(trace)],
                              capture_output=True, text=True, encoding='utf-8', timeout=90, check=True)
        rows = list(csv.DictReader(io.StringIO(proc.stdout)))
        if not rows:
            raise ValueError(f'No native EGL submissions: {stage}')
        gaps, statistics = gap_statistics([float(row['mono_us']) for row in rows])
        record = next((row for row in events if row['type'] == 'hold-observations' and row['stage'] == stage), None)
        cycles = []
        if record:
            for down in (row for row in record['touches'] if row['action'] == 'down'):
                up = next(row for row in record['touches'] if row['action'] == 'up' and row['cycle'] == down['cycle'])

                def maximum(start, finish):
                    return max((gap for a, b, gap in gaps if b >= start and a <= finish), default=None)

                cycles.append({
                    'cycle': down['cycle'],
                    'pressWindowMaxSubmissionGapMs': maximum(down['monoUs'] + 400000, up['monoUs']),
                    'releaseWindowMaxSubmissionGapMs': maximum(up['monoUs'], up['monoUs'] + 500000),
                })
        result.append(dict(run=run.name, stage=stage, thread=rows[0]['name'],
                           metric='completed eglSwapBuffers calls; not final display pixels',
                           **statistics, cycles=cycles))
        print(stage, 'native max gap', statistics['maxGapMs'], 'ms')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=pathlib.Path)
    parser.add_argument('--trace-processor', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = analyze(args.run, args.trace_processor, args.completed_only)
    args.output.write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
