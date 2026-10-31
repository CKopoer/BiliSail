$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-media-notification.ps1')
$checks = 0
$names = @('ic_media_notification', 'audio_service_play_arrow', 'audio_service_pause', 'audio_service_stop', 'ic_media_rewind_10', 'ic_media_forward_10')
# Match aapt's actual compiled resource output, including the non-value spec row.
function New-MediaResourceReport([string]$PackageId) {
  return ($names | ForEach-Object {
    "spec resource 0x7f070065 ${PackageId}:drawable/${_}: flags=0x00000000"
    "  resource 0x7f070065 ${PackageId}:drawable/${_}: t=0x03 d=0x0000001b (s=0x0008 r=0x00)"
  }) -join "`n"
}
function Assert-Rejected([string]$Report) {
  $rejected = $false
  try { Assert-AndroidMediaNotificationResources $Report }
  catch {
    if ($_.Exception.Message -notlike 'APK is missing media notification drawable/*') { throw }
    $rejected = $true
  }
  if (!$rejected) { throw 'An APK with missing media resources was accepted.' }
  $script:checks++
}

foreach ($packageId in @('dev.bilisail.bilisail', 'dev.bilisail.bilisail.test')) {
  $report = New-MediaResourceReport $packageId
  Assert-AndroidMediaNotificationResources $report
  $checks++
  Assert-AndroidMediaNotificationResources ($report.Replace("`n", "`r`n"))
  $checks++
  foreach ($name in $names) {
    Assert-Rejected (($report -split "`n" | Where-Object { $_ -notmatch "drawable/${name}:" }) -join "`n")
  }
  # A name in the spec table alone, or a null value, cannot supply an icon.
  Assert-Rejected (($report -split "`n" | Where-Object { $_ -match '^spec ' }) -join "`n")
  Assert-Rejected ($report.Replace('t=0x03', 't=0x00'))
  Assert-Rejected ($report.Replace('resource 0x7f070065', 'resource 0x00000000'))
  Assert-Rejected ($report.Replace('drawable/audio_service_stop:', 'drawable/audio_service_stop_extra:'))
}
Assert-Rejected ''
Write-Output "Android media notification resource checks passed: $checks"
