# The official Flutter checkout supports bootstrapping native ARM64 Dart even
# when flutter-action initially selects the Windows x64 distribution.
$ErrorActionPreference = 'Stop'
if (!$IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'Arm64') {
  throw 'Native ARM64 Flutter bootstrap requires Windows ARM64.'
}
. (Join-Path $PSScriptRoot 'windows-architecture.ps1')
$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
$flutterRoot = Split-Path (Split-Path $flutterCommand -Parent) -Parent
$cache = Join-Path $flutterRoot 'bin/cache'
$dart = Join-Path $cache 'dart-sdk/bin/dart.exe'
if (!(Test-Path -LiteralPath $dart) -or (Get-WindowsBinaryArchitecture $dart) -cne 'arm64') {
  $oldArchitecture = $env:PROCESSOR_ARCHITECTURE
  try {
    $env:PROCESSOR_ARCHITECTURE = 'ARM64'
    foreach ($name in @('engine-dart-sdk.stamp', 'flutter_tools.stamp', 'flutter_tools.snapshot')) {
      $file = Join-Path $cache $name
      if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    & (Join-Path $flutterRoot 'bin/internal/update_dart_sdk.ps1')
  } finally { $env:PROCESSOR_ARCHITECTURE = $oldArchitecture }
}
if ((Get-WindowsBinaryArchitecture $dart) -cne 'arm64') {
  throw 'The pinned Flutter engine did not supply native ARM64 Dart; refusing an x64 fallback.'
}
& flutter --version
if ($LASTEXITCODE -ne 0) { throw 'Native ARM64 Flutter bootstrap failed.' }
& $dart --version
if ($LASTEXITCODE -ne 0) { throw 'Native ARM64 Dart could not run.' }
