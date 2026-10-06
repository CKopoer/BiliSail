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
  $sdk = (& flutter --version --machine | ConvertFrom-Json)
  if ($sdk.frameworkVersion -ne '3.47.6') { throw 'This checkout is verified with Flutter 3.47.6.' }
  $pubArgs = @('pub', 'get')
  if ($EnforceLockfile) { $pubArgs += '--enforce-lockfile' }
  if (!$SkipPub) { Invoke-Check flutter $pubArgs }
  Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test')
  Invoke-Check flutter @('analyze')
  Invoke-Check flutter @('test')
  foreach ($package in @('bili_api', 'bili_player', 'bili_danmaku')) {
    Push-Location (Join-Path $repoRoot "packages/$package")
    try {
      $runner = if ($package -eq 'bili_api') { 'dart' } else { 'flutter' }
      if (!$SkipPub) { Invoke-Check $runner $pubArgs }
      Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
      Invoke-Check $runner @('analyze')
      Invoke-Check $runner @('test')
    } finally { Pop-Location }
  }
} finally { Pop-Location }
