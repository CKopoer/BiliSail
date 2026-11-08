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
      if ($mask -band 2) { 'windows-x64'; 'windows-arm64' }
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
  $windows = ((Invoke-Plan '1.2.5+0' 2).matrix | ConvertFrom-Json).include
  $arm64 = $windows | Where-Object target -eq 'windows-arm64'
  if ($arm64.runner -cne 'windows-11-arm' -or $arm64.arch -cne 'x64') { throw 'Windows ARM64 requires an ARM64 host with the x64 Flutter SDK.' }
  $checks++
  $allTargets = @('android-arm64', 'windows-x64', 'windows-arm64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64')
  for ($mask = 1; $mask -lt (1 -shl $allTargets.Count); $mask++) {
    $expected = @(for ($index = 0; $index -lt $allTargets.Count; $index++) {
      if ($mask -band (1 -shl $index)) { $allTargets[$index] }
    })
    $plan = Invoke-Plan '1.2.5+0' 31 (ConvertTo-Json -InputObject $expected -Compress)
    $targets = @(($plan.matrix | ConvertFrom-Json).include.target)
    if (($targets -join ',') -cne ($expected -join ',')) { throw "Wrong missing-target subset for mask $mask." }
    $entries = @(($plan.matrix | ConvertFrom-Json).include)
    $apple = @($entries | Where-Object { $_.target -like 'macos-*' -or $_.target -eq 'ios-arm64' })
    if ($apple.Count -and (@($apple | Where-Object cache_writer).Count -ne 1 -or
        @($apple | Where-Object { $_.runner -cne 'macos-15' -or $_.arch -cne 'arm64' -or !$_.cache_sdk }).Count)) {
      throw "Apple cross builds require one ARM64 host cache writer for subset $mask."
    }
    if (@($entries | Where-Object { $_.mux_cache_writer -ne ($_.target -ne 'linux-x64') }).Count) {
      throw 'Linux mux cache writes belong only to native regression.'
    }
    $checks++
  }
  foreach ($invalid in @('[]', 'null', '"macos-x64"', '{}', '["unknown"]',
    '["macos-x64","macos-x64"]', '["macos-x64",null]', '[42]', 'not-json')) {
    Assert-Rejected '1.2.5+0' 31 $invalid
  }
  Assert-Rejected '1.2.5+0' 1 '["windows-x64"]'
  $full = ((Invoke-Plan '1.2.5+0' 31).matrix | ConvertFrom-Json).include
  if (@($full | Where-Object cache_writer).target -join ',' -cne 'windows-x64,windows-arm64,macos-arm64') {
    throw 'Each non-Linux host ABI must have exactly one Pub cache writer.'
  }
  if (@($full | Where-Object cache_sdk).target -join ',' -cne 'android-arm64,macos-arm64,macos-x64,ios-arm64,linux-x64') {
    throw 'Only Linux and Apple ARM64 should retain Flutter SDK snapshots.'
  }
  $iosOnly = ((Invoke-Plan '1.2.5+0' 31 '["ios-arm64"]').matrix | ConvertFrom-Json).include[0]
  if (!$iosOnly.cache_writer -or !$iosOnly.cache_sdk) { throw 'iOS-only builds must own their ARM64 caches.' }
  $checks += 3
} finally {
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
  Remove-Item -LiteralPath $outputFile
}
Write-Output "CI build plan checks passed: $checks"
