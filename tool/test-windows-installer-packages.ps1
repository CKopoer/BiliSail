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
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailInstallDirDlg']/*[local-name()='Control' and @Type='PathEdit' and @Property='WIXUI_INSTALLDIR' and @Indirect='yes']" 'MSI directory editor is missing.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailInstallDirDlg']/*[local-name()='Control' and @Id='ChangeFolder']/*[local-name()='Publish' and @Event='DoAction' and @Value='BiliSailChooseInstallFolder']" 'MSI modern folder picker is unreachable.'
Assert-PackageNode $msiXml "//*[local-name()='CustomAction' and @Id='BiliSailChooseInstallFolder' and @BinaryRef='BsInstallerUI' and @DllEntry='ChooseInstallFolder']" 'MSI modern folder picker is not embedded.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailInstallDirDlg']/*[local-name()='Control' and @Id='ChangeFolder']/*[local-name()='Publish' and @Event='SetTargetPath' and @Value='INSTALLFOLDER' and contains(@Condition, 'BILISAIL_FOLDER_PICKED')]" 'MSI does not apply folder selections only after confirmation.'
if ($msiXml.SelectSingleNode("//*[local-name()='Dialog' and @Id='BrowseDlg']")) { throw 'MSI still embeds the legacy folder browser.' }
$checks++

# The first page now combines welcome and directory selection; confirmation
# must remain reachable in both directions without a placeholder license page.
Assert-PackageNode $msiXml "//*[local-name()='InstallUISequence']/*[local-name()='Show' and @Dialog='BiliSailInstallDirDlg']" 'MSI does not start with directory selection.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailInstallDirDlg']/*[local-name()='Control' and @Id='Next']/*[local-name()='Publish' and @Event='NewDialog' and @Value='BiliSailVerifyReadyDlg']" 'MSI installation confirmation is unreachable.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailVerifyReadyDlg']/*[local-name()='Control' and @Id='Back']/*[local-name()='Publish' and @Event='NewDialog' and @Value='BiliSailInstallDirDlg' and @Condition='NOT Installed']" 'MSI confirmation cannot return to directory selection.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailVerifyReadyDlg']/*[local-name()='Control' and @Id='Folder' and @Text='[INSTALLFOLDER]']" 'MSI confirmation does not show its actual destination.'
Assert-PackageNode $msiXml "//*[local-name()='Package' and @Language='1033']" 'MSI product language changed and could break the existing upgrade chain.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailInstallDirDlg' and @Title='BiliSail 哔帆 · 安装']" 'MSI is not localized in Simplified Chinese.'
Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailProgressDlg']/*[local-name()='Control' and @Id='ProgressBar']/*[local-name()='Subscribe' and @Event='SetProgress']" 'MSI progress is not connected to the installer engine.'
foreach ($mode in @('Repair', 'Remove')) {
  Assert-PackageNode $msiXml "//*[local-name()='Dialog' and @Id='BiliSailMaintenanceTypeDlg']/*[local-name()='Control' and @Id='${mode}Button']/*[local-name()='Publish' and @Event='NewDialog' and @Value='BiliSailVerifyReadyDlg']" "MSI $mode confirmation is unreachable."
}
foreach ($exit in @('success', 'error', 'cancel')) {
  Assert-PackageNode $msiXml "//*[local-name()='InstallUISequence']/*[local-name()='Show' and @OnExit='$exit' and starts-with(@Dialog, 'BiliSail')]" "MSI $exit exit page is missing."
}
# MSI paints bitmap controls over native buttons/edits even if they appear
# behind text. Check the compiled rectangles to prevent an invisible installer.
foreach ($dialog in $msiXml.SelectNodes("//*[local-name()='Dialog' and starts-with(@Id, 'BiliSail')]")) {
  foreach ($bitmap in $dialog.SelectNodes("*[local-name()='Control' and @Type='Bitmap']")) {
    foreach ($control in $dialog.SelectNodes("*[local-name()='Control' and (@Type='PushButton' or @Type='PathEdit' or @Type='ProgressBar')]")) {
      if ([int]$bitmap.X -lt ([int]$control.X + [int]$control.Width) -and
          ([int]$bitmap.X + [int]$bitmap.Width) -gt [int]$control.X -and
          [int]$bitmap.Y -lt ([int]$control.Y + [int]$control.Height) -and
          ([int]$bitmap.Y + [int]$bitmap.Height) -gt [int]$control.Y) {
        throw "MSI artwork overlaps $($dialog.Id)/$($control.Id)."
      }
    }
  }
  $checks++
}
foreach ($source in @('InstallerUI.wxs', 'BundleTheme.xml', 'Bundle.zh-CN.wxl', 'LICENSE.TXT')) {
  Assert-PackageNode $msiXml "//*[local-name()='Directory' and @Name='installer-ui']//*[local-name()='File' and @Name='$source']" "MSI does not ship the adapted UI source/license: $source."
}
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
Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='Options']/*[local-name()='Button' and @Name='BiliSailBrowseButton']" 'EXE modern folder picker is unreachable.'
Assert-PackageNode $baXml "//*[local-name()='WixBalBAFunctions' and @FilePath='BiliSailInstallerUI.dll']" 'EXE modern folder picker helper is not registered.'
if (!(Test-Path -LiteralPath (Join-Path $baDirectory 'BiliSailInstallerUI.dll'))) { throw 'EXE does not embed its folder picker helper.' }
$checks++
if ($themeXml.SelectSingleNode("//*[local-name()='BrowseDirectoryAction']")) { throw 'EXE still uses the legacy folder browser.' }
$checks++
Assert-PackageNode $burnXml "//*[local-name()='Registration']/*[local-name()='Arp' and @DisplayName='BiliSail' and not(@DisableRemove='yes') and not(@DisableRemove='1')]" 'EXE has no removable Windows Apps registration.'
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $null
try {
  $database = $installer.OpenDatabase($Msi, 0)
  foreach ($action in @('RegisterProduct', 'RemoveFiles')) {
    $view = $database.OpenView(('SELECT `Action` FROM `InstallExecuteSequence` WHERE `Action` = ''{0}''' -f $action))
    $record = $null
    try {
      $view.Execute()
      $record = $view.Fetch()
      if (!$record) { throw "MSI is missing the $action standard action." }
      $checks++
    } finally {
      if ($record) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) | Out-Null }
      $view.Close()
      [Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) | Out-Null
    }
  }
} finally {
  if ($database) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) | Out-Null }
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) | Out-Null
}
foreach ($property in @('ARPNOREMOVE', 'ARPSYSTEMCOMPONENT')) {
  if ($msiXml.SelectSingleNode("//*[local-name()='Property' and @Id='$property' and @Value='1']")) { throw "Standalone MSI hides/disables its Apps entry with $property." }
  $checks++
}
Assert-PackageNode $burnXml "//*[local-name()='MsiPackage' and @Id='BiliSailMsi' and @Permanent='no']/*[local-name()='MsiProperty' and @Id='ARPSYSTEMCOMPONENT' and @Value='1']" 'EXE must hide its child MSI while keeping it removable.'
Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='Install']/*[local-name()='Label' and text()='[InstallFolder]']" 'EXE does not show its actual destination before installation.'
Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='Options']/*[local-name()='Button' and @Name='OptionsCancelButton']/*[local-name()='ChangePageAction' and @Page='Install' and @Cancel='yes']" 'EXE cannot discard directory edits.'
foreach ($page in @('Loading', 'Install', 'Options', 'Progress', 'Modify', 'Success', 'Failure', 'Help')) {
  Assert-PackageNode $themeXml "//*[local-name()='Page' and @Name='$page']" "EXE $page page is missing."
}
$duplicates = @($themeXml.SelectNodes('//*[@Name]') | Group-Object Name | Where-Object Count -gt 1)
if ($duplicates.Count) { throw "EXE theme has duplicate control/page names: $($duplicates.Name -join ', ')." }
$checks++
[xml]$localizationXml = Get-Content -LiteralPath (Join-Path $baDirectory 'thm.wxl') -Raw
Assert-PackageNode $localizationXml "/*[local-name()='WixLocalization' and @Language='2052']" 'EXE is not localized in Simplified Chinese.'
Assert-PackageNode $localizationXml "//*[local-name()='String' and @Id='ConfirmCancelMessage' and string-length(@Value) > 0]" 'EXE cancellation confirmation is missing.'
Assert-PackageNode $themeXml "//*[local-name()='Hypertext' and @Name='FailureLogFileLink']" 'EXE failure log link is missing.'

Write-Output "Windows installer package checks passed ($checks cases)."
