$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'macos-release-validation.ps1')
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-Rejected([scriptblock]$Action) {
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  if (!$rejected) { throw 'Unsafe macOS release validation input was accepted.' }
}

$valid = '<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.network.client</key><true/></dict></plist>'
Confirm-MacOSReleaseEntitlements $valid
Confirm-MacOSReleaseEntitlements (Get-Content (Join-Path $repoRoot 'macos/Runner/Release.entitlements') -Raw)
foreach ($invalid in @(
  '', '<plist><array/></plist>', '<plist><dict/></plist>',
  $valid.Replace('<true/>', '<false/>'),
  $valid.Replace('<true/>', '<string>true</string>'),
  $valid.Replace('</dict>', '<key>keychain-access-groups</key><array/></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.application-identifier</key><string>TEAM.app</string></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.security.cs.allow-jit</key><true/></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.security.get-task-allow</key><true/></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.security.get-task-allow</key><false/></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.security.app-sandbox</key><true/></dict>'),
  $valid.Replace('</dict>', '<key>com.apple.security.network.server</key></dict>')
)) { Assert-Rejected { Confirm-MacOSReleaseEntitlements $invalid } }
foreach ($source in @('Release', 'DebugProfile')) {
  [xml]$plist = Get-Content (Join-Path $repoRoot "macos/Runner/$source.entitlements") -Raw
  if ('keychain-access-groups' -in @($plist.plist.dict.key)) { throw 'Source entitlements still enable Keychain Sharing.' }
}
$runId = '0123456789abcdef0123456789abcdef'
$marker = "BILISAIL_RELEASE_SMOKE_OK:write:$runId"
Confirm-MacOSSmokeResult 0 "native message`n$marker`n" 'write' $runId
Assert-Rejected { Confirm-MacOSSmokeResult 1 $marker 'write' $runId }
Assert-Rejected { Confirm-MacOSSmokeResult 0 '' 'write' $runId }
Assert-Rejected { Confirm-MacOSSmokeResult 0 "prefix $marker" 'write' $runId }
Assert-Rejected { Confirm-MacOSSmokeResult 0 $marker 'read-delete' $runId }
Assert-Rejected { Confirm-MacOSSmokeResult 0 $marker 'write' 'fedcba9876543210fedcba9876543210' }
Write-Output 'macOS release entitlement and smoke acknowledgement checks passed (22 cases).'
