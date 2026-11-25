param([Parameter(Mandatory)][string]$CMake)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content -LiteralPath (Join-Path $repoRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$package = $config.packages | Where-Object { $_.name -eq 'media_kit' }
if ($package.rootUri -notlike 'file:*') { throw 'Resolve the pinned media_kit package before preparing native assets.' }
$packageRoot = ([uri]$package.rootUri).LocalPath
$catalog = Get-Content -LiteralPath (Join-Path $packageRoot 'hook/native_bundles.json') -Raw | ConvertFrom-Json
$bundle = $catalog.bundles.windows_x64
if ($catalog.schema -ne 1 -or $bundle.format -cnotin '7z','zip' -or
    $bundle.sha256 -cnotmatch '^[a-f0-9]{64}$' -or ([uri]$bundle.url).Scheme -ne 'https') {
  throw 'Invalid media_kit Windows x64 native bundle catalog.'
}
# The Native Assets hook verifies and extracts ZIPs directly on Windows.
if ($bundle.format -ceq 'zip') { return }

# Use the cache layout of the locked Native Assets hook. Windows process
# lookup can select System32 tar.exe even when PATH starts with another tar.
$cache = Join-Path $repoRoot ".dart_tool/hooks_runner/shared/media_kit/build/prebuilt/$($bundle.sha256)"
$files = Join-Path $cache 'files'
$directory = [IO.DirectoryInfo]::new($files)
while ($directory.FullName -ine $repoRoot) {
  if ($directory.Exists -and ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The Windows media asset cache cannot traverse a directory link.'
  }
  $directory = $directory.Parent
}
$stage = Join-Path $cache ([guid]::NewGuid().ToString('N'))
$extracted = Join-Path $stage 'files'
New-Item -ItemType Directory -Path $extracted -Force | Out-Null
try {
  $archive = Join-Path $cache 'archive.7z'
  if (!(Test-Path -LiteralPath $archive -PathType Leaf) -or
      (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $bundle.sha256) {
    $download = Join-Path $stage 'archive.7z'
    Invoke-WebRequest -Uri $bundle.url -OutFile $download -MaximumRetryCount 2 -TimeoutSec 180
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $bundle.sha256) {
      throw 'Windows media bundle SHA-256 mismatch.'
    }
    Move-Item -LiteralPath $download -Destination $archive -Force
  }

  $entries = & $CMake -E tar tf $archive
  if ($LASTEXITCODE -ne 0) { throw 'Could not list the verified Windows media bundle.' }
  foreach ($entry in $entries) {
    $name = $entry.Replace('\', '/')
    if ($name.StartsWith('/') -or $name.Contains(':') -or '..' -in $name.Split('/')) {
      throw "Unsafe native archive path: $entry"
    }
  }
  Push-Location -LiteralPath $extracted
  try {
    & $CMake -E tar xf $archive
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the verified Windows media bundle.' }
  } finally { Pop-Location }

  $hashes = [ordered]@{}
  Get-ChildItem -LiteralPath $extracted -File -Recurse | ForEach-Object {
    $hashes[[IO.Path]::GetRelativePath($extracted, $_.FullName)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  if (!$hashes.Contains($bundle.library)) { throw 'The extracted Windows bundle does not contain the pinned libmpv DLL.' }
  $stamp = Join-Path $stage 'extracted.json'
  $hashes | ConvertTo-Json | Set-Content -LiteralPath $stamp -Encoding utf8NoBOM
  if (Test-Path -LiteralPath $files) { Remove-Item -LiteralPath $files -Recurse -Force }
  Move-Item -LiteralPath $extracted -Destination $files
  Move-Item -LiteralPath $stamp -Destination (Join-Path $cache 'extracted.json') -Force
  Write-Output "Prepared verified Windows x64 media assets ($($hashes.Count) files)."
} finally {
  Remove-Item -LiteralPath $stage -Recurse -Force
}
