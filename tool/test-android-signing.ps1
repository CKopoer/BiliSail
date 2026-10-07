$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-signing.ps1')

$names = @(
  'ANDROID_KEYSTORE_BASE64', 'ANDROID_KEYSTORE_PATH', 'ANDROID_KEYSTORE_PASSWORD',
  'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_SIGNING_CERTIFICATE_SHA256',
  'ANDROID_PREVIEW_SIGNING'
)
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }
$checks = 0
$fixtureDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail-signing-check-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
$fixturePath = Join-Path $fixtureDirectory 'fixture.jks'
[System.IO.File]::WriteAllBytes($fixturePath, [byte[]]@(1, 2, 3))

function Reset-SigningFixture {
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $null) }
}
function Set-SigningFixture {
  Reset-SigningFixture
  $env:ANDROID_KEYSTORE_BASE64 = [Convert]::ToBase64String([byte[]]@(1, 2, 3))
  $env:ANDROID_KEYSTORE_PASSWORD = 'fixture-password'
  $env:ANDROID_KEY_ALIAS = 'fixture'
  $env:ANDROID_KEY_PASSWORD = 'fixture-password'
  $env:ANDROID_SIGNING_CERTIFICATE_SHA256 = 'a' * 64
}
function Assert-True([bool]$Condition, [string]$Message) {
  if (!$Condition) { throw $Message }
  $script:checks++
}
function Assert-Rejected([scriptblock]$Action, [string]$Expected) {
  $caught = $false
  try { & $Action | Out-Null }
  catch {
    $caught = $true
    if ($_.Exception.Message -notlike "*$Expected*") { throw }
  }
  Assert-True $caught "Expected rejection: $Expected"
}

try {
  Reset-SigningFixture
  Assert-Rejected { Initialize-AndroidSigning } 'exactly one'
  foreach ($name in @('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')) {
    Set-SigningFixture
    [Environment]::SetEnvironmentVariable($name, $null)
    Assert-Rejected { Initialize-AndroidSigning } $name
  }
  Set-SigningFixture
  $env:ANDROID_SIGNING_CERTIFICATE_SHA256 = $null
  Assert-Rejected { Initialize-AndroidSigning } 'ANDROID_SIGNING_CERTIFICATE_SHA256'
  Set-SigningFixture
  $env:ANDROID_KEYSTORE_PATH = $fixturePath
  Assert-Rejected { Initialize-AndroidSigning } 'exactly one'
  Set-SigningFixture
  $env:ANDROID_KEYSTORE_BASE64 = $null
  $env:ANDROID_KEYSTORE_PATH = Join-Path $fixtureDirectory 'missing.jks'
  Assert-Rejected { Initialize-AndroidSigning } 'does not exist'
  Set-SigningFixture
  $env:ANDROID_KEYSTORE_BASE64 = 'invalid base64'
  $env:ANDROID_PREVIEW_SIGNING = 'prior-value'
  Assert-Rejected { Initialize-AndroidSigning } 'invalid'
  Assert-True ($env:ANDROID_PREVIEW_SIGNING -eq 'prior-value' -and !$env:ANDROID_KEYSTORE_PATH) 'Failed initialization changed caller environment.'
  Set-SigningFixture
  Assert-Rejected { Initialize-AndroidSigning -Preview } 'must not receive'

  Set-SigningFixture
  $state = Initialize-AndroidSigning
  try {
    Assert-True ($state.Signing -eq 'configured-keystore' -and $env:ANDROID_PREVIEW_SIGNING -eq 'false') 'Fixed signing was not selected.'
    Assert-True ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($env:ANDROID_KEYSTORE_PATH)) -eq $env:ANDROID_KEYSTORE_BASE64) 'Decoded keystore differs from its input.'
    $temporaryDirectory = $state.TemporaryDirectory
  } finally { Clear-AndroidSigning $state }
  Assert-True (!(Test-Path -LiteralPath $temporaryDirectory) -and !$env:ANDROID_KEYSTORE_PATH -and !$env:ANDROID_PREVIEW_SIGNING) 'Signing cleanup did not remove temporary material and restore the environment.'

  Set-SigningFixture
  $env:ANDROID_KEYSTORE_BASE64 = $null
  $env:ANDROID_KEYSTORE_PATH = $fixturePath
  $state = Initialize-AndroidSigning
  Clear-AndroidSigning $state
  Assert-True ((Test-Path -LiteralPath $fixturePath) -and $env:ANDROID_KEYSTORE_PATH -eq $fixturePath) 'Cleanup removed the caller-owned keystore.'
  Reset-SigningFixture
  $state = Initialize-AndroidSigning -Preview
  try { Assert-True ($state.Signing -eq 'temporary-debug-key' -and $env:ANDROID_PREVIEW_SIGNING -eq 'true') 'Explicit preview signing was not selected.' }
  finally { Clear-AndroidSigning $state }

  # Exercise the verifier's output boundary without requiring an SDK or an APK.
  function Get-AndroidApkSigner { return 'Invoke-FakeApkSigner' }
  function Invoke-FakeApkSigner {
    $global:LASTEXITCODE = $script:fakeExitCode
    return $script:fakeReport
  }
  $fakeExitCode = 0
  $fixedState = [pscustomobject]@{ Signing = 'configured-keystore'; ExpectedSha256 = 'a' * 64 }
  $fakeReport = "Signer #1 certificate SHA-256 digest: $('a' * 64)"
  Assert-True ((Confirm-AndroidApkSigning 'fixture.apk' $fixedState) -eq ('a' * 64)) 'Matching certificate was rejected.'
  $fakeReport = "Signer #1 certificate SHA-256 digest: $('b' * 64)"
  Assert-Rejected { Confirm-AndroidApkSigning 'fixture.apk' $fixedState } 'does not match'
  $fakeReport = 'No signing certificate'
  Assert-Rejected { Confirm-AndroidApkSigning 'fixture.apk' $fixedState } 'exactly one'
  $fakeReport = @(
    "Signer #1 certificate SHA-256 digest: $('a' * 64)",
    "Signer #2 certificate SHA-256 digest: $('b' * 64)"
  )
  Assert-Rejected { Confirm-AndroidApkSigning 'fixture.apk' $fixedState } 'exactly one'
  $fakeExitCode = 1
  Assert-Rejected { Confirm-AndroidApkSigning 'fixture.apk' $fixedState } 'verification failed'
  Write-Output "Android signing boundary checks passed: $checks"
} finally {
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
  Remove-Item -LiteralPath $fixturePath -Force
  Remove-Item -LiteralPath $fixtureDirectory -Force
}
