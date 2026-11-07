$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-architecture.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "bilisail-pe-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  foreach ($architecture in @('x64', 'arm64')) {
    $bytes = [byte[]]::new(134)
    [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes, 0)
    [BitConverter]::GetBytes([uint32]128).CopyTo($bytes, 60)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
    $machine = if ($architecture -eq 'x64') { 0x8664 } else { 0xaa64 }
    [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 132)
    $directory = Join-Path $testRoot $architecture
    New-Item -ItemType Directory -Path $directory | Out-Null
    $binary = Join-Path $directory 'player.dll'
    [IO.File]::WriteAllBytes($binary, $bytes)
    Confirm-WindowsPayloadArchitecture $directory $architecture
    $other = if ($architecture -eq 'x64') { 'arm64' } else { 'x64' }
    $rejected = $false
    try { Confirm-WindowsPayloadArchitecture $directory $other } catch { $rejected = $true }
    if (!$rejected) { throw 'A payload with the wrong architecture was accepted.' }
    foreach ($invalid in @([byte[]]::new(0), [byte[]]::new(64), $bytes[0..129])) {
      [IO.File]::WriteAllBytes($binary, [byte[]]$invalid)
      $rejected = $false
      try { Get-WindowsBinaryArchitecture $binary | Out-Null } catch { $rejected = $true }
      if (!$rejected) { throw 'A malformed binary was accepted.' }
    }
  }
  Write-Output 'Windows binary architecture checks passed.'
} finally {
  $resolved = [IO.Path]::GetFullPath($testRoot)
  if ($resolved -ne $testRoot -or !(Split-Path $resolved -Leaf).StartsWith('bilisail-pe-')) { throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
