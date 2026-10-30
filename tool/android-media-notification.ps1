# audio_service resolves these icons by name. Dart references are invisible to
# Android's resource shrinker, so validate the compiled APK before distribution.
function Assert-AndroidMediaNotificationResources([string]$Report) {
  foreach ($name in @('ic_media_notification', 'audio_service_play_arrow', 'audio_service_pause', 'audio_service_stop')) {
    $entry = [regex]::Match($Report,
      "(?m)^\s*resource\s+(0x[0-9a-fA-F]+)\s+[^\s:]+:drawable/$([regex]::Escape($name)):\s+t=0x03\b")
    if (!$entry.Success -or [Convert]::ToInt64($entry.Groups[1].Value.Substring(2), 16) -eq 0) {
      throw "APK is missing media notification drawable/$name. Keep dynamically referenced audio_service icons when shrinking resources."
    }
  }
}

function Confirm-AndroidMediaNotificationResources([string]$Package, [string]$Aapt) {
  if (!$Aapt) {
    $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (!$sdkRoot) { throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT to verify APK media notification resources.' }
    $toolName = if ($IsWindows) { 'aapt.exe' } else { 'aapt' }
    $Aapt = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
      Sort-Object { $_.Name -as [version] } -Descending |
      ForEach-Object { Join-Path $_.FullName $toolName } |
      Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (!$Aapt) { throw 'Android SDK aapt is required to verify APK media notification resources.' }
  }
  $report = & $Aapt dump resources $Package
  if ($LASTEXITCODE -ne 0) { throw 'Could not inspect APK media notification resources.' }
  Assert-AndroidMediaNotificationResources ($report -join [Environment]::NewLine)
}
