param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [ValidatePattern('^[A-Fa-f0-9]{7,40}$')][string]$ReferenceCommit,
  [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$validation = Join-Path $repoRoot 'build/validation'
if (!$OutputPath) { $OutputPath = Join-Path $validation "$Label.summary.json" }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$matrix = Get-Content -LiteralPath (Join-Path $validation "$Label.matrix.json") -Raw | ConvertFrom-Json
function Get-Statistics([double[]]$Values) {
  if (!$Values -or $Values.Count -eq 0) { return $null }
  $ordered = @($Values | Sort-Object)
  [ordered]@{
    mean = [math]::Round(($Values | Measure-Object -Average).Average, 4)
    p95 = [math]::Round($ordered[[math]::Ceiling($ordered.Count * 0.95) - 1], 4)
    min = [math]::Round($ordered[0], 4)
    max = [math]::Round($ordered[-1], 4)
    count = $ordered.Count
  }
}
function Read-Samples([string]$File) {
  @(Get-Content -LiteralPath (Join-Path $validation $File) | ForEach-Object { $_ | ConvertFrom-Json })
}
$rows = foreach ($run in $matrix.runs) {
  $playback = Read-Samples "windows-gpu-playback-$($run.label).jsonl"
  $gpu = Read-Samples "windows-gpu-engine-$($run.label).jsonl"
  $fixture = Get-Content -LiteralPath (Join-Path $validation "windows-gpu-playback-$($run.label).fixture.json") -Raw | ConvertFrom-Json
  $clocks = @(Import-Csv -LiteralPath (Join-Path $validation "windows-gpu-clocks-$($run.label).csv") `
    -Header 'localTime', 'pstate', 'coreClock', 'memoryClock', 'gpuPercent', 'decodePercent', 'powerW' | ForEach-Object {
      $nativeTime = [datetime]::ParseExact($_.localTime, 'yyyy/MM/dd HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
      [pscustomobject]@{
        utc = [TimeZoneInfo]::ConvertTimeToUtc($nativeTime, [TimeZoneInfo]::Local)
        clockMHz = [double]$_.coreClock.Trim().Split(' ')[0]
        powerW = [double]$_.powerW.Trim().Split(' ')[0]
      }
    })
  foreach ($stage in @('video', 'danmaku', 'controls')) {
    $samples = @($playback | Where-Object stage -eq $stage)
    if ($samples.Count -ne $matrix.seconds) { throw "Incomplete stage: $($run.label) $stage" }
    $start = ([DateTimeOffset]$samples[0].timeUtc).UtcDateTime
    $end = ([DateTimeOffset]$samples[-1].timeUtc).UtcDateTime
    $engines = @($gpu | Where-Object {
      $time = ([DateTimeOffset]$_.timeUtc).UtcDateTime
      $time -ge $start -and $time -le $end
    })
    $clock = @($clocks | Where-Object { $_.utc -ge $start -and $_.utc -le $end })
    [ordered]@{
      label = $run.label
      mode = $run.mode
      implementation = $run.implementation
      round = $run.round
      stage = $stage
      seconds = $samples.Count
      mediaSha256 = $fixture.mediaSha256
      outputs = @($samples | ForEach-Object { "$($_.outputWidth)x$($_.outputHeight)" } | Sort-Object -Unique)
      hwdec = @($samples.hwdec | Sort-Object -Unique)
      framesPerSecond = Get-Statistics $samples.dartFrames
      uiUs = Get-Statistics @($samples | ForEach-Object { $_.uiUs })
      rasterUs = Get-Statistics @($samples | ForEach-Object { $_.rasterUs })
      process3dPercent = Get-Statistics @($engines | Where-Object engineType -eq '3d' | ForEach-Object percent)
      gpuClockMHz = Get-Statistics $clock.clockMHz
      wholeGpuPowerW = Get-Statistics $clock.powerW
      visible = Get-Statistics $samples.visible
      imagePaintsPerSecond = [math]::Round(($samples[-1].imagePaints - $samples[0].imagePaints) / ($end - $start).TotalSeconds, 4)
      directPaintsDelta = $samples[-1].directPaints - $samples[0].directPaints
      maxFrameDrops = ($samples.frameDrops | Measure-Object -Maximum).Maximum
      maxDecoderDrops = ($samples.decoderDrops | Measure-Object -Maximum).Maximum
      maxAbsAvsyncSeconds = (@($samples | ForEach-Object { [math]::Abs($_.avsyncSeconds) }) | Measure-Object -Maximum).Maximum
    }
  }
}
$hashes = [ordered]@{}
foreach ($implementation in @('before', 'after')) {
  $bundle = $matrix.bundles.$implementation
  $hashes[$implementation] = [ordered]@{
    dartSha256 = $bundle.dartSha256
    engineSha256 = $bundle.engineSha256
    mpvSha256 = $bundle.mpvSha256
  }
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
[ordered]@{
  referenceCommit = $ReferenceCommit
  bundles = $hashes
  width = $matrix.width
  height = $matrix.height
  opacity = $matrix.opacity
  arrivalsPerSecond = $matrix.arrivalsPerSecond
  rounds = 2
  samples = @($rows)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Host "Wrote $(@($rows).Count) stage summaries to $OutputPath"
