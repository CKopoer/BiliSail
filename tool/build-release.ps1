param(
  [Parameter(Mandatory)][ValidateSet('android-arm64', 'windows-x64', 'macos-arm64')][string]$Target,
  [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Invoke-BuildCommand([string]$Executable, [string[]]$Parameters) {
  & $Executable @Parameters
  if ($LASTEXITCODE -ne 0) { throw "$Executable failed: $LASTEXITCODE" }
}

function New-MsixPackage([string]$Staging, [string]$Destination, [string]$PackageVersion) {
  $sdkTool = Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin/*/x64/makeappx.exe" |
    Sort-Object FullName -Descending | Select-Object -First 1
  if (!$sdkTool) { throw 'Windows SDK MakeAppx.exe was not found.' }
  $signTool = Join-Path $sdkTool.DirectoryName 'signtool.exe'
  $makePri = Join-Path $sdkTool.DirectoryName 'makepri.exe'
  if (!(Test-Path -LiteralPath $makePri)) { throw 'Windows SDK MakePri.exe was not found.' }
  $publisher = if ($env:MSIX_PUBLISHER) { $env:MSIX_PUBLISHER } else { 'CN=BiliSail' }
  [xml]$manifest = Get-Content 'windows/packaging/AppxManifest.xml' -Raw
  $manifest.Package.Identity.Version = $PackageVersion
  $manifest.Package.Identity.Publisher = $publisher
  $manifest.Save((Join-Path $Staging 'AppxManifest.xml'))

  # MSIX taskbar icons use manifest resources rather than the EXE's ICO.
  # Both shell themes need unplated variants, even when they share the same image.
  Add-Type -AssemblyName System.Drawing
  $assetDir = Join-Path $Staging 'Assets'
  New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
  $icon = [System.Drawing.Image]::FromFile((Join-Path $repoRoot 'assets/branding/app_icon.png'))
  try {
    $targetSizes = @(16, 20, 24, 30, 32, 36, 40, 44, 48, 60, 64, 72, 80, 96, 256)
    foreach ($size in @(@(44, 50, 150) + $targetSizes | Sort-Object -Unique)) {
      $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($icon, 0, 0, $size, $size)
        $filenames = @(
          if ($size -in @(44, 50, 150)) { "Logo$size.png" }
          if ($size -in $targetSizes) {
            "Logo44.targetsize-$size.png"
            "Logo44.targetsize-${size}_altform-unplated.png"
            "Logo44.targetsize-${size}_altform-lightunplated.png"
          }
        )
        foreach ($filename in $filenames) {
          $bitmap.Save((Join-Path $assetDir $filename), [System.Drawing.Imaging.ImageFormat]::Png)
        }
      } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
  } finally { $icon.Dispose() }
  # Qualified filenames alone are insufficient: the shell resolves them through PRI.
  # An explicit file list preserves the Assets/ prefix and excludes Flutter data.
  $resourceList = Join-Path $Staging 'msix-icons.resfiles'
  Get-ChildItem -LiteralPath $assetDir -File | ForEach-Object { "Assets\$($_.Name)" } |
    Set-Content -LiteralPath $resourceList -Encoding ascii
  try {
    Invoke-BuildCommand $makePri @('new', '/pr', $Staging, '/cf', (Join-Path $repoRoot 'windows/packaging/priconfig.xml'), '/mn', (Join-Path $Staging 'AppxManifest.xml'), '/of', (Join-Path $Staging 'resources.pri'), '/o') | Out-Host
  } finally { Remove-Item -LiteralPath $resourceList }
  Invoke-BuildCommand $sdkTool.FullName @('pack', '/d', $Staging, '/p', $Destination, '/o') | Out-Host

  $certificate = $null
  $certificateFile = $null
  $createdCertificates = @()
  try {
    if ($env:MSIX_CERTIFICATE_BASE64) {
      $certificateFile = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail-$([guid]::NewGuid()).pfx"
      [System.IO.File]::WriteAllBytes($certificateFile, [Convert]::FromBase64String($env:MSIX_CERTIFICATE_BASE64))
      $password = if ($env:MSIX_CERTIFICATE_PASSWORD) {
        ConvertTo-SecureString -String $env:MSIX_CERTIFICATE_PASSWORD -AsPlainText -Force
      } else { [System.Security.SecureString]::new() }
      $existingThumbprints = @(Get-ChildItem Cert:\CurrentUser\My | ForEach-Object { $_.Thumbprint })
      $imported = @(Import-PfxCertificate -FilePath $certificateFile -Password $password -CertStoreLocation Cert:\CurrentUser\My)
      $createdCertificates = @($imported | Where-Object { $_.Thumbprint -notin $existingThumbprints })
      $certificate = $imported | Where-Object { $_.HasPrivateKey -and $_.Subject -ceq $publisher } | Select-Object -First 1
      if (!$certificate) { throw 'The signing PFX must contain a private key matching MSIX_PUBLISHER.' }
      $signing = 'configured-certificate'
    } else {
      if ($env:MSIX_CERTIFICATE_PASSWORD) { throw 'MSIX signing secrets are incomplete.' }
      $certificate = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature -FriendlyName 'BiliSail preview package signing' -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(1) -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
      $createdCertificates = @($certificate)
      $signing = 'self-signed-preview'
    }
    if ($certificate.NotAfter -le (Get-Date)) { throw 'The MSIX signing certificate has expired.' }
    Invoke-BuildCommand $signTool @('sign', '/fd', 'SHA256', '/sha1', $certificate.Thumbprint, '/s', 'My', $Destination) | Out-Host
    Export-Certificate -Cert $certificate -FilePath ([System.IO.Path]::ChangeExtension($Destination, '.cer')) | Out-Null
    return $signing
  } finally {
    if ($certificateFile -and (Test-Path -LiteralPath $certificateFile)) { Remove-Item -LiteralPath $certificateFile }
    foreach ($createdCertificate in $createdCertificates) {
      if ($createdCertificate.HasPrivateKey) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($createdCertificate.Thumbprint)" -DeleteKey }
      else { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($createdCertificate.Thumbprint)" }
    }
  }
}

if ($Version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+[1-9]\d*$') {
  throw 'Version must be x.y.z+N, for example 0.1.0+1.'
}
$buildName, $buildNumber = $Version.Split('+')
if ([long]$buildNumber -gt 2100000000) { throw 'Android build number is too large.' }
if ($Target -eq 'android-arm64' -and [long]$buildNumber -gt 2099998000) { throw 'Android arm64 split APK reserves 2000 in its version code.' }
if ($Target -eq 'windows-x64' -and @(($Version -split '[.+]') | Where-Object { [long]$_ -gt 65535 }).Count) {
  throw 'MSIX version components must be at most 65535.'
}
if ($Target -eq 'windows-x64' -and (!$IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64')) {
  throw 'windows-x64 requires a Windows x64 host.'
}
if ($Target -eq 'macos-arm64' -and (!$IsMacOS -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'Arm64')) {
  throw 'macos-arm64 requires an Apple Silicon macOS host.'
}

$oldMacSigningIdentity = $env:FLUTTER_XCODE_CODE_SIGN_IDENTITY
$oldMacSigningStyle = $env:FLUTTER_XCODE_CODE_SIGN_STYLE
Push-Location $repoRoot
try {
  # Finish SDK bootstrap before capturing the machine-readable version.
  Invoke-BuildCommand flutter @('--version')
  $sdkJson = & flutter --version --machine
  if ($LASTEXITCODE -ne 0) { throw 'Could not read Flutter SDK version.' }
  $sdk = $sdkJson | ConvertFrom-Json
  if ($sdk.frameworkVersion -ne '3.47.6') { throw 'This checkout is verified with Flutter 3.47.6.' }
  $revision = & git rev-parse HEAD
  if ($LASTEXITCODE -ne 0) { throw 'Could not read source revision.' }
  $sourceChanges = & git status --porcelain
  if ($LASTEXITCODE -ne 0) { throw 'Could not read source status.' }
  $sourceDirty = [bool]$sourceChanges
  $lockHash = (Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash
  Invoke-BuildCommand flutter @('pub', 'get', '--enforce-lockfile')
  # Release builds must regenerate native registrants without dev-only plugins.
  # In Flutter 3.47.6 --no-pub skips that regeneration (not just dependency fetching).
  $versionArgs = @('--release', '--build-name', $buildName, '--build-number', $buildNumber)
  $name = "BiliSail-$Version-$Target"
  $outputRoot = Join-Path $repoRoot "artifacts/$Target"
  $releaseDir = Join-Path $outputRoot 'release'
  # Refuse to mix a new package with an earlier local build's staging/metadata.
  if (Test-Path -LiteralPath $outputRoot) { throw "$outputRoot already exists. Move it aside before rebuilding." }
  New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

  switch ($Target) {
    'android-arm64' {
      Invoke-BuildCommand flutter (@('build', 'apk', '--target-platform', 'android-arm64', '--split-per-abi') + $versionArgs)
      $package = Join-Path $releaseDir "$name.apk"
      Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk' -Destination $package
      $apk = [System.IO.Compression.ZipFile]::OpenRead($package)
      try {
        $abis = @($apk.Entries.FullName | Where-Object { $_ -match '^lib/' } | ForEach-Object { $_.Split('/')[1] } | Sort-Object -Unique)
        if ($abis.Count -ne 1 -or $abis[0] -ne 'arm64-v8a') { throw 'APK contains unexpected native ABIs.' }
      } finally { $apk.Dispose() }
      $signing = 'temporary-debug-key'
    }
    'windows-x64' {
      Invoke-BuildCommand flutter (@('build', 'windows') + $versionArgs)
      $staging = Join-Path $outputRoot $name
      Copy-Item -LiteralPath 'build/windows/x64/runner/Release' -Destination $staging -Recurse
      if (!(Test-Path -LiteralPath (Join-Path $staging 'bilisail.exe'))) { throw 'Windows executable is missing.' }
      # An existing local build directory can still contain the pre-rename EXE.
      $oldExecutable = Join-Path $staging 'bili_lite.exe'
      if (Test-Path -LiteralPath $oldExecutable) { Remove-Item -LiteralPath $oldExecutable }
      # Bundle the application-local VC++ runtime required on a clean machine.
      $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
      $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
      if ($LASTEXITCODE -ne 0 -or !$visualStudio) { throw 'Visual Studio C++ installation was not found.' }
      $runtime = Get-ChildItem "$visualStudio/VC/Redist/MSVC/*/x64/Microsoft.VC143.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
      if (!$runtime) { throw 'Visual C++ x64 redistributable DLLs were not found.' }
      foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        Copy-Item -LiteralPath (Join-Path $runtime.FullName $dll) -Destination $staging
      }
      Copy-Item -LiteralPath 'THIRD_PARTY_NOTICES.md' -Destination $staging
      $package = Join-Path $releaseDir "$name.msix"
      $signing = New-MsixPackage $staging $package "$buildName.$buildNumber"
    }
    'macos-arm64' {
      Invoke-BuildCommand flutter @('config', '--enable-macos-desktop', '--enable-macos-arm64-only')
      # Flutter 3.47.6 forwards FLUTTER_XCODE_* settings to xcodebuild.
      $env:FLUTTER_XCODE_CODE_SIGN_IDENTITY = '-'
      $env:FLUTTER_XCODE_CODE_SIGN_STYLE = 'Manual'
      Invoke-BuildCommand flutter (@('build', 'macos') + $versionArgs)
      Invoke-BuildCommand lipo @('build/macos/Build/Products/Release/BiliSail.app/Contents/MacOS/BiliSail', '-verify_arch', 'arm64')
      $staging = Join-Path $outputRoot $name
      New-Item -ItemType Directory -Path $staging -Force | Out-Null
      Invoke-BuildCommand ditto @('build/macos/Build/Products/Release/BiliSail.app', (Join-Path $staging 'BiliSail.app'))
      Copy-Item -LiteralPath 'THIRD_PARTY_NOTICES.md' -Destination $staging
      $package = Join-Path $releaseDir "$name.zip"
      # ditto preserves the .app executable bits, symlinks and resource forks.
      Invoke-BuildCommand ditto @('-c', '-k', '--sequesterRsrc', '--keepParent', $staging, $package)
      $signing = 'ad-hoc-not-notarized'
    }
  }

  if ((Get-FileHash -LiteralPath 'pubspec.lock' -Algorithm SHA256).Hash -ne $lockHash) {
    throw 'Build changed pubspec.lock; do not publish this package.'
  }
  $metadata = [ordered]@{
    version = $Version
    target = $Target
    sourceRevision = $revision
    sourceDirty = $sourceDirty
    androidVersionCode = if ($Target -eq 'android-arm64') { [long]$buildNumber + 2000 } else { $null }
    flutterVersion = $sdk.frameworkVersion
    flutterRevision = $sdk.frameworkRevision
    engineRevision = $sdk.engineRevision
    dartVersion = $sdk.dartSdkVersion
    signing = $signing
    runnerImage = $env:ImageVersion
    pubspecLockSha256 = $lockHash.ToLowerInvariant()
  }
  $metadataPath = Join-Path $releaseDir "$name.build-info.json"
  $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataPath -Encoding utf8
  foreach ($file in @(Get-ChildItem -LiteralPath $releaseDir -File | ForEach-Object { $_.FullName })) {
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([System.IO.Path]::GetFileName($file))" | Set-Content -LiteralPath "$file.sha256" -Encoding ascii
  }
  Write-Output "Packaged $package"
} finally {
  if ($Target -eq 'macos-arm64') {
    $env:FLUTTER_XCODE_CODE_SIGN_IDENTITY = $oldMacSigningIdentity
    $env:FLUTTER_XCODE_CODE_SIGN_STYLE = $oldMacSigningStyle
  }
  Pop-Location
}
