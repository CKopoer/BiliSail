"""Combine Dart timings, native counters, GPU samples and clipped Perfetto CPU data."""
import argparse
import json
import math
import pathlib
import re
import statistics
import subprocess


def load(path):
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line]


def percentile(values, fraction):
    values = sorted(values)
    return values[math.ceil((len(values)-1)*fraction)] if values else None


def mean(values):
    return statistics.mean(values) if values else None


def source_url(value):
    if not value:
        return value
    repo_uri = pathlib.Path(__file__).resolve().parents[2].as_uri() + '/'
    if value.startswith(repo_uri):
        return 'repository:' + value[len(repo_uri):]
    if '/flutter/packages/flutter/' in value:
        return 'flutter-sdk:' + value.split('/flutter/', 1)[1]
    if value.startswith('file:'):
        return 'external:' + '/'.join(value.split('/')[-3:])
    return value


def hold_summary(events, stage, begin, end, delay_ms):
    record = next((x for x in events if x['type'] == 'hold-observations'
                   and x.get('stage') == stage), None)
    if not record:
        return None
    samples = [x for x in record['observations'] if begin <= x['monoUs'] <= end]
    native_samples = [x for x in samples if x.get('nativeRate') is not None]
    rate_key = 'nativeRate' if samples and len(native_samples) == len(samples) else 'rate'
    touches = record['touches']
    cycles = []
    for down in [x for x in touches if x['action'] == 'down']:
        up = next((x for x in touches if x['action'] == 'up' and x['cycle'] == down['cycle']), None)
        next_down = next((x for x in touches if x['action'] == 'down' and x['monoUs'] > down['monoUs']), None)
        fast = next((x for x in samples if down['monoUs'] <= x['monoUs'] < (up['monoUs'] if up else end)
                     and x[rate_key] == 2), None)
        restored = next((x for x in samples if up and up['monoUs'] <= x['monoUs'] <
                         (next_down['monoUs'] if next_down else end) and x[rate_key] == 1), None)
        cycles.append({'cycle': down['cycle'], 'downMonoUs': down['monoUs'],
                       'upMonoUs': up['monoUs'] if up else None,
                       'pressTo2xMs': (fast['monoUs']-down['monoUs'])/1000 if fast else None,
                       'afterHoldThresholdMs': (fast['monoUs']-down['monoUs'])/1000-delay_ms if fast else None,
                       'releaseTo1xMs': (restored['monoUs']-up['monoUs'])/1000 if restored else None})
    gaps = []
    if samples:
        last_change = samples[0]['monoUs']
        previous_position = samples[0]['positionMs']
        for row in samples[1:]:
            if row['positionMs'] != previous_position:
                gaps.append((row['monoUs']-last_change)/1000)
                last_change = row['monoUs']
                previous_position = row['positionMs']
        gaps.append((samples[-1]['monoUs']-last_change)/1000)
    return {'observationCount': len(samples), 'observationIntervalMs': 50,
            'rateLatencyBasis': 'native-speed' if rate_key == 'nativeRate' else 'snapshot-optimistic',
            'nativeRateObservationCount': len(native_samples),
            'nativeSampledRates': sorted({x['nativeRate'] for x in native_samples}),
            'cycles': cycles, 'completedCycles': sum(x['pressTo2xMs'] is not None and
                x['releaseTo1xMs'] is not None for x in cycles),
            'sampledRates': sorted({x['rate'] for x in samples}),
            'maxPositionUpdateGapMs': max(gaps, default=None),
            'bufferingObservations': sum(x['buffering'] for x in samples),
            'maxAvsyncMs': max((abs(x['avsyncSeconds'])*1000 for x in samples
                               if x.get('avsyncSeconds') is not None), default=None)}


