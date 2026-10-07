# WiX is a build-time dependency; the native Burn UI needs no .NET on users' PCs.
$script:WindowsWixVersion = '6.0.2'
$script:WindowsPackagingRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../windows/packaging'))

function Get-WindowsMsiVersion([string]$Version) {
  if ($Version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+[1-9]\d*$') {
    throw 'Version must be x.y.z+N.'
  }
  $major, $minor, $patch, $number = @($Version -split '[.+]' | ForEach-Object { [long]$_ })
  # MSI ignores a fourth field. Reserve 1000 revisions per patch so +N upgrades
  # and patch upgrades both compare correctly using its three-field version.
  if ($major -gt 255 -or $minor -gt 255 -or $number -gt 999 -or $patch -gt 65 -or ($patch * 1000 + $number) -gt 65535) {
    throw 'Windows installers require x/y <= 255, N <= 999 and z*1000+N <= 65535.'
  }
  return "$major.$minor.$($patch * 1000 + $number)"
}

function Invoke-WixCommand([string]$Wix, [string[]]$Parameters) {
  & $Wix @Parameters | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "WiX failed: $LASTEXITCODE" }
}

function Initialize-WindowsInstallerTools([string]$ToolsDirectory) {
  if (!$IsWindows) { throw 'Windows installers require a Windows host.' }
  $oldTelemetry = $env:DOTNET_CLI_TELEMETRY_OPTOUT
  try {
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    & dotnet tool install wix --version $script:WindowsWixVersion --tool-path $ToolsDirectory --source https://api.nuget.org/v3/index.json | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the pinned WiX toolset.' }
  } finally { $env:DOTNET_CLI_TELEMETRY_OPTOUT = $oldTelemetry }
  $wix = Join-Path $ToolsDirectory 'wix.exe'
  foreach ($extension in @('WixToolset.BootstrapperApplications.wixext', 'WixToolset.UI.wixext', 'WixToolset.Util.wixext')) {
    Invoke-WixCommand $wix @('extension', 'add', '-g', "$extension/$script:WindowsWixVersion")
  }
  return $wix
}

function New-WindowsMsi([string]$Wix, [string]$Staging, [string]$Destination, [string]$Version) {
  foreach ($required in @('bilisail.exe', 'flutter_windows.dll', 'libmpv-2.dll', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'THIRD_PARTY_NOTICES.md')) {
    if (!(Test-Path -LiteralPath (Join-Path $Staging $required) -PathType Leaf)) { throw "Windows payload is missing $required." }
  }
  # Build before MSIX adds package identity, icons and PRI to this directory.
  if (Test-Path -LiteralPath (Join-Path $Staging 'AppxManifest.xml')) { throw 'MSI payload must be staged before MSIX packaging.' }
  Invoke-WixCommand $Wix @('build', (Join-Path $script:WindowsPackagingRoot 'Installer.wxs'), '-arch', 'x64', '-ext', "WixToolset.UI.wixext/$script:WindowsWixVersion", '-d', "PayloadDirectory=$Staging", '-d', "MsiVersion=$(Get-WindowsMsiVersion $Version)", '-d', "DisplayVersion=$Version", '-d', "AppIcon=$(Join-Path $script:WindowsPackagingRoot '../runner/resources/app_icon.ico')", '-pdbtype', 'none', '-o', $Destination)
}

function New-WindowsBundle([string]$Wix, [string]$Msi, [string]$Destination, [string]$Version) {
  Get-WindowsMsiVersion $Version | Out-Null
  Invoke-WixCommand $Wix @('build', (Join-Path $script:WindowsPackagingRoot 'Bundle.wxs'), '-arch', 'x64', '-ext', "WixToolset.BootstrapperApplications.wixext/$script:WindowsWixVersion", '-ext', "WixToolset.Util.wixext/$script:WindowsWixVersion", '-d', "MsiPackage=$Msi", '-d', "BundleVersion=$($Version.Replace('+', '.'))", '-d', "AppIcon=$(Join-Path $script:WindowsPackagingRoot '../runner/resources/app_icon.ico')", '-pdbtype', 'none', '-o', $Destination)
}

function Complete-WindowsBundleSigning([string]$Wix, [string]$Bundle, [string]$Destination, [string]$WorkingDirectory, [scriptblock]$SignFile) {
  $engine = Join-Path $WorkingDirectory 'bundle-engine.exe'
  Invoke-WixCommand $Wix @('burn', 'detach', $Bundle, '-engine', $engine)
  & $SignFile $engine | Out-Host
  Invoke-WixCommand $Wix @('burn', 'reattach', $Bundle, '-engine', $engine, '-o', $Destination)
  & $SignFile $Destination | Out-Host
}
