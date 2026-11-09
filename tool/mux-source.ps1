function Save-VerifiedMuxSourceArchive([string]$SourceRoot) {
  $scriptText = Get-Content -LiteralPath (Join-Path $SourceRoot 'packages/bili_mux/tool/build.sh') -Raw
  $version = [regex]::Match($scriptText, '(?m)^version=(n[0-9.]+)\r?$').Groups[1].Value
  $expected = [regex]::Match($scriptText, '(?m)^archive_sha=([a-f0-9]{64})\r?$').Groups[1].Value
  if (!$version -or !$expected) { throw 'Review the changed mux source pin before downloading.' }
  $cache = Join-Path $SourceRoot 'build/download_mux'
  New-Item -ItemType Directory -Path $cache -Force | Out-Null
  $archive = Join-Path $cache "$version.tar.gz"
  if (Test-Path -LiteralPath $archive -PathType Leaf) {
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
      throw 'FFmpeg source hash mismatch.'
    }
    return $archive
  }
  $temporary = Join-Path $cache "$version-$([guid]::NewGuid().ToString('N')).tmp"
  try {
    & curl.exe --fail --location --retry 3 --connect-timeout 30 --max-time 600 `
      "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/$version" --output $temporary
    if ($LASTEXITCODE -ne 0) { throw 'Could not download the pinned FFmpeg source.' }
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
      throw 'FFmpeg source hash mismatch.'
    }
    Move-Item -LiteralPath $temporary -Destination $archive
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
  }
  return $archive
}
