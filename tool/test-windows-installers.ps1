$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-installers.ps1')

# MSI's three-field comparison must preserve Flutter's patch and build ordering.
$versions = @('0.3.0+0', '0.3.0+1', '0.3.0+2', '0.3.0+999', '0.3.1+0', '0.3.1+1', '0.4.0+1', '1.0.0+0', '1.0.0+1', '1.0.2+0')
$previous = [version]'0.0.0'
foreach ($version in $versions) {
  $actual = [version](Get-WindowsMsiVersion $version)
  if ($actual -le $previous) { throw "MSI upgrade ordering was lost for $version." }
  $previous = $actual
}
if ((Get-WindowsMsiVersion '255.255.65+535') -ne '255.255.65535') { throw 'MSI maximum version mapping failed.' }
foreach ($invalid in @('0.3.0', '0.3.0+-1', '0.3.0+00', '0.3.0+01', '0.3.0+1000', '256.0.0+1', '0.256.0+1', '0.3.65+536', '0.3.66+1')) {
  $rejected = $false
  try { Get-WindowsMsiVersion $invalid | Out-Null } catch { $rejected = $true }
  if (!$rejected) { throw "Invalid MSI version was accepted: $invalid" }
}
if ((Get-WindowsMsiVersion '1.0.2+0') -ne '1.0.2000') { throw 'Zero-build MSI mapping failed.' }
Write-Output 'Windows installer version checks passed.'

# Exercise the production MSI/Bundle orchestration without requiring WiX or C++.
# The release directory must contain only final packages, never native SDKs/artwork.
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "bilisail-installer-boundary-$([guid]::NewGuid().ToString('N'))"))
$release = Join-Path $testRoot 'release'
$staging = Join-Path $testRoot 'payload'
$work = Join-Path $testRoot 'installer-work'
try {
  New-Item -ItemType Directory -Path $release, $staging, $work -Force | Out-Null
  foreach ($required in @('bilisail.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'THIRD_PARTY_NOTICES.md')) {
    $file = Join-Path $staging $required
    New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
    Set-Content -LiteralPath $file -Value 'test payload'
  }
  function Build-WindowsInstallerNative([string]$WorkingDirectory) {
    $headers = Join-Path $WorkingDirectory 'sdk/wixtoolset.bootstrapperapplicationapi/build/native/include'
    $binary = Join-Path $WorkingDirectory 'build/Release/BiliSailInstallerUI.dll'
    New-Item -ItemType Directory -Path $headers, (Split-Path $binary -Parent) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $headers 'BootstrapperApplicationTypes.h') -Value 'test SDK header'
    Set-Content -LiteralPath $binary -Value 'test native helper'
    return $binary
  }
  function New-WindowsInstallerArtwork([string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Destination 'dialog.bmp') -Value 'test artwork'
  }
  function Invoke-WixCommand([string]$Wix, [string[]]$Parameters) {
    $helper = Join-Path $work 'installer-native/build/Release/BiliSailInstallerUI.dll'
    $artwork = Join-Path $work 'installer-artwork'
    if ("InstallerUIHelper=$helper" -cnotin $Parameters -or "InstallerArtwork=$artwork" -cnotin $Parameters) {
      throw 'WiX must consume build-only resources from installer-work.'
    }
    $destination = $Parameters[[Array]::IndexOf($Parameters, '-o') + 1]
    Set-Content -LiteralPath $destination -Value 'test installer'
  }
  $msi = Join-Path $release 'BiliSail-1.2.6+0-windows-x64.msi'
  New-WindowsMsi 'test-wix' $staging $msi '1.2.6+0' $work
  New-WindowsBundle 'test-wix' $msi (Join-Path $work 'unsigned-setup.exe') '1.2.6+0'
  $entries = @(Get-ChildItem -LiteralPath $release -Force)
  if ($entries.Count -ne 1 -or $entries[0].FullName -ne $msi -or $entries[0].PSIsContainer) {
    throw 'Installer build-only files leaked into the release directory.'
  }
  foreach ($required in @('installer-native/build/Release/BiliSailInstallerUI.dll', 'installer-artwork/dialog.bmp', 'unsigned-setup.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $work $required) -PathType Leaf)) { throw "Missing build-only file: $required" }
  }
  if (!(Test-Path -LiteralPath (Join-Path $staging 'data/licenses/wix/installer-ui/BootstrapperApplicationTypes.h') -PathType Leaf)) {
    throw 'Moving build files must preserve the SDK header supplied with the adapted UI source.'
  }
  Write-Output 'Windows installer release-directory boundary checks passed.'
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    if ((Resolve-Path -LiteralPath $testRoot).Path -ne $testRoot) { throw 'Unexpected installer test cleanup path.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
