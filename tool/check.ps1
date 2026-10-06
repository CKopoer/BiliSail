param([switch]$SkipPub, [switch]$EnforceLockfile)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Invoke-Check([string]$Executable, [string[]]$Parameters) {
  & $Executable @Parameters
  if ($LASTEXITCODE -ne 0) {
    throw "$Executable $($Parameters -join ' ') failed: $LASTEXITCODE"
  }
}

Push-Location $repoRoot
try {
  # A cold Windows SDK can emit pub bootstrap output before the machine JSON.
  Invoke-Check flutter @('--version')
  $sdk = (& flutter --version --machine | ConvertFrom-Json)
  if ($sdk.frameworkVersion -ne '3.47.6') { throw 'This checkout is verified with Flutter 3.47.6.' }
  $pubArgs = @('pub', 'get')
  if ($EnforceLockfile) { $pubArgs += '--enforce-lockfile' }
  $packages = @('bili_api', 'bili_player', 'bili_danmaku')
  if (!$SkipPub) {
    Invoke-Check flutter $pubArgs
    # Root analysis also scans local packages; their dev dependencies need their own configs.
    foreach ($package in $packages) {
      Push-Location (Join-Path $repoRoot "packages/$package")
      try {
        $runner = if ($package -eq 'bili_api') { 'dart' } else { 'flutter' }
        Invoke-Check $runner $pubArgs
      } finally { Pop-Location }
    }
  }
  Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test')
  Invoke-Check flutter @('analyze')
  Invoke-Check flutter @('test')
  foreach ($package in $packages) {
    Push-Location (Join-Path $repoRoot "packages/$package")
    try {
      $runner = if ($package -eq 'bili_api') { 'dart' } else { 'flutter' }
      Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
      Invoke-Check $runner @('analyze')
      Invoke-Check $runner @('test')
    } finally { Pop-Location }
  }
} finally { Pop-Location }
