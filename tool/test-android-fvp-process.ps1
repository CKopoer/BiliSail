param([Parameter(Mandatory)][string]$DeviceId, [switch]$SkipReleaseBuild)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program failed: $LASTEXITCODE" }
}
Push-Location $repoRoot
$fixtureServer = $null
$restoreRequired = $false
$reverseCreated = $false
$powerState = $null
$port = 18764
try {
  $powerState = (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  Invoke-Checked adb @('-s', $DeviceId, 'shell', 'svc', 'power', 'stayon', 'usb')
  Invoke-Checked adb @('-s', $DeviceId, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
  if (!$SkipReleaseBuild) { & "$PSScriptRoot/build-android-development.ps1" -Mode Release -SkipMuxBuild }
  $restoreApk = Join-Path $repoRoot 'build/development/android-arm64/BiliSail-test-arm64-release.apk'
  $restoreIdentity = Confirm-AndroidDevelopmentApk $restoreApk 'Release'
  $fixtureBuild = [int]$restoreIdentity.VersionCode % 100
  $fixtureVersion = "$($restoreIdentity.VersionName)+$fixtureBuild"
  New-Item -ItemType Directory -Force -Path 'build/validation' | Out-Null
  # Debug is deliberate: run-as must only signal this signed test worker.
  Invoke-Checked flutter @('build', 'apk', '--debug', '--target-platform', 'android-arm64', '--split-per-abi',
    '--target', 'integration_test/android_fvp_process_test.dart', $AndroidDevelopmentBuildArgument,
    "--build-number=$fixtureBuild", "--dart-define=BILISAIL_RELEASE_VERSION=$fixtureVersion")
  $fixtureApk = Join-Path $repoRoot 'build/validation/fvp-process-debug.apk'
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk' -Destination $fixtureApk
  $fixtureIdentity = Confirm-AndroidDevelopmentApk $fixtureApk 'Debug'
  if ($fixtureIdentity.VersionCode -ne $restoreIdentity.VersionCode) { throw 'Fixture and restore version codes differ.' }
  $restoreRequired = $true
  Install-AndroidDevelopmentApk $DeviceId $fixtureApk 'Debug'
  if ((& adb -s $DeviceId reverse --list) -match "tcp:$port\s") { throw 'Fixture reverse port is already in use.' }
  Invoke-Checked adb @('-s', $DeviceId, 'reverse', "tcp:$port", "tcp:$port")
  $reverseCreated = $true
  $fixtureServer = Start-Process -FilePath (Get-Command python).Source -ArgumentList @(
    'tool/validation/fvp_process_fixture.py', '--device', $DeviceId, '--port', "$port",
    '--output', 'build/validation/fvp-process-host.json') -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput 'build/validation/fvp-process-server.log' -RedirectStandardError 'build/validation/fvp-process-server-error.log'
  Invoke-Checked flutter @('drive', '--debug', '--no-pub', '--keep-app-running', '-d', $DeviceId,
    '--driver', 'tool/validation/fvp_process_driver.dart', '--use-application-binary', $fixtureApk)
  $observed = Get-Content 'build/validation/fvp-process-host.json' -Raw | ConvertFrom-Json
  if (!$observed.playing.workerPid -or !$observed.reopened.workerPid -or
      $observed.playing.uiPid -ne $observed.reopened.uiPid -or
      $observed.playing.workerPid -eq $observed.reopened.workerPid) { throw 'Process identity validation failed.' }
  & adb -s $DeviceId logcat -b crash -d --pid=$($observed.playing.workerPid) -v threadtime |
    Set-Content 'build/validation/fvp-process-crash.log'
  & adb -s $DeviceId shell dumpsys activity exit-info $AndroidDevelopmentPackageId |
    Set-Content 'build/validation/fvp-process-exit-info.txt'
} finally {
  try {
  if ($fixtureServer -and !$fixtureServer.HasExited) { Stop-Process -Id $fixtureServer.Id }
  if ($reverseCreated) { & adb -s $DeviceId reverse --remove "tcp:$port" }
  if ($restoreRequired) {
    Install-AndroidDevelopmentApk $DeviceId $restoreApk 'Release'
    Invoke-Checked adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $AndroidDevelopmentPackageId)
    Invoke-Checked adb @('-s', $DeviceId, 'shell', 'am', 'start', '-n', "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity")
  }
  } finally {
  if ($null -ne $powerState -and
      (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim() -eq '2') {
    if ($powerState -eq 'null') { & adb -s $DeviceId shell settings delete global stay_on_while_plugged_in }
    else { & adb -s $DeviceId shell settings put global stay_on_while_plugged_in $powerState }
  }
  Pop-Location
  }
}
