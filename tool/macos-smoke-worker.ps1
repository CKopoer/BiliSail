param(
  [Parameter(Mandatory)][string]$Executable,
  [Parameter(Mandatory)][ValidateSet('startup', 'write', 'read-delete', 'verify-deleted', 'cleanup')][string]$Phase,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$RunId,
  [Parameter(Mandatory)][string]$WorkingDirectory,
  [ValidateRange(1, 60)][int]$TimeoutSeconds = 60,
  [ValidateRange(1, 300)][int]$LaunchTimeoutSeconds = 180,
  [string]$LauncherArgumentsJson = '[]'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'macos-release-validation.ps1')
try {
  Invoke-MacOSReleaseSmokePhaseCore -Executable $Executable -Phase $Phase -RunId $RunId `
    -WorkingDirectory $WorkingDirectory -TimeoutSeconds $TimeoutSeconds -LaunchTimeoutSeconds $LaunchTimeoutSeconds `
    -LauncherArguments @($LauncherArgumentsJson | ConvertFrom-Json)
} catch {
  # The parent reads the sanitized progress/result snapshot, including failures
  # before normal process exit. Never print an arbitrary native exception.
  Write-Host "macOS smoke worker '$Phase' failed."
  exit 1
}
