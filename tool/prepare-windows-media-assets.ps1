param(
  [Parameter(Mandatory)][string]$Tar,
  [string]$CacheRoot = (Join-Path $PSScriptRoot '../.dart_tool/hooks_runner/shared/media_kit/build/prebuilt'),
  [string]$ArchivePath
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content (Join-Path $repoRoot '.dart_tool/package_config.json') -Raw | ConvertFrom-Json
$package = @($config.packages | Where-Object { $_.name -eq 'media_kit' })
if ($package.Count -ne 1 -or $package[0].rootUri -notlike 'file:*') { throw 'Resolve media_kit before preparing its native cache.' }
$packageRoot = ([Uri]$package[0].rootUri).LocalPath
$catalog = Get-Content (Join-Path $packageRoot 'hook/native_bundles.json') -Raw | ConvertFrom-Json
$bundle = $catalog.bundles.windows_x64
if ($catalog.schema -ne 1 -or $bundle.format -ne '7z' -or
    $bundle.sha256 -cnotmatch '^[a-f0-9]{64}$' -or ([Uri]$bundle.url).Scheme -ne 'https') {
  throw 'Review the pinned media-kit Windows bundle catalog.'
}
$cache = [IO.Path]::GetFullPath((Join-Path $CacheRoot $bundle.sha256))
if (!$cache.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'The native cache must stay inside the workspace.'
}
$ancestor = [IO.DirectoryInfo]::new($cache)
while ($ancestor.FullName -ine $repoRoot) {
  if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The native cache cannot traverse a directory link.'
  }
  $ancestor = $ancestor.Parent
}
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$archive = Join-Path $cache 'archive.7z'
if ($ArchivePath) { Copy-Item -LiteralPath $ArchivePath -Destination $archive -Force }
if (!(Test-Path -LiteralPath $archive) -or (Get-FileHash $archive -Algorithm SHA256).Hash -ine $bundle.sha256) {
  Invoke-WebRequest -Uri $bundle.url -OutFile "$archive.partial" -MaximumRetryCount 2 -RetryIntervalSec 2 -TimeoutSec 180
  if ((Get-FileHash "$archive.partial" -Algorithm SHA256).Hash -ine $bundle.sha256) { throw 'Native bundle SHA-256 mismatch.' }
  Move-Item -LiteralPath "$archive.partial" -Destination $archive -Force
}
if ((Get-FileHash $archive -Algorithm SHA256).Hash -ine $bundle.sha256) { throw 'Native bundle SHA-256 mismatch.' }
$names = & $Tar -tf $archive
if ($LASTEXITCODE -ne 0) { throw 'Could not list the verified native archive.' }
foreach ($name in $names) {
  $normalized = $name.Replace('\', '/')
  if ($normalized.StartsWith('/') -or $normalized.Contains(':') -or '..' -in $normalized.Split('/')) {
    throw "Unsafe native archive path: $name"
  }
}
$files = Join-Path $cache 'files'
# This is the checked, fixed child of a SHA-addressed cache within the workspace.
if (Test-Path -LiteralPath $files) {
  if ((Get-Item -LiteralPath $files).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Native cache cannot be a link.' }
  Remove-Item -LiteralPath $files -Recurse -Force
}
New-Item -ItemType Directory -Path $files | Out-Null
& $Tar -xf $archive -C $files
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the verified native archive.' }
$hashes = [ordered]@{}
Get-ChildItem -LiteralPath $files -Recurse -File | ForEach-Object {
  $hashes[[IO.Path]::GetRelativePath($files, $_.FullName)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
if (!$hashes.Count) { throw 'The native archive is empty.' }
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cache 'extracted.json') -Encoding utf8NoBOM
Write-Output "Prepared verified media-kit cache ($($hashes.Count) files): $cache"
