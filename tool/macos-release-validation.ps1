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
        $line -cmatch '^BILISAIL_RELEASE_STAGE:(window-create|window-ready|dependencies|dependencies-ready|first-frame-wait|first-frame|playback-windows|credentials|closed)$' -or
        $line -cmatch '^BILISAIL_RELEASE_SMOKE_FAILED:(startup|write|read-delete|verify-deleted|cleanup)$') {
      $Matches[0]
    } elseif ($line -cmatch 'BILISAIL_FOCUS_NATIVE revision=(\d+) active=([01]) key=([01]) view=(\d+|<null>) responder=[A-Za-z0-9_.]+ inView=([01])$') {
      "BILISAIL_FOCUS_NATIVE revision=$($Matches[1]) active=$($Matches[2]) key=$($Matches[3]) view=$($Matches[4]) inView=$($Matches[5])"
    }
  }
}

function Invoke-MacOSReleaseSmokePhase {
  param(
    [string]$Executable, [string]$Phase, [string]$RunId, [string]$WorkingDirectory,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 60
  )
  $start = [System.Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $Executable
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @('--bilisail-release-smoke', $Phase, $RunId)) { $start.ArgumentList.Add($argument) }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $start
  $started = $false
  try {
    $started = $process.Start()
    if (!$started) { throw 'Could not launch the macOS Release application.' }
    # Drain both pipes while waiting so native output cannot deadlock the probe.
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    $timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill(); $process.WaitForExit() }
    $output = $outputTask.GetAwaiter().GetResult()
    $errors = $errorTask.GetAwaiter().GetResult()
    # Export only the fixed smoke stages and numeric native focus state.
    # Discard responder names and every other native/network output field.
    Get-MacOSSmokeDiagnosticLines ($output + "`n" + $errors) | ForEach-Object { Write-Host $_ }
    # Never persist raw native/network output, which can contain URL queries.
    $status = [ordered]@{
      phase = $Phase
      timedOut = $timedOut
      exitCode = $process.ExitCode
      acknowledged = "BILISAIL_RELEASE_SMOKE_OK:${Phase}:$RunId" -cin @($output -split '\r?\n')
      stderrPresent = ![string]::IsNullOrWhiteSpace($errors)
    }
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkingDirectory "$Phase.result.json") -Encoding utf8
    if ($timedOut) { throw "macOS Release smoke phase '$Phase' timed out." }
    Confirm-MacOSSmokeResult $process.ExitCode $output $Phase $RunId
    Write-Host "macOS Release smoke phase '$Phase' passed."
  } finally {
    # Only stop the exact child process created above, never an existing app.
    if ($started -and !$process.HasExited) { $process.Kill(); $process.WaitForExit() }
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
