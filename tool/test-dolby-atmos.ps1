param([string]$DeviceId, [switch]$PrepareSample, [switch]$SkipMuxBuild)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'dolby-vision-fixtures.ps1')
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
function Assert-Exit([string]$operation) {
  if ($LASTEXITCODE -ne 0) { throw "$operation failed ($LASTEXITCODE)." }
}
Push-Location $root
try {
  $dir = (New-Item -ItemType Directory -Force 'build/validation/atmos').FullName
  $original = 'build/validation/dolby-vision/dolby-profile5-prefix.mp4'
  if ($PrepareSample) { Initialize-DolbyVisionFixture (Split-Path $original) }
  if (!(Test-Path $original)) { throw 'Prepare the pinned Dolby sample with -PrepareSample.' }
  & ffmpeg -v error -y -i $original -t 8 -map 0:a:0 -c copy -f mp4 "$dir/joc.m4a"
  Assert-Exit 'JOC extraction'
  $profile = & ffprobe -v error -select_streams a:0 -show_entries stream=profile -of csv=p=0 "$dir/joc.m4a"
  if ($profile -notmatch 'Dolby Atmos') { throw 'Fixture has no verified Atmos profile.' }
  Copy-Item 'test/fixtures/media/video.mp4' "$dir/video.mp4" -Force
  Copy-Item 'test/fixtures/media/audio.m4a' "$dir/aac.m4a" -Force
  & ffmpeg -v error -y -i "$dir/aac.m4a" -c:a eac3 -b:a 192k -f mp4 "$dir/ddp.m4a"
  Assert-Exit 'Ordinary DD+ extraction'
  & ffmpeg -v error -y -i "$dir/video.mp4" -i "$dir/joc.m4a" -map 0:v -map 1:a -t 8 -c copy "$dir/joc.mkv"
  Assert-Exit 'JOC Matroska remux'
  & ffmpeg -v error -y -i $original -t 6 -map 0:v:0 -map 0:a:0 -c copy -strict unofficial "$dir/p5-joc.mp4"
  Assert-Exit 'Dolby Vision and Atmos remux'
  $target = 'integration_test/dolby_atmos_output_test.dart'
  if (!$DeviceId) {
    & flutter test --no-pub $target -d windows "--dart-define=ATMOS_FIXTURES=$dir"
    Assert-Exit 'Windows Atmos regression'
    & python tool/validation/windows_ddp_carrier.py 'build/windows/x64/runner/Debug/libmpv-2.dll' "$dir/joc.m4a"
    Assert-Exit 'Windows lossless DD+ carrier'
    return
  }

  & "$PSScriptRoot/build-android-development.ps1" -Mode Release -SkipMuxBuild:$SkipMuxBuild
  $normal = "$dir/ordinary-release.apk"
  Copy-Item 'build/development/android-arm64/BiliSail-test-arm64-release.apk' $normal -Force
  $identity = Confirm-AndroidDevelopmentApk $normal 'Release'
  $cert = (Get-Content -Raw 'build/development/android-arm64/signing-certificate.sha256').Trim()
  $installed = (& adb -s $DeviceId shell pm path $AndroidDevelopmentPackageId) | Select-Object -First 1
  if ($installed -match '^package:(.+\.apk)$') {
    & adb -s $DeviceId pull $Matches[1].Trim() "$dir/previous.apk"
    Assert-Exit 'Installed APK inspection'
    if ((Confirm-AndroidApkSigning "$dir/previous.apk" ([pscustomobject]@{ Signing = 'temporary-debug-key' })) -cne $cert) {
      throw 'Installed test package signing certificate differs.'
    }
  }
  $deviceDir = "/sdcard/Android/data/$AndroidDevelopmentPackageId/files/atmos-" + [guid]::NewGuid().ToString('N')
  $fixtureInstalled = $false
  try {
    & adb -s $DeviceId shell mkdir -p $deviceDir
    Assert-Exit 'Device fixture directory'
    $files = 'video.mp4','joc.m4a','joc.mkv','aac.m4a','ddp.m4a','p5-joc.mp4'
    foreach ($name in $files) {
      & adb -s $DeviceId push "$dir/$name" "$deviceDir/$name"
      Assert-Exit 'Device fixture'
    }
    & flutter build apk --profile --target-platform android-arm64 --split-per-abi --target $target "--dart-define=ATMOS_FIXTURES=$deviceDir" $AndroidDevelopmentBuildArgument
    Assert-Exit 'Fixture build'
    $apk = 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk'
    $fixture = Confirm-AndroidDevelopmentApk $apk 'Profile'
    if ($fixture.VersionCode -ne $identity.VersionCode -or $fixture.VersionName -cne $identity.VersionName -or
      (Confirm-AndroidApkSigning $apk ([pscustomobject]@{ Signing = 'temporary-debug-key' })) -cne $cert) {
      throw 'Fixture version or signing certificate differs from the ordinary test Release.'
    }
    Install-AndroidDevelopmentApk $DeviceId $apk 'Profile'
    $fixtureInstalled = $true
    & adb -s $DeviceId shell input keyevent KEYCODE_WAKEUP
    & flutter drive --profile --no-pub --keep-app-running -d $DeviceId --driver tool/validation/seek_synchronization_driver.dart --use-application-binary $apk
    Assert-Exit 'Android Atmos regression'
  } finally {
    try {
      if ($fixtureInstalled) {
        Install-AndroidDevelopmentApk $DeviceId $normal 'Release'
        & adb -s $DeviceId shell am start -n "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity"
        Assert-Exit 'Ordinary test Release launch'
      }
    } finally {
      foreach ($name in $files) {
        & adb -s $DeviceId shell rm -f "$deviceDir/$name"
      }
      & adb -s $DeviceId shell rmdir $deviceDir
    }
  }
} finally { Pop-Location }
