param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [string]$MediaPath,
  [string]$ExePath = 'build/windows/x64/runner/Profile/bilisail.exe',
  [ValidateRange(1, 20)][int]$Arrivals = 20,
  [ValidateRange(10, 60)][int]$Seconds = 30,
  [switch]$Reverse,
  [switch]$Inline,
  [int]$CounterProcessId = 0
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$folder = Join-Path $repoRoot 'build/validation/4k60'
if ($CounterProcessId) {
  # One continuous PDH query, including other PIDs for whole-engine / DWM context.
  $dwmIds = @((Get-Process dwm -ErrorAction SilentlyContinue).Id)
  $previous = $null
  Get-Counter '\GPU Engine(*)\Utilization Percentage' -SampleInterval 1 -MaxSamples 360 -ErrorAction SilentlyContinue |
    ForEach-Object {
      $process = Get-Process -Id $CounterProcessId -ErrorAction SilentlyContinue
      if (!$process) { break }
      $counterSet = $_
      $engines = @($counterSet.CounterSamples | Where-Object {
        $_.Status -eq 0 -and [double]::IsFinite($_.CookedValue) -and $_.CookedValue -ge 0
      } | ForEach-Object {
        if ($_.Path -match 'pid_(\d+)_luid_(.+?)_phys_(\d+)_eng_(\d+)_engtype_([^\)]+)\)') {
          [pscustomobject]@{
            pid = [int]$Matches[1]; luid = $Matches[2]; adapter = [int]$Matches[3]
            engine = [int]$Matches[4]; type = $Matches[5]; percent = $_.CookedValue
          }
        }
      })
      $now = $counterSet.Timestamp.ToUniversalTime().ToString('o')
      [pscustomobject]@{
        timeUtc = $now; intervalStartUtc = $previous
        pid = $CounterProcessId; cpuSeconds = $process.CPU
        workingSetBytes = $process.WorkingSet64; privateBytes = $process.PrivateMemorySize64
        processEngines = @($engines | Where-Object { $_.pid -eq $CounterProcessId })
        dwmEngines = @($engines | Where-Object { $_.pid -in $dwmIds })
        wholeEngines = @($engines | Group-Object luid,adapter,engine,type | ForEach-Object {
          $first = $_.Group[0]
          [pscustomobject]@{
            luid = $first.luid; adapter = $first.adapter; engine = $first.engine
            type = $first.type; percent = ($_.Group | Measure-Object percent -Sum).Sum
          }
        })
      } | ConvertTo-Json -Compress -Depth 6 | Add-Content -LiteralPath (Join-Path $folder "$Label.counters.jsonl")
      $previous = $now
    }
  exit
}
$ExePath = [IO.Path]::GetFullPath((Join-Path $repoRoot $ExePath))
$MediaPath = [IO.Path]::GetFullPath($MediaPath)
if (!(Test-Path -LiteralPath $ExePath) -or !(Test-Path -LiteralPath $MediaPath)) {
  throw 'Build windows_4k60_probe.dart in Profile and download the fixture first.'
}
New-Item -ItemType Directory -Force $folder | Out-Null
if (Get-ChildItem -LiteralPath $folder -Filter "$Label.*") { throw 'Use a fresh label' }
$names = @('BILI_4K_LABEL','BILI_4K_MEDIA','BILI_4K_ARRIVALS','BILI_4K_SECONDS','BILI_4K_REVERSE','BILI_4K_FULLSCREEN')
$old = @{}
foreach ($name in $names) { $old[$name] = [Environment]::GetEnvironmentVariable($name) }
$probe = $null; $counterJob = $null; $clockJob = $null
try {
  $env:BILI_4K_LABEL = $Label; $env:BILI_4K_MEDIA = $MediaPath
  $env:BILI_4K_ARRIVALS = "$Arrivals"; $env:BILI_4K_SECONDS = "$Seconds"
  $env:BILI_4K_REVERSE = if ($Reverse) { '1' } else { '0' }
  $env:BILI_4K_FULLSCREEN = if ($Inline) { '0' } else { '1' }
  [pscustomobject]@{
    label = $Label; arrivals = $Arrivals; seconds = $Seconds
    reverse = $Reverse.IsPresent; fullscreen = !$Inline
    mediaPath = $MediaPath; mediaBytes = (Get-Item -LiteralPath $MediaPath).Length
    mediaSha256 = (Get-FileHash -LiteralPath $MediaPath).Hash
    gitHead = (& git -C $repoRoot rev-parse HEAD)
    bundleHashes = @(foreach ($name in @('bilisail.exe','data/app.so','flutter_windows.dll','libmpv-2.dll','media_kit_video_plugin.dll','libEGL.dll','libGLESv2.dll')) {
      $item = Join-Path (Split-Path $ExePath) $name
      [pscustomobject]@{ name = $name; sha256 = (Get-FileHash -LiteralPath $item).Hash }
    })
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder "$Label.fixture.json")
  $probe = Start-Process -FilePath $ExePath -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $folder "$Label.stdout.log") `
    -RedirectStandardError (Join-Path $folder "$Label.stderr.log")
  $counterJob = Start-Job -ScriptBlock {
    param($scriptPath, $sampleLabel, $probeId)
    & pwsh -NoProfile -File $scriptPath -Label $sampleLabel -CounterProcessId $probeId
    if ($LASTEXITCODE -ne 0) { throw 'Counter sampler failed' }
  } -ArgumentList $PSCommandPath, $Label, $probe.Id
  if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    $clockJob = Start-Job -ScriptBlock {
      param($probeId)
      while (Get-Process -Id $probeId -ErrorAction SilentlyContinue) {
        & nvidia-smi '--query-gpu=timestamp,pstate,clocks.gr,clocks.mem,utilization.gpu,utilization.decoder,power.draw' '--format=csv,noheader,nounits'
        Start-Sleep -Seconds 1
      }
    } -ArgumentList $probe.Id
  }
  if (!$probe.WaitForExit(330000)) { throw 'Probe exceeded deadline' }
  if ($probe.ExitCode -ne 0) { throw "Probe failed with $($probe.ExitCode)" }
  Wait-Job $counterJob -Timeout 10 | Out-Null
  Receive-Job $counterJob -ErrorAction Stop | Out-Null
  $rows = @(Get-Content -LiteralPath (Join-Path $folder "$Label.playback.jsonl") | ConvertFrom-Json)
  if ($rows[-1].type -ne 'complete') { throw 'Missing completion marker' }
  Write-Host "Completed 4K60 benchmark: $Label"
} finally {
  if ($probe -and !$probe.HasExited) { $probe.Kill(); $probe.WaitForExit() }
  foreach ($job in @($counterJob, $clockJob)) { if ($job) { Stop-Job $job -ErrorAction SilentlyContinue } }
  if ($clockJob) { Receive-Job $clockJob | Set-Content -LiteralPath (Join-Path $folder "$Label.clocks.csv") }
  foreach ($job in @($counterJob, $clockJob)) { if ($job) { Remove-Job $job -Force } }
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $old[$name]) }
}
