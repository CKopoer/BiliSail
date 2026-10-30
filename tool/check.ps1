param(
  [switch]$SkipPub,
  [switch]$EnforceLockfile,
  [ValidateSet('All', 'Lint', 'RootTests', 'PackageTests')]
  [string]$Stage = 'All',
  [ValidateRange(1, 64)]
  [int]$TotalShards = 1,
  [ValidateRange(0, 63)]
  [int]$ShardIndex = 0,
  [switch]$SkipMuxTests
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($ShardIndex -ge $TotalShards) { throw 'ShardIndex must be less than TotalShards.' }
if (($TotalShards -ne 1 -or $ShardIndex -ne 0) -and $Stage -ne 'RootTests') {
  throw 'Test shards are only supported by the RootTests stage.'
}
if ($SkipMuxTests -and $Stage -ne 'PackageTests') {
  throw 'SkipMuxTests is only supported by the PackageTests stage with a separate native mux job.'
}
$runLint = $Stage -in @('All', 'Lint')
$runRootTests = $Stage -in @('All', 'RootTests')
$runPackageTests = $Stage -in @('All', 'PackageTests')
$packages = @('bili_api', 'bili_player', 'bili_danmaku', 'bili_mux')
$testPackages = @($packages | Where-Object { !$SkipMuxTests -or $_ -ne 'bili_mux' })

function Invoke-Check([string]$Executable, [string[]]$Parameters) {
  & $Executable @Parameters
  if ($LASTEXITCODE -ne 0) {
    throw "$Executable $($Parameters -join ' ') failed: $LASTEXITCODE"
  }
}

Push-Location $repoRoot
try {
  if ($runLint) {
    & (Join-Path $PSScriptRoot 'test-android-version.ps1')
    & (Join-Path $PSScriptRoot 'test-android-signing.ps1')
    & (Join-Path $PSScriptRoot 'test-android-development.ps1')
    & (Join-Path $PSScriptRoot 'test-android-media-notification.ps1')
    & (Join-Path $PSScriptRoot 'test-windows-installers.ps1')
    & (Join-Path $PSScriptRoot 'test-windows-msix-identity.ps1')
    & (Join-Path $PSScriptRoot 'test-macos-release-validation.ps1')
    & (Join-Path $PSScriptRoot 'test-ios-package-validation.ps1')
  }
  # A cold Windows SDK can emit pub bootstrap output before the machine JSON.
  Invoke-Check flutter @('--version')
  $sdk = (& flutter --version --machine | ConvertFrom-Json)
  if ($sdk.frameworkVersion -ne '3.47.6') { throw 'This checkout is verified with Flutter 3.47.6.' }
  $pubArgs = @('pub', 'get')
  if ($EnforceLockfile) { $pubArgs += '--enforce-lockfile' }
  if (!$SkipPub) {
    if ($runLint -or $runRootTests) { Invoke-Check flutter $pubArgs }
    # Root analysis scans every package, including its tests and dev dependencies.
    $pubPackages = if ($runLint) { $packages } elseif ($runPackageTests) { $testPackages } else { @() }
    foreach ($package in $pubPackages) {
      Push-Location (Join-Path $repoRoot "packages/$package")
      try {
        $runner = if ($package -eq 'bili_api') { 'dart' } else { 'flutter' }
        Invoke-Check $runner $pubArgs
      } finally { Pop-Location }
    }
  }
  if ($runLint) {
    Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test')
    Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'linux/plugins/flutter_inappwebview_linux/lib')
    foreach ($package in $packages) {
      Push-Location (Join-Path $repoRoot "packages/$package")
      try {
        Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test')
      } finally { Pop-Location }
    }
    Invoke-Check flutter @('analyze', '--no-pub')
    # Flutter excludes generated platform trees from root analysis; this local
    # Dart-only platform adapter is maintained source rather than a generated file.
    Invoke-Check dart @('analyze', 'linux/plugins/flutter_inappwebview_linux/lib')
  }
  if ($runRootTests) {
    $testArgs = @('test', '--no-pub')
    if ($TotalShards -gt 1) {
      $testArgs += @('--total-shards', "$TotalShards", '--shard-index', "$ShardIndex")
    }
    Invoke-Check flutter $testArgs
  }
  if ($runPackageTests) {
    foreach ($package in $testPackages) {
      Push-Location (Join-Path $repoRoot "packages/$package")
      try {
        $runner = if ($package -eq 'bili_api') { 'dart' } else { 'flutter' }
        $testArgs = @('test')
        if ($runner -eq 'flutter') { $testArgs += '--no-pub' }
        Invoke-Check $runner $testArgs
      } finally { Pop-Location }
    }
  }
} finally { Pop-Location }
