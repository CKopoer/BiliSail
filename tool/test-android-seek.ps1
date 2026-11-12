param(
  [Parameter(Mandatory)][string]$DeviceId,
  [switch]$SkipReleaseBuild,
  [ValidateSet('all', 'renderedTexture', 'directTexture')][string]$Output = 'all',
  [ValidateSet('synchronization', 'cache')][string]$Suite = 'synchronization'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
function Invoke-SeekCheck([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Program failed: $LASTEXITCODE" }
}
Push-Location $repoRoot
$restoreRequired = $false
$powerState = $null
$fixtureDirectory = "/sdcard/Android/data/$AndroidDevelopmentPackageId/files/seek-regression-$([Guid]::NewGuid().ToString('N'))"
try {
  Invoke-SeekCheck adb @('-s', $DeviceId, 'get-state')
  $powerState = (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  Write-Output "Original stay_on_while_plugged_in: $powerState"
  Invoke-SeekCheck adb @('-s', $DeviceId, 'shell', 'svc', 'power', 'stayon', 'usb')
  Invoke-SeekCheck adb @('-s', $DeviceId, 'shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
  if (!$SkipReleaseBuild) { & "$PSScriptRoot/build-android-development.ps1" -Mode Release }
  $restoreApk = Join-Path $repoRoot 'build/development/android-arm64/BiliSail-test-arm64-release.apk'
  $restoreIdentity = Confirm-AndroidDevelopmentApk $restoreApk 'Release'
  $restoreCertificate = Confirm-AndroidApkSigning $restoreApk ([pscustomobject]@{ Signing = 'temporary-debug-key' })
  $fixtureBuild = [int]$restoreIdentity.VersionCode % 100
  $fixtureVersion = "$($restoreIdentity.VersionName)+$fixtureBuild"
  New-Item -ItemType Directory -Force -Path 'build/validation' | Out-Null
  # The tiny desktop fixture can fit entirely in Android's demuxer read-ahead.
  # CBR filler keeps the same known video but puts the 9s target beyond 32 MiB,
  # so the delayed-Range assertions actually exercise a new network read.
  $mediaDirectory = Join-Path $repoRoot 'build/validation/seek-fixtures'
  New-Item -ItemType Directory -Force -Path $mediaDirectory | Out-Null
  if ($Suite -eq 'cache') {
    Invoke-SeekCheck ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
      '-i', 'testsrc2=size=160x90:rate=24:duration=720', '-an', '-c:v', 'libx264', '-preset', 'veryfast',
      '-crf', '28', '-pix_fmt', 'yuv420p', '-g', '24', '-movflags', '+faststart', (Join-Path $mediaDirectory 'video.mp4'))
    Invoke-SeekCheck ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
      '-i', 'sine=frequency=440:sample_rate=48000:duration=720', '-vn', '-c:a', 'aac', '-b:a', '64k',
      '-movflags', '+faststart', (Join-Path $mediaDirectory 'audio.m4a'))
  } else {
    Invoke-SeekCheck ffmpeg @('-hide_banner', '-loglevel', 'error', '-y',
      '-i', 'test/fixtures/media/video.mp4', '-an', '-c:v', 'libx264', '-preset', 'ultrafast',
      '-pix_fmt', 'yuv420p', '-b:v', '64M', '-minrate', '64M', '-maxrate', '64M', '-bufsize', '64M',
      '-x264-params', 'nal-hrd=cbr:force-cfr=1', '-movflags', '+faststart', (Join-Path $mediaDirectory 'video.mp4'))
    Copy-Item -LiteralPath 'test/fixtures/media/audio.m4a' -Destination $mediaDirectory
  }
  $entrypoint = if ($Suite -eq 'cache') { 'integration_test/native_seek_cache_test.dart' } else { 'integration_test/android_seek_synchronization_test.dart' }
  Invoke-SeekCheck flutter @('build', 'apk', '--profile', '--target-platform', 'android-arm64', '--split-per-abi',
    '--target', $entrypoint, $AndroidDevelopmentBuildArgument,
    "--build-number=$fixtureBuild", "--dart-define=BILISAIL_RELEASE_VERSION=$fixtureVersion",
    "--dart-define=BILI_TEST_MEDIA_DIR=$fixtureDirectory",
    "--dart-define=BILI_TEST_OUTPUT=$Output")
  $fixtureApk = Join-Path $repoRoot 'build/validation/seek-profile.apk'
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $fixtureApk
  $fixtureIdentity = Confirm-AndroidDevelopmentApk $fixtureApk 'Profile'
  $fixtureCertificate = Confirm-AndroidApkSigning $fixtureApk ([pscustomobject]@{ Signing = 'temporary-debug-key' })
  if ($fixtureIdentity.VersionCode -ne $restoreIdentity.VersionCode -or $fixtureCertificate -cne $restoreCertificate) {
    throw 'Fixture and restore versions/signatures differ.'
  }
  $restoreRequired = $true
  Install-AndroidDevelopmentApk $DeviceId $fixtureApk 'Profile'
  Invoke-SeekCheck adb @('-s', $DeviceId, 'shell', 'mkdir', '-p', $fixtureDirectory)
  foreach ($name in @('video.mp4', 'audio.m4a')) {
    Invoke-SeekCheck adb @('-s', $DeviceId, 'push', (Join-Path $mediaDirectory $name), "$fixtureDirectory/$name")
  }
  Invoke-SeekCheck flutter @('drive', '--profile', '--no-pub', '--keep-app-running', '-d', $DeviceId,
    '--driver', 'tool/validation/seek_synchronization_driver.dart', '--use-application-binary', $fixtureApk)
} finally {
  try {
    if ($restoreRequired) {
      & adb -s $DeviceId shell rm -f "$fixtureDirectory/video.mp4" "$fixtureDirectory/audio.m4a"
      & adb -s $DeviceId shell rmdir $fixtureDirectory
      Install-AndroidDevelopmentApk $DeviceId $restoreApk 'Release'
      Invoke-SeekCheck adb @('-s', $DeviceId, 'shell', 'am', 'force-stop', $AndroidDevelopmentPackageId)
      Invoke-SeekCheck adb @('-s', $DeviceId, 'shell', 'am', 'start', '-n', "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity")
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
