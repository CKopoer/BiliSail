function Get-WindowsMuxToolchain([string]$SourceRoot, [string]$Target) {
  if ($Target -cnotmatch '^windows-(x64|arm64)$') { throw 'Invalid Windows mux target.' }
  $lock = Get-Content -LiteralPath (Join-Path $SourceRoot 'tool/windows-mux-toolchains.json') -Raw | ConvertFrom-Json -AsHashtable
  if ($lock.schema -ne 1 -or $lock.setupAction -cnotmatch '^[a-f0-9]{40}$') { throw 'Invalid Windows mux toolchain lock.' }
  $spec = $lock.toolchains[$Target]
  $expectedSystem = if ($Target -eq 'windows-arm64') { 'CLANGARM64' } else { 'UCRT64' }
  if (!$spec -or $spec.msystem -cne $expectedSystem -or !$spec.packages.Count -or !$spec.packages.Contains('make')) {
    throw 'Windows mux toolchain lock is incomplete.'
  }
  foreach ($entry in $spec.packages.GetEnumerator()) {
    if ($entry.Key -cnotmatch '^(make|mingw-w64-(ucrt-x86_64|clang-aarch64)-[a-z0-9+_-]+)$' -or
        $entry.Value -cnotmatch '^[0-9][a-zA-Z0-9._+]*-[0-9]+$') { throw 'Invalid Windows mux package pin.' }
  }
  foreach ($name in ($spec.install -split ' ')) {
    if (!$spec.packages.Contains($name)) { throw 'Windows mux install package is not locked.' }
  }
  return $spec
}

function Get-WindowsMuxCacheToolchain([string]$SourceRoot, [string]$Target) {
  $spec = Get-WindowsMuxToolchain $SourceRoot $Target
  $lines = @('windows-mux-lock-v1', $Target, $spec.msystem)
  $lines += @($spec.packages.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" })
  # Runner changes and custom flags cannot silently consume an older binary.
  foreach ($name in @('ImageOS', 'ImageVersion', 'CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET')) {
    $lines += "$name=$([Environment]::GetEnvironmentVariable($name))"
  }
  return $lines -join "`n"
}

function Confirm-WindowsMuxPackages([System.Collections.IDictionary]$Spec, [string[]]$Installed) {
  $actual = @{}
  foreach ($line in $Installed) {
    if ($line -match '^(\S+) (\S+)$') { $actual[$Matches[1]] = $Matches[2] }
  }
  foreach ($entry in $Spec.packages.GetEnumerator()) {
    if ($actual[$entry.Key] -cne $entry.Value) {
      throw "Windows mux toolchain drift: $($entry.Key) requires $($entry.Value), found '$($actual[$entry.Key])'. Review tool/windows-mux-toolchains.json before rebuilding."
    }
  }
}

function Get-WindowsMuxInstalledPackages([string]$MsysRoot) {
  $pacman = Join-Path $MsysRoot 'usr/bin/pacman.exe'
  $installed = @(& $pacman -Q)
  if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Windows mux toolchain.' }
  return $installed
}
