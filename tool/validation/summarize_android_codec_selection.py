"""Match per-case codec creation logs to Android's hardware/software flags."""
import argparse
import datetime as dt
import json
import pathlib
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('run', type=pathlib.Path)
parser.add_argument('--capabilities', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
events = [json.loads(line) for line in (args.run/'events.jsonl').read_text(encoding='utf-8-sig').splitlines() if line]
caps = json.loads(args.capabilities.read_text(encoding='utf-8-sig'))
by_name = {row['name']: row for row in caps}
local_tz = dt.timezone(dt.timedelta(hours=8))


def stamp(value):
    return dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


starts = [row for row in events if row['type'] == 'stage-config']
year = dt.datetime.fromtimestamp(stamp(starts[0]['timeUtc']), local_tz).year
created = []
for line in (args.run/'device-logcat.log').read_text(encoding='utf-8', errors='replace').splitlines():
    match = re.match(r'^(\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)', line)
    component = re.search(r'Created component \[([^\]]+)\]', line)
    if match and component and component[1] in by_name:
        time = dt.datetime.strptime(match[1], '%m-%d %H:%M:%S.%f').replace(year=year, tzinfo=local_tz)
        created.append((time.timestamp(), component[1]))

rows = []
for index, start in enumerate(starts):
    stage = start['stage']
    end = stamp(starts[index+1]['timeUtc']) if index+1 < len(starts) else float('inf')
    names = sorted({name for time, name in created if stamp(start['timeUtc']) <= time < end})
    samples = [row for row in events if row['type']=='sample' and row.get('stage')==stage]
    failures = [row['reason'] for row in events if row['type']=='case-failed' and row.get('stage')==stage]
    components = [by_name[name] for name in names]
    only_hardware = bool(components) and all(x['hardwareAccelerated'] and not x['softwareOnly'] for x in components)
    rows.append({'stage':stage,'codecCreatedComponents':components,'onlyHardwareComponentsCreated':only_hardware,
        'hwdec':sorted({row['hwdec'] for row in samples}),
        'videoCodec':sorted({row['videoCodec'] for row in samples if row.get('videoCodec')}),
        'sampleCount':len(samples),'failures':failures})
    print(f"{stage}: {names}, hardware flags={only_hardware}, samples={len(samples)}, failures={len(failures)}")
args.output.write_text(json.dumps(rows, indent=2), encoding='utf-8')
