# Check actual PE headers before signing or publishing a Windows payload.
function Get-WindowsBinaryArchitecture([string]$Path) {
  $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
  try {
    if ($reader.BaseStream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw "Invalid Windows binary: $Path" }
    $reader.BaseStream.Position = 0x3c
    $offset = $reader.ReadUInt32()
    if ($offset -lt 64 -or $offset + 6 -gt $reader.BaseStream.Length) { throw "Invalid PE offset: $Path" }
    $reader.BaseStream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE signature: $Path" }
    switch ($reader.ReadUInt16()) {
      0x8664 { return 'x64' }
      0xaa64 { return 'arm64' }
      default { throw "Unsupported PE architecture: $Path" }
    }
  } finally { $reader.Dispose() }
}

function Confirm-WindowsPayloadArchitecture([string]$Directory, [ValidateSet('x64', 'arm64')][string]$Architecture) {
  $binaries = @(Get-ChildItem -LiteralPath $Directory -Recurse -File | Where-Object Extension -in @('.exe', '.dll'))
  if (!$binaries.Count) { throw "No Windows binaries found in $Directory" }
  foreach ($binary in $binaries) {
    $actual = Get-WindowsBinaryArchitecture $binary.FullName
    if ($actual -cne $Architecture) { throw "Expected $Architecture, found $actual in $($binary.FullName)" }
  }
  Write-Output "Verified $($binaries.Count) Windows $Architecture binaries."
}
