# Retry only dependency transport failures, before any packaging or publishing.
function Invoke-BuildDependencyCommand {
  param(
    [Parameter(Mandatory)][string]$Executable,
    [string[]]$Parameters = @(),
    [ValidateRange(1, 3)][int]$MaxAttempts = 3,
    [ValidateRange(0, 30)][int]$RetryDelaySeconds = 5
  )
  $PSNativeCommandUseErrorActionPreference = $false
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $tail = [System.Collections.Generic.Queue[string]]::new()
    & $Executable @Parameters 2>&1 | ForEach-Object {
      $line = "$_"
      Write-Host $line
      $tail.Enqueue($line)
      if ($tail.Count -gt 2000) { $null = $tail.Dequeue() }
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { return }
    $log = $tail -join "`n"
    $integrityOrBuildError = $log -match '(?im)(?:SHA-?256|checksum|hash)[^\r\n]*(?:mismatch|failed|does not match)|^\s*(?:error:|[^\r\n]+:\d+(?::\d+)?: (?:fatal )?error:)|error [A-Z]+\d+|Error \(Xcode\)|framework [^\r\n]*not found|linker command failed'
    $downloadError = $log -match '(?im)HTTP response code said error|(?:HTTP (?:response|error)[^\r\n]*|Server returned HTTP response code: )50[0234]|curl: \((?:5|6|7|18|22|28|35|52|56)\)|(?:Failed to download|native download failed)|Connection (?:reset|timed out)|Could not resolve host'
    if ($attempt -eq $MaxAttempts -or $integrityOrBuildError -or !$downloadError) {
      throw "$Executable failed: $exitCode (attempt $attempt/$MaxAttempts)"
    }
    Write-Warning "Dependency download failed; retrying $Executable ($($attempt + 1)/$MaxAttempts)."
    Start-Sleep -Seconds ($RetryDelaySeconds * $attempt)
  }
}
