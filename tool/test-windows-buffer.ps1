$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
  $fixtureDir = Join-Path $repoRoot 'build/validation/player-buffer-fixtures'
  New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
  & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=160x90:rate=24:duration=720' -an -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -g 24 -movflags +faststart (Join-Path $fixtureDir 'video.mp4')
  if ($LASTEXITCODE -ne 0) { throw 'Forward buffer video fixture generation failed.' }
  & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=720' -vn -c:a aac -b:a 64k -movflags +faststart (Join-Path $fixtureDir 'audio.m4a')
  if ($LASTEXITCODE -ne 0) { throw 'Forward buffer audio fixture generation failed.' }
  Copy-Item -LiteralPath 'test/fixtures/media/video_preview.mp4' -Destination (Join-Path $fixtureDir 'short.mp4') -Force
  $env:BILI_TEST_BUFFER_DIR = $fixtureDir
  & flutter test integration_test/windows_buffer_ahead_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows forward buffer validation failed: $LASTEXITCODE" }
} finally {
  Remove-Item Env:BILI_TEST_BUFFER_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
