"""Summarize completed local playback runs, excluding warmup and partial PDH intervals."""

import argparse
import csv
import datetime as dt
import json
import math
import pathlib
import re
import statistics


def load(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line]


def stamp(value):
    return dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def percentile(values, fraction):
    values = sorted(values)
    return values[math.ceil((len(values) - 1) * fraction)] if values else None


def mean(values):
    return statistics.mean(values) if values else None


def summarize(folder, label):
    rows = load(folder / f'{label}.playback.jsonl')
    if rows[-1]['type'] != 'complete':
        raise ValueError(f'Incomplete run: {label}')
    metadata = next(r for r in rows if r['type'] == 'metadata')
    counters = load(folder / f'{label}.counters.jsonl')
    fixture = json.loads((folder / f'{label}.fixture.json').read_text(encoding='utf-8-sig'))
    clocks = []
    clock_file = folder / f'{label}.clocks.csv'
    if clock_file.exists():
        for row in csv.reader(clock_file.read_text(encoding='utf-8-sig').splitlines()):
            if len(row) == 7:
                # nvidia-smi's wall clock is local Windows time; record the offset.
                local = dt.datetime.strptime(row[0].strip(), '%Y/%m/%d %H:%M:%S.%f')
                clocks.append((local.astimezone().timestamp(), [x.strip() for x in row[1:]]))
    result = []
    for begin in [r for r in rows if r['type'] == 'phase-start']:
        stage = begin['stage']
        end = next(r for r in rows if r['type'] == 'phase-end' and r['stage'] == stage)
        start_t, end_t = stamp(begin['timeUtc']), stamp(end['timeUtc'])
        samples = [r for r in rows if r['type'] == 'sample' and r['stage'] == stage]
        last = samples[-1]
        selected = [r for r in counters if r['intervalStartUtc'] and
                    start_t <= stamp(r['intervalStartUtc']) and stamp(r['timeUtc']) <= end_t]
        if len(selected) < metadata['seconds'] * .7:
            raise ValueError(f'Insufficient GPU samples: {label}/{stage}')
        luids = {e['luid'] for r in selected for e in r['processEngines'] if e['percent'] > .1}
        if len(luids) != 1:
            raise ValueError(f'Unexpected active GPU adapters: {luids}')
        luid = luids.pop()

        def engine_load(key, kind):
            return [sum(e['percent'] for e in r[key] if e['luid'] == luid and e['type'] == kind)
                    for r in selected]

        cpu = []
        for before, after in zip(counters, counters[1:]):
            if start_t <= stamp(before['timeUtc']) < stamp(after['timeUtc']) <= end_t:
                cpu.append((after['cpuSeconds'] - before['cpuSeconds']) /
                           (stamp(after['timeUtc']) - stamp(before['timeUtc'])) * 100)
        ui = [v / 1000 for r in samples for v in r['uiUs']]
        raster = [v / 1000 for r in samples for v in r['rasterUs']]
        total = [v / 1000 for r in samples for v in r['totalUs']]
        busy = [max(u, r) for u, r in zip(ui, raster)]
        steady_clocks = [v for t, v in clocks if start_t <= t <= end_t]
        duration = end['elapsedMs'] / 1000
        paints = last['imagePaints'] - begin['imagePaints']
        entry = {
            'label': label, 'stage': stage, 'arrivalsPerSecond': metadata['arrivals'],
            'fullscreen': metadata['fullscreen'], 'profile': metadata['profile'],
            'release': metadata['release'], 'seconds': duration,
            'gpuSamples': len(selected), 'luid': luid,
            'process3dMean': mean(engine_load('processEngines', '3d')),
            'process3dP95': percentile(engine_load('processEngines', '3d'), .95),
            'videoDecodeMean': mean(engine_load('processEngines', 'videodecode')),
            'copyMean': mean(engine_load('processEngines', 'copy')),
            'dwm3dMean': mean(engine_load('dwmEngines', '3d')),
            'whole3dMean': mean(engine_load('wholeEngines', '3d')),
            'cpuOneCorePercent': mean(cpu),
            'workingSetPeakMiB': max(r['workingSetBytes'] for r in selected) / 2**20,
            'privatePeakMiB': max(r['privateBytes'] for r in selected) / 2**20,
            'dartFps': sum(r['dartFrames'] for r in samples) / duration,
            'uiP95Ms': percentile(ui, .95), 'rasterP95Ms': percentile(raster, .95),
            'rasterP99Ms': percentile(raster, .99), 'rasterMaxMs': max(raster),
            'totalP95Ms': percentile(total, .95),
            'busyOver16_67': sum(v > 1000 / 60 for v in busy),
            'busyOver6_06': sum(v > 1000 / 165 for v in busy),
            'frameCount': len(busy),
            'visibleMean': mean([r['visible'] for r in samples]),
            'visibleMin': min(r['visible'] for r in samples),
            'visibleMax': max(r['visible'] for r in samples),
            'commentDropDelta': last['droppedComments'] - begin['droppedComments'],
            'pendingMax': max(r['pending'] for r in samples),
            'controlsVisible': sorted({r['controlsVisible'] for r in samples}),
            'rasterCachePeakMiB': max(r['rasterBytes'] for r in samples) / 2**20,
            'cacheHitPercent': (last['cacheHits'] - begin['cacheHits']) / paints * 100 if paints else None,
            'rasterBuilds': last['rasterBuilds'] - begin['rasterBuilds'],
            'directPaints': last['directPaints'] - begin['directPaints'],
            'frameDropDelta': last['frameDrops'] - begin['frameDrops'],
            'decoderDropDelta': last['decoderDrops'] - begin['decoderDrops'],
            'frameDropStart': begin['frameDrops'], 'frameDropEnd': last['frameDrops'],
            'maxAvsyncMs': max(abs(r['avsyncSeconds']) * 1000 for r in samples),
            'positionStartMs': begin['positionMs'], 'positionEndMs': last['positionMs'],
            'mediaAdvancePerWallSecond': (last['positionMs'] - begin['positionMs']) / 1000 / duration,
            'hwdec': sorted({r['hwdec'] for r in samples}),
            'decoded': sorted({tuple(r['decoded']) for r in samples}),
            'output': sorted({tuple(r['output']) for r in samples}),
            'surface': sorted({tuple(r['surface']) for r in samples}),
            'refreshRateApi': sorted({r['refreshRate'] for r in samples}),
            'buffering': any(r['buffering'] or r['seeking'] for r in samples),
            'errors': max(r['errors'] for r in samples),
            'pstates': sorted({v[0] for v in steady_clocks}),
            'gpuClockMeanMHz': mean([float(v[1]) for v in steady_clocks]),
            'gpuPowerMeanW': mean([float(v[5]) for v in steady_clocks]),
            'fixtureSha256': fixture['mediaSha256'],
        }
        result.append(entry)
        print(f"{label}/{stage}: 3D {entry['process3dMean']:.2f}%, "
              f"decode {entry['videoDecodeMean']:.2f}%, CPU {entry['cpuOneCorePercent']:.1f}% of one core, "
              f"raster95 {entry['rasterP95Ms']:.3f}ms, fps {entry['dartFps']:.1f}, "
              f"visible {entry['visibleMean']:.1f}, drops {entry['frameDropDelta']}/{entry['decoderDropDelta']}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('labels', nargs='+')
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    if any(not re.fullmatch(r'[A-Za-z0-9_-]+', label) for label in args.labels):
        parser.error('Labels must contain only letters, digits, underscores and hyphens')
    folder = pathlib.Path(__file__).resolve().parents[2] / 'build/validation/4k60'
    rows = [row for label in args.labels for row in summarize(folder, label)]
    output = args.output or folder / 'summary.json'
    output.write_text(json.dumps(rows, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
