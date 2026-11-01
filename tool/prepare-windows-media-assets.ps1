param(
  [string]$ArchiveDirectory = (Join-Path $PSScriptRoot '../build/windows/x64')
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = [IO.Path]::GetFullPath($ArchiveDirectory)
if (!$cache.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The native archive cache must stay inside the workspace.'
}
$bundles = @(
  @{
    name = 'mpv-dev-x86_64-20260607-git-43b14a4.7z'
    url = 'https://github.com/bggRGjQaUbCoE/mpv-winbuild-cmake/releases/download/20260607/mpv-dev-x86_64-20260607-git-43b14a4.7z'
    sha256 = '4efaccac571b390ba12db822a0acb50a89e9ccf0797827ca0d3b223341ceff52'
  },
  @{
    name = 'ANGLE.7z'
    url = 'https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z'
    sha256 = 'cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a'
  }
)
New-Item -ItemType Directory -Path $cache -Force | Out-Null
foreach ($bundle in $bundles) {
  $archive = Join-Path $cache $bundle.name
  if (!(Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $bundle.sha256) {
    Invoke-WebRequest -Uri $bundle.url -OutFile "$archive.partial" -MaximumRetryCount 2 -RetryIntervalSec 2 -TimeoutSec 180
    if ((Get-FileHash -LiteralPath "$archive.partial" -Algorithm SHA256).Hash -ine $bundle.sha256) {
      throw 'PiliPlus native archive SHA-256 mismatch.'
    }
    Move-Item -LiteralPath "$archive.partial" -Destination $archive -Force
  }
  Write-Output "Verified PiliPlus native archive: $($bundle.name)"
}
# The pinned library plugin still checks its own MD5 and extracts these archives.
