. (Join-Path $PSScriptRoot 'windows-architecture.ps1')

function Get-WindowsRuntimeRequiredFiles([ValidateSet('x64', 'arm64')][string]$Architecture) {
  $required = @('msvcp140.dll', 'vcruntime140.dll')
  if ($Architecture -eq 'x64') { $required += 'vcruntime140_1.dll' }
  return $required
}

# Directory names alone do not prove the architecture of redistributable files.
# Return only a fully checked set so callers can preflight before compiling.
function Get-WindowsRuntimeFiles([string]$Directory, [ValidateSet('x64', 'arm64')][string]$Architecture) {
  $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.dll' -File -ErrorAction Stop | Sort-Object Name)
  $selected = @(foreach ($dll in $files) {
    $actual = Get-WindowsBinaryArchitecture $dll.FullName
    # The ARM64 CRT directory can include this x64 exception-handling runtime.
    # It is not part of our native ARM64 runtime contract. Do not exempt other
    # foreign binaries or skip reading the PE header of this optional file.
    if ($Architecture -eq 'arm64' -and $dll.Name -eq 'vcruntime140_1.dll' -and $actual -eq 'x64') {
      Write-Host "Skipping x64 compatibility runtime for ARM64: $($dll.FullName)"
      continue
    }
    if ($actual -cne $Architecture) {
      throw "Expected $Architecture, found $actual in VC++ runtime $($dll.FullName)"
    }
    Write-Host "Selected VC++ $Architecture runtime: $($dll.FullName)"
    $dll
  })
  foreach ($required in (Get-WindowsRuntimeRequiredFiles $Architecture)) {
    if ($required -notin $selected.Name) {
      throw "Visual C++ $Architecture runtime is missing $required in $Directory"
    }
  }
  return $selected
}
