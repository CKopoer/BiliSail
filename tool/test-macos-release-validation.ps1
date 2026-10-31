$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'macos-release-validation.ps1')
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

# Use the actual JSON boundary: PowerShell turns an ISO string into DateTime,
# whose ordinary string conversion loses its UTC offset and precision.
$expectedStartedUtc = [DateTimeOffset]::Parse('2026-10-31T07:00:00.1234560+00:00')
$jsonStartedUtc = ('{"started":"' + $expectedStartedUtc.ToString('o') + '"}' | ConvertFrom-Json -AsHashtable).started
foreach ($timestamp in @($expectedStartedUtc, $expectedStartedUtc.UtcDateTime, $jsonStartedUtc, $expectedStartedUtc.ToString('o'))) {
  $roundtrip = ConvertTo-MacOSStackTimestamp $timestamp
  if ($roundtrip -notmatch '^2026-10-31T07:00:00\.1234560(Z|\+00:00)$' -or
      [DateTimeOffset]::Parse($roundtrip) -ne $expectedStartedUtc) {
    throw 'A parsed process timestamp lost its offset or fractional precision before stack collection.'
  }
}

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

# A synchronously completing reader must yield after bounded chunks even when
# there is no newline, then discard the entire oversized line before recovery.
$pipe = @{
  reader = [System.IO.StringReader]::new(('x' * 65536) + "$marker`n$marker`n")
  buffer = [char[]]::new(1024); closed = $false; present = $false
  pending = ''; discarding = $false; oversizedLines = 0
}
try {
  $pipe.task = $pipe.reader.ReadAsync($pipe.buffer, 0, $pipe.buffer.Length)
  if (@(Read-MacOSSmokePipe $pipe).Count -or $pipe.closed -or !$pipe.discarding -or $pipe.pending.Length -gt 512) {
    throw 'Unterminated output escaped the per-pass read and retention bounds.'
  }
  $lines = @()
  while (!$pipe.closed) { $lines += @(Read-MacOSSmokePipe $pipe) }
  if ($pipe.oversizedLines -ne 1 -or $lines.Count -ne 1 -or $lines[0] -cne $marker) {
    throw 'A discarded long-line suffix was accepted or the next complete line was lost.'
  }
} finally { $pipe.reader.Dispose() }

