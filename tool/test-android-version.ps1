$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'android-version.ps1')
$checks = 0
function Assert-Code([string]$Version, [int]$Expected) {
  $actual = Get-AndroidVersionCode $Version
  if ($actual -ne $Expected) { throw "$Version encoded as $actual, expected $Expected." }
  $script:checks++
}
function Assert-Rejected([scriptblock]$Action) {
  $rejected = $false
  try { & $Action | Out-Null } catch { $rejected = $true }
  if (!$rejected) { throw 'Invalid version or manifest was accepted.' }
  $script:checks++
}

Assert-Code '0.0.0+1' 1
Assert-Code '0.5.3+7' 5307
Assert-Code '0.5.5+2' 5502
Assert-Code '0.5.5+99' 5599
Assert-Code '0.5.6+1' 5601
Assert-Code '0.5.9+99' 5999
Assert-Code '0.6.0+1' 6001
Assert-Code '0.9.9+99' 9999
Assert-Code '1.0.0+1' 10001
Assert-Code '209999.9.9+99' 2099999999
foreach ($invalid in @(
  '0.10.0+1', '0.0.10+1', '0.5.5+100', '0.5.5+0',
  '210000.0.0+1', '999999999999999999999999999999999999.0.0+1',
  '-1.0.0+1', '0.5.5+-1', '00.5.5+1', '0.05.5+1', '0.5.05+1',
  '0.5.5+01', '0.5.5', '0.5.5-rc+1', '0.5.5+2 ', ''
)) { Assert-Rejected { Get-AndroidVersionCode $invalid } }
if ((Get-AndroidVersionCode '0.5.5+2') -le 2007) { throw 'Cannot upgrade the historical arm64 APK.' }
$checks++

$valid = "package: name='dev.bilisail.bilisail' versionCode='5502' versionName='0.5.5' platformBuildVersionName='16'"
if ((ConvertFrom-AndroidApkBadging $valid '0.5.5+2') -ne 5502) { throw 'Valid APK rejected.' }
$checks++
foreach ($invalidReport in @(
  $valid.Replace("'5502'", "'7502'"), # Accidental ABI offset.
  $valid.Replace("'5502'", "'2002'"), # Old build-number-only encoding.
  $valid.Replace("'5502'", "'2'"),
  $valid.Replace("'0.5.5'", "'0.5.4'"),
  $valid.Replace("'dev.bilisail.bilisail'", "'another.app'"),
  'not an APK manifest'
)) { Assert-Rejected { ConvertFrom-AndroidApkBadging $invalidReport '0.5.5+2' } }
Write-Output "Android version checks passed: $checks"
