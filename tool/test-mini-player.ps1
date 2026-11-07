param([string]$DeviceId, [switch]$SkipMuxBuild)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')

function Invoke-MiniValidation([string]$Executable, [string[]]$Parameters) {
  & $Executable @Parameters
  if ($LASTEXITCODE -ne 0) { throw "$Executable failed: $LASTEXITCODE" }
}

Push-Location $repoRoot
try {
  if (!$DeviceId) {
    if (!$SkipMuxBuild) { & (Join-Path $PSScriptRoot 'build-download-mux.ps1') -Target windows-x64 }
    $previousMedia = $env:BILI_TEST_MEDIA_DIR
    try {
      $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
      Invoke-MiniValidation flutter @('test', 'integration_test/mini_player_test.dart', '-d', 'windows')
    } finally { $env:BILI_TEST_MEDIA_DIR = $previousMedia }
    return
  }
  Invoke-MiniValidation adb @('-s', $DeviceId, 'get-state')
  # A normal AOT APK must exist before a fixture can replace the test app.
  & (Join-Path $PSScriptRoot 'build-android-development.ps1') -Mode Release -SkipMuxBuild:$SkipMuxBuild
  $restorePackage = Join-Path $repoRoot 'build/development/android-arm64/BiliSail-test-arm64-release.apk'
  $version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\S+)\s*$').Matches.Groups[1].Value
  $powerState = (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  $watcher = $null
  try {
    Invoke-MiniValidation adb @('-s', $DeviceId, 'shell', 'svc', 'power', 'stayon', 'usb')
    Invoke-MiniValidation adb @('-s', $DeviceId, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    Invoke-MiniValidation flutter @('build', 'apk', '--profile', '--target-platform', 'android-arm64', '--split-per-abi',
      '--target', 'integration_test/mini_player_test.dart', $AndroidDevelopmentBuildArgument,
      "--dart-define=BILISAIL_RELEASE_VERSION=$version")
    $fixture = Join-Path $repoRoot 'build/validation/mini-player-android.apk'
    New-Item -ItemType Directory -Force -Path (Split-Path $fixture) | Out-Null
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $fixture
    Install-AndroidDevelopmentApk $DeviceId $fixture 'Profile'
    $mediaDirectory = '/sdcard/Android/data/dev.bilisail.bilisail.test/files/mini-player'
    Invoke-MiniValidation adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $mediaDirectory)
    Invoke-MiniValidation adb @('-s', $DeviceId, 'push', 'test/fixtures/media/video.mp4', "$mediaDirectory/video.mp4")
    Invoke-MiniValidation adb @('-s', $DeviceId, 'push', 'test/fixtures/media/audio.m4a', "$mediaDirectory/audio.m4a")
    $watcher = Start-Job -ArgumentList $DeviceId -ScriptBlock {
      param($targetDevice)
      $expires = [DateTime]::UtcNow.AddSeconds(100)
      while ([DateTime]::UtcNow -lt $expires) {
        $activities = & adb -s $targetDevice shell dumpsys activity activities
        if ($activities -match 'type=standard mode=pinned.*dev\.bilisail\.bilisail\.test|dev\.bilisail\.bilisail\.test.*mode=pinned') {
          Start-Sleep -Seconds 2
          & adb -s $targetDevice shell am start -n 'dev.bilisail.bilisail.test/dev.bilisail.bilisail.MainActivity'
          return
        }
        Start-Sleep -Milliseconds 400
      }
      throw 'The test activity did not enter system PiP.'
    }
    Invoke-MiniValidation flutter @('drive', '--profile', '--no-pub', '--keep-app-running', '-d', $DeviceId,
      '--driver', 'tool/validation/mini_player_driver.dart', '--use-application-binary', $fixture)
    Receive-Job -Job $watcher -Wait -ErrorAction Stop
  } finally {
    if ($watcher) { Stop-Job -Job $watcher -ErrorAction SilentlyContinue; Remove-Job -Job $watcher -Force -ErrorAction SilentlyContinue }
    try {
      Install-AndroidDevelopmentApk $DeviceId $restorePackage 'Release'
      & adb -s $DeviceId shell am force-stop $AndroidDevelopmentPackageId
      & adb -s $DeviceId shell am start -n "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity"
    } finally {
      if ($powerState -eq 'null') { & adb -s $DeviceId shell settings delete global stay_on_while_plugged_in }
      else { & adb -s $DeviceId shell settings put global stay_on_while_plugged_in $powerState }
    }
  }
} finally { Pop-Location }
