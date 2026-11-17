$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousMpv = $env:BILI_TEST_NATIVE_MPV
$previousMedia = $env:BILI_TEST_HTTP_AUDIO_DIR
Push-Location $repoRoot
try {
  $fixtureDir = Join-Path $repoRoot 'build/validation/http-audio-fixtures'
  New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
  & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=160x90:rate=24:duration=300' -an -c:v libx264 -preset veryfast -crf 28 -g 24 -movflags +faststart (Join-Path $fixtureDir 'video.mp4')
  if ($LASTEXITCODE -ne 0) { throw 'HTTP audio regression video generation failed.' }
  & ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=240' -ac 2 -c:a aac -b:a 320k -movflags +faststart (Join-Path $fixtureDir 'audio.m4a')
  if ($LASTEXITCODE -ne 0) { throw 'HTTP audio regression audio generation failed.' }
  $nativeLibrary = @(
    'build/windows/x64/runner/Release/libmpv-2.dll',
    'build/windows/x64/runner/Debug/libmpv-2.dll'
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (!$nativeLibrary) { throw 'Build the Windows application before native HTTP audio validation.' }
  $env:BILI_TEST_NATIVE_MPV = (Resolve-Path $nativeLibrary).Path
  $env:BILI_TEST_HTTP_AUDIO_DIR = $fixtureDir
  Push-Location packages/bili_player
  try {
    & flutter test --no-pub test/native_http_audio_playback_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'HTTP audio regression failed.' }
  } finally { Pop-Location }
} finally {
  $env:BILI_TEST_NATIVE_MPV = $previousMpv
  $env:BILI_TEST_HTTP_AUDIO_DIR = $previousMedia
  Pop-Location
}
