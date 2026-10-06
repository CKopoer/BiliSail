param([switch]$Online, [string]$PgcEpisodeId, [switch]$SavedSession)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
  $mediaDirectory = Join-Path $repoRoot '.dart_tool/content_media'
  New-Item -ItemType Directory -Path $mediaDirectory -Force | Out-Null
  & ffmpeg -hide_banner -loglevel error -y -i test/fixtures/media/video.mp4 -i test/fixtures/media/audio.m4a -c copy -hls_time 2 -hls_list_size 0 -hls_segment_filename (Join-Path $mediaDirectory 'segment-%03d.ts') (Join-Path $mediaDirectory 'live.m3u8')
  if ($LASTEXITCODE -ne 0) { throw 'HLS fixture generation failed' }
  & ffmpeg -hide_banner -loglevel error -y -i test/fixtures/media/video.mp4 -i test/fixtures/media/audio.m4a -c copy -f flv (Join-Path $mediaDirectory 'live.flv')
  if ($LASTEXITCODE -ne 0) { throw 'FLV fixture generation failed' }
  $env:BILI_CONTENT_MEDIA_DIR = $mediaDirectory
  $arguments = @('test', 'integration_test/windows_content_playback_test.dart', '-d', 'windows')
  if ($Online) { $arguments += '--dart-define=BILI_CONTENT_ONLINE=true' }
  if ($PgcEpisodeId) {
    if (!$Online -or $PgcEpisodeId -notmatch '^[1-9][0-9]*$') {
      throw 'PgcEpisodeId requires -Online and a positive episode ID.'
    }
    $arguments += "--dart-define=BILI_CONTENT_EPISODE=$PgcEpisodeId"
  }
  if ($SavedSession) {
    if (!$Online) { throw 'SavedSession requires -Online.' }
    $arguments += '--dart-define=BILI_CONTENT_SAVED_SESSION=true'
  }
  & flutter @arguments
  if ($LASTEXITCODE -ne 0) { throw 'Windows content playback validation failed' }
} finally {
  Remove-Item Env:BILI_CONTENT_MEDIA_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
