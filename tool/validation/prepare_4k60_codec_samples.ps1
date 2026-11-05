param(
  [string]$Source = 'build/validation/4k60/bbb_sunflower_2160p_60fps_normal.mp4',
  [string]$Audio = 'build/validation/android-4k60/audio.m4a',
  [string]$Output = 'build/validation/android-4k60-codecs/media'
)
$ErrorActionPreference = 'Stop'
$Source = [IO.Path]::GetFullPath($Source)
$Audio = [IO.Path]::GetFullPath($Audio)
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path $Output | Out-Null
if ((Get-FileHash -LiteralPath $Source).Hash -cne '35DB9A007021F1B0066993E1D2C4448C83A8B279F799C97D33CBBA73980A8A36') {
  throw 'Use the recorded public Big Buck Bunny source to preserve the comparison.'
}
$variants = @(
  @{Name='hevc-main8'; Encoder='hevc_nvenc'; Profile='main'; TenBit=$false; Tag='hvc1'},
  @{Name='hevc-main10'; Encoder='hevc_nvenc'; Profile='main10'; TenBit=$true; Tag='hvc1'},
  @{Name='av1-main8'; Encoder='av1_nvenc'; Profile='0'; TenBit=$false; Tag='av01'},
  @{Name='av1-main10'; Encoder='av1_nvenc'; Profile='0'; TenBit=$true; Tag='av01'}
)
$files = @('h264-high8.mp4','audio.m4a') + @($variants | ForEach-Object { "$($_.Name).mp4" })
foreach ($name in $files) { if (Test-Path -LiteralPath (Join-Path $Output $name)) { throw 'Use a fresh output directory.' } }
& ffmpeg -hide_banner -loglevel error -i $Source -t 90 -map 0:v:0 -c copy -an -movflags +faststart (Join-Path $Output 'h264-high8.mp4')
if ($LASTEXITCODE -ne 0) { throw 'H.264 baseline preparation failed' }
& ffmpeg -hide_banner -loglevel error -i $Audio -t 90 -c copy -movflags +faststart (Join-Path $Output 'audio.m4a')
if ($LASTEXITCODE -ne 0) { throw 'AAC preparation failed' }
foreach ($variant in $variants) {
  $name = $variant.Name
  $target = Join-Path $Output "$name.mp4"
  $parameters = @('-hide_banner','-hwaccel','cuda','-hwaccel_output_format','cuda','-i',$Source,
    '-t','90','-map','0:v:0','-an')
  if ($variant.TenBit) { $parameters += @('-vf','scale_cuda=format=p010le') }
  $parameters += @('-c:v',$variant.Encoder,'-pix_fmt','cuda','-preset','p5','-tune','hq','-profile:v',$variant.Profile,
    '-rc','vbr','-b:v','8M','-maxrate','12M','-bufsize','24M','-g','120',
    '-tag:v',$variant.Tag,'-movflags','+faststart',$target)
  & ffmpeg @parameters *> (Join-Path $Output "$name.encode.log")
  if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $Output "$name.encode.log") -Tail 20; throw "Encoding failed: $name" }
  Write-Output "Encoded $name"
}
$metadata = @(foreach ($name in $files) {
  $path = Join-Path $Output $name
  $probe = & ffprobe -v error -show_streams -show_format -of json $path
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $name" }
  $details = $probe -join "`n" | ConvertFrom-Json
  [pscustomobject]@{name=$name;bytes=(Get-Item $path).Length;sha256=(Get-FileHash $path).Hash;probe=$details}
})
$metadata | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $Output 'media-metadata.json') -Encoding utf8
Write-Output "Codec fixtures prepared: $Output"
