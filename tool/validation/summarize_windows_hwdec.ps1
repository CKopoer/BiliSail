param(
  [Parameter(Mandatory)][string[]]$BeforeLabels,
  [Parameter(Mandatory)][string[]]$AfterLabels,
  [Parameter(Mandatory)][string]$OutputPath,
  [string]$ClockTimeZone = 'China Standard Time'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$directory = Join-Path $root 'build/validation'
if ($BeforeLabels.Count -ne $AfterLabels.Count -or $BeforeLabels.Count -lt 3) {
  throw 'Provide at least three paired baseline/candidate runs.'
}
if (Test-Path -LiteralPath $OutputPath) { throw 'Preserve existing results; choose a new output path.' }
$clockZone = [TimeZoneInfo]::FindSystemTimeZoneById($ClockTimeZone)
function Stats($Values) {
  $sorted = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
  if ($sorted.Count -eq 0) { return $null }
  [ordered]@{
    count = $sorted.Count
    mean = ($sorted | Measure-Object -Average).Average
    p95 = $sorted[[Math]::Ceiling($sorted.Count * .95) - 1]
    max = $sorted[-1]
  }
}
function Read-Lines([string]$Path) { @(Get-Content -LiteralPath $Path | ConvertFrom-Json) }
# ConvertFrom-Json can already have produced a UTC DateTime. Parsing its
# culture-formatted string would discard the offset and shift it by 8 hours.
function Instant($Value) { [datetimeoffset]$Value }
$runs = @()
foreach ($variant in @('before', 'after')) {
  $labels = if ($variant -eq 'before') { $BeforeLabels } else { $AfterLabels }
  foreach ($label in $labels) {
    if ($label -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid sample label.' }
    $rows = Read-Lines "$directory/windows-gpu-playback-$label.jsonl"
    $gpu = Read-Lines "$directory/windows-gpu-engine-$label.jsonl"
    $fixture = Get-Content -Raw -LiteralPath "$directory/windows-gpu-playback-$label.fixture.json" | ConvertFrom-Json
    $bundle = Split-Path $fixture.exePath
    $hashes = [ordered]@{}
    foreach ($file in @('bilisail.exe', 'data/app.so', 'flutter_windows.dll', 'media_kit_video_plugin.dll', 'libmpv-2.dll', 'libEGL.dll', 'libGLESv2.dll')) {
      $hashes[$file] = (Get-FileHash -LiteralPath (Join-Path $bundle $file) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $clocks = @(foreach ($line in Get-Content -LiteralPath "$directory/windows-gpu-clocks-$label.csv") {
      $parts = $line.Split(',').Trim()
      if ($parts.Count -ne 7) { throw "Invalid GPU clock sample: $label" }
      $local = [datetime]::ParseExact($parts[0], 'yyyy/MM/dd HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
      [pscustomobject]@{
        time = [TimeZoneInfo]::ConvertTimeToUtc($local, $clockZone)
        coreMHz = [double]($parts[2] -replace ' MHz$', '')
        memoryMHz = [double]($parts[3] -replace ' MHz$', '')
        watts = [double]($parts[6] -replace ' W$', '')
      }
    })
    $stages = [ordered]@{}
    foreach ($stage in @('video', 'danmaku', 'controls')) {
      $samples = @($rows | Where-Object stage -eq $stage)
      if ($samples.Count -ne $fixture.seconds) { throw "Incomplete stage: $label $stage" }
      $expectedDecoder = if ($variant -eq 'before') { 'd3d11va-copy' } else { 'd3d11va' }
      foreach ($sample in $samples) {
        if ($sample.phase -ne 'playing' -or $sample.hwdec -ne $expectedDecoder) { throw "Unexpected playback/decoder: $label $stage" }
      }
      $start = (Instant $samples[0].timeUtc).AddSeconds(-1)
      $end = Instant $samples[-1].timeUtc
      $counters = @($gpu | Where-Object { (Instant $_.timeUtc) -gt $start -and (Instant $_.timeUtc) -le $end })
      $byTime = @($counters | Group-Object timeUtc | Sort-Object Name)
      if ($byTime.Count -lt 5) { throw "Too few GPU samples: $label $stage" }
      $engineStats = [ordered]@{}
      foreach ($engine in @($counters.engineType | Sort-Object -Unique)) {
        # Sum engines of the same type per timestamp on the captured adapters.
        $engineStats[$engine] = Stats @(foreach ($time in $byTime) {
          ($time.Group | Where-Object engineType -eq $engine | Measure-Object percent -Sum).Sum
        })
      }
      $firstCounter = $byTime[0].Group[0]
      $lastCounter = $byTime[-1].Group[0]
      $cpuSpan = ((Instant $lastCounter.timeUtc) - (Instant $firstCounter.timeUtc)).TotalSeconds
      $stageClocks = @($clocks | Where-Object { $_.time -gt $start.UtcDateTime -and $_.time -le $end.UtcDateTime })
      if ($stageClocks.Count -lt 5) { throw "Too few GPU clock samples: $label $stage" }
      $stages[$stage] = [ordered]@{
        startUtc = $start.ToUniversalTime().ToString('o')
        endUtc = $end.ToUniversalTime().ToString('o')
        decoder = $expectedDecoder
        outputSizes = @($samples | ForEach-Object { "$($_.outputWidth)x$($_.outputHeight)" } | Sort-Object -Unique)
        decodedSizes = @($samples | ForEach-Object { "$($_.decodedWidth)x$($_.decodedHeight)" } | Sort-Object -Unique)
        mode = @($samples.mode | Sort-Object -Unique)
        opacity = @($samples.opacity | Sort-Object -Unique)
        arrivals = @($samples.arrivals | Sort-Object -Unique)
        visible = Stats $samples.visible
        fps = ($samples.dartFrames | Measure-Object -Sum).Sum / $samples.Count
        uiUs = Stats $samples.uiUs
        rasterUs = Stats $samples.rasterUs
        gpuEngines = $engineStats
        cpuMsPerSecond = ($lastCounter.cpuSeconds - $firstCounter.cpuSeconds) / $cpuSpan * 1000
        workingSetBytes = Stats @($byTime | ForEach-Object { $_.Group[0].workingSetBytes })
        coreMHz = Stats $stageClocks.coreMHz
        memoryMHz = Stats $stageClocks.memoryMHz
        boardWatts = Stats $stageClocks.watts
        frameDropRange = @($samples.frameDrops | Measure-Object -Minimum -Maximum | ForEach-Object { $_.Minimum; $_.Maximum })
        decoderDropRange = @($samples.decoderDrops | Measure-Object -Minimum -Maximum | ForEach-Object { $_.Minimum; $_.Maximum })
        maxAbsAvsyncMs = ($samples.avsyncSeconds | ForEach-Object { [Math]::Abs($_) * 1000 } | Measure-Object -Maximum).Maximum
      }
    }
    $trace = Get-Content -LiteralPath "$directory/windows-gpu-playback-$label.log" | Select-String 'VIDEO_RENDER_TRACE frames=(\d+).*callbacks=(\d+)'
    if (!$trace) { throw "Missing native render trace: $label" }
    $runs += [pscustomobject]@{
      label = $label; variant = $variant; secondsPerStage = $fixture.seconds
      mediaSha256 = $fixture.mediaSha256.ToLowerInvariant(); mediaBytes = $fixture.mediaBytes
      hashes = $hashes; stages = $stages
      nativeRenderCalls = [int]$trace.Matches[0].Groups[1].Value
      nativeUpdateCallbacks = [int]$trace.Matches[0].Groups[2].Value
    }
  }
}
foreach ($file in @('data/app.so', 'flutter_windows.dll', 'bilisail.exe', 'libEGL.dll', 'libGLESv2.dll')) {
  if (@($runs | ForEach-Object { $_.hashes[$file] } | Sort-Object -Unique).Count -ne 1) { throw "Mismatched common binary: $file" }
}
if (@($runs.mediaSha256 | Sort-Object -Unique).Count -ne 1) { throw 'Mismatched source media.' }
foreach ($stage in @('video', 'danmaku', 'controls')) {
  foreach ($field in @('outputSizes', 'decodedSizes', 'mode', 'opacity', 'arrivals')) {
    $values = @($runs | ForEach-Object { $_.stages[$stage][$field] -join ',' } | Sort-Object -Unique)
    if ($values.Count -ne 1) { throw "Mismatched input/output: $stage $field" }
  }
}
[ordered]@{
  date = '2026-11-01'; clockTimeZone = $ClockTimeZone
  method = 'Windows Profile / Skia / ANGLE, three AB/BA/AB pairs; stage clocks are whole-board values, GPU is process-specific; no fixed GPU clocks.'
  runs = $runs
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "Saved matched hardware-decoding comparison: $OutputPath"
