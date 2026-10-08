param([ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label = 'current')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mediaDir = Join-Path $repoRoot 'build/validation/preview-contention-media'
New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=1280x720:rate=60' -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 30 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -movflags +faststart "$mediaDir/main.mp4"
if ($LASTEXITCODE -ne 0) { throw 'Main playback fixture generation failed.' }
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=854x480:rate=30' -t 20 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -an -movflags +faststart "$mediaDir/preview.mp4"
if ($LASTEXITCODE -ne 0) { throw 'Preview fixture generation failed.' }
$oldMedia = $env:BILI_TEST_MEDIA_DIR
$oldTrace = $env:BILISAIL_VIDEO_RENDER_TRACE
Push-Location $repoRoot
try {
  $env:BILI_TEST_MEDIA_DIR = $mediaDir
  $env:BILISAIL_VIDEO_RENDER_TRACE = '1'
  $log = "build/validation/video-preview-contention-$Label.log"
  $reportPath = 'build/validation/video-preview-contention.json'
  if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
  & flutter run -d windows --profile --no-pub -t tool/validation/video_preview_contention_probe.dart 2>&1 | Tee-Object -FilePath $log
  if ($LASTEXITCODE -ne 0) { throw 'Preview contention probe failed.' }
  if (!(Test-Path -LiteralPath $reportPath)) { throw 'The native probe did not write a report.' }
  $report = Get-Content $reportPath -Raw | ConvertFrom-Json
  if ($report.Count -ne 4 -or @($report | Where-Object { !$_.previewOutput -or $_.previewDecodedAudio -or !$_.mainPlaying -or $_.mainBuffering -or !$_.mainDecodedAudio -or $_.mainAdvanceMs -lt 800 }).Count -ne 0) {
    throw 'Preview contention probe did not retain main and silent preview playback.'
  }
  Copy-Item -LiteralPath 'build/validation/video-preview-contention.json' -Destination "build/validation/video-preview-contention-$Label.json"
  $renderRows = @(Select-String -LiteralPath $log -Pattern 'VIDEO_RENDER_TRACE frames=(\d+) maxGapMs=(\d+) hardware=(\d)' | ForEach-Object {
    $match = $_.Matches[0]
    [pscustomobject]@{ frames = [int]$match.Groups[1].Value; maxGapMs = [int]$match.Groups[2].Value; hardware = [int]$match.Groups[3].Value }
  })
  $gpuCreates = @(Select-String -LiteralPath $log -Pattern 'VideoOutput: Using H/W rendering\.').Count
  if ($renderRows.Count -ne 5 -or $gpuCreates -ne 5 -or @($renderRows | Where-Object { $_.hardware -ne 1 }).Count -ne 0) {
    throw 'The profile probe did not capture all five GPU outputs.'
  }
  $mainRender = $renderRows | Sort-Object frames -Descending | Select-Object -First 1
  $mainRender | ConvertTo-Json | Set-Content -LiteralPath "build/validation/video-preview-contention-$Label-render.json"
} finally {
  $env:BILI_TEST_MEDIA_DIR = $oldMedia
  $env:BILISAIL_VIDEO_RENDER_TRACE = $oldTrace
  # Environment changes alone do not invalidate CMake's generated patch copy.
  # Regenerate it now so subsequent normal builds cannot retain trace code.
  & cmake -S windows -B build/windows/x64 > build/validation/preview-contention-cmake-reset.log 2>&1
  $resetExitCode = $LASTEXITCODE
  Pop-Location
  if ($resetExitCode -ne 0) { throw 'CMake trace reset failed; inspect preview-contention-cmake-reset.log.' }
}
