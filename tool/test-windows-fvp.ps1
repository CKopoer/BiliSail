param()
$ErrorActionPreference = 'Stop'
$previousMedia = $env:BILI_TEST_MEDIA_DIR
$previousLive = $env:BILI_FVP_LIVE_MEDIA_DIR
Push-Location (Join-Path $PSScriptRoot '..')
try {
  & (Join-Path $PSScriptRoot 'test-windows-fvp-audio-clock.ps1')
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  $liveDirectory = Join-Path (Get-Location) '.dart_tool/fvp_media'
  New-Item -ItemType Directory -Path $liveDirectory -Force | Out-Null
  & ffmpeg -hide_banner -loglevel error -y -i test/fixtures/media/video.mp4 -i test/fixtures/media/audio.m4a -c copy -f flv (Join-Path $liveDirectory 'live.flv')
  if ($LASTEXITCODE -ne 0) { throw 'fvp FLV fixture generation failed' }
  & ffmpeg -hide_banner -loglevel error -y -i test/fixtures/media/video.mp4 -i test/fixtures/media/audio.m4a -c copy -hls_time 2 -hls_list_size 0 -hls_segment_filename (Join-Path $liveDirectory 'segment-%03d.ts') (Join-Path $liveDirectory 'live.m3u8')
  if ($LASTEXITCODE -ne 0) { throw 'fvp HLS fixture generation failed' }
  $env:BILI_FVP_LIVE_MEDIA_DIR = $liveDirectory
  & ffmpeg -hide_banner -loglevel error -y -stream_loop 3 -i test/fixtures/media/video.mp4 -t 30 -c copy -movflags +faststart (Join-Path $liveDirectory 'long-video.mp4')
  if ($LASTEXITCODE -ne 0) { throw 'fvp long video fixture generation failed' }
  & ffmpeg -hide_banner -loglevel error -y -stream_loop 3 -i test/fixtures/media/audio.m4a -t 30 -c copy -movflags +faststart (Join-Path $liveDirectory 'long-audio.m4a')
  if ($LASTEXITCODE -ne 0) { throw 'fvp long audio fixture generation failed' }
  $audioBytes = [IO.File]::ReadAllBytes((Join-Path $liveDirectory 'long-audio.m4a'))
  [IO.File]::WriteAllBytes((Join-Path $liveDirectory 'truncated-audio.m4a'), $audioBytes[0..59999])
  $videoBytes = [IO.File]::ReadAllBytes((Join-Path $liveDirectory 'long-video.mp4'))
  [IO.File]::WriteAllBytes((Join-Path $liveDirectory 'truncated-video.mp4'), $videoBytes[0..179999])
  & flutter test integration_test/windows_fvp_audio_recovery_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows fvp audio recovery failed: $LASTEXITCODE" }
  & flutter test integration_test/fvp_backend_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows fvp backend validation failed: $LASTEXITCODE" }
  & flutter test integration_test/windows_fvp_seek_synchronization_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows fvp seek synchronization failed: $LASTEXITCODE" }
  & flutter test integration_test/fvp_seek_end_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows fvp EOF seek validation failed: $LASTEXITCODE" }
} finally {
  $env:BILI_TEST_MEDIA_DIR = $previousMedia
  $env:BILI_FVP_LIVE_MEDIA_DIR = $previousLive
  Pop-Location
}
