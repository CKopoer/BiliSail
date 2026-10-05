$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $repoRoot
try {
  $fixtureDir = Join-Path $repoRoot 'artifacts/video-codecs'
  New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null
  Copy-Item -LiteralPath 'test/fixtures/media/audio.m4a' -Destination (Join-Path $fixtureDir 'audio.m4a') -Force
  $encoders = @(
    @{ Name = 'h264'; Encoder = 'libx264'; Options = @('-preset', 'ultrafast', '-crf', '28') },
    @{ Name = 'hevc'; Encoder = 'libx265'; Options = @('-preset', 'ultrafast', '-crf', '28', '-x265-params', 'log-level=error:pools=2', '-tag:v', 'hvc1') },
    @{ Name = 'av1'; Encoder = 'libaom-av1'; Options = @('-cpu-used', '8', '-crf', '40', '-threads', '2') }
  )
  foreach ($codec in $encoders) {
    $outputPath = Join-Path $fixtureDir "$($codec.Name).mp4"
    $arguments = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=256x144:rate=24', '-t', '4', '-an', '-c:v', $codec.Encoder, '-pix_fmt', 'yuv420p') + $codec.Options + @($outputPath)
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) { throw "Fixture encoding failed: $($codec.Name)" }
    $actualCodec = & ffprobe '-v' 'error' '-select_streams' 'v:0' '-show_entries' 'stream=codec_name' '-of' 'default=noprint_wrappers=1:nokey=1' $outputPath
    if ($LASTEXITCODE -ne 0 -or $actualCodec -ne $codec.Name) { throw "Unexpected fixture codec: $actualCodec" }
  }
  $env:BILI_TEST_CODEC_DIR = $fixtureDir
  & flutter test integration_test/windows_video_codecs_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw "Windows codec validation failed: $LASTEXITCODE" }
} finally {
  Remove-Item Env:BILI_TEST_CODEC_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