def trace_summary(binary, trace, begin, end, pid):
    # Dart Timeline uses MONOTONIC; Android Perfetto uses BOOTTIME. Map using
    # clock snapshots, not wall time or the host/USB command's arrival time.
    sql = f'''
CREATE PERFETTO VIEW probe_bounds AS
 SELECT {begin*1000}+CAST(AVG(ts-clock_value) AS INT) AS begin_ns,
        {end*1000}+CAST(AVG(ts-clock_value) AS INT) AS end_ns
 FROM clock_snapshot WHERE clock_id=3;
CREATE PERFETTO VIEW cpu_bounds AS
 SELECT MAX(begin_ns,(SELECT MAX(first) FROM
   (SELECT MIN(ts) AS first FROM sched GROUP BY cpu))) AS begin_ns,
 MIN(end_ns,(SELECT MAX(ts+dur) FROM sched WHERE dur>0)) AS end_ns
 FROM probe_bounds;
WITH cpu AS (
 SELECT t.tid,t.name,SUM(MIN(s.ts+s.dur,b.end_ns)-MAX(s.ts,b.begin_ns))/1e6 AS ms
 FROM sched s JOIN thread t USING(utid) JOIN process p USING(upid) CROSS JOIN cpu_bounds b
 WHERE p.pid={pid} AND s.dur>0 AND s.ts<b.end_ns AND s.ts+s.dur>b.begin_ns
 GROUP BY t.utid ORDER BY ms DESC LIMIT 20
), slices AS (
 SELECT t.tid,t.name AS thread_name,s.name,COUNT(*) AS count,
 SUM(MIN(s.ts+s.dur,b.end_ns)-MAX(s.ts,b.begin_ns))/1e6 AS ms,MAX(s.dur)/1e6 AS max_ms
 FROM slice s JOIN thread_track tr ON s.track_id=tr.id JOIN thread t USING(utid)
 JOIN process p USING(upid) CROSS JOIN cpu_bounds b
 WHERE p.pid={pid} AND s.dur>0 AND s.ts<b.end_ns AND s.ts+s.dur>b.begin_ns
 GROUP BY t.utid,s.name ORDER BY ms DESC LIMIT 25
), states AS (
 SELECT t.name,s.state,s.blocked_function,SUM(MIN(s.ts+s.dur,b.end_ns)-MAX(s.ts,b.begin_ns))/1e6 AS ms
 FROM thread_state s JOIN thread t USING(utid) JOIN process p USING(upid) CROSS JOIN cpu_bounds b
 WHERE p.pid={pid} AND s.dur>0 AND s.ts<b.end_ns AND s.ts+s.dur>b.begin_ns
 AND (t.name LIKE '%raster%' OR t.name LIKE '%.ui') GROUP BY t.utid,s.state,s.blocked_function
)
SELECT 'bounds' AS kind,json_object('startNs',begin_ns,'endNs',end_ns,'seconds',(end_ns-begin_ns)/1e9) AS data FROM cpu_bounds
UNION ALL SELECT 'cpu',json_object('tid',tid,'thread',name,'cpuMs',ms) FROM cpu
UNION ALL SELECT 'slice',json_object('tid',tid,'thread',thread_name,'name',name,'inclusiveMs',ms,'maxMs',max_ms,'count',count) FROM slices
UNION ALL SELECT 'state',json_object('thread',name,'state',state,'blockedFunction',blocked_function,'ms',ms) FROM states
UNION ALL SELECT 'stats',json_object('name',name,'value',value,'severity',severity)
 FROM stats WHERE value>0 AND (severity='error' OR name LIKE '%overwrit%' OR name LIKE '%lost%');
'''
    query_file = trace.with_suffix('.analysis.sql')
    query_file.write_text(sql, encoding='utf-8')
    result = subprocess.run([str(binary), 'query', '--format', 'csv', '-f', str(query_file), str(trace)],
                            capture_output=True, text=True, encoding='utf-8', timeout=90)
    if result.returncode:
        raise RuntimeError(result.stderr[-1000:])
    trace.with_suffix('.analysis.csv').write_text(result.stdout, encoding='utf-8')
    parsed = {'cpu': [], 'slice': [], 'state': [], 'stats': []}
    # This trace-processor build quotes text fields without escaping embedded
    # JSON quotes. Preserve the JSON payload rather than parsing it as CSV.
    for line in result.stdout.splitlines()[1:]:
        match = re.fullmatch(r'"([a-z]+)","(.*)"', line)
        if not match:
            continue
        kind, payload = match.groups()
        value = json.loads(payload)
        if kind == 'bounds':
            parsed['bounds'] = value
        else:
            parsed[kind].append(value)
    return parsed


