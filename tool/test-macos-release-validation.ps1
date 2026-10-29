$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'macos-release-validation.ps1')
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-Rejected([scriptblock]$Action) {
  $rejected = $false
  try { & $Action } catch { $rejected = $true }
  if (!$rejected) { throw 'Unsafe macOS release validation input was accepted.' }
}

$valid = '<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.network.client</key><true/><key>com.apple.security.assets.pictures.read-write</key><true/></dict></plist>'
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
  $valid.Replace('<key>com.apple.security.assets.pictures.read-write</key><true/>', '')
  $valid.Replace('</dict>', '<key>com.apple.security.assets.pictures.read-write</key><true/></dict>')
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
Write-Output 'macOS release entitlement and smoke acknowledgement checks passed (24 cases).'
$safe = @(Get-MacOSSmokeDiagnosticLines @'
BILISAIL_RELEASE_STAGE:first-frame-wait
BILISAIL_FOCUS_STAGE:foreground
BILISAIL_FOCUS_NATIVE revision=3 active=1 key=1 view=2 responder=FlutterView inView=1
BILISAIL_RELEASE_SMOKE_FAILED:startup
BILISAIL_CREDENTIAL_STAGE:write-first
BILISAIL_CREDENTIAL_STAGE:read-second
BILISAIL_CREDENTIAL_STAGE:cleanup-recommendation
BILISAIL_NATIVE_STAGE:plugins-register
BILISAIL_RELEASE_STAGE:dart-entry
BILISAIL_NATIVE_STAGE:plugins-register private
BILISAIL_CREDENTIAL_STAGE:write-first private
BILISAIL_CREDENTIAL_STAGE:https://example.invalid/?token=private
BILISAIL_RELEASE_STAGE:https://example.invalid/?token=private
native https://example.invalid/?token=private
'@)
if ($safe.Count -ne 9 -or ($safe -join "`n") -match 'private|FlutterView|https:') {
  throw 'macOS smoke diagnostics leaked non-whitelisted output.'
}

# Exercise real child processes: parser-only checks cannot detect conflated
# launch/probe deadlines, pipe deadlocks or acknowledgements on the wrong pipe.
$processFixture = Join-Path $PSScriptRoot 'fixtures/macos-smoke-process.ps1'
$pwsh = (Get-Process -Id $PID).Path
$smokeTestDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail-smoke-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $smokeTestDirectory | Out-Null
try {
  foreach ($scenario in @('slow-launch', 'launch-timeout', 'native-hang', 'probe-timeout', 'duplicate-entry', 'failure', 'missing-ack', 'stderr-ack', 'no-entry', 'flood')) {
    Remove-Item -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Force -ErrorAction SilentlyContinue
    $launchLimit = if ($scenario -eq 'launch-timeout') { 1 } elseif ($scenario -eq 'native-hang') { 3 } else { 10 }
    $probeLimit = if ($scenario -in @('slow-launch', 'probe-timeout', 'duplicate-entry')) { 1 } else { 3 }
    $failure = $null
    try {
      Invoke-MacOSReleaseSmokePhase -Executable $pwsh -Phase 'verify-deleted' -RunId $runId `
        -WorkingDirectory $smokeTestDirectory -TimeoutSeconds $probeLimit -LaunchTimeoutSeconds $launchLimit `
        -LauncherArguments @('-NoProfile', '-File', $processFixture, $scenario)
    } catch { $failure = $_.Exception.Message }
    $json = Get-Content -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Raw
    $status = $json | ConvertFrom-Json
    if ($json -match 'private|https:|example.invalid') { throw "Raw child output leaked in scenario '$scenario'." }
    switch ($scenario) {
      { $_ -in @('slow-launch', 'flood') } {
        if ($failure -or $status.timedOut -or !$status.acknowledged -or !$status.outputDrained -or $status.exitCode -ne 0) {
          throw "Valid smoke child '$scenario' was rejected: $failure"
        }
        if ($scenario -eq 'slow-launch' -and $status.launchMilliseconds -lt 1200) { throw 'Launch time was charged to the wrong budget.' }
      }
      { $_ -in @('launch-timeout', 'native-hang') } {
        if (!$failure -or !$status.timedOut -or $status.timeoutKind -ne 'launch' -or $null -ne $status.launchMilliseconds) {
          throw "Native launch deadline was not enforced in '$scenario'."
        }
        if ($scenario -eq 'native-hang' -and $status.lastStage -cne 'BILISAIL_NATIVE_STAGE:plugins-register') { throw 'Native startup stage was lost.' }
      }
      { $_ -in @('probe-timeout', 'duplicate-entry') } {
        if (!$failure -or !$status.timedOut -or $status.timeoutKind -ne 'probe' -or $status.acknowledged -or $null -eq $status.launchMilliseconds) {
          throw "Dart execution deadline was not enforced in '$scenario'."
        }
      }
      'failure' {
        if (!$failure -or $status.timedOut -or $status.exitCode -ne 7) { throw 'A failed child was accepted.' }
      }
      { $_ -in @('missing-ack', 'stderr-ack') } {
        if (!$failure -or $status.acknowledged -or $status.timedOut) { throw 'A missing stdout acknowledgement was accepted.' }
      }
      'no-entry' {
        if ($failure -notmatch 'exited before Dart entry' -or !$status.acknowledged) { throw 'A child without Dart entry was accepted.' }
      }
    }
  }
  Write-Output 'macOS smoke process supervision checks passed (10 cases).'
} finally {
  # Remove only the known fixture output and the directory created above.
  Remove-Item -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $smokeTestDirectory -Force
}