# Exercise real child processes: parser-only checks cannot detect conflated
# launch/probe deadlines, pipe deadlocks or acknowledgements on the wrong pipe.
$processFixture = Join-Path $PSScriptRoot 'fixtures/macos-smoke-process.ps1'
$pwsh = (Get-Process -Id $PID).Path
$smokeTestDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "bilisail smoke $([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $smokeTestDirectory | Out-Null
try {
  $scenarios = @('slow-launch', 'launch-timeout', 'native-hang', 'probe-timeout', 'duplicate-entry', 'failure', 'missing-ack', 'stderr-ack', 'no-entry', 'flood', 'unterminated-ack', 'unterminated-output', 'long-line-recovery')
  foreach ($scenario in $scenarios) {
    Remove-Item -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Force -ErrorAction SilentlyContinue
    $launchLimit = if ($scenario -eq 'launch-timeout') { 1 } elseif ($scenario -eq 'native-hang') { 3 } else { 10 }
    $probeLimit = if ($scenario -in @('slow-launch', 'probe-timeout', 'duplicate-entry', 'unterminated-output')) { 1 } else { 3 }
    $failure = $null
    try {
      Invoke-MacOSReleaseSmokePhase -Executable $pwsh -Phase 'verify-deleted' -RunId $runId `
        -WorkingDirectory $smokeTestDirectory -TimeoutSeconds $probeLimit -LaunchTimeoutSeconds $launchLimit `
        -LauncherArguments @('-NoProfile', '-File', $processFixture, $scenario)
    } catch { $failure = $_.Exception.Message }
    $json = Get-Content -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Raw
    $status = $json | ConvertFrom-Json
    if ($json -match 'private|https:|example.invalid') { throw "Raw child output leaked in scenario '$scenario'." }
    if ($status.supervisorTimedOut -or $status.supervisorTimeoutSeconds -ne $launchLimit + $probeLimit + 30) {
      throw "The independent supervisor did not preserve the phase budgets in '$scenario'."
    }
    if ($status.processId -le 0 -or ![DateTimeOffset]::Parse($status.processStartedUtc)) { throw 'Owned native process identity was not recorded.' }
    if ($status.workerProcessId -le 0 -or ![DateTimeOffset]::Parse($status.workerStartedUtc) -or $null -eq $status.workerExitCode) { throw 'Worker process identity or exit code was not recorded.' }
    switch ($scenario) {
      { $_ -in @('slow-launch', 'flood', 'long-line-recovery') } {
        if ($failure -or $status.timedOut -or !$status.acknowledged -or !$status.outputDrained -or $status.exitCode -ne 0) {
          throw "Valid smoke child '$scenario' was rejected: $failure"
        }
        if ($scenario -eq 'slow-launch' -and $status.launchMilliseconds -lt 1200) { throw 'Launch time was charged to the wrong budget.' }
        if ($scenario -eq 'long-line-recovery' -and ($status.oversizedLines -ne 2 -or 'BILISAIL_RELEASE_STAGE:window-ready' -cin @($status.stages.stage))) {
          throw 'An oversized line was retained or its apparently valid suffix was accepted.'
        }
      }
      { $_ -in @('launch-timeout', 'native-hang') } {
        if (!$failure -or !$status.timedOut -or $status.timeoutKind -ne 'launch' -or $null -ne $status.launchMilliseconds) {
          throw "Native launch deadline was not enforced in '$scenario'."
        }
        if ($scenario -eq 'native-hang' -and $status.lastStage -cne 'BILISAIL_NATIVE_STAGE:plugins-register') { throw 'Native startup stage was lost.' }
      }
      { $_ -in @('probe-timeout', 'duplicate-entry', 'unterminated-output') } {
        if (!$failure -or !$status.timedOut -or $status.timeoutKind -ne 'probe' -or $status.acknowledged -or $null -eq $status.launchMilliseconds) {
          throw "Dart execution deadline was not enforced in '$scenario'."
        }
        if ($scenario -eq 'unterminated-output' -and ($status.oversizedLines -lt 1 -or $status.lastStage -cne 'BILISAIL_FOCUS_STAGE:space')) {
          throw 'Unterminated output hid the last focus stage or escaped the line-size bound.'
        }
      }
      'failure' {
        if (!$failure -or $status.timedOut -or $status.exitCode -ne 7) { throw 'A failed child was accepted.' }
      }
      { $_ -in @('missing-ack', 'stderr-ack', 'unterminated-ack') } {
        if (!$failure -or $status.acknowledged -or $status.timedOut) { throw 'A missing stdout acknowledgement was accepted.' }
      }
      'no-entry' {
        if ($failure -notmatch 'exited before Dart entry' -or !$status.acknowledged) { throw 'A child without Dart entry was accepted.' }
      }
    }
  }
  # Observe a real worker's snapshot while its native child is still hung, then
  # end it using the independent parent deadline before the inner 60s timer.
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $pwsh
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $fixturePidPath = Join-Path $smokeTestDirectory 'child.pid'
  $start.Environment['BILISAIL_SMOKE_FIXTURE_PID_PATH'] = $fixturePidPath
  foreach ($argument in @(
    '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'macos-smoke-worker.ps1'),
    '-Executable', $pwsh, '-Phase', 'verify-deleted', '-RunId', $runId,
    '-WorkingDirectory', $smokeTestDirectory, '-TimeoutSeconds', '60', '-LaunchTimeoutSeconds', '10',
    '-LauncherArgumentsJson', (ConvertTo-Json -InputObject @('-NoProfile', '-File', $processFixture, 'unterminated-output') -Compress)
  )) { $start.ArgumentList.Add($argument) }
  $worker = [System.Diagnostics.Process]::new()
  $worker.StartInfo = $start
  $workerStarted = $false
  $child = $null
  try {
    Remove-Item -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Force
    $workerStarted = $worker.Start()
    $wait = [System.Diagnostics.Stopwatch]::StartNew()
    $observed = $false
    while ($wait.ElapsedMilliseconds -lt 5000 -and !$worker.HasExited) {
      $path = Join-Path $smokeTestDirectory 'verify-deleted.result.json'
      if (Test-Path -LiteralPath $path) {
        $progress = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($progress.lastStage -ceq 'BILISAIL_FOCUS_STAGE:space') { $observed = $true; break }
      }
      Start-Sleep -Milliseconds 20
    }
    if (!$observed -or $worker.HasExited) { throw 'A live worker did not publish its sanitized focus stage.' }
    $child = Get-Process -Id ([int](Get-Content -LiteralPath $fixturePidPath -Raw))
    $wait.Restart()
    if (!(Wait-MacOSSmokeSupervisor $worker 100) -or $wait.ElapsedMilliseconds -gt 5000 -or !$worker.HasExited -or !$child.WaitForExit(1000)) {
      throw 'The independent parent failed to terminate a stalled worker and its child.'
    }
    $progress = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($progress.lastStage -cne 'BILISAIL_FOCUS_STAGE:space') { throw 'Forced termination lost the last complete snapshot.' }
  } finally {
    if ($workerStarted -and !$worker.HasExited) { $worker.Kill($true); [void]$worker.WaitForExit(5000) }
    $worker.Dispose()
    if ($child) {
      if (!$child.HasExited) { $child.Kill(); [void]$child.WaitForExit(5000) }
      $child.Dispose()
    }
    Remove-Item -LiteralPath $fixturePidPath -Force -ErrorAction SilentlyContinue
  }
  Write-Output "macOS smoke process supervision checks passed ($($scenarios.Count + 1) cases)."
} finally {
  # Remove only the known fixture output and the directory created above.
  Remove-Item -LiteralPath (Join-Path $smokeTestDirectory 'verify-deleted.result.json') -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $smokeTestDirectory -Force
}
