param(
  [ValidateSet('Read', 'Play', 'Pause', 'Seek', 'Stop', 'Absent')]
  [string]$Action = 'Read',
  [string]$Title = 'BiliSail system media fixture',
  [long]$PositionMs = 3000
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
$null = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime]
function Wait-WinRT($Operation, [Type]$ResultType) {
  $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  } | Select-Object -First 1
  $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
  if (!$task.Wait(10000)) { throw 'System media request timed out.' }
  return $task.Result
}
$manager = Wait-WinRT ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
$target = $null
foreach ($candidate in $manager.GetSessions()) {
  $properties = Wait-WinRT ($candidate.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
  if ($properties.Title -ceq $Title) { $target = $candidate; break }
}
if ($Action -eq 'Absent') {
  if ($target) { throw 'Fixture system media session still exists.' }
  Write-Output 'absent'
  exit 0
}
if (!$target) { throw 'Fixture system media session not found.' }
switch ($Action) {
  'Play' { $ok = Wait-WinRT ($target.TryPlayAsync()) ([bool]) }
  'Pause' { $ok = Wait-WinRT ($target.TryPauseAsync()) ([bool]) }
  'Seek' { $ok = Wait-WinRT ($target.TryChangePlaybackPositionAsync($PositionMs * 10000)) ([bool]) }
  'Stop' { $ok = Wait-WinRT ($target.TryStopAsync()) ([bool]) }
  'Read' {
    $info = $target.GetPlaybackInfo()
    $timeline = $target.GetTimelineProperties()
    [pscustomobject]@{
      Title = $Title; Status = $info.PlaybackStatus.ToString()
      PositionMs = $timeline.Position.TotalMilliseconds
      DurationMs = $timeline.EndTime.TotalMilliseconds
    } | ConvertTo-Json -Compress
    exit 0
  }
}
if (!$ok) { throw 'System media command was rejected.' }
Write-Output 'accepted'
