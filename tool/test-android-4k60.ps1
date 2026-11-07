param(
  [Parameter(Mandatory)][string]$DeviceId,
  [Parameter(Mandatory)][string]$ConfigPath,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9_-]+$')][string]$Label,
  [switch]$UsePreparedApks,
  [switch]$DebugProbe,
  [switch]$SkipMuxBuild
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
. (Join-Path $PSScriptRoot 'android-signing.ps1')
$folder = Join-Path $repoRoot "build/validation/android-4k60/$Label"
if (Test-Path -LiteralPath $folder) { throw 'Use a fresh label' }
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$normal = Join-Path $repoRoot 'build/validation/android-4k60/ordinary-release.apk'
$profile = Join-Path $repoRoot 'build/validation/android-4k60/probe-profile.apk'
if ($DebugProbe) { $profile = Join-Path $repoRoot 'build/validation/android-4k60/probe-debug.apk' }
$probeMode = if ($DebugProbe) { 'Debug' } else { 'Profile' }
$server = $null; $logcat = $null; $installed = $false; $reversed = $false; $power = $null
$previousSdk = $env:ANDROID_HOME
Push-Location $repoRoot
try {
  if (!$env:ANDROID_HOME -and !$env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = Split-Path (Split-Path (Get-Command adb).Source)
  }
  if (!$UsePreparedApks) {
    if ($DebugProbe) { throw 'Debug validation requires an explicitly prepared APK' }
    & (Join-Path $PSScriptRoot 'build-android-development.ps1') -Mode Release -SkipMuxBuild:$SkipMuxBuild
    Copy-Item -LiteralPath 'build/development/android-arm64/BiliSail-test-arm64-release.apk' -Destination $normal
    & flutter build apk --profile --target-platform android-arm64 --split-per-abi --target tool/validation/android_4k60_probe.dart $AndroidDevelopmentBuildArgument
    if ($LASTEXITCODE -ne 0) { throw 'Profile build failed' }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' -Destination $profile
  }
  $restore = Join-Path $folder 'ordinary-release.apk'
  Copy-Item -LiteralPath $normal -Destination $restore
  $runProfile = Join-Path $folder 'probe-profile.apk'
  Copy-Item -LiteralPath $profile -Destination $runProfile
  $profile = $runProfile
  Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $folder 'config.json')
  $normalIdentity = Confirm-AndroidDevelopmentApk $restore 'Release'
  $profileIdentity = Confirm-AndroidDevelopmentApk $profile $probeMode
  if ($normalIdentity.VersionCode -ne $profileIdentity.VersionCode) { throw 'APK versions differ' }
  $cert = (Get-Content -LiteralPath 'build/development/android-arm64/signing-certificate.sha256' -Raw).Trim()
  foreach ($apk in @($restore,$profile)) {
    if ((Confirm-AndroidApkSigning $apk ([pscustomobject]@{Signing='temporary-debug-key'})) -cne $cert) { throw 'APK signatures differ' }
  }
  $installedPath = (& adb -s $DeviceId shell pm path $AndroidDevelopmentPackageId) |
    Where-Object { $_ -match '^package:.*base\.apk$' } | Select-Object -First 1
  if ($installedPath) {
    $before = Join-Path $folder 'installed-before.apk'
    & adb -s $DeviceId pull $installedPath.Substring(8).Trim() $before
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect installed signing identity' }
    if ((Confirm-AndroidApkSigning $before ([pscustomobject]@{Signing='temporary-debug-key'})) -cne $cert) { throw 'Installed APK signature differs; preserve data' }
  }
  [pscustomobject]@{
    normal=$normalIdentity; profile=$profileIdentity; certificate=$cert
    ordinarySha256=(Get-FileHash -LiteralPath $restore).Hash
    profileSha256=(Get-FileHash -LiteralPath $profile).Hash
    gitHead=(& git rev-parse HEAD)
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'identity.json')
  $power = (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim()
  @{StayOnWhilePluggedIn=$power;Device=$DeviceId} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'device-state-before.json')
  & adb -s $DeviceId shell svc power stayon usb
  & adb -s $DeviceId shell input keyevent KEYCODE_WAKEUP
  $policy = (& adb -s $DeviceId shell dumpsys window policy) -join "`n"
  if ($policy -match '(?m)^\s+showing=true\s*$') { throw 'Unlock the device before profiling' }
  $python = (Get-Command python).Source
  $collector = Join-Path $PSScriptRoot 'validation/android_4k60_collector.py'
  $config = Join-Path $folder 'config.json'
  $server = Start-Process -FilePath $python -ArgumentList @('"'+$collector+'"','--device',$DeviceId,'--output','"'+$folder+'"','--config','"'+$config+'"') -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $folder 'collector.log') -RedirectStandardError (Join-Path $folder 'collector.stderr.log')
  $wait = [Diagnostics.Stopwatch]::StartNew()
  while (!(Test-Path -LiteralPath (Join-Path $folder 'server.json'))) {
    if ($server.HasExited -or $wait.Elapsed.TotalSeconds -gt 10) { throw 'Collector failed to start' }
    Start-Sleep -Milliseconds 100
  }
  & adb -s $DeviceId reverse --no-rebind tcp:18965 tcp:18965
  if ($LASTEXITCODE -ne 0) { throw 'Loopback forwarding failed' }
  $reversed = $true
  Install-AndroidDevelopmentApk $DeviceId $profile $probeMode
  $installed = $true
  & adb -s $DeviceId shell am force-stop $AndroidDevelopmentPackageId
  & adb -s $DeviceId shell am start -n "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity" --ez trace-systrace true --ez enable-dart-profiling true
  if ($LASTEXITCODE -ne 0) { throw 'Probe launch failed' }
  $pidWait = [Diagnostics.Stopwatch]::StartNew()
  do {
    $probeId = ((& adb -s $DeviceId shell pidof $AndroidDevelopmentPackageId) -join '').Trim()
    if ($probeId -match '^\d+$') { break }
    Start-Sleep -Milliseconds 100
  } while ($pidWait.Elapsed.TotalSeconds -lt 15)
  if ($probeId -notmatch '^\d+$') { throw 'Probe PID unavailable' }
  $logcat = Start-Process -FilePath (Get-Command adb).Source -ArgumentList @('-s',$DeviceId,'logcat',"--pid=$probeId",'-T','1','-v','threadtime') -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $folder 'device-logcat.log') -RedirectStandardError (Join-Path $folder 'logcat.stderr.log')
  $scenarios = @(Get-Content -LiteralPath $config -Raw | ConvertFrom-Json)
  $timeoutSeconds = 100 + ($scenarios | ForEach-Object { $_.seconds + 25 } | Measure-Object -Sum).Sum
  $runWatch = [Diagnostics.Stopwatch]::StartNew()
  $completed = $false
  while ($runWatch.Elapsed.TotalSeconds -lt $timeoutSeconds) {
    if ($server.HasExited) { throw 'Collector stopped unexpectedly' }
    $currentProbe = ((& adb -s $DeviceId shell pidof $AndroidDevelopmentPackageId) -join '').Trim()
    if ($currentProbe -cne $probeId) { throw 'Probe process exited or restarted before completion' }
    $events = Join-Path $folder 'events.jsonl'
    if (Test-Path -LiteralPath $events) {
      $last = Get-Content -LiteralPath $events -Tail 1 | ConvertFrom-Json
      if ($last.type -eq 'failed') { throw "Probe failed: $($last.reason)" }
      if ($last.type -eq 'complete') { $completed = $true; break }
    }
    Start-Sleep -Milliseconds 500
  }
  if (!$completed) { throw "Probe exceeded deadline after $($runWatch.Elapsed.TotalSeconds)s (budget $timeoutSeconds, last event $($last.type))" }
  Write-Output "Completed Android 4K60 run: $Label"
} finally {
  try {
    if ($installed) {
      Install-AndroidDevelopmentApk $DeviceId $restore 'Release'
      & adb -s $DeviceId shell am force-stop $AndroidDevelopmentPackageId
      & adb -s $DeviceId shell am start -n "$AndroidDevelopmentPackageId/dev.bilisail.bilisail.MainActivity"
      $afterPath = (& adb -s $DeviceId shell pm path $AndroidDevelopmentPackageId | Select-Object -First 1).Substring(8).Trim()
      $after = Join-Path $folder 'installed-restored.apk'
      & adb -s $DeviceId pull $afterPath $after
      if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $after).Hash -cne (Get-FileHash -LiteralPath $restore).Hash) { throw 'Restored APK hash mismatch' }
      (Get-FileHash -LiteralPath $after).Hash | Set-Content -LiteralPath (Join-Path $folder 'restored.sha256')
    }
  } finally {
    if ($reversed) { & adb -s $DeviceId reverse --remove tcp:18965 }
    $forwardFile = Join-Path $folder 'vm-forward.json'
    if (Test-Path -LiteralPath $forwardFile) {
      $forward = Get-Content -LiteralPath $forwardFile -Raw | ConvertFrom-Json
      & adb -s $DeviceId forward --remove "tcp:$($forward.port)"
    }
    if ($null -ne $power -and (& adb -s $DeviceId shell settings get global stay_on_while_plugged_in).Trim() -eq '2') {
      if ($power -eq 'null') { & adb -s $DeviceId shell settings delete global stay_on_while_plugged_in }
      else { & adb -s $DeviceId shell settings put global stay_on_while_plugged_in $power }
    }
    foreach ($process in @($logcat,$server)) { if ($process -and !$process.HasExited) { Stop-Process -Id $process.Id } }
    $env:ANDROID_HOME = $previousSdk
    Pop-Location
  }
}
