param([string]$FFmpeg = 'ffmpeg')
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PSScriptRoot '../test/fixtures'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($codec in @('h264', 'hevc', 'av1')) {
  $encoder = switch ($codec) { 'h264' { 'libx264' }; 'hevc' { 'libx265' }; 'av1' { 'libaom-av1' } }
  $options = switch ($codec) {
    'h264' { @('-preset', 'ultrafast', '-bf', '2') }
    'hevc' { @('-preset', 'ultrafast', '-x265-params', 'pools=1:frame-threads=1:log-level=error') }
    'av1' { @('-cpu-used', '8', '-crf', '40') }
  }
  & $FFmpeg -nostdin -hide_banner -v error -y -f lavfi -i 'testsrc2=size=160x90:rate=12' -t 1 -an -c:v $encoder @options -movflags 'frag_keyframe+empty_moov+default_base_moof' -f mp4 (Join-Path $destination "$codec.m4s")
  if ($LASTEXITCODE -ne 0) { throw "Fixture generation failed: $codec" }
}
& $FFmpeg -nostdin -hide_banner -v error -y -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 1 -c:a aac -b:a 32k -output_ts_offset 0.25 (Join-Path $destination 'audio.m4a')
if ($LASTEXITCODE -ne 0) { throw 'Audio fixture generation failed' }
