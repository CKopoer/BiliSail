param(
  [Parameter(Mandatory)][string]$Wix,
  [Parameter(Mandatory)][string]$WorkingDirectory,
  [ValidateSet('perMachine', 'perUser')][string]$Scope = 'perMachine',
  [switch]$PauseForSettings
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'Installer lifecycle validation requires Windows.' }
if ($Scope -eq 'perMachine') {
  $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'perMachine validation needs an elevated PowerShell. Use perUser only for a separately reported user-scope check.'
  }
}
. (Join-Path $PSScriptRoot 'windows-installers.ps1')
$tag = [guid]::NewGuid().ToString('N')
$run = Join-Path ([IO.Path]::GetFullPath($WorkingDirectory)) "lifecycle-$tag"
$source = Join-Path $run 'source'
$payload = Join-Path $run 'payload'
$installed = Join-Path $run '哔帆 安装验证'
$displayName = "BiliSail 安装验证 $($tag.Substring(0, 8))"
$menuName = "BiliSail Installer Validation $tag"
$installerKey = "Software\BiliSail\InstallerValidation\$tag"
$productCode = '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}'
$msi = Join-Path $run 'validation.msi'
$bundle = Join-Path $run 'validation.exe'
$registryRoot = if ($Scope -eq 'perMachine') { 'HKLM:' } else { 'HKCU:' }
$uninstallRoot = "$registryRoot\Software\Microsoft\Windows\CurrentVersion\Uninstall"
$productKey = Join-Path $uninstallRoot $productCode
$productKeys = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productCode", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$productCode")
New-Item -ItemType Directory -Path $payload -Force | Out-Null
Copy-Item -LiteralPath $script:WindowsPackagingRoot -Destination $source -Recurse
$helper = Build-WindowsInstallerNative (Join-Path $WorkingDirectory 'installer-native')
$artwork = Join-Path $run 'artwork'
New-WindowsInstallerArtwork $artwork

