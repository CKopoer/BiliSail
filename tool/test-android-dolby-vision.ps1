param(
  [Parameter(Mandatory)][string]$DeviceId,
  [switch]$PrepareSample,
  [switch]$SkipMuxBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
. (Join-Path $PSScriptRoot 'dolby-vision-fixtures.ps1')
$output = Join-Path $repoRoot 'build/validation/android-dolby-vision'
$fixtures = Join-Path $repoRoot 'build/validation/dolby-vision'
$normalApk = Join-Path $repoRoot 'build/development/android-arm64/BiliSail-test-arm64-release.apk'
$previousSdk = $env:ANDROID_HOME
$power = $null
$server = $null
$port = $null
$reversed = $false
$fixtureInstalled = $false
Push-Location $repoRoot
try {
  if (!$env:ANDROID_HOME -and !$env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = Split-Path (Split-Path (Get-Command adb -ErrorAction Stop).Source)
  }
  & adb -s $DeviceId get-state
  if ($LASTEXITCODE -ne 0) { throw 'The selected Android device is unavailable.' }
  if ($PrepareSample) { Initialize-DolbyVisionFixture $fixtures }
  foreach ($name in @('video.mp4', 'reference-playing.png')) {
    if (!(Test-Path -LiteralPath (Join-Path $fixtures $name))) {
      throw 'Run with -PrepareSample to prepare the public Dolby sample.'
    }
  }
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  # Always preserve a fresh ordinary Release before installing a fixture entry.
  & (Join-Path $PSScriptRoot 'build-android-development.ps1') -Mode Release -SkipMuxBuild:$SkipMuxBuild
  $restoreApk = Join-Path $output 'ordinary-release.apk'
  Copy-Item -LiteralPath $normalApk -Destination $restoreApk
  $normalIdentity = Confirm-AndroidDevelopmentApk $restoreApk 'Release'
  $expectedCert = (Get-Content -LiteralPath 'build/development/android-arm64/signing-certificate.sha256' -Raw).Trim()
  $installedPath = (& adb -s $DeviceId shell pm path $AndroidDevelopmentPackageId) |
    Where-Object { $_ -match '^package:.*base\.apk$' } | Select-Object -First 1
  if ($installedPath) {
    $installedApk = Join-Path $output 'installed-before.apk'
    & adb -s $DeviceId pull $installedPath.Substring(8).Trim() $installedApk
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the installed test APK.' }
    $installedCert = Confirm-AndroidApkSigning $installedApk ([pscustomobject]@{ Signing = 'temporary-debug-key' })
    if ($installedCert -cne $expectedCert) { throw 'Installed signing identity differs. Preserve the installed application and data.' }
  }
  $serverState = Join-Path $output 'server.json'
  if (Test-Path -LiteralPath $serverState) { Remove-Item -LiteralPath $serverState }
  $python = (Get-Command python -ErrorAction Stop).Source
  $serverScript = Join-Path $PSScriptRoot 'validation/android_dolby_vision_server.py'
  $server = Start-Process -FilePath $python -ArgumentList @('"' + $serverScript + '"', '--device', $DeviceId, '--output', '"' + $output + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $output 'server.log') -RedirectStandardError (Join-Path $output 'server-errors.log')
  $waiting = [Diagnostics.Stopwatch]::StartNew()
  while (!(Test-Path -LiteralPath $serverState)) {
    if ($server.HasExited -or $waiting.Elapsed.TotalSeconds -gt 10) { throw 'Local fixture server failed to start.' }
    Start-Sleep -Milliseconds 100
  }
  $port = (Get-Content -LiteralPath $serverState -Raw | ConvertFrom-Json).port
  & flutter build apk --profile --target-platform android-arm64 --split-per-abi --target integration_test/android_dolby_vision_test.dart "--dart-define=DOVI_FIXTURE_BASE=http://127.0.0.1:$port" $AndroidDevelopmentBuildArgument
  if ($LASTEXITCODE -ne 0) { throw 'Dolby Vision test APK build failed.' }
  $apk = Join-Path $output 'dolby-vision-profile.apk'
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $apk
  $cert = Confirm-AndroidApkSigning $apk ([pscustomobject]@{ Signing = 'temporary-debug-key' })
  if ($cert -cne $expectedCert) { throw 'Test and ordinary APK signatures differ.' }
  $testIdentity = Confirm-AndroidDevelopmentApk $apk 'Profile'
  if ($testIdentity.VersionCode -ne $normalIdentity.VersionCode -or $testIdentity.VersionName -cne $normalIdentity.VersionName) {
    throw 'Test and preserved ordinary APK versions differ. Installation was cancelled.'
  }
  $testIdentity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'test-identity.json')
  (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -LiteralPath "$apk.sha256"
  $power = (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  @{ Device = $DeviceId; StayOnWhilePluggedIn = $power } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'device-state-before.json')
  & adb -s $DeviceId shell svc power stayon usb
  & adb -s $DeviceId shell input keyevent KEYCODE_WAKEUP
  & adb -s $DeviceId reverse --no-rebind "tcp:$port" "tcp:$port"
  if ($LASTEXITCODE -ne 0) { throw 'Could not establish the local fixture tunnel.' }
  $reversed = $true
  Install-AndroidDevelopmentApk $DeviceId $apk 'Profile'
  $fixtureInstalled = $true
  & flutter drive --profile --no-pub --keep-app-running -d $DeviceId --driver tool/validation/dolby_vision_driver.dart --use-application-binary $apk
  $testExit = $LASTEXITCODE
  $testProcess = (& adb -s $DeviceId shell pidof $AndroidDevelopmentPackageId).Trim()
  if ($testProcess -match '^\d+$') {
    & adb -s $DeviceId logcat -d "--pid=$testProcess" -v threadtime > (Join-Path $output 'device-logcat.log')
  }
  if ($testExit -ne 0) { throw "Dolby Vision validation failed (exit $testExit); inspect results.json." }
} finally {
  try {
    if ($fixtureInstalled) {
      Install-AndroidDevelopmentApk $DeviceId $restoreApk 'Release'
      & adb -s $DeviceId shell am force-stop $AndroidDevelopmentPackageId
      & adb -s $DeviceId shell am start -n "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity"
      if ($LASTEXITCODE -ne 0) { throw 'Ordinary Release restoration launch failed.' }
    }
  } finally {
    try {
      if ($reversed) { & adb -s $DeviceId reverse --remove "tcp:$port" }
      if ($null -ne $power) {
        $currentPower = @(& adb -s $DeviceId shell settings get global stay_on_while_plugged_in) -join ''
        if ($currentPower.Trim() -eq '2') {
          if ($power -eq 'null') { & adb -s $DeviceId shell settings delete global stay_on_while_plugged_in }
          else { & adb -s $DeviceId shell settings put global stay_on_while_plugged_in $power }
        }
      }
    } finally {
      if ($null -ne $server -and !$server.HasExited) { Stop-Process -Id $server.Id -ErrorAction SilentlyContinue }
      $env:ANDROID_HOME = $previousSdk
      Pop-Location
    }
  }
}
