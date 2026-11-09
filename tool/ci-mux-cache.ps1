param(
  [Parameter(Mandatory)][ValidateSet('windows-x64', 'windows-arm64', 'android-arm64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64')][string]$Target,
  [ValidateSet('Prepare', 'Validate')][string]$Mode = 'Prepare'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mux-cache.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$identityFile = Join-Path $repo "build/ci-mux/$Target/identity.txt"
$directory = Join-Path $repo "packages/bili_mux/native/prebuilt/$Target"
if ($Mode -eq 'Prepare') {
  if ($Target.StartsWith('windows-')) {
    . (Join-Path $PSScriptRoot 'windows-mux-toolchain.ps1')
    $spec = Get-WindowsMuxToolchain $repo $Target
    $toolchain = Get-WindowsMuxCacheToolchain $repo $Target
    "msystem=$($spec.msystem)" >> $env:GITHUB_OUTPUT
    "install=$($spec.install)" >> $env:GITHUB_OUTPUT
  } else {
    $toolchain = (& (Join-Path $PSScriptRoot 'build-download-mux.ps1') -Target $Target -Mode Identity) -join "`n"
  }
  $identity = Get-MuxCacheIdentity $repo $Target $toolchain
  New-Item -ItemType Directory -Path (Split-Path $identityFile -Parent) -Force | Out-Null
  [IO.File]::WriteAllText($identityFile, $identity)
  "key=bilisail-mux-v1-$Target-$identity" >> $env:GITHUB_OUTPUT
  "path=$directory" >> $env:GITHUB_OUTPUT
} else {
  $valid = $false
  if (Test-Path -LiteralPath (Join-Path $directory 'cache-manifest.json')) {
    try {
      Confirm-MuxSnapshot $directory $Target ([IO.File]::ReadAllText($identityFile))
      $valid = $true
    } catch { Write-Warning "Rebuilding invalid mux snapshot: $($_.Exception.Message)" }
  }
  if (!$valid) { Clear-MuxSnapshot $repo $Target }
  "valid=$($valid.ToString().ToLowerInvariant())" >> $env:GITHUB_OUTPUT
}
