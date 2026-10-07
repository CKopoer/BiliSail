param(
  [Parameter(Mandatory)][string]$Wix,
  [Parameter(Mandatory)][string]$Msi,
  [Parameter(Mandatory)][string]$Bundle,
  [Parameter(Mandatory)][string]$WorkingDirectory
)

$ErrorActionPreference = 'Stop'
if (!$IsWindows) { throw 'Windows installer package checks require a Windows host.' }
. (Join-Path $PSScriptRoot 'windows-installers.ps1')

# Inspect the compiled packages, not just source XML. Never install the app or
# change machine registration during CI; UI/device acceptance remains separate.
$inspection = Join-Path $WorkingDirectory "package-check-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $inspection | Out-Null
$decompiled = Join-Path $inspection 'installer.wxs'
$baDirectory = Join-Path $inspection 'ba'
Invoke-WixCommand $Wix @('msi', 'decompile', $Msi, '-o', $decompiled)
Invoke-WixCommand $Wix @('burn', 'extract', $Bundle, '-oba', $baDirectory)

[xml]$msiXml = Get-Content -LiteralPath $decompiled -Raw
[xml]$burnXml = Get-Content -LiteralPath (Join-Path $baDirectory 'manifest.xml') -Raw
[xml]$baXml = Get-Content -LiteralPath (Join-Path $baDirectory 'BootstrapperApplicationData.xml') -Raw
[xml]$themeXml = Get-Content -LiteralPath (Join-Path $baDirectory 'thm.xml') -Raw
$checks = 0
function Assert-PackageNode([xml]$Document, [string]$XPath, [string]$Message) {
  if (!$Document.SelectSingleNode($XPath)) { throw $Message }
  $script:checks++
}

Assert-PackageNode $msiXml "//*[local-name()='Property' and @Id='WIXUI_INSTALLDIR' and @Value='INSTALLFOLDER']" 'MSI directory UI is not bound to INSTALLFOLDER.'
Assert-PackageNode $msiXml "//*[local-name()='Property' and @Id='INSTALLFOLDER' and @Secure='yes']" 'MSI directory choice cannot cross elevation.'
Assert-PackageNode $msiXml "//*[local-name()='StandardDirectory' and @Id='ProgramFiles64Folder']/*[local-name()='Directory' and @Id='INSTALLFOLDER' and @Name='BiliSail']" 'MSI default directory changed.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='InstallDirDlg']/*[local-name()='Control' and @Type='PathEdit' and @Property='WIXUI_INSTALLDIR' and @Indirect='yes']" 'MSI directory editor is missing.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='InstallDirDlg']/*[local-name()='Control' and @Id='ChangeFolder']/*[local-name()='Publish' and @Event='SpawnDialog' and @Value='BrowseDlg']" 'MSI folder browser is unreachable.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BrowseDlg']/*[local-name()='Control' and @Id='OK']/*[local-name()='Publish' and @Event='SetTargetPath' and @Value='[_BrowseProperty]']" 'MSI browser does not apply its selected path.'

# Windows Installer uses the last applicable NewDialog event. WiX decompiles
# ControlEvent rows in their execution order, including our navigation override.
$welcomeRoutes = $msiXml.SelectNodes("//*[local-name()='Dialog' and @Id='WelcomeDlg']/*[local-name()='Control' and @Id='Next']/*[local-name()='Publish' and @Event='NewDialog' and @Condition='NOT Installed']")
$backRoutes = $msiXml.SelectNodes("//*[local-name()='Dialog' and @Id='InstallDirDlg']/*[local-name()='Control' and @Id='Back']/*[local-name()='Publish' and @Event='NewDialog']")
if (!$welcomeRoutes.Count -or $welcomeRoutes[-1].Value -ne 'InstallDirDlg' -or !$backRoutes.Count -or $backRoutes[-1].Value -ne 'WelcomeDlg') {
  throw 'MSI wizard navigation does not skip the placeholder licence in both directions.'
}
$checks++
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='InstallDirDlg']/*[local-name()='Control' and @Id='Next']/*[local-name()='Publish' and @Event='NewDialog' and @Value='VerifyReadyDlg']" 'MSI installation confirmation is unreachable.'
Assert-PackageNode $msiXml "//*[local-name()='Property' and @Id='BILISAIL_PREVIOUS_INSTALLFOLDER']/*[local-name()='RegistrySearch' and @Root='HKLM' and @Key='Software\BiliSail\Installer' and @Name='InstallFolder' and @Bitness='always64']" 'MSI does not read the previous x64 installation directory.'
Assert-PackageNode $msiXml "//*[local-name()='RegistryValue' and @Root='HKLM' and @Key='Software\BiliSail\Installer' and @Name='InstallFolder' and @Value='[INSTALLFOLDER]']" 'MSI does not save the chosen installation directory.'
Assert-PackageNode $msiXml "//*[local-name()='CustomAction' and @Id='SetINSTALLFOLDER' and @Property='INSTALLFOLDER' and @Value='[BILISAIL_PREVIOUS_INSTALLFOLDER]']" 'MSI directory restore action is missing.'
foreach ($sequence in @('InstallUISequence', 'InstallExecuteSequence')) {
  Assert-PackageNode $msiXml "//*[local-name()='$sequence']/*[local-name()='Custom' and @Action='SetINSTALLFOLDER' and @Before='CostFinalize' and @Condition='NOT INSTALLFOLDER AND BILISAIL_PREVIOUS_INSTALLFOLDER']" "MSI restore must precede costing and preserve explicit choices in $sequence."
}
Assert-PackageNode $msiXml "//*[local-name()='Shortcut' and @Target='[INSTALLFOLDER]bilisail.exe' and @WorkingDirectory='INSTALLFOLDER']" 'MSI shortcut no longer follows the selected directory.'
Assert-PackageNode $burnXml "//*[local-name()='Variable' and @Id='InstallFolder' and @Value='[ProgramFiles64Folder]BiliSail' and @Persisted='yes']" 'EXE default/persisted directory variable is missing.'
Assert-PackageNode $burnXml "//*[local-name()='RegistrySearch' and @Variable='InstallFolder' and @Root='HKLM' and @Key='Software\BiliSail\Installer' and @Value='InstallFolder' and @Win64='yes']" 'EXE does not reuse the MSI installation directory.'
Assert-PackageNode $burnXml "//*[local-name()='MsiPackage' and @Id='BiliSailMsi']/*[local-name()='MsiProperty' and @Id='INSTALLFOLDER' and @Value='[InstallFolder]']" 'EXE does not pass its selected directory to MSI.'
Assert-PackageNode $baXml "//*[local-name()='WixStdbaOptions' and not(@SuppressOptionsUI='1') and not(@SuppressOptionsUI='yes')]" 'EXE hides the directory options.'
Assert-PackageNode $themeXml "//*[local-name()='Button' and @Name='OptionsButton']/*[local-name()='ChangePageAction' and @Page='Options']" 'EXE directory options page is unreachable.'
Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='Options']/*[local-name()='Editbox' and @Name='InstallFolder']" 'EXE directory editor is missing.'
Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='Options']/*[local-name()='Button']/*[local-name()='BrowseDirectoryAction' and @VariableName='InstallFolder']" 'EXE browser does not update the MSI directory variable.'

Write-Output "Windows installer package checks passed ($checks cases)."
