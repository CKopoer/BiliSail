$script:BuildStageTimings = [System.Collections.Generic.List[object]]::new()
$script:BuildTimingFile = $null

function Save-BuildStageTimings {
  if (!$script:BuildTimingFile) { return }
  try {
    New-Item -ItemType Directory -Path (Split-Path $script:BuildTimingFile -Parent) -Force | Out-Null
    $json = ConvertTo-Json -InputObject @($script:BuildStageTimings.ToArray()) -Depth 4
    [IO.File]::WriteAllText($script:BuildTimingFile, $json + "`n")
  } catch { Write-Warning 'Could not save build timing diagnostics; preserving the build result.' }
}

function Invoke-BuildStage([string]$StageName, [scriptblock]$Action) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $succeeded = $false
  Write-Host "::group::$StageName"
  try {
    # Scriptblocks can read caller variables; do not shadow the package $name.
    & $Action
    $succeeded = $true
  } finally {
    $watch.Stop()
    $script:BuildStageTimings.Add([ordered]@{
      stage = $StageName; seconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3); success = $succeeded
    })
    Write-Host "$StageName finished in $([Math]::Round($watch.Elapsed.TotalSeconds, 1))s (success=$succeeded)"
    Write-Host '::endgroup::'
    Save-BuildStageTimings
  }
}
