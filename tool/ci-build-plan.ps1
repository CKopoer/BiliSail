$ErrorActionPreference = 'Stop'
$version = $env:REQUESTED_VERSION.Trim()
if (!$version) {
  $match = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\S+)\s*$')
  if (!$match.Success) { throw 'pubspec.yaml has no version.' }
  $version = $match.Groups[1].Value
}
if ($version -cnotmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+(0|[1-9]\d*)$') {
  throw 'Version must be x.y.z+N, for example 0.1.0+1.'
}
if ($env:ENABLE_ANDROID -eq 'true') {
  . (Join-Path $PSScriptRoot 'android-version.ps1')
  Get-AndroidVersionCode $version | Out-Null
}
$platforms = @(
  if ($env:ENABLE_ANDROID -eq 'true') { @{ target = 'android-arm64'; runner = 'ubuntu-24.04'; arch = 'x64' } }
  if ($env:ENABLE_WINDOWS -eq 'true') {
    @{ target = 'windows-x64'; runner = 'windows-2022'; arch = 'x64' }
    # Use the x64 Flutter distribution, then require native ARM64 Dart using
    # the SDK's own bootstrap script. The target follows the Dart process ABI.
    @{ target = 'windows-arm64'; runner = 'windows-11-arm'; arch = 'x64' }
  }
  if ($env:ENABLE_MACOS -eq 'true') {
    @{ target = 'macos-arm64'; runner = 'macos-15'; arch = 'arm64' }
    @{ target = 'macos-x64'; runner = 'macos-15'; arch = 'arm64' }
  }
  if ($env:ENABLE_IOS -eq 'true') { @{ target = 'ios-arm64'; runner = 'macos-15'; arch = 'arm64' } }
  if ($env:ENABLE_LINUX -eq 'true') { @{ target = 'linux-x64'; runner = 'ubuntu-24.04'; arch = 'x64' } }
)
if (!$platforms.Count) { throw 'Select at least one platform.' }
if ($env:ENABLE_WINDOWS -eq 'true' -and @(($version -split '[.+]') | Where-Object { [long]$_ -gt 65535 }).Count) {
  throw 'MSIX version components must be at most 65535.'
}
if ($env:ENABLE_WINDOWS -eq 'true') {
  . (Join-Path $PSScriptRoot 'windows-installers.ps1')
  Get-WindowsMsiVersion $version | Out-Null
}
if (![string]::IsNullOrWhiteSpace($env:BUILD_TARGETS)) {
  $targets = ConvertFrom-Json -InputObject $env:BUILD_TARGETS -NoEnumerate
  if ($targets -isnot [array] -or !$targets.Count -or
      @($targets | Where-Object { $_ -isnot [string] -or $_ -cnotin $platforms.target }).Count -or
      @($targets | Select-Object -Unique).Count -ne $targets.Count) {
    throw 'Build targets must be a nonempty JSON array of distinct selected targets.'
  }
  $platforms = @($platforms | Where-Object { $_.target -cin $targets })
}
$appleWriter = @('macos-arm64', 'macos-x64', 'ios-arm64') | Where-Object { $_ -in $platforms.target } | Select-Object -First 1
foreach ($platform in $platforms) {
  # Linux Pub/SDK writes belong to lint. Apple ARM64 has one build writer,
  # including an iOS-only release; Windows ARM64 uses its actual host Pub ABI.
  $platform.cache_sdk = !$platform.target.StartsWith('windows-')
  $platform.cache_writer = $platform.target -in @('windows-x64', 'windows-arm64') -or $platform.target -eq $appleWriter
  # Linux application builds read the snapshot published by native regression.
  $platform.mux_cache_writer = $platform.target -ne 'linux-x64'
}
"version=$version" >> $env:GITHUB_OUTPUT
"matrix=$(@{ include = @($platforms) } | ConvertTo-Json -Depth 3 -Compress)" >> $env:GITHUB_OUTPUT
