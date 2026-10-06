$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  if (![System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)) {
    throw 'This native preview probe currently validates Windows only.'
  }
  $probeReport = 'build/validation/video-preview-idle.json'
  if (Test-Path -LiteralPath $probeReport) { Remove-Item -LiteralPath $probeReport }
  & flutter run -d windows --no-pub -t tool/validation/video_preview_idle_probe.dart
  if ($LASTEXITCODE -ne 0) { throw 'Native preview probe failed to run.' }
  # Flutter run can return success when the app deliberately exits with failure.
  # Require the result from the actual production-binding test as well.
  if (!(Test-Path -LiteralPath $probeReport)) { throw 'Native preview probe returned no report.' }
  $probeResults = Get-Content -LiteralPath $probeReport -Raw | ConvertFrom-Json
  if ($probeResults.Count -ne 2 -or
      @($probeResults | Where-Object { !$_.completed -or !$_.opened -or !$_.decoded -or !$_.outputAtOpen }).Count -gt 0) {
    throw 'Idle native preview did not reach its first output frame without external frames.'
  }
  $probeResults | Format-Table
} finally { Pop-Location }
