# This helper is also loaded by offline boundary tests on Windows/Linux.
function Confirm-MacOSReleaseEntitlements([string]$EntitlementsXml) {
  $document = [System.Xml.XmlDocument]::new()
  $document.XmlResolver = $null
  $document.LoadXml($EntitlementsXml)
  $dict = $document.SelectSingleNode('/plist/dict')
  if (!$dict) { throw 'Signed macOS entitlements must contain a plist dictionary.' }
  $nodes = @($dict.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
  $required = @('com.apple.security.app-sandbox', 'com.apple.security.network.client', 'com.apple.security.assets.pictures.read-write')
  $seen = @()
  for ($index = 0; $index -lt $nodes.Count; $index += 2) {
    $key = $nodes[$index]
    if ($key.Name -ne 'key' -or $index + 1 -ge $nodes.Count) { throw 'Malformed signed macOS entitlements.' }
    if ($key.InnerText -notin $required -or $key.InnerText -in $seen) {
      throw "Unexpected or duplicate signed macOS entitlement: $($key.InnerText)"
    }
    if ($nodes[$index + 1].Name -ne 'true') { throw "Required entitlement is not enabled: $($key.InnerText)" }
    $seen += $key.InnerText
  }
  if ($seen.Count -ne $required.Count) { throw 'Signed macOS entitlements are missing Sandbox, network or Pictures access.' }
}

function Confirm-MacOSReleaseSignature([string]$App, [string]$WorkingDirectory) {
  & codesign --verify --deep --strict --verbose=2 $App
  if ($LASTEXITCODE -ne 0) { throw 'macOS application signature verification failed.' }
  $entitlements = & codesign --display --entitlements :- $App 2> (Join-Path $WorkingDirectory 'codesign-display.log')
  if ($LASTEXITCODE -ne 0) { throw 'Could not extract signed macOS entitlements.' }
  $xml = $entitlements -join "`n"
  Confirm-MacOSReleaseEntitlements $xml
  # Inspect the signed bundle, not just the source .entitlements file.
  [System.IO.File]::WriteAllText((Join-Path $WorkingDirectory 'signed-entitlements.plist'), $xml)
  if (Test-Path -LiteralPath (Join-Path $App 'Contents/embedded.provisionprofile')) {
    throw 'Ad-hoc macOS packages must not embed a machine-specific provisioning profile.'
  }
}

function Confirm-MacOSSmokeResult([int]$ExitCode, [string]$Output, [string]$Phase, [string]$RunId) {
  $marker = "BILISAIL_RELEASE_SMOKE_OK:${Phase}:$RunId"
  if ($ExitCode -ne 0 -or $marker -cnotin @($Output -split '\r?\n')) {
    throw "macOS Release smoke phase '$Phase' failed (exit $ExitCode or missing acknowledgement)."
  }
}

function Get-MacOSSmokeDiagnosticLines([string]$Text) {
  foreach ($line in ($Text -split '\r?\n')) {
    if ($line -cmatch '^BILISAIL_FOCUS_STAGE:(foreground|prepare|present|primary|space|passed)$' -or
        $line -cmatch '^BILISAIL_NATIVE_STAGE:(application|engine-create|plugins-register|plugins-ready|engine-run|engine-running)$' -or
        $line -cmatch '^BILISAIL_RELEASE_STAGE:(dart-entry|window-create|window-ready|dependencies|dependencies-ready|first-frame-wait|first-frame|playback-windows|credentials|closed)$' -or
        $line -cmatch '^BILISAIL_CREDENTIAL_STAGE:(empty|write-first|read-first|write-second|read-second|read-restart|delete|deleted|cleanup-bootstrap|cleanup-recommendation)$' -or
        $line -cmatch '^BILISAIL_RELEASE_SMOKE_FAILED:(startup|write|read-delete|verify-deleted|cleanup)$') {
      $Matches[0]
    } elseif ($line -cmatch 'BILISAIL_FOCUS_NATIVE revision=(\d+) active=([01]) key=([01]) view=(\d+|<null>) responder=[A-Za-z0-9_.]+ inView=([01])$') {
      "BILISAIL_FOCUS_NATIVE revision=$($Matches[1]) active=$($Matches[2]) key=$($Matches[3]) view=$($Matches[4]) inView=$($Matches[5])"
    }
  }
}

function Write-MacOSSmokeStatus([string]$Path, [System.Collections.IDictionary]$Status) {
  # A killed worker must leave either the previous complete snapshot or the new
  # one, never a partially written JSON document for the parent/artifact upload.
  $temporary = "$Path.new"
  [System.IO.File]::WriteAllText($temporary, ($Status | ConvertTo-Json -Depth 5))
  [System.IO.File]::Move($temporary, $Path, $true)
}

function Wait-MacOSSmokeSupervisor([System.Diagnostics.Process]$Process, [int]$TimeoutMilliseconds) {
  # This parent never reads redirected pipes or runs the probe loop. A wedged
  # reader, native child or worker teardown cannot prevent this deadline.
  $timedOut = !$Process.WaitForExit($TimeoutMilliseconds)
  if ($timedOut) {
    $Process.Kill($true)
    if (!$Process.WaitForExit(5000)) { throw 'macOS smoke supervisor did not stop after termination.' }
  }
  return $timedOut
}

function ConvertTo-MacOSStackTimestamp([object]$StartedUtc) {
  # ConvertFrom-Json automatically materializes ISO dates as DateTime. A
  # [string] parameter then formats them using the current culture and loses
  # both the timezone and fractional seconds before Python can match a report.
  if ($StartedUtc -is [DateTimeOffset]) { return $StartedUtc.ToUniversalTime().ToString('o') }
  if ($StartedUtc -is [DateTime]) { return $StartedUtc.ToUniversalTime().ToString('o') }
  if ($StartedUtc -is [string]) { return $StartedUtc }
  return $null
}

function Save-MacOSNativeStack {
  param(
    [ValidateSet('crash', 'sample')][string]$Mode,
    [int]$ProcessId, [object]$StartedUtc, [string]$Phase, [string]$WorkingDirectory,
    [ValidateSet('BiliSail', 'pwsh')][string]$ProcessName = 'BiliSail'
  )
  $StartedUtc = ConvertTo-MacOSStackTimestamp $StartedUtc
  if (!$IsMacOS -or $ProcessId -le 0 -or !$StartedUtc) { return }
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'python3'
  $start.UseShellExecute = $false
  $name = if ($ProcessName -eq 'pwsh') { "$Phase.worker.$Mode.json" } else { "$Phase.$Mode.json" }
  foreach ($argument in @(
    (Join-Path $PSScriptRoot 'macos_crash_diagnostics.py'), '--mode', $Mode,
    '--pid', "$ProcessId", '--started', $StartedUtc, '--phase', $Phase, '--process-name', $ProcessName,
    '--output', (Join-Path $WorkingDirectory $name)
  )) { $start.ArgumentList.Add($argument) }
  $collector = [System.Diagnostics.Process]::new()
  $collector.StartInfo = $start
  $launched = $false
  try {
    $launched = $collector.Start()
    if (!$launched -or !$collector.WaitForExit(25000)) {
      Write-Warning 'macOS stack collection did not finish within its deadline.'
    } elseif ($collector.ExitCode -ne 0) {
      Write-Warning 'macOS stack collection failed; the original smoke failure is preserved.'
    }
  } catch {
    # Diagnostics must not replace the application failure or expose a raw
    # native/Python exception, which may contain paths or app-specific data.
    Write-Warning 'macOS stack collector could not run; the original smoke failure is preserved.'
  } finally {
    if ($launched -and !$collector.HasExited) { $collector.Kill($true); [void]$collector.WaitForExit(5000) }
    $collector.Dispose()
  }
}

function Invoke-MacOSReleaseSmokePhase {
  param(
    [string]$Executable, [string]$Phase, [string]$RunId, [string]$WorkingDirectory,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 60,
    [ValidateRange(1, 300)][int]$LaunchTimeoutSeconds = 180,
    [string[]]$LauncherArguments = @()
  )
  $resultPath = Join-Path $WorkingDirectory "$Phase.result.json"
  $status = [ordered]@{ phase = $Phase; timedOut = $false; timeoutKind = $null; acknowledged = $false; lastStage = $null }
  Write-MacOSSmokeStatus $resultPath $status
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = (Get-Process -Id $PID).Path
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  # Inherit only the worker's sanitized console output. No parent pipe reader
  # shares the worker's timer or can wait for a native child's newline/EOF.
  foreach ($argument in @(
    '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'macos-smoke-worker.ps1'),
    '-Executable', $Executable, '-Phase', $Phase, '-RunId', $RunId,
    '-WorkingDirectory', $WorkingDirectory, '-TimeoutSeconds', "$TimeoutSeconds",
    '-LaunchTimeoutSeconds', "$LaunchTimeoutSeconds", '-LauncherArgumentsJson', (ConvertTo-Json -InputObject @($LauncherArguments) -Compress)
  )) { $start.ArgumentList.Add($argument) }
  $worker = [System.Diagnostics.Process]::new()
  $worker.StartInfo = $start
  # Include worker startup, bounded live sampling, and stop/drain budgets.
  $supervisorTimeoutSeconds = $LaunchTimeoutSeconds + $TimeoutSeconds + 30
  $clock = [System.Diagnostics.Stopwatch]::StartNew()
  $started = $false
  $workerStartedUtc = [DateTimeOffset]::UtcNow.ToString('o')
  try {
    $started = $worker.Start()
    if (!$started) { throw 'Could not launch the macOS smoke supervisor.' }
    $timedOut = Wait-MacOSSmokeSupervisor $worker ($supervisorTimeoutSeconds * 1000)
    $status = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -AsHashtable
    $status.supervisorTimeoutSeconds = $supervisorTimeoutSeconds
    $status.supervisorElapsedMilliseconds = $clock.ElapsedMilliseconds
    $status.supervisorTimedOut = $timedOut
    $status.workerProcessId = $worker.Id
    $status.workerStartedUtc = $workerStartedUtc
    $status.workerExitCode = $worker.ExitCode
    if ($timedOut) {
      $status.timedOut = $true
      $status.timeoutKind = 'supervisor'
      $status.acknowledged = $false
    }
    Write-MacOSSmokeStatus $resultPath $status
    Write-Host "macOS smoke worker '$Phase' exited with code $($worker.ExitCode)."
    if (!$timedOut -and $worker.ExitCode -in @(132, 133, 134, 135, 136, 138, 139)) {
      Save-MacOSNativeStack -Mode crash -ProcessName pwsh -ProcessId $worker.Id -StartedUtc $workerStartedUtc -Phase $Phase -WorkingDirectory $WorkingDirectory
    }
    if (!$status.timedOut -and $status.exitCode -in @(132, 133, 134, 135, 136, 138, 139)) {
      Save-MacOSNativeStack -Mode crash -ProcessId $status.processId -StartedUtc $status.processStartedUtc -Phase $Phase -WorkingDirectory $WorkingDirectory
    }
    if ($timedOut) { throw "macOS Release smoke phase '$Phase' supervisor timed out (last stage: $($status.lastStage))." }
    if ($worker.ExitCode -ne 0) {
      if (!$status.timedOut -and $status.Contains('launchMilliseconds') -and $null -eq $status.launchMilliseconds) {
        throw "macOS Release smoke phase '$Phase' exited before Dart entry."
      }
      throw "macOS Release smoke phase '$Phase' failed (last stage: $($status.lastStage), timeout: $($status.timeoutKind))."
    }
    if ($status.timedOut -or !$status.outputDrained -or $null -eq $status.launchMilliseconds) {
      throw "macOS Release smoke phase '$Phase' has an incomplete supervisor result."
    }
    $marker = if ($status.acknowledged) { "BILISAIL_RELEASE_SMOKE_OK:${Phase}:$RunId" } else { '' }
    Confirm-MacOSSmokeResult $status.exitCode $marker $Phase $RunId
  } finally {
    if ($started -and !$worker.HasExited) { $worker.Kill($true); [void]$worker.WaitForExit(5000) }
    $worker.Dispose()
  }
}

function Read-MacOSSmokePipe([hashtable]$Pipe) {
  # ReadLineAsync has no line-size bound and can keep consuming a continuously
  # available unterminated line before returning control to its caller. Fixed
  # chunks bound both synchronous work and retained text in every pass.
  for ($index = 0; $index -lt 16 -and !$Pipe.closed -and $Pipe.task.IsCompleted; $index++) {
    $count = $Pipe.task.GetAwaiter().GetResult()
    if ($count -eq 0) { $Pipe.closed = $true; break }
    $text = [string]::new($Pipe.buffer, 0, $count)
    if (![string]::IsNullOrWhiteSpace($text)) { $Pipe.present = $true }
    $parts = $text -split '\r\n|\r|\n'
    for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
      if (!$Pipe.discarding) {
        if ($Pipe.pending.Length + $parts[$partIndex].Length -le 512) {
          $Pipe.pending += $parts[$partIndex]
        } else {
          $Pipe.pending = ''
          $Pipe.discarding = $true
          $Pipe.oversizedLines++
        }
      }
      if ($partIndex -lt $parts.Count - 1) {
        if (!$Pipe.discarding -and $Pipe.pending.Length) { $Pipe.pending }
        $Pipe.pending = ''
        $Pipe.discarding = $false
      }
    }
    $Pipe.task = $Pipe.reader.ReadAsync($Pipe.buffer, 0, $Pipe.buffer.Length)
  }
}

