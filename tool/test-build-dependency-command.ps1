$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build-dependency-command.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "bilisail-download-retry-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $testRoot | Out-Null
$fixture = Join-Path $testRoot 'command.ps1'
@'
param([string]$StatePath, [string]$Message, [int]$Failures)
$count = if (Test-Path -LiteralPath $StatePath) { [int](Get-Content -LiteralPath $StatePath -Raw) + 1 } else { 1 }
Set-Content -LiteralPath $StatePath -Value $count
if ($count -le $Failures) { [Console]::Error.WriteLine($Message); exit 1 }
Write-Output 'Dependency command completed.'
exit 0
'@ | Set-Content -LiteralPath $fixture
$cases = @(
  @{ Message = 'success'; Failures = 0; Attempts = 1; Rejected = $false },
  @{ Message = 'Server returned HTTP response code: 504 for URL: https://example.invalid/gradle.zip'; Failures = 1; Attempts = 2; Rejected = $false },
  @{ Message = 'curl: (22) The requested URL returned error: 504'; Failures = 9; Attempts = 3; Rejected = $true },
  @{ Message = 'media-kit native download failed for https://example.invalid/ANGLE.7z: 22;"HTTP response code said error"'; Failures = 2; Attempts = 3; Rejected = $false },
  @{ Message = 'Failed to download https://example.invalid/mdk.tar.xz: "HTTP response code said error"'; Failures = 1; Attempts = 2; Rejected = $false },
  @{ Message = 'curl: (28) Operation timed out'; Failures = 1; Attempts = 2; Rejected = $false },
  @{ Message = 'curl: (22) HTTP error 504; SHA-256 mismatch'; Failures = 9; Attempts = 1; Rejected = $true },
  @{ Message = "curl: (22) HTTP error 504`nerror: invalid source code"; Failures = 9; Attempts = 1; Rejected = $true },
  @{ Message = "Failed to download unused optional file`nError (Xcode): Framework 'Mpv' not found"; Failures = 9; Attempts = 1; Rejected = $true },
  @{ Message = 'error C2065: undeclared identifier'; Failures = 9; Attempts = 1; Rejected = $true },
  @{ Message = 'Unknown build failure'; Failures = 9; Attempts = 1; Rejected = $true }
)
try {
  $index = 0
  foreach ($case in $cases) {
    $statePath = Join-Path $testRoot "$index.txt"
    $rejected = $false
    try {
      Invoke-BuildDependencyCommand (Get-Process -Id $PID).Path @('-NoProfile', '-File', $fixture, $statePath, $case.Message, "$($case.Failures)") -RetryDelaySeconds 0
    } catch { $rejected = $true }
    $attempts = [int](Get-Content -LiteralPath $statePath -Raw)
    if ($attempts -ne $case.Attempts -or $rejected -ne $case.Rejected) {
      throw "Wrong retry behavior for case ${index}: attempts=$attempts rejected=$rejected"
    }
    $index++
  }
} finally {
  Remove-Item -LiteralPath $fixture
  Get-ChildItem -LiteralPath $testRoot -Filter '*.txt' -File | Remove-Item
  Remove-Item -LiteralPath $testRoot
}
Write-Output "Dependency download retry checks passed: $($cases.Count)"