def summarize(folder, binary, completed_only=False):
    events = load(folder/'events.jsonl')
    if not completed_only and events[-1]['type'] != 'complete':
        raise ValueError(f'Incomplete run: {folder}')
    rows = []
    for begin in [x for x in events if x['type'] == 'phase-start']:
        stage = begin['stage']
        end = next((x for x in events if x['type'] == 'phase-end' and x.get('stage') == stage), None)
        if end is None:
            continue
        samples = [x for x in events if x['type'] == 'sample' and x.get('stage') == stage]
        metadata = next(x for x in events if x['type']=='metadata' and x.get('stage')==stage)
        startup = next((x for x in events if x['type']=='startup' and x.get('stage')==stage), {})
        duration = (end['monoUs']-begin['monoUs'])/1e6
        ui = [v/1000 for x in samples for v in x['uiUs']]
        raster = [v/1000 for x in samples for v in x['rasterUs']]
        gpu = load(folder/f'{stage}.gpu.jsonl')
        # GPU totals are the device's global busy time in each preceding interval.
        busy = [x['busyPercent'] for x in gpu if x.get('busyPercent') is not None]
        present = sorted({line[1] for x in gpu for line in x.get('surfaceTimesNs', [])
            if begin['monoUs']*1000 <= line[1] <= end['monoUs']*1000 and 0 < line[1] < 2**63-1})
        intervals = [(b-a)/1e6 for a,b in zip(present,present[1:])]
        tr = trace_summary(binary, folder/f'{stage}.perfetto-trace',begin['monoUs'],end['monoUs'],begin['pid'])
        cpu_seconds = tr['bounds']['seconds']
        for item in tr['cpu']:
            item['percentOfOneCore'] = item['cpuMs']/cpu_seconds/10
        cpu = None
        cpu_file = folder/f'{stage}.dart-cpu.json'
        if cpu_file.exists():
            profile = json.loads(cpu_file.read_text()).get('result',{})
            functions = sorted(profile.get('functions',[]), key=lambda x:x.get('exclusiveTicks',0), reverse=True)
            cpu = {'sampleCount':profile.get('sampleCount'), 'samplePeriodUs':profile.get('samplePeriod'),
                'topExclusive':[{'name':x['function'].get('name') if isinstance(x.get('function'),dict) else x.get('function'),
                    'url':source_url(x.get('resolvedUrl')),'exclusiveTicks':x.get('exclusiveTicks'), 'inclusiveTicks':x.get('inclusiveTicks')}
                    for x in functions[:15]]}
        paints=end['imagePaints']-begin['imagePaints']
        data={'run':folder.name,'stage':stage,'seconds':duration,'sampleCount':len(samples),
            'scenario':metadata['scenario'],'settings':metadata['settings'],
            'nativeOutput':metadata.get('nativeOutput'),
            'firstPlayingMs':startup.get('firstPlayingMs'),
            'decoded':sorted({tuple(x['decoded']) for x in samples}),
            'output':sorted({tuple(x['output']) for x in samples}),
            'surface':sorted({tuple(x['surface']) for x in samples}),
            'view':sorted({tuple(x['view']) for x in samples}),
            'refreshRate':sorted({x['refreshRate'] for x in samples}),
            'queueActive':sorted({x['queueActive'] for x in samples}),
            'hwdec':sorted({x['hwdec'] for x in samples}),
            'videoCodec':sorted({x['videoCodec'] for x in samples if x.get('videoCodec')}),
            'audioDecodedAll':all(x.get('audioDecoded') is True for x in samples),
            'frameDropDelta':end['frameDrops']-begin['frameDrops'],
            'decoderDropDelta':end['decoderDrops']-begin['decoderDrops'],
            'avsyncSamplesAvailable':sum(x.get('avsyncSeconds') is not None for x in samples),
            'maxAvsyncMs':max((abs(x['avsyncSeconds'])*1000 for x in samples if x.get('avsyncSeconds') is not None), default=None),
            'bufferingSamples':sum(x['buffering'] for x in samples),
            'phaseCounts':{p:sum(x['phase']==p for x in samples) for p in {x['phase'] for x in samples}},
            'positionAdvanceSeconds':(end['positionMs']-begin['positionMs'])/1000,
            'positionStartMs':begin['positionMs'],'positionEndMs':end['positionMs'],
            'requestedRate':metadata['scenario'].get('rate',1),
            'sampledRates':sorted({x['rate'] for x in samples}),
            'mediaAdvancePerWallSecond':(end['positionMs']-begin['positionMs'])/1000/duration,
            'bufferedSampleMs':[x.get('bufferedMs') for x in samples],
            'uiP95Ms':percentile(ui,.95),'rasterP95Ms':percentile(raster,.95),
            'rasterP99Ms':percentile(raster,.99),'rasterMaxMs':max(raster,default=None),
            'rasterFrames':len(raster),'rasterOver8_33':sum(x>1000/120 for x in raster),
            'rasterOver16_67':sum(x>1000/60 for x in raster),
            'dartTimingFramesPerSecond':len(raster)/duration,
            'globalGpuBusyMean':mean(busy),'globalGpuBusyP95':percentile(busy,.95),
            'gpuSamples':len(busy),'visibleMean':mean([x['visible'] for x in samples]),
            'visibleMax':max(x['visible'] for x in samples),
            'controlsVisible':sorted({x['controlsVisible'] for x in samples}),
            'rasterCacheSamplePeakMiB':max(x['rasterBytes'] for x in samples)/2**20,
            'cacheHitPercent':(end['cacheHits']-begin['cacheHits'])/paints*100 if paints else None,
            'directPaintDelta':end['directPaints']-begin['directPaints'],
            'surfacePresentCount':len(present),
            'surfacePresentCoverageSeconds':(present[-1]-present[0])/1e9 if len(present)>1 else None,
            'surfacePresentFps':(len(present)-1)*1e9/(present[-1]-present[0]) if len(present)>1 else None,
            'surfaceIntervalP95Ms':percentile(intervals,.95),
            'surfaceIntervalsOver25Ms':sum(x>25 for x in intervals),
            'surfaceIntervalsOver50Ms':sum(x>50 for x in intervals),
            'errors':max(x['errors'] for x in samples),'perfetto':tr,'dartCpu':cpu,
            'longPress':hold_summary(events,stage,begin['monoUs'],end['monoUs'],
                                    metadata['settings'].get('holdDelayMs',400))}
        rows.append(data)
        print(f"{folder.name}/{stage}: GPU={data['globalGpuBusyMean']:.1f}% raster95={data['rasterP95Ms']} "
              f"DartFrame={data['dartTimingFramesPerSecond']:.1f}/s present={data['surfacePresentFps']} "
              f"drops={data['frameDropDelta']}/{data['decoderDropDelta']} buffer={data['bufferingSamples']}")
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runs',nargs='+',type=pathlib.Path)
    parser.add_argument('--trace-processor',type=pathlib.Path,required=True)
    parser.add_argument('--output',type=pathlib.Path,required=True)
    parser.add_argument('--completed-only',action='store_true')
    args=parser.parse_args()
    rows=[x for folder in args.runs for x in summarize(folder,args.trace_processor,args.completed_only)]
    args.output.write_text(json.dumps(rows,indent=2),encoding='utf-8')


if __name__=='__main__':
    main()
