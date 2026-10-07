$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-installers.ps1')

# MSI's three-field comparison must preserve Flutter's patch and build ordering.
$versions = @('0.3.0+1', '0.3.0+2', '0.3.0+999', '0.3.1+1', '0.4.0+1', '1.0.0+1')
$previous = [version]'0.0.0'
foreach ($version in $versions) {
  $actual = [version](Get-WindowsMsiVersion $version)
  if ($actual -le $previous) { throw "MSI upgrade ordering was lost for $version." }
  $previous = $actual
}
if ((Get-WindowsMsiVersion '255.255.65+535') -ne '255.255.65535') { throw 'MSI maximum version mapping failed.' }
foreach ($invalid in @('0.3.0', '0.3.0+0', '0.3.0+1000', '256.0.0+1', '0.256.0+1', '0.3.65+536', '0.3.66+1')) {
  $rejected = $false
  try { Get-WindowsMsiVersion $invalid | Out-Null } catch { $rejected = $true }
  if (!$rejected) { throw "Invalid MSI version was accepted: $invalid" }
}
Write-Output 'Windows installer version checks passed (14 cases).'
