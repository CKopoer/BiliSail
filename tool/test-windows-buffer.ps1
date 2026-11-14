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
  foreach ($duration in @('8.7', '140.5')) {
    $name = if ($duration -eq '8.7') { 'eof_video.mp4' } else { 'eof_video_long.mp4' }
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=160x90:rate=30:duration=$duration" -an -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -g 30 -movflags +faststart (Join-Path $fixtureDir $name)
    if ($LASTEXITCODE -ne 0) { throw "DASH EOF video fixture generation failed: $name" }
  }
  foreach ($audio in @(
    @{ Name = 'eof_audio_equal.m4a'; Rate = 48000; Duration = '8.7' },
    @{ Name = 'eof_audio_short.m4a'; Rate = 48000; Duration = '8.05' },
    @{ Name = 'eof_audio_long.m4a'; Rate = 44100; Duration = '139.86' }
  )) {
    & ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=440:sample_rate=$($audio.Rate):duration=$($audio.Duration)" -vn -c:a aac -b:a 64k -movflags +faststart (Join-Path $fixtureDir $audio.Name)
    if ($LASTEXITCODE -ne 0) { throw "DASH EOF audio fixture generation failed: $($audio.Name)" }
  }
  $env:BILI_TEST_BUFFER_DIR = $fixtureDir
  & flutter test integration_test/windows_dash_eof_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows normal DASH EOF validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_resume_startup_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows HTTP resume startup validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_buffer_ahead_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows forward buffer validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_prefetch_recovery_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows prefetch recovery validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_rebuffer_recovery_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows repeated buffering recovery validation failed: $LASTEXITCODE" }
  & flutter test integration_test/native_seek_cache_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows cached seek validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_dash_rapid_seek_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows DASH rapid seek failed: $LASTEXITCODE" }
} finally {
  Remove-Item Env:BILI_TEST_BUFFER_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
