# Shared by packaging and its offline signing-boundary checks.
function Initialize-AndroidSigning([switch]$Preview) {
  $signingValues = @(
    $env:ANDROID_KEYSTORE_BASE64, $env:ANDROID_KEYSTORE_PATH,
    $env:ANDROID_KEYSTORE_PASSWORD, $env:ANDROID_KEY_ALIAS, $env:ANDROID_KEY_PASSWORD
  )
  if ($Preview) {
    if (@($signingValues | Where-Object { ![string]::IsNullOrWhiteSpace($_) }).Count) {
      throw 'Preview builds must not receive the Android release signing key.'
    }
  } else {
    if ([string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_BASE64) -eq [string]::IsNullOrWhiteSpace($env:ANDROID_KEYSTORE_PATH)) {
      throw 'Provide exactly one of ANDROID_KEYSTORE_BASE64 or ANDROID_KEYSTORE_PATH.'
    }
    foreach ($name in @('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD')) {
      if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Android release signing requires $name."
      }
    }
    if ($env:ANDROID_SIGNING_CERTIFICATE_SHA256 -cnotmatch '^[0-9a-fA-F]{64}$') {
      throw 'Android release signing requires ANDROID_SIGNING_CERTIFICATE_SHA256.'
    }
  }

  $state = [pscustomobject]@{
    Signing = if ($Preview) { 'temporary-debug-key' } else { 'configured-keystore' }
    ExpectedSha256 = $env:ANDROID_SIGNING_CERTIFICATE_SHA256
    TemporaryDirectory = $null
    PreviousStorePath = $env:ANDROID_KEYSTORE_PATH
    PreviousPreview = $env:ANDROID_PREVIEW_SIGNING
  }
  try {
    $env:ANDROID_PREVIEW_SIGNING = if ($Preview) { 'true' } else { 'false' }
    if (!$Preview) {
      if ($env:ANDROID_KEYSTORE_BASE64) {
        try { $keyBytes = [Convert]::FromBase64String($env:ANDROID_KEYSTORE_BASE64) }
        catch { throw 'ANDROID_KEYSTORE_BASE64 is invalid.' }
        if (!$keyBytes.Length) { throw 'ANDROID_KEYSTORE_BASE64 is empty.' }
        $state.TemporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail-android-signing-$([Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $state.TemporaryDirectory | Out-Null
        if (!$IsWindows) {
          & chmod 700 $state.TemporaryDirectory
          if ($LASTEXITCODE -ne 0) { throw 'Could not protect the temporary signing directory.' }
        }
        $env:ANDROID_KEYSTORE_PATH = Join-Path $state.TemporaryDirectory 'release.jks'
        [System.IO.File]::WriteAllBytes($env:ANDROID_KEYSTORE_PATH, $keyBytes)
      }
      if (!(Test-Path -LiteralPath $env:ANDROID_KEYSTORE_PATH -PathType Leaf)) {
        throw 'The configured Android keystore file does not exist.'
      }
      $env:ANDROID_KEYSTORE_PATH = [System.IO.Path]::GetFullPath($env:ANDROID_KEYSTORE_PATH)
    }
    return $state
  } catch {
    Clear-AndroidSigning $state
    throw
  }
}

function Clear-AndroidSigning($State) {
  if ($null -eq $State) { return }
  [Environment]::SetEnvironmentVariable('ANDROID_KEYSTORE_PATH', $State.PreviousStorePath)
  [Environment]::SetEnvironmentVariable('ANDROID_PREVIEW_SIGNING', $State.PreviousPreview)
  if ($State.TemporaryDirectory -and (Test-Path -LiteralPath $State.TemporaryDirectory)) {
    # Remove only the one file and directory created by this invocation.
    $keyFile = Join-Path $State.TemporaryDirectory 'release.jks'
    if (Test-Path -LiteralPath $keyFile) { Remove-Item -LiteralPath $keyFile -Force }
    Remove-Item -LiteralPath $State.TemporaryDirectory -Force
  }
}

function Get-AndroidApkSigner {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
  if (!$sdkRoot) { throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT to verify the APK signature.' }
  $toolName = if ($IsWindows) { 'apksigner.bat' } else { 'apksigner' }
  $versions = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
    Sort-Object { $_.Name -as [version] } -Descending
  foreach ($version in $versions) {
    $candidate = Join-Path $version.FullName $toolName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  throw 'Android SDK apksigner was not found.'
}

function Confirm-AndroidApkSigning([string]$Package, $State) {
  $tool = Get-AndroidApkSigner
  $report = & $tool verify --verbose --print-certs-pem $Package
  if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
  # PEM is a standard certificate encoding; human-readable digest labels can
  # change between SDK versions and must not determine the signing identity.
  $certificates = [regex]::Matches(($report -join [Environment]::NewLine), '-----BEGIN CERTIFICATE-----\s*([A-Za-z0-9+/=\s]+?)\s*-----END CERTIFICATE-----')
  if ($certificates.Count -ne 1) {
    throw "APK must have exactly one signing certificate (found $($certificates.Count); tool: $tool)."
  }
  try {
    $certificateBytes = [Convert]::FromBase64String($certificates[0].Groups[1].Value)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateBytes)
  } catch { throw 'Invalid APK signing certificate.' }
  try {
    $sha256 = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($certificate.RawData)).ToLowerInvariant()
  } finally { $certificate.Dispose() }
  if ($State.Signing -eq 'configured-keystore' -and $sha256 -ne $State.ExpectedSha256.ToLowerInvariant()) {
    throw 'APK signing certificate does not match ANDROID_SIGNING_CERTIFICATE_SHA256.'
  }
  return $sha256
}
