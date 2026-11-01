param(
  [string]$ArchiveDirectory = (Join-Path $PSScriptRoot '../build/windows/x64')
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = [IO.Path]::GetFullPath($ArchiveDirectory)
if (!$cache.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The native archive cache must stay inside the workspace.'
}
& cmake "-DBILISAIL_MEDIA_ASSET_CACHE=$cache" -P (Join-Path $repoRoot 'windows/native/media-assets.cmake')
if ($LASTEXITCODE -ne 0) { throw 'Windows media asset preparation failed.' }
Write-Output 'Verified Windows media archives against windows/native/media-assets.cmake.'
