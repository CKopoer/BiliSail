param(
  [Parameter(Mandatory)][string]$DeviceId,
  [switch]$SkipMuxBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
$output = Join-Path $repoRoot 'build/validation/android-player-gestures'
$previousSdk = $env:ANDROID_HOME
$previousOutput = $env:STARTUP_OUTPUT
$server = $null
$power = $null
$reversed = $false
$fixtureInstalled = $false
Push-Location $repoRoot
try {
  if (!$env:ANDROID_HOME -and !$env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = Split-Path (Split-Path (Get-Command adb -ErrorAction Stop).Source)
  }
  & adb -s $DeviceId get-state
  if ($LASTEXITCODE -ne 0) { throw 'The selected Android device is unavailable.' }
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  & (Join-Path $PSScriptRoot 'build-android-development.ps1') -Mode Release -SkipMuxBuild:$SkipMuxBuild
  $restoreApk = Join-Path $output 'ordinary-release.apk'
  Copy-Item -LiteralPath 'build/development/android-arm64/BiliSail-test-arm64-release.apk' -Destination $restoreApk
  $normalIdentity = Confirm-AndroidDevelopmentApk $restoreApk 'Release'
  $certificate = (Get-Content -LiteralPath 'build/development/android-arm64/signing-certificate.sha256' -Raw).Trim()
  $serverState = Join-Path $output 'server.json'
  if (Test-Path -LiteralPath $serverState) { Remove-Item -LiteralPath $serverState }
  $python = (Get-Command python -ErrorAction Stop).Source
  $serverScript = Join-Path $PSScriptRoot 'validation/android_dolby_vision_server.py'
  $server = Start-Process -FilePath $python -ArgumentList @('"' + $serverScript + '"', '--device', $DeviceId, '--output', '"' + $output + '"') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $output 'server.log') -RedirectStandardError (Join-Path $output 'server-errors.log')
  $watch = [Diagnostics.Stopwatch]::StartNew()
  while (!(Test-Path -LiteralPath $serverState)) {
    if ($server.HasExited -or $watch.Elapsed.TotalSeconds -gt 10) { throw 'Local media server failed to start.' }
    Start-Sleep -Milliseconds 100
  }
  $port = (Get-Content -LiteralPath $serverState -Raw | ConvertFrom-Json).port
  & flutter build apk --profile --target-platform android-arm64 --split-per-abi --target integration_test/android_fullscreen_orientation_test.dart "--dart-define=GESTURE_FIXTURE_BASE=http://127.0.0.1:$port" $AndroidDevelopmentBuildArgument
  if ($LASTEXITCODE -ne 0) { throw 'Player gesture test APK build failed.' }
  $apk = Join-Path $output 'player-gestures-profile.apk'
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $apk
  $testIdentity = Confirm-AndroidDevelopmentApk $apk 'Profile'
  if ($testIdentity.VersionCode -ne $normalIdentity.VersionCode -or $testIdentity.VersionName -cne $normalIdentity.VersionName) {
    throw 'Fixture and ordinary APK versions differ.'
  }
  $testCertificate = Confirm-AndroidApkSigning $apk ([pscustomobject]@{ Signing = 'temporary-debug-key' })
  if ($certificate -cne $testCertificate) { throw 'Fixture and ordinary APK signatures differ.' }
  $testIdentity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'test-identity.json')
  (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -LiteralPath "$apk.sha256"
  & adb -s $DeviceId get-state
  if ($LASTEXITCODE -ne 0) { throw 'The device disconnected before installation; no fixture APK was installed.' }
  $powerRead = @(& adb -s $DeviceId shell settings get global stay_on_while_plugged_in)
  if ($LASTEXITCODE -ne 0) { throw 'Could not read the original device power setting.' }
  $power = ($powerRead -join '').Trim()
  & adb -s $DeviceId shell svc power stayon usb
  & adb -s $DeviceId shell input keyevent KEYCODE_WAKEUP
  & adb -s $DeviceId reverse --no-rebind "tcp:$port" "tcp:$port"
  if ($LASTEXITCODE -ne 0) { throw 'Could not establish local media tunnel.' }
  $reversed = $true
  Install-AndroidDevelopmentApk $DeviceId $apk 'Profile'
  $fixtureInstalled = $true
  $env:STARTUP_OUTPUT = $output
  & flutter drive --profile --no-pub --keep-app-running -d $DeviceId --driver tool/validation/video_startup_driver.dart --use-application-binary $apk
  if ($LASTEXITCODE -ne 0) { throw 'Android player gesture validation failed.' }
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
      $env:STARTUP_OUTPUT = $previousOutput
      Pop-Location
    }
  }
}
