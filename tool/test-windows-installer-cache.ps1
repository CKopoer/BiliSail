# Linux-only fake native executable harness; real Windows packaging remains a CI build.
if (!$IsLinux) { Write-Host 'WiX cache shim tests require Linux; skipped.'; return }
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('wix-cache-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path "$fixture/tool" -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'windows-installers.ps1') "$fixture/tool/windows-installers.ps1"
. "$fixture/tool/windows-installers.ps1"
$originalWindows = $IsWindows
Set-Variable IsWindows $true -Force
function dotnet {
  $script:attempts++
  $directory = $args[[array]::IndexOf($args, '--tool-path') + 1]
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  if ($script:scenario -eq 'missing' -and $script:attempts -eq 1) {
    $global:LASTEXITCODE = 0
    return
  }
  $version = if ($script:attempts -eq 1) { '0.0.0' } else { '6.0.2+test' }
  "#!/bin/sh`necho '$version'`nexit 0`n" | Set-Content "$directory/wix.exe" -Encoding utf8NoBOM
  & /bin/chmod +x "$directory/wix.exe"
  $global:LASTEXITCODE = 0
}
try {
  foreach ($scenario in @('wrong-version', 'missing')) {
    $script:scenario = $scenario
    $script:attempts = 0
    $result = Initialize-WindowsInstallerTools "$fixture/$scenario/tools"
    if ($script:attempts -ne 2) { throw "Expected cold retry for $scenario" }
    if (!(Test-Path $result)) { throw 'No validated executable' }
  }
  Write-Host 'WiX cache tests passed: missing executable and wrong version recover via one cold retry.'
} finally {
  Set-Variable IsWindows $originalWindows -Force
  Remove-Item $fixture -Recurse -Force
}
