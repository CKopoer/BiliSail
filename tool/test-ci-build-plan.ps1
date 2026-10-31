$ErrorActionPreference = 'Stop'
$checks = 0
$outputFile = [System.IO.Path]::GetTempFileName()
$names = @('GITHUB_OUTPUT', 'REQUESTED_VERSION', 'ENABLE_ANDROID', 'ENABLE_WINDOWS', 'ENABLE_MACOS', 'ENABLE_IOS', 'ENABLE_LINUX', 'BUILD_TARGETS')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name) }

function Invoke-Plan([string]$Version, [int]$Mask, [string]$BuildTargets = '') {
  $env:REQUESTED_VERSION = $Version
  $env:BUILD_TARGETS = $BuildTargets
  for ($index = 0; $index -lt 5; $index++) {
    [Environment]::SetEnvironmentVariable($names[$index + 2], (($Mask -band (1 -shl $index)) -ne 0).ToString().ToLowerInvariant())
  }
  [System.IO.File]::WriteAllText($outputFile, '')
  & (Join-Path $PSScriptRoot 'ci-build-plan.ps1')
  $values = @{}
  foreach ($line in Get-Content -LiteralPath $outputFile) {
    $key, $value = $line -split '=', 2
    $values[$key] = $value
  }
  return $values
}

function Assert-Rejected([string]$Version, [int]$Mask, [string]$BuildTargets = '') {
  $rejected = $false
  try { Invoke-Plan $Version $Mask $BuildTargets | Out-Null } catch { $rejected = $true }
  if (!$rejected) { throw "Invalid plan accepted: version=$Version mask=$Mask" }
  $script:checks++
}

try {
  $env:GITHUB_OUTPUT = $outputFile
  Assert-Rejected '1.2.5+0' 0
  for ($mask = 1; $mask -lt 32; $mask++) {
    $plan = Invoke-Plan '1.2.5+0' $mask
    $targets = @(($plan.matrix | ConvertFrom-Json).include.target)
    $expected = @(
      if ($mask -band 1) { 'android-arm64' }
      if ($mask -band 2) { 'windows-x64' }
      if ($mask -band 4) { 'macos-arm64'; 'macos-x64' }
      if ($mask -band 8) { 'ios-arm64' }
      if ($mask -band 16) { 'linux-x64' }
    )
    if ($plan.version -cne '1.2.5+0' -or ($targets -join ',') -cne ($expected -join ',')) {
      throw "Incorrect version or platforms for mask $mask."
    }
    $checks++
  }
  if ((Invoke-Plan ' 1.2.5+1 ' 31).version -cne '1.2.5+1') { throw 'Version override was not trimmed.' }
  $checks++
  $sourceVersion = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\S+)\s*$').Groups[1].Value
  if ((Invoke-Plan '' 31).version -cne $sourceVersion) { throw 'Empty version did not use pubspec.yaml.' }
  $checks++
  foreach ($version in @('v1.2.5', '1.2.5', '01.2.5+0', '1.2.5+-1', '1.2.5+00')) { Assert-Rejected $version 31 }
  Assert-Rejected '1.10.5+0' 1
  Assert-Rejected '1.2.5+100' 1
  Assert-Rejected '256.2.5+0' 2
  Assert-Rejected '1.2.65+999' 2
  if ((Invoke-Plan '256.10.5+1000' 16).version -cne '256.10.5+1000') { throw 'Unselected platform constrained version.' }
  $checks++
  $allTargets = @('android-arm64', 'windows-x64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64')
  for ($mask = 1; $mask -lt 64; $mask++) {
    $expected = @(for ($index = 0; $index -lt 6; $index++) {
      if ($mask -band (1 -shl $index)) { $allTargets[$index] }
    })
    $plan = Invoke-Plan '1.2.5+0' 31 (ConvertTo-Json -InputObject $expected -Compress)
    $targets = @(($plan.matrix | ConvertFrom-Json).include.target)
    if (($targets -join ',') -cne ($expected -join ',')) { throw "Wrong missing-target subset for mask $mask." }
    $checks++
  }
  foreach ($invalid in @('[]', 'null', '"macos-x64"', '{}', '["unknown"]',
    '["macos-x64","macos-x64"]', '["macos-x64",null]', '[42]', 'not-json')) {
    Assert-Rejected '1.2.5+0' 31 $invalid
  }
  Assert-Rejected '1.2.5+0' 1 '["windows-x64"]'
} finally {
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
  Remove-Item -LiteralPath $outputFile
}
Write-Output "CI build plan checks passed: $checks"
