$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-flutter.ps1')
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "bilisail-windows-sdk-$([guid]::NewGuid().ToString('N'))"))
$previousExitCode = $global:LASTEXITCODE

function Assert-SdkRejected([scriptblock]$Action, [string]$Message) {
  $errorText = $null
  try { & $Action | Out-Null } catch { $errorText = $_.Exception.Message }
  if (!$errorText -or !$errorText.Contains($Message)) { throw "Expected SDK error '$Message', got '$errorText'." }
}

try {
  $version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.flutter-version') -Raw).Trim()
  $pin = Get-WindowsFlutterRelease $version
  if ($pin.version -cne $version) { throw 'The Windows SDK pin drifted from the project SDK.' }
  Assert-SdkRejected { Get-WindowsFlutterRelease '0.0.0' } 'release pin'
  $source = Join-Path $testRoot 'source-sdk'
  foreach ($path in @('bin/flutter.bat', 'bin/internal/update_dart_sdk.ps1', 'bin/cache/dart-sdk/bin/dart.exe')) {
    $file = Join-Path $source $path
    New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($file, 'fixture')
  }
  $pe = [byte[]]::new(134)
  [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($pe, 0)
  [BitConverter]::GetBytes([uint32]128).CopyTo($pe, 60)
  [BitConverter]::GetBytes([uint32]0x4550).CopyTo($pe, 128)
  [BitConverter]::GetBytes([uint16]0x8664).CopyTo($pe, 132)
  [IO.File]::WriteAllBytes((Join-Path $source 'bin/cache/dart-sdk/bin/dart.exe'), $pe)
  $archive = Join-Path $testRoot 'sdk.zip'
  [IO.File]::WriteAllText($archive, 'fixture archive')
  $release = [pscustomobject]@{ revision = '1' * 40; sha256 = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() }
  $script:SdkFixtureRevision = $release.revision
  $script:SdkExtractions = 0
  $script:SdkExtractFailure = $false
  function git { $global:LASTEXITCODE = 0; $script:SdkFixtureRevision }
  function Expand-SdkFixture {
    if ('-mmt=4' -notin $args) { throw 'Native extraction lost its bounded parallelism.' }
    $output = @($args | Where-Object { "$_".StartsWith('-o') })
    if ($output.Count -ne 1) { throw 'SDK extraction destination was lost.' }
    $destinationPath = $output[0].Substring(2)
    Copy-Item -LiteralPath $source -Destination (Join-Path $destinationPath 'flutter') -Recurse
    $script:SdkExtractions++
    $global:LASTEXITCODE = if ($script:SdkExtractFailure) { 2 } else { 0 }
  }
  $destination = Join-Path $testRoot 'destination'
  Expand-WindowsFlutterSdk $archive $destination $release 'Expand-SdkFixture'
  if ($script:SdkExtractions -ne 1) { throw 'The verified archive was not extracted exactly once.' }
  $root = Join-Path $destination 'flutter'
  Confirm-WindowsFlutterSdk $root $release
  [IO.File]::WriteAllText($archive, 'corrupt archive')
  $badDestination = Join-Path $testRoot 'bad-destination'
  Assert-SdkRejected { Expand-WindowsFlutterSdk $archive $badDestination $release 'Expand-SdkFixture' } 'SHA-256 mismatch'
  if ($script:SdkExtractions -ne 1 -or (Test-Path $badDestination)) { throw 'An unverified SDK archive reached extraction.' }
  [IO.File]::WriteAllText($archive, 'fixture archive')
  $script:SdkExtractFailure = $true
  Assert-SdkRejected { Expand-WindowsFlutterSdk $archive (Join-Path $testRoot 'failed-extraction') $release 'Expand-SdkFixture' } 'extraction failed'
  $script:SdkExtractFailure = $false
  $script:SdkFixtureRevision = '2' * 40
  Assert-SdkRejected { Confirm-WindowsFlutterSdk $root $release } 'revision'
  $script:SdkFixtureRevision = $release.revision
  Assert-SdkRejected { Confirm-WindowsFlutterSdk $root $release -AllowedDartArchitectures @('arm64') } 'Dart architecture'
  $dart = Join-Path $root 'bin/cache/dart-sdk/bin/dart.exe'
  [BitConverter]::GetBytes([uint16]0xaa64).CopyTo($pe, 132)
  [IO.File]::WriteAllBytes($dart, $pe)
  Confirm-WindowsFlutterSdk $root $release -AllowedDartArchitectures @('x64', 'arm64')
  Assert-SdkRejected { Confirm-WindowsFlutterSdk $root $release } 'Dart architecture'
  Remove-Item -LiteralPath (Join-Path $root 'bin/internal/update_dart_sdk.ps1')
  Assert-SdkRejected { Confirm-WindowsFlutterSdk $root $release } 'missing'
  Write-Output 'Native Windows Flutter SDK extraction checks passed.'
} finally {
  if ((Split-Path $testRoot -Leaf) -notlike 'bilisail-windows-sdk-*' -or [IO.Path]::GetFullPath($testRoot) -cne $testRoot) { throw 'Unsafe SDK fixture cleanup path.' }
  if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
  $global:LASTEXITCODE = $previousExitCode
}
