param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
$revision = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.flutter-version') -Raw).Trim()
if ($revision -cnotmatch '^[a-f0-9]{40}$') { throw 'Expected a full Flutter main Git revision.' }

$root = [IO.Path]::GetFullPath($Destination)
if (!(Test-Path -LiteralPath $root) -or !(Get-ChildItem -LiteralPath $root -Force | Select-Object -First 1)) {
  # Development versions are derived from Git tags and history.
  & git clone --config core.longpaths=true --filter=blob:none --no-checkout --branch main https://github.com/flutter/flutter.git $root
  if ($LASTEXITCODE -ne 0) { throw 'Could not clone Flutter main.' }
  & git -C $root checkout -B main $revision
  if ($LASTEXITCODE -ne 0) { throw "Could not check out Flutter $revision." }
}
$head = & git -C $root rev-parse HEAD
$channel = & git -C $root branch --show-current
if ($head -cne $revision -or $channel -cne 'main') {
  throw "Expected Flutter main at $revision in $root. Choose a new SDK directory to install this revision."
}

$env:FLUTTER_ROOT = $root
$env:PATH = (Join-Path $root 'bin') + [IO.Path]::PathSeparator + $env:PATH
$flutter = if ($IsWindows) { 'bin/flutter.bat' } else { 'bin/flutter' }
& (Join-Path $root $flutter) --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter main bootstrap failed.' }
if ($IsWindows) {
  . (Join-Path $PSScriptRoot 'windows-architecture.ps1')
  $hostArch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  if ((Get-WindowsBinaryArchitecture (Join-Path $root 'bin/cache/dart-sdk/bin/dart.exe')) -cne $hostArch) {
    throw "Flutter must use native $hostArch Dart on this Windows host."
  }
}
