param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
  [Parameter(Mandatory)][string]$BeforeExe,
  [Parameter(Mandatory)][string]$AfterExe,
  [Parameter(Mandatory)][string]$MediaPath,
  [ValidateRange(10, 20)][int]$Seconds = 10
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validation = Join-Path $repoRoot 'build/validation'
$BeforeExe = [IO.Path]::GetFullPath($BeforeExe)
$AfterExe = [IO.Path]::GetFullPath($AfterExe)
$MediaPath = [IO.Path]::GetFullPath($MediaPath)
$metadata = Join-Path $validation "$Label.matrix.json"
if (Test-Path -LiteralPath $metadata) { throw 'Use a fresh matrix label.' }
$bundles = [ordered]@{}
foreach ($pair in @(@('before', $BeforeExe), @('after', $AfterExe))) {
  $directory = Split-Path $pair[1]
  $bundles[$pair[0]] = [ordered]@{
    exe = $pair[1]
    dartSha256 = (Get-FileHash -LiteralPath (Join-Path $directory 'data/app.so') -Algorithm SHA256).Hash
    engineSha256 = (Get-FileHash -LiteralPath (Join-Path $directory 'flutter_windows.dll') -Algorithm SHA256).Hash
    mpvSha256 = (Get-FileHash -LiteralPath (Join-Path $directory 'libmpv-2.dll') -Algorithm SHA256).Hash
  }
}
if ($bundles.before.engineSha256 -ne $bundles.after.engineSha256 -or
    $bundles.before.mpvSha256 -ne $bundles.after.mpvSha256) {
  throw 'Compare the same Flutter engine and native player binary.'
}
$runs = [Collections.Generic.List[object]]::new()
foreach ($round in @(1, 2)) {
  $modes = if ($round -eq 1) { @('scroll', 'mixed', 'fixed') } else { @('fixed', 'mixed', 'scroll') }
  $implementations = if ($round -eq 1) { @('before', 'after') } else { @('after', 'before') }
  foreach ($mode in $modes) {
    foreach ($implementation in $implementations) {
      $runs.Add([ordered]@{
        label = "$Label-$mode-$implementation-$round"
        mode = $mode
        implementation = $implementation
        round = $round
      })
    }
  }
}
[ordered]@{
  bundles = $bundles
  seconds = $Seconds
  width = 960
  height = 540
  arrivalsPerSecond = 20
  opacity = 0.8
  runs = $runs
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadata -Encoding utf8

$saved = @{}
foreach ($name in @('BILI_GPU_MODE', 'BILI_GPU_ARRIVALS', 'BILI_GPU_OPACITY', 'BILI_GPU_PANEL', 'BILI_GPU_SIZE')) {
  $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $repoRoot
try {
  $env:BILI_GPU_ARRIVALS = '20'
  $env:BILI_GPU_OPACITY = '0.8'
  $env:BILI_GPU_PANEL = 'panel'
  $env:BILI_GPU_SIZE = '960'
  foreach ($run in $runs) {
    $env:BILI_GPU_MODE = $run.mode
    & (Join-Path $PSScriptRoot 'test-windows-gpu-playback.ps1') -Label $run.label `
      -ExePath $bundles[$run.implementation].exe -MediaPath $MediaPath -Seconds $Seconds
    $samples = Get-Content -LiteralPath (Join-Path $validation "windows-gpu-playback-$($run.label).jsonl") |
      ForEach-Object { $_ | ConvertFrom-Json } |
      Where-Object { $_.stage -in @('video', 'danmaku', 'controls') }
    if (@($samples).Count -ne 3 * $Seconds -or @($samples | Where-Object {
      $_.phase -ne 'playing' -or $_.outputWidth -ne 960 -or $_.outputHeight -ne 540 -or
      $_.mode -ne $run.mode -or $_.hwdec -ne 'd3d11va'
    }).Count -gt 0) {
      throw "Unmatched dimensions, scenario or playback state: $($run.label). Preserve the data and use a new label."
    }
  }
} finally {
  foreach ($name in $saved.Keys) {
    [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
  }
  Pop-Location
}
Write-Host "Completed matched danmaku matrix: $Label"
