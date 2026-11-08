param(
  [Parameter(Mandatory)][string]$Destination,
  [Parameter(Mandatory)][string]$ExpectedCacheKey,
  [Parameter(Mandatory)][string]$PubCache
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows -or !$env:GITHUB_ENV -or !$env:GITHUB_PATH -or !$env:RUNNER_TOOL_CACHE -or !$env:RUNNER_TEMP) {
  throw 'This SDK installer requires a Windows GitHub-hosted runner.'
}
. (Join-Path $PSScriptRoot 'windows-flutter.ps1')
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.flutter-version') -Raw).Trim()
$release = Get-WindowsFlutterRelease $version
if ($ExpectedCacheKey -cne "flutter-windows-stable-$version-x64-$($release.revision)") {
  throw 'Flutter Action metadata differs from the pinned Windows release.'
}
$destinationPath = [IO.Path]::GetFullPath($Destination)
$toolCacheRoot = [IO.Path]::GetFullPath($env:RUNNER_TOOL_CACHE).TrimEnd([char[]]'\/')
if (!$destinationPath.StartsWith($toolCacheRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Flutter SDK destination must stay within the runner tool cache.'
}
$flutterRoot = Join-Path $destinationPath 'flutter'
if (!(Test-Path -LiteralPath (Join-Path $flutterRoot 'bin/flutter.bat'))) {
  $archive = Join-Path $env:RUNNER_TEMP "bilisail-flutter-$version-$([guid]::NewGuid().ToString('N')).zip"
  $storage = if ($env:FLUTTER_STORAGE_BASE_URL) { $env:FLUTTER_STORAGE_BASE_URL.TrimEnd('/') } else { 'https://storage.googleapis.com' }
  if (([uri]$storage).Scheme -cne 'https') { throw 'Flutter SDK downloads require HTTPS.' }
  $url = "$storage/flutter_infra_release/releases/$($release.archive)"
  $sevenZipCommand = Get-Command 7z.exe -CommandType Application -ErrorAction SilentlyContinue
  $sevenZip = if ($sevenZipCommand) { $sevenZipCommand.Source } else { Join-Path $env:ProgramFiles '7-Zip/7z.exe' }
  if (!(Test-Path -LiteralPath $sevenZip -PathType Leaf)) { throw 'The Windows runner must supply native 7-Zip.' }
  try {
    $downloadWatch = [Diagnostics.Stopwatch]::StartNew()
    & curl.exe --fail --location --retry 3 --retry-max-time 300 --connect-timeout 30 --max-time 300 --output $archive $url
    if ($LASTEXITCODE -ne 0) { throw 'Pinned Flutter SDK download failed.' }
    Write-Host "Flutter SDK download finished in $([Math]::Round($downloadWatch.Elapsed.TotalSeconds, 1))s"
    Expand-WindowsFlutterSdk $archive $destinationPath $release $sevenZip
  } finally {
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive }
  }
}
$allowedDart = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { @('x64', 'arm64') } else { @('x64') }
Confirm-WindowsFlutterSdk $flutterRoot $release -AllowedDartArchitectures $allowedDart
"FLUTTER_ROOT=$flutterRoot" >> $env:GITHUB_ENV
"PUB_CACHE=$PubCache" >> $env:GITHUB_ENV
@((Join-Path $flutterRoot 'bin'), (Join-Path $flutterRoot 'bin/cache/dart-sdk/bin'), (Join-Path $PubCache 'bin')) >> $env:GITHUB_PATH
Write-Host "Installed verified Flutter $version ($($release.revision)) using native Windows extraction."