# Clone the production authoring with fresh identities and an inert payload.
# Never register, upgrade, repair, or remove a user's real BiliSail product.
[xml]$packageXml = Get-Content -LiteralPath (Join-Path $source 'Installer.wxs') -Raw
$package = $packageXml.SelectSingleNode("//*[local-name()='Package']")
$package.SetAttribute('Name', $displayName)
$package.SetAttribute('Scope', $Scope)
$package.SetAttribute('ProductCode', $productCode)
$package.SetAttribute('UpgradeCode', [guid]::NewGuid().ToString())
foreach ($node in $packageXml.SelectNodes("//*[local-name()='RegistrySearch' or local-name()='RegistryValue']")) {
  if ($node.Key -eq 'Software\BiliSail\Installer') {
    $node.SetAttribute('Key', $installerKey)
    $node.SetAttribute('Root', $(if ($Scope -eq 'perMachine') { 'HKLM' } else { 'HKCU' }))
  }
}
$packageXml.SelectSingleNode("//*[local-name()='Directory' and @Id='INSTALLFOLDER']").SetAttribute('Name', $menuName)
$packageXml.SelectSingleNode("//*[local-name()='Directory' and @Id='AppMenuFolder']").SetAttribute('Name', $menuName)
$packageXml.SelectSingleNode("//*[local-name()='Component' and @Id='StartMenuShortcut']").SetAttribute('Guid', [guid]::NewGuid().ToString())
if ($Scope -eq 'perUser') {
  $packageXml.SelectSingleNode("//*[local-name()='StandardDirectory' and @Id='ProgramFiles64Folder']").SetAttribute('Id', 'LocalAppDataFolder')
}
$packageXml.Save((Join-Path $source 'Installer.wxs'))
[xml]$bundleXml = Get-Content -LiteralPath (Join-Path $source 'Bundle.wxs') -Raw
$bundleNode = $bundleXml.SelectSingleNode("//*[local-name()='Bundle']")
$bundleNode.SetAttribute('Name', $displayName)
$bundleNode.SetAttribute('UpgradeCode', [guid]::NewGuid().ToString())
$bundleXml.SelectSingleNode("//*[local-name()='Variable' and @Name='InstallFolder']").SetAttribute('Value', $installed)
$search = $bundleXml.SelectSingleNode("//*[local-name()='RegistrySearch']")
$search.SetAttribute('Key', $installerKey)
$search.SetAttribute('Root', $(if ($Scope -eq 'perMachine') { 'HKLM' } else { 'HKCU' }))
$bundleXml.Save((Join-Path $source 'Bundle.wxs'))
foreach ($name in @('bilisail.exe', 'flutter_windows.dll', 'data/fixture.txt')) {
  $path = Join-Path $payload $name
  New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
  [IO.File]::WriteAllText($path, "Inert installer fixture $tag")
}
$icon = Join-Path $script:WindowsPackagingRoot '../runner/resources/app_icon.ico'
Invoke-WixCommand $Wix @('build', (Join-Path $source 'Installer.wxs'), (Join-Path $source 'InstallerUI.wxs'), '-culture', 'zh-CN', '-arch', 'x64', '-ext', "WixToolset.UI.wixext/$script:WindowsWixVersion", '-d', "InstallerUIHelper=$helper", '-d', "InstallerArtwork=$artwork", '-d', "PayloadDirectory=$payload", '-d', 'MsiVersion=1.2.3001', '-d', 'DisplayVersion=validation', '-d', "AppIcon=$icon", '-pdbtype', 'none', '-o', $msi)
Invoke-WixCommand $Wix @('build', (Join-Path $source 'Bundle.wxs'), '-arch', 'x64', '-ext', "WixToolset.BootstrapperApplications.wixext/$script:WindowsWixVersion", '-ext', "WixToolset.Util.wixext/$script:WindowsWixVersion", '-d', "InstallerUIHelper=$helper", '-d', "PackagingDirectory=$source", '-d', "InstallerArtwork=$artwork", '-d', "MsiPackage=$msi", '-d', 'BundleVersion=1.2.3.1', '-d', "AppIcon=$icon", '-pdbtype', 'none', '-o', $bundle)
$ba = Join-Path $run 'ba'
Invoke-WixCommand $Wix @('burn', 'extract', $bundle, '-oba', $ba)
[xml]$manifest = Get-Content -LiteralPath (Join-Path $ba 'manifest.xml') -Raw
$bundleCode = $manifest.SelectSingleNode("//*[local-name()='Registration']").Code
$bundleKey = Join-Path $uninstallRoot $bundleCode
$cacheRoot = if ($Scope -eq 'perMachine') { $env:ProgramData } else { $env:LOCALAPPDATA }
$cachedBundle = Join-Path $cacheRoot "Package Cache/$bundleCode/validation.exe"
$results = [ordered]@{ scope = $Scope; displayName = $displayName; productCode = $productCode; bundleCode = $bundleCode; stages = @() }
$resultFile = Join-Path $run 'result.json'
function Save-Results { $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultFile -Encoding utf8 }
function Quote-Path([string]$Path) {
  if ($Path.Contains('"')) { throw 'Unexpected quote in validation path.' }
  return '"' + $Path + '"'
}
function Invoke-LifecycleProcess([string]$Executable, [string[]]$Arguments) {
  $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WindowStyle Hidden -PassThru
  if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Installer validation timed out.' }
  if ($process.ExitCode -ne 0) { throw "Installer validation failed: $($process.ExitCode). See $run." }
}
function Assert-Installed([string]$Type, [string]$Key) {
  $entry = Get-ItemProperty -LiteralPath $Key
  if ($entry.DisplayName -ne $displayName -or !$entry.UninstallString -or $entry.SystemComponent -eq 1 -or $entry.NoRemove -eq 1) {
    throw "$Type is not registered as a visible, removable application."
  }
  if (!(Test-Path -LiteralPath (Join-Path $installed 'data/fixture.txt'))) { throw "$Type did not install its payload." }
  $entries = @(foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem -LiteralPath $root | Get-ItemProperty | Where-Object { $_.DisplayName -eq $displayName -and $_.SystemComponent -ne 1 }
  })
  if ($entries.Count -ne 1) { throw "$Type created duplicate/missing Apps entries." }
  [IO.File]::WriteAllText((Join-Path $installed 'unowned-user-file.txt'), $tag)
  $results.stages += @{ type = $Type; installed = $true; visibleAppsEntries = $entries.Count; uninstallString = $entry.UninstallString }
  Save-Results
  if ($PauseForSettings) {
    $gate = Join-Path $run "continue-$Type"
    Write-Host "Ready for Windows Settings inspection: $displayName; then create $gate"
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    while (!(Test-Path -LiteralPath $gate)) {
      if ([DateTime]::UtcNow -ge $deadline) { throw 'Windows Settings inspection timed out.' }
      Start-Sleep -Milliseconds 250
    }
  }
  return $entry
}
function Assert-Removed([string]$Type, [string]$Key) {
  if ((Test-Path -LiteralPath $Key) -or (Test-Path -LiteralPath $productKey) -or (Test-Path -LiteralPath (Join-Path $installed 'bilisail.exe'))) {
    throw "$Type left its application registration or owned executable installed."
  }
  if ((Get-Content -LiteralPath (Join-Path $installed 'unowned-user-file.txt') -Raw) -cne $tag) { throw "$Type deleted or changed an unowned file." }
  $menuRoot = [Environment]::GetFolderPath($(if ($Scope -eq 'perMachine') { 'CommonPrograms' } else { 'Programs' }))
  if (Test-Path -LiteralPath (Join-Path $menuRoot "$menuName/BiliSail.lnk")) { throw "$Type left its Start menu shortcut." }
  if (Test-Path -LiteralPath "$registryRoot\$installerKey") { throw "$Type left its installation directory registration." }
  $results.stages += @{ type = $Type; uninstalled = $true; appsEntryRemoved = $true; shortcutRemoved = $true; unownedFilePreserved = $true }
  Save-Results
}
try {
  Invoke-LifecycleProcess msiexec.exe @('/i', (Quote-Path $msi), "INSTALLFOLDER=$(Quote-Path $installed)", '/qn', '/norestart', '/l*v', (Quote-Path (Join-Path $run 'msi-install.log')))
  # Windows Installer may expose a user product through the machine ARP key;
  # its actual installed registration is authoritative, not our expected hive.
  $productKey = @($productKeys | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
  if (!$productKey) { throw 'MSI did not register an Apps entry.' }
  $entry = Assert-Installed 'msi' $productKey
  if ($entry.UninstallString -notmatch ('(?i)^MsiExec\.exe\s+/X' + [regex]::Escape($productCode) + '$')) { throw 'MSI Apps entry does not offer direct uninstall.' }
  Remove-Item -LiteralPath (Join-Path $installed 'data/fixture.txt')
  Invoke-LifecycleProcess msiexec.exe @('/fa', (Quote-Path $msi), '/qn', '/norestart', '/l*v', (Quote-Path (Join-Path $run 'msi-repair.log')))
  if (!(Test-Path -LiteralPath (Join-Path $installed 'data/fixture.txt'))) { throw 'MSI repair did not restore the file.' }
  $results.stages += @{ type = 'msi'; repaired = $true }
  Invoke-LifecycleProcess msiexec.exe @('/x', $productCode, '/qn', '/norestart', '/l*v', (Quote-Path (Join-Path $run 'msi-uninstall.log')))
  Assert-Removed 'msi' $productKey
  Invoke-LifecycleProcess $bundle @('/quiet', '/norestart', '/log', (Quote-Path (Join-Path $run 'exe-install.log')))
  $entry = Assert-Installed 'exe' $bundleKey
  if ($entry.UninstallString -notmatch ([regex]::Escape($cachedBundle) + '"?\s+/uninstall') -or !(Test-Path -LiteralPath $cachedBundle)) { throw 'EXE Apps entry does not point to its cached uninstaller.' }
  $child = Get-ItemProperty -LiteralPath $productKey
  if ($child.SystemComponent -ne 1) { throw 'EXE did not hide its embedded MSI Apps entry.' }
  Remove-Item -LiteralPath (Join-Path $installed 'data/fixture.txt')
  Invoke-LifecycleProcess $cachedBundle @('/repair', '/quiet', '/norestart', '/log', (Quote-Path (Join-Path $run 'exe-repair.log')))
  if (!(Test-Path -LiteralPath (Join-Path $installed 'data/fixture.txt'))) { throw 'EXE repair did not restore the file.' }
  $results.stages += @{ type = 'exe'; repaired = $true; embeddedMsiHidden = $true }
  # Use the exact cached uninstaller that Settings exposes, without the original source EXE.
  Move-Item -LiteralPath $bundle -Destination (Join-Path $run 'original-setup.saved')
  Invoke-LifecycleProcess $cachedBundle @('/uninstall', '/quiet', '/norestart', '/log', (Quote-Path (Join-Path $run 'exe-uninstall.log')))
  Assert-Removed 'exe' $bundleKey
  $results.success = $true
  Save-Results
  Write-Output "Installer lifecycle validation passed ($Scope): $resultFile"
} finally {
  # Only this run's random fixture identities may be removed, including on failure.
  if ((Test-Path -LiteralPath $bundleKey) -and (Test-Path -LiteralPath $cachedBundle)) {
    Invoke-LifecycleProcess $cachedBundle @('/uninstall', '/quiet', '/norestart')
  }
  if (@($productKeys | Where-Object { Test-Path -LiteralPath $_ }).Count) { Invoke-LifecycleProcess msiexec.exe @('/x', $productCode, '/qn', '/norestart') }
}
