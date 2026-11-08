. (Join-Path $PSScriptRoot 'windows-architecture.ps1')

function Get-WindowsFlutterRelease([string]$Version) {
  $release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'flutter-windows-sdk.json') -Raw | ConvertFrom-Json
  if ($release.version -cne $Version -or $release.revision -cnotmatch '^[a-f0-9]{40}$' -or
      $release.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $release.archive -cne "stable/windows/flutter_windows_$Version-stable.zip") {
    throw 'Windows Flutter release pin does not match the requested SDK; update the official archive digest with the SDK version.'
  }
  return $release
}

function Confirm-WindowsFlutterSdk([string]$Root, [object]$Release, [string[]]$AllowedDartArchitectures = @('x64')) {
  foreach ($path in @('bin/flutter.bat', 'bin/internal/update_dart_sdk.ps1', 'bin/cache/dart-sdk/bin/dart.exe')) {
    if (!(Test-Path -LiteralPath (Join-Path $Root $path) -PathType Leaf)) { throw "Flutter SDK is missing $path" }
  }
  $revision = & git -C $Root rev-parse HEAD
  if ($LASTEXITCODE -ne 0 -or $revision -cne $Release.revision) { throw 'Flutter SDK revision does not match the pinned release.' }
  $dartArchitecture = Get-WindowsBinaryArchitecture (Join-Path $Root 'bin/cache/dart-sdk/bin/dart.exe')
  if ($dartArchitecture -notin $AllowedDartArchitectures) { throw 'Flutter SDK contains an unexpected Dart architecture.' }
}

function Expand-WindowsFlutterSdk([string]$Archive, [string]$Destination, [object]$Release, [string]$SevenZip) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -cne $Release.sha256) { throw 'Flutter SDK archive SHA-256 mismatch; refusing extraction.' }
  Write-Host "Flutter SDK digest verification finished in $([Math]::Round($watch.Elapsed.TotalSeconds, 1))s"
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  # Use the runner's native executable, rather than MSYS unzip on ARM64.
  $watch.Restart()
  & $SevenZip x $Archive "-o$Destination" -y -bso0 -bsp0 -mmt=4 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'Native Flutter SDK extraction failed.' }
  Write-Host "Native Flutter SDK extraction finished in $([Math]::Round($watch.Elapsed.TotalSeconds, 1))s"
  Confirm-WindowsFlutterSdk (Join-Path $Destination 'flutter') $Release
}
