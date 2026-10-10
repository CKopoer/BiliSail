# Shared by CI preparation, packaging and offline version-boundary checks.
function Get-AndroidVersionCode([string]$Version) {
  if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.([0-9])\.([0-9])\+([1-9][0-9]?)$') {
    throw 'Android version must be major.minor.patch+build: minor/patch 0..9, build 1..99.'
  }
  $major = [System.Numerics.BigInteger]::Parse($Matches[1])
  if ($major -gt 209999) { throw 'Android compact versionCode must not exceed 2100000000.' }
  return [int]($major * 10000 + [int]$Matches[2] * 1000 + [int]$Matches[3] * 100 + [int]$Matches[4])
}

function ConvertFrom-AndroidApkBadging([string]$Report, [string]$Version) {
  $expectedCode = Get-AndroidVersionCode $Version
  $expectedName = $Version.Split('+')[0]
  $package = [regex]::Match($Report, "(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'")
  if (!$package.Success -or $package.Groups[1].Value -cne 'dev.bilisail.bilisail' -or
      $package.Groups[2].Value -cne [string]$expectedCode -or
      $package.Groups[3].Value -cne $expectedName) {
    throw "APK manifest must contain dev.bilisail.bilisail, versionName=$expectedName, versionCode=$expectedCode."
  }
  return $expectedCode
}

function Confirm-AndroidApkVersion([string]$Package, [string]$Version) {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
  if (!$sdkRoot) { throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT to verify the APK version.' }
  $toolName = if ($IsWindows) { 'aapt.exe' } else { 'aapt' }
  $versions = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Directory |
    Sort-Object { $_.Name -as [version] } -Descending
  $tool = $versions | ForEach-Object { Join-Path $_.FullName $toolName } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (!$tool) { throw 'Android SDK aapt was not found.' }
  $report = & $tool dump badging $Package
  if ($LASTEXITCODE -ne 0) { throw 'Could not read APK manifest version.' }
  return ConvertFrom-AndroidApkBadging ($report -join [Environment]::NewLine) $Version
}
