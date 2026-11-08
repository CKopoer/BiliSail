$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-architecture.ps1')
. (Join-Path $PSScriptRoot 'windows-runtime.ps1')

function Write-TestWindowsBinary([string]$Path, [string]$Architecture) {
  $bytes = [byte[]]::new(134)
  [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes, 0)
  [BitConverter]::GetBytes([uint32]128).CopyTo($bytes, 60)
  [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
  $machine = if ($Architecture -eq 'x64') { 0x8664 } else { 0xaa64 }
  [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 132)
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Assert-RuntimeRejected([scriptblock]$Action, [string]$ExpectedError) {
  $message = $null
  try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
  if (!$message -or !$message.Contains($ExpectedError)) {
    throw "Expected runtime error '$ExpectedError', got '$message'."
  }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) "bilisail-pe-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  foreach ($architecture in @('x64', 'arm64')) {
    $directory = Join-Path $testRoot $architecture
    New-Item -ItemType Directory -Path $directory | Out-Null
    $binary = Join-Path $directory 'player.dll'
    Write-TestWindowsBinary $binary $architecture
    $bytes = [IO.File]::ReadAllBytes($binary)
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

  foreach ($architecture in @('x64', 'arm64')) {
    $runtimeDirectory = Join-Path $testRoot "runtime-$architecture"
    $staging = Join-Path $testRoot "staging-$architecture"
    New-Item -ItemType Directory -Path $runtimeDirectory, $staging | Out-Null
    foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'concrt140.dll')) {
      Write-TestWindowsBinary (Join-Path $runtimeDirectory $name) $architecture
    }
    # Reproduce an ARM64 CRT directory containing the x64-only helper. The x64
    # target must still copy and require that same filename.
    $optionalRuntime = Join-Path $runtimeDirectory 'vcruntime140_1.dll'
    Write-TestWindowsBinary $optionalRuntime 'x64'
    $selected = @(Get-WindowsRuntimeFiles $runtimeDirectory $architecture)
    $expectedCount = if ($architecture -eq 'x64') { 4 } else { 3 }
    if ($selected.Count -ne $expectedCount -or 'concrt140.dll' -notin $selected.Name) {
      throw "Unexpected $architecture runtime selection."
    }
    foreach ($dll in $selected) { Copy-Item -LiteralPath $dll.FullName -Destination $staging }
    Confirm-WindowsPayloadArchitecture $staging $architecture
    $hasHelper = Test-Path -LiteralPath (Join-Path $staging 'vcruntime140_1.dll')
    if ($hasHelper -ne ($architecture -eq 'x64')) { throw 'The x64-only runtime leaked into ARM64 or was omitted from x64.' }

    $requiredRuntime = Join-Path $runtimeDirectory 'msvcp140.dll'
    Remove-Item -LiteralPath $requiredRuntime
    Assert-RuntimeRejected { Get-WindowsRuntimeFiles $runtimeDirectory $architecture } 'missing msvcp140.dll'
    $other = if ($architecture -eq 'x64') { 'arm64' } else { 'x64' }
    Write-TestWindowsBinary $requiredRuntime $other
    Assert-RuntimeRejected { Get-WindowsRuntimeFiles $runtimeDirectory $architecture } "Expected $architecture, found $other"
    Write-TestWindowsBinary $requiredRuntime $architecture

    $foreign = Join-Path $runtimeDirectory 'unexpected.dll'
    Write-TestWindowsBinary $foreign $other
    Assert-RuntimeRejected { Get-WindowsRuntimeFiles $runtimeDirectory $architecture } "Expected $architecture, found $other"
    Remove-Item -LiteralPath $foreign
    [IO.File]::WriteAllBytes($optionalRuntime, [byte[]]::new(0))
    Assert-RuntimeRejected { Get-WindowsRuntimeFiles $runtimeDirectory $architecture } 'Invalid Windows binary'
    Remove-Item -LiteralPath $optionalRuntime
    if ($architecture -eq 'x64') {
      Assert-RuntimeRejected { Get-WindowsRuntimeFiles $runtimeDirectory $architecture } 'missing vcruntime140_1.dll'
    } else {
      Get-WindowsRuntimeFiles $runtimeDirectory $architecture | Out-Null
      # The full payload check must still reject an unrelated foreign plugin.
      Write-TestWindowsBinary (Join-Path $staging 'plugin.dll') 'x64'
      Assert-RuntimeRejected { Confirm-WindowsPayloadArchitecture $staging $architecture } 'Expected arm64, found x64'
    }
  }
  Write-Output 'Windows binary architecture checks passed.'
} finally {
  $resolved = [IO.Path]::GetFullPath($testRoot)
  if ($resolved -ne $testRoot -or !(Split-Path $resolved -Leaf).StartsWith('bilisail-pe-')) { throw 'Unsafe test cleanup path.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
