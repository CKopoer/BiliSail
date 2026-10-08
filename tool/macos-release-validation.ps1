# This helper is also loaded by offline boundary tests on Windows/Linux.
function Confirm-MacOSReleaseEntitlements([string]$EntitlementsXml) {
  $document = [System.Xml.XmlDocument]::new()
  $document.XmlResolver = $null
  $document.LoadXml($EntitlementsXml)
  $dict = $document.SelectSingleNode('/plist/dict')
  if (!$dict) { throw 'Signed macOS entitlements must contain a plist dictionary.' }
  $nodes = @($dict.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
  $required = @('com.apple.security.app-sandbox', 'com.apple.security.network.client')
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
  if ($seen.Count -ne $required.Count) { throw 'Signed macOS entitlements are missing Sandbox or network access.' }
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
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) { throw "macOS Release smoke phase '$Phase' timed out." }
    $output = $outputTask.GetAwaiter().GetResult()
    $errors = $errorTask.GetAwaiter().GetResult()
    # Never persist raw native/network output, which can contain URL queries.
    $status = [ordered]@{
      phase = $Phase
      exitCode = $process.ExitCode
      acknowledged = "BILISAIL_RELEASE_SMOKE_OK:${Phase}:$RunId" -cin @($output -split '\r?\n')
      stderrPresent = ![string]::IsNullOrWhiteSpace($errors)
    }
    $status | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkingDirectory "$Phase.result.json") -Encoding utf8
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
    entitlements = 'sandbox-network-client-only'
    startup = 'first-frame-and-3-seconds'
    credentials = 'write-read-restart-read-delete-restart-absent'
  }
}