function Invoke-MacOSReleaseSmokePhaseCore {
  param(
    [string]$Executable, [string]$Phase, [string]$RunId, [string]$WorkingDirectory,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 60,
    [ValidateRange(1, 300)][int]$LaunchTimeoutSeconds = 180,
    # Offline tests run the same process supervisor against a pwsh fixture.
    [string[]]$LauncherArguments = @()
  )
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $Executable
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @($LauncherArguments) + @('--bilisail-release-smoke', $Phase, $RunId)) { $start.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $start
  $started = $false
  $startedUtc = [DateTimeOffset]::UtcNow.ToString('o')
  $clock = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $started = $process.Start()
    if (!$started) { throw 'Could not launch the macOS Release application.' }
    $processStartedMilliseconds = $clock.ElapsedMilliseconds
    Write-Host "macOS Release smoke phase '$Phase' launched."
    $resultPath = Join-Path $WorkingDirectory "$Phase.result.json"
    $progress = [ordered]@{ phase = $Phase; processId = $process.Id; processStartedUtc = $startedUtc; timedOut = $false; timeoutKind = $null; acknowledged = $false; lastStage = $null; stages = @() }
    Write-MacOSSmokeStatus $resultPath $progress
    # Raw output stays in bounded memory; only complete, whitelisted lines can
    # update a diagnostic snapshot or acknowledge the probe.
    $pipes = @(
      @{ reader = $process.StandardOutput; buffer = [char[]]::new(1024); closed = $false; stderr = $false; present = $false; pending = ''; discarding = $false; oversizedLines = 0 }
      @{ reader = $process.StandardError; buffer = [char[]]::new(1024); closed = $false; stderr = $true; present = $false; pending = ''; discarding = $false; oversizedLines = 0 }
    )
    foreach ($pipe in $pipes) { $pipe.task = $pipe.reader.ReadAsync($pipe.buffer, 0, $pipe.buffer.Length) }
    $marker = "BILISAIL_RELEASE_SMOKE_OK:${Phase}:$RunId"
    $acknowledged = $false
    $stderrPresent = $false
    $dartEntryMilliseconds = $null
    $lastStage = $null
    $stages = [System.Collections.Generic.List[object]]::new()
    $diagnosticCount = 0
    $timedOut = $false
    $timeoutKind = $null
    $exitedAt = $null
    while ($true) {
      foreach ($pipe in $pipes) {
        foreach ($line in @(Read-MacOSSmokePipe $pipe)) {
          if (!$pipe.stderr -and $line -ceq $marker) { $acknowledged = $true }
          foreach ($diagnostic in @(Get-MacOSSmokeDiagnosticLines $line)) {
            if ($diagnostic -ceq 'BILISAIL_RELEASE_STAGE:dart-entry' -and $null -eq $dartEntryMilliseconds) {
              $dartEntryMilliseconds = $clock.ElapsedMilliseconds
            }
            if ($diagnosticCount -lt 128) {
              Write-Host "macOS smoke '$Phase' +$($clock.ElapsedMilliseconds)ms $diagnostic"
              $diagnosticCount++
            }
            if ($diagnostic -cmatch '^BILISAIL_(NATIVE|RELEASE|CREDENTIAL|FOCUS)_STAGE:') {
              $lastStage = $diagnostic
              if ($stages.Count -lt 128) {
                $stages.Add([ordered]@{ stage = $diagnostic; elapsedMilliseconds = $clock.ElapsedMilliseconds })
                $progress.lastStage = $lastStage
                $progress.stages = $stages.ToArray()
                Write-MacOSSmokeStatus $resultPath $progress
              }
            }
          }
        }
        if ($pipe.stderr -and $pipe.present) { $stderrPresent = $true }
      }
      if ($process.HasExited) {
        if ($null -eq $exitedAt) { $exitedAt = $clock.ElapsedMilliseconds }
        if ($pipes[0].closed -and $pipes[1].closed) { break }
        # Descendants must not hold inherited pipes open indefinitely either.
        if ($clock.ElapsedMilliseconds - $exitedAt -ge 5000) { break }
      } elseif (!$timedOut) {
        if ($null -eq $dartEntryMilliseconds -and $clock.ElapsedMilliseconds -ge $LaunchTimeoutSeconds * 1000) {
          $timeoutKind = 'launch'
        } elseif ($null -ne $dartEntryMilliseconds -and $clock.ElapsedMilliseconds - $dartEntryMilliseconds -ge $TimeoutSeconds * 1000) {
          $timeoutKind = 'probe'
        }
        if ($null -ne $timeoutKind) {
          $timedOut = $true
          Write-Host "macOS smoke '$Phase' timed out during $timeoutKind (last stage: $lastStage)."
          $progress.timedOut = $true
          $progress.timeoutKind = $timeoutKind
          Write-MacOSSmokeStatus $resultPath $progress
          Save-MacOSNativeStack -Mode sample -ProcessId $process.Id -StartedUtc $startedUtc -Phase $Phase -WorkingDirectory $WorkingDirectory
          $process.Kill($true)
          if (!$process.WaitForExit(5000)) { throw 'macOS smoke child did not stop after termination.' }
        }
      }
      [System.Threading.Thread]::Sleep(10)
    }
    $outputDrained = $pipes[0].closed -and $pipes[1].closed
    $status = [ordered]@{
      phase = $Phase
      processId = $process.Id
      processStartedUtc = $startedUtc
      timedOut = $timedOut
      timeoutKind = $timeoutKind
      exitCode = $process.ExitCode
      acknowledged = $acknowledged
      stderrPresent = $stderrPresent
      outputDrained = $outputDrained
      oversizedLines = $pipes[0].oversizedLines + $pipes[1].oversizedLines
      lastStage = $lastStage
      processStartMilliseconds = $processStartedMilliseconds
      launchMilliseconds = $dartEntryMilliseconds
      probeMilliseconds = if ($null -ne $dartEntryMilliseconds) { $clock.ElapsedMilliseconds - $dartEntryMilliseconds } else { $null }
      launchTimeoutSeconds = $LaunchTimeoutSeconds
      probeTimeoutSeconds = $TimeoutSeconds
      elapsedMilliseconds = $clock.ElapsedMilliseconds
      stages = $stages.ToArray()
    }
    Write-MacOSSmokeStatus $resultPath $status
    if ($timedOut) { throw "macOS Release smoke phase '$Phase' timed out during $timeoutKind (last stage: $lastStage)." }
    if (!$outputDrained) { throw "macOS Release smoke phase '$Phase' did not close its output pipes." }
    if ($null -eq $dartEntryMilliseconds) { throw "macOS Release smoke phase '$Phase' exited before Dart entry." }
    $confirmation = if ($acknowledged) { $marker } else { '' }
    Confirm-MacOSSmokeResult $process.ExitCode $confirmation $Phase $RunId
    Write-Host "macOS Release smoke phase '$Phase' passed."
  } finally {
    # Only stop the exact child process created above, never an existing app.
    if ($started -and !$process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(5000) }
    $process.Dispose()
  }
}

function Test-MacOSReleaseApp([string]$App, [string]$WorkingDirectory) {
  New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
  Confirm-MacOSReleaseSignature $App $WorkingDirectory
  $executable = Join-Path $App 'Contents/MacOS/BiliSail'
  if (!(Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'macOS Release executable is missing.' }
  $runId = [guid]::NewGuid().ToString('N')
  $passed = $false
  try {
    foreach ($phase in @('startup', 'write', 'read-delete', 'verify-deleted')) {
      Invoke-MacOSReleaseSmokePhase $executable $phase $runId $WorkingDirectory
    }
    $passed = $true
  } finally {
    if (!$passed) {
      try { Invoke-MacOSReleaseSmokePhase $executable 'cleanup' $runId $WorkingDirectory } catch {
        Write-Warning 'Isolated macOS smoke keys could not be cleaned up; inspect the failed probe on this runner.'
      }
    }
  }
  # Recheck after execution before building the DMG.
  Confirm-MacOSReleaseSignature $App $WorkingDirectory
  return [ordered]@{
    signature = 'passed'
    entitlements = 'sandbox-network-client-pictures-only'
    startup = 'first-frame-and-3-seconds'
    credentials = 'write-read-restart-read-delete-restart-absent'
  }
}
