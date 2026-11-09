. (Join-Path $PSScriptRoot 'windows-architecture.ps1')

function Get-MuxCacheIdentity([string]$SourceRoot, [string]$Target, [string]$Toolchain) {
  $paths = @('packages/bili_mux/tool/build.sh', 'packages/bili_mux/tool/package-apple-framework.sh',
    'tool/build-download-mux.ps1', 'tool/mux-cache.ps1')
  if ($Target.StartsWith('windows-')) {
    $paths += @('tool/windows-mux-toolchain.ps1', 'tool/windows-mux-toolchains.json', 'tool/mux-source.ps1')
  }
  $paths += @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'packages/bili_mux/native') -File |
    ForEach-Object { "packages/bili_mux/native/$($_.Name)" })
  $inputs = @(foreach ($path in ($paths | Sort-Object)) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $SourceRoot $path) -Algorithm SHA256).Hash.ToLowerInvariant()
    "$path=$hash"
  })
  $material = (@('mux-cache-v1', $Target, $Toolchain.Trim()) + $inputs) -join "`n"
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($material))).ToLowerInvariant()
}

function Get-MuxSnapshotFiles([string]$Directory) {
  if ((Get-Item -LiteralPath $Directory).LinkType) { throw 'Mux cache root must not be a link.' }
  $root = [IO.Path]::GetFullPath($Directory) + [IO.Path]::DirectorySeparatorChar
  # Framework symlinks must remain internal to the component being cached.
  foreach ($entry in (Get-ChildItem -LiteralPath $Directory -Recurse -Force)) {
    if ($entry.LinkType) {
      $resolved = $entry.ResolveLinkTarget($true)
      if (!$resolved -or !$resolved.FullName.StartsWith($root, [StringComparison]::Ordinal)) {
        throw "Mux cache contains an external or broken link: $($entry.Name)"
      }
    }
  }
  return @(Get-ChildItem -LiteralPath $Directory -Recurse -File -Force |
    Where-Object FullName -ne (Join-Path $Directory 'cache-manifest.json') | ForEach-Object {
      [pscustomobject][ordered]@{
        path = [IO.Path]::GetRelativePath($Directory, $_.FullName).Replace('\', '/')
        bytes = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      }
    } | Sort-Object { $_.path })
}

function Confirm-MuxBinary([string]$Path, [string]$Target) {
  $architecture = $Target.Split('-')[-1]
  if ($Target.StartsWith('windows-')) {
    if ((Get-WindowsBinaryArchitecture $Path) -cne $architecture) { throw 'Mux PE architecture mismatch.' }
    return
  }
  $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
  try {
    if ($reader.BaseStream.Length -lt 20) { throw 'Invalid mux binary header.' }
    $magic = $reader.ReadUInt32()
    if ($Target.StartsWith('macos-') -or $Target.StartsWith('ios-')) {
      $cpu = $reader.ReadUInt32()
      $expected = if ($architecture -eq 'x64') { 0x01000007 } else { 0x0100000c }
      if ($magic -ne 4277009103 -or $cpu -ne $expected) { throw 'Mux Mach-O architecture mismatch.' }
    } else {
      $class = $reader.ReadByte()
      $encoding = $reader.ReadByte()
      $reader.BaseStream.Position = 18
      $machine = $reader.ReadUInt16()
      $expected = if ($architecture -eq 'x64') { 62 } else { 183 }
      if ($magic -ne 0x464c457f -or $class -ne 2 -or $encoding -ne 1 -or $machine -ne $expected) {
        throw 'Mux ELF architecture mismatch.'
      }
    }
  } finally { $reader.Dispose() }
}

function Confirm-MuxSnapshot([string]$Directory, [string]$Target, [string]$Identity) {
  $manifest = Get-Content -LiteralPath (Join-Path $Directory 'cache-manifest.json') -Raw | ConvertFrom-Json
  if ($manifest.schema -ne 1 -or $manifest.target -cne $Target -or $manifest.identity -cne $Identity) {
    throw 'Mux cache source/toolchain identity mismatch.'
  }
  $actual = @(Get-MuxSnapshotFiles $Directory)
  $declared = @($manifest.files)
  if (!$actual.Count -or $actual.Count -ne $declared.Count) { throw 'Mux cache file set mismatch.' }
  for ($index = 0; $index -lt $actual.Count; $index++) {
    $file = $actual[$index]
    $saved = $declared[$index]
    if ($file.path -cne $saved.path -or $file.bytes -ne $saved.bytes -or $file.sha256 -cne $saved.sha256) {
      throw "Mux cache digest mismatch: $($file.path)"
    }
  }
  $required = @('configure.log', 'COPYING.LGPLv2.1', 'source.txt')
  if ($Target.StartsWith('windows-')) {
    $binary = 'bili_mux.dll'
    $required += @('bili_mux.LGPL.txt', 'bili_mux.source.txt', 'bili_mux.configuration.txt', 'toolchain.txt')
  } elseif ($Target.StartsWith('macos-') -or $Target.StartsWith('ios-')) {
    $binary = 'BiliMux.framework/BiliMux'
    $required += 'BiliMux.framework/Info.plist'
  } else { $binary = 'libbili_mux.so' }
  foreach ($path in ($required + $binary)) {
    if (!(Test-Path -LiteralPath (Join-Path $Directory $path) -PathType Leaf)) { throw "Mux cache missing $path" }
  }
  $total = ($actual | Measure-Object -Property bytes -Sum).Sum
  if ($total -gt 80000000) { throw 'Mux snapshot exceeds its 80 MB payload limit.' }
  Confirm-MuxBinary (Join-Path $Directory $binary) $Target
}

function Write-MuxSnapshot([string]$Directory, [string]$Target, [string]$Identity) {
  $files = @(Get-MuxSnapshotFiles $Directory)
  if (($files | Measure-Object -Property bytes -Sum).Sum -gt 80000000) {
    Write-Warning 'Mux output is too large to cache; retaining the uncached build.'
    return $false
  }
  $manifest = [ordered]@{ schema = 1; target = $Target; identity = $Identity; files = $files }
  [IO.File]::WriteAllText((Join-Path $Directory 'cache-manifest.json'), ($manifest | ConvertTo-Json -Depth 5))
  Confirm-MuxSnapshot $Directory $Target $Identity
  return $true
}

function Clear-MuxSnapshot([string]$SourceRoot, [string]$Target) {
  if ($Target -cnotmatch '^(windows-(x64|arm64)|macos-(x64|arm64)|android-arm64|ios-arm64|linux-x64)$') { throw 'Invalid mux target.' }
  $parent = [IO.Path]::GetFullPath((Join-Path $SourceRoot 'packages/bili_mux/native/prebuilt'))
  $directory = [IO.Path]::GetFullPath((Join-Path $parent $Target))
  if ((Split-Path $directory -Parent) -cne $parent) { throw 'Unsafe mux cache cleanup path.' }
  foreach ($relative in @('packages', 'packages/bili_mux', 'packages/bili_mux/native', 'packages/bili_mux/native/prebuilt')) {
    $ancestor = Join-Path $SourceRoot $relative
    if ((Test-Path -LiteralPath $ancestor) -and (Get-Item -LiteralPath $ancestor).LinkType) {
      throw 'Mux cache cleanup must not traverse a redirected parent.'
    }
  }
  if (Test-Path -LiteralPath $directory) {
    if ((Get-Item -LiteralPath $directory).LinkType -or (Resolve-Path -LiteralPath $directory).Path -cne $directory) {
      throw 'Mux cache root must be a real workspace directory.'
    }
    Remove-Item -LiteralPath $directory -Recurse -Force
  }
}
