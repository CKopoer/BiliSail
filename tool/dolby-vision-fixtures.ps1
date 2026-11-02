function Initialize-DolbyVisionFixture([string]$Fixtures) {
  $sourceUrl = 'https://media.developer.dolby.com/DolbyVision_Atmos/mp4/iOS_P5_GlassBlowing2_1920x1080%4059.94fps_15200kbps.mp4'
  $prefixHash = '2e1a62c39519ccef267353672aff6c2985b7ef145739fb60b56029fa91ec6fac'
  New-Item -ItemType Directory -Force -Path $Fixtures | Out-Null
  $prefix = Join-Path $Fixtures 'dolby-profile5-prefix.mp4'
  if (!(Test-Path -LiteralPath $prefix)) {
    & curl.exe -4 --http1.1 --location --fail --show-error --silent --connect-timeout 10 --max-time 180 --range 0-33554431 $sourceUrl --output "$prefix.partial"
    if ($LASTEXITCODE -ne 0) { throw 'Dolby sample download failed.' }
    if ((Get-FileHash -LiteralPath "$prefix.partial" -Algorithm SHA256).Hash -ne $prefixHash) {
      throw 'Dolby sample prefix changed; review its source before updating the hash.'
    }
    Move-Item -LiteralPath "$prefix.partial" -Destination $prefix
  }
  if ((Get-FileHash -LiteralPath $prefix -Algorithm SHA256).Hash -ne $prefixHash) {
    throw 'Cached Dolby sample prefix does not match the pinned SHA-256.'
  }
  & ffmpeg -v error -y -i $prefix -ss 10 -t 6 -map 0:v:0 -c copy -strict unofficial "$Fixtures/video.mp4"
  if ($LASTEXITCODE -ne 0) { throw 'Dolby test clip extraction failed.' }
  $probe = (& ffprobe -v error -select_streams v:0 -show_entries stream_side_data=dv_profile,dv_bl_signal_compatibility_id -of json "$Fixtures/video.mp4" | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0) { throw 'Dolby sample inspection failed.' }
  $dovi = @($probe.streams[0].side_data_list | Where-Object { $_.dv_profile -eq 5 -and $_.dv_bl_signal_compatibility_id -eq 0 })
  if ($dovi.Count -ne 1) { throw 'The sample must be Profile 5 without an HDR10 compatible base layer.' }
  $mapping = 'libplacebo=apply_dolbyvision=1:colorspace=bt709:color_primaries=bt709:color_trc=iec61966-2-1:format=yuv420p10le'
  & ffmpeg -v error -y -i "$Fixtures/video.mp4" -vf "$mapping,scale=640:360" -frames:v 1 -update 1 "$Fixtures/reference.png"
  if ($LASTEXITCODE -ne 0) { throw 'Dolby-aware reference rendering failed; FFmpeg needs libplacebo/Vulkan.' }
  & ffmpeg -v error -y -i "$Fixtures/video.mp4" -vf "select=gte(t\,0.510),$mapping,scale=320:180,format=rgb24" -frames:v 1 -update 1 "$Fixtures/reference-playing.png"
  if ($LASTEXITCODE -ne 0) { throw 'Dolby-aware playing reference rendering failed.' }
  & ffmpeg -v error -i "$Fixtures/video.mp4" -f null -
  if ($LASTEXITCODE -ne 0) { throw 'Dolby sample decode validation failed.' }
}
