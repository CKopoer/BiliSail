param(
  [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64',
  [string]$ArchiveDirectory = (Join-Path $PSScriptRoot "../build/windows/$Architecture")
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-dependency-command.ps1')
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = [IO.Path]::GetFullPath($ArchiveDirectory)
if (!$cache.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The native archive cache must stay inside the workspace.'
}
Invoke-BuildDependencyCommand cmake @("-DFLUTTER_TARGET_PLATFORM=windows-$Architecture", "-DBILISAIL_MEDIA_ASSET_CACHE=$cache", '-P', (Join-Path $repoRoot 'windows/native/media-assets.cmake'))
Write-Output 'Verified Windows media assets against the personal media-kit library manifest.'
