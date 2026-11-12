"""Summarize the surface probe without treating unavailable native values as zero."""
import argparse
import csv
import io
import json
import math
from pathlib import Path
import subprocess


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[math.ceil((len(ordered) - 1) * fraction)] if ordered else None


def cpu_summary(trace, binary, start, end):
    # Count application CPU work via Android UID.
    sql = f"""WITH offset AS (SELECT AVG(ts-clock_value) AS ns FROM clock_snapshot WHERE clock_id=3),
requested AS (SELECT {start['monoUs']}*1000+ns AS first,{end['monoUs']}*1000+ns AS last FROM offset),
available AS (SELECT MIN(ts) AS first,
  MAX(ts+dur) AS last FROM sched WHERE dur>0),
bounds AS (SELECT MAX(r.first,a.first) AS first,MIN(r.last,a.last) AS last FROM requested r,available a)
SELECT p.pid,p.name,SUM(MIN(s.ts+s.dur,b.last)-MAX(s.ts,b.first))/1e6 AS cpu_ms,
  (b.last-b.first)/1e6 AS window_ms
FROM sched s JOIN thread t USING(utid) JOIN process p USING(upid) CROSS JOIN bounds b
WHERE p.uid=(SELECT uid FROM process WHERE pid={start['pid']} LIMIT 1)
AND s.dur>0 AND s.ts<b.last AND s.ts+s.dur>b.first GROUP BY p.upid;
"""
    query = trace.with_suffix('.surface.sql')
    query.write_text(sql, encoding='utf-8')
    result = subprocess.run([str(binary), 'query', '--format', 'csv', '-f', str(query), str(trace)],
                            capture_output=True, text=True, encoding='utf-8', timeout=90, check=True)
    rows = list(csv.DictReader(io.StringIO(result.stdout)))
    if not rows:
        raise ValueError(f'No application UID CPU samples: {trace}')
    elapsed_ms = float(rows[0]['window_ms'])
    return {
        'processes': [{'pid': int(row['pid']), 'name': row['name'], 'cpuMs': float(row['cpu_ms'])} for row in rows],
        'cpuPercentOneCore': sum(float(row['cpu_ms']) for row in rows) / elapsed_ms * 100,
        'coveredSeconds': elapsed_ms/1000,
        'coverageFraction': elapsed_ms/((end['monoUs']-start['monoUs'])/1000),
    }


def summarize(folder, binary):
    events = [json.loads(line) for line in (folder / 'events.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
    output = []
    for start in (row for row in events if row['type'] == 'phase-start'):
        stage = start['stage']
        end = next((row for row in events if row['type'] == 'phase-end' and row['stage'] == stage), None)
        if end is None:
            continue
        samples = [row for row in events if row.get('stage') == stage and row['type'] in ('phase-start', 'sample', 'phase-end')]
        metadata = next(row for row in events if row.get('stage') == stage and row['type'] == 'metadata')
        config = next(row['scenario'] for row in events if row.get('stage') == stage and row['type'] == 'stage-config')
        gpu = [json.loads(line) for line in (folder / f'{stage}.gpu.jsonl').read_text().splitlines() if line]
        valid_gpu = [row for row in gpu if row.get('totalUs', 0) > 0]
        ui = [value / 1000 for row in samples for value in row['uiUs']]
        raster = [value / 1000 for row in samples for value in row['rasterUs']]
        presents = sorted({value[1] for row in gpu for value in row.get('surfaceTimesNs', []) if 0 < value[1] < 2**63-1})
        gaps = [(b-a)/1e6 for a, b in zip(presents, presents[1:])]
        elapsed = (end['monoUs'] - start['monoUs']) / 1e6
        drops = [row['frameDrops'] for row in samples if row.get('frameDrops') is not None]
        av = [abs(row['avsyncSeconds']) for row in samples if row.get('avsyncSeconds') is not None]
        output.append({
            'run': folder.name, 'stage': stage, 'backend': config['backend'],
            'requestedRate': config.get('rate', 3),
            'requestedRateAchieved': abs((end['positionMs']-start['positionMs'])/1000/elapsed - config.get('rate', 3)) <= max(.1, config.get('rate', 3)*.05),
            'requestedDirect': config['direct'], 'presentation': metadata.get('presentation', 'Flutter.Texture'),
            'actualOutput': metadata['videoOutput'], 'hwdec': metadata['hwdec'],
            'seconds': elapsed,
            'mediaSecondsPerWallSecond': (end['positionMs']-start['positionMs'])/1000/elapsed,
            'gpuBusyPercent': sum(row['busyUs'] for row in valid_gpu)/sum(row['totalUs'] for row in valid_gpu)*100 if valid_gpu else None,
            'uiP95Ms': percentile(ui, .95), 'rasterP95Ms': percentile(raster, .95),
            'flutterFramesPerSecond': sum(row['dartFrames'] for row in samples)/elapsed,
            'nativeFrameDropDelta': drops[-1]-drops[0] if drops else None,
            'nativeAvSyncAbsMaxMs': max(av)*1000 if av else None,
            'cacheBytesMax': max((row['cacheBytes'] for row in samples if row.get('cacheBytes') is not None), default=None),
            'cacheSecondsMax': max((row['cacheSeconds'] for row in samples if row.get('cacheSeconds') is not None), default=None),
            'allControlsVisible': all(row.get('controlsVisible') is True for row in samples),
            'allSubtitlesPresent': all(bool(row.get('subtitle')) for row in samples),
            'minimumVisibleComments': min(row['visible'] for row in samples),
            'observedLayerPresentHz': (len(presents)-1)/((presents[-1]-presents[0])/1e9) if len(presents)>1 else None,
            'observedLayerMaxGapMs': max(gaps) if gaps else None,
            'cpu': cpu_summary(folder/f'{stage}.perfetto-trace', binary, start, end) if binary else None,
        })
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs', type=Path, nargs='+')
    parser.add_argument('--trace-processor', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = [row for folder in args.runs for row in summarize(folder, args.trace_processor)]
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for row in rows:
        print(row['stage'], 'GPU', row['gpuBusyPercent'], 'CPU', (row['cpu'] or {}).get('cpuPercentOneCore'),
              'speed', round(row['mediaSecondsPerWallSecond'], 3))


if __name__ == '__main__':
    main()
