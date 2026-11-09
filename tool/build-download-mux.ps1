param(
  [Parameter(Mandatory)][ValidateSet('windows-x64', 'windows-arm64', 'android-arm64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64')][string]$Target,
  [string]$MsysRoot = $(if ($env:BILI_MUX_MSYS_ROOT) { $env:BILI_MUX_MSYS_ROOT } else { 'C:\msys64' }),
  [string]$AndroidNdk,
  [ValidateSet('Build', 'Identity', 'Archive')][string]$Mode = 'Build'
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildScript = Join-Path $repoRoot 'packages/bili_mux/tool/build.sh'
$cacheEnabled = $Mode -eq 'Build' -and $env:BILISAIL_MUX_CACHE -eq 'true'
$publishCache = $cacheEnabled
$reuse = $false
if ($cacheEnabled) {
  . (Join-Path $PSScriptRoot 'mux-cache.ps1')
  $identity = [IO.File]::ReadAllText((Join-Path $repoRoot "build/ci-mux/$Target/identity.txt"))
  $component = Join-Path $repoRoot "packages/bili_mux/native/prebuilt/$Target"
  if (Test-Path -LiteralPath (Join-Path $component 'cache-manifest.json')) {
    try { Confirm-MuxSnapshot $component $Target $identity; $reuse = $true }
    catch { Write-Warning "Mux cache validation failed; rebuilding: $($_.Exception.Message)"; Clear-MuxSnapshot $repoRoot $Target }
  }
}
if ($IsWindows -and $Target.StartsWith('windows-') -and $reuse) {
  # A validated DLL needs only its matching source tarball for distribution.
  # Avoid installing MSYS2 or extracting all of FFmpeg on this path.
  . (Join-Path $PSScriptRoot 'mux-source.ps1')
  Save-VerifiedMuxSourceArchive $repoRoot | Out-Null
  if ($env:GITHUB_OUTPUT) { 'mux-ready=true' >> $env:GITHUB_OUTPUT }
  Write-Output "Reused verified mux component for $Target without installing MSYS2; source archive verified."
  return
}
$scriptMode = if ($reuse) { 'archive' } else { $Mode.ToLowerInvariant() }
if ($Target -eq 'android-arm64') {
  if (!$AndroidNdk) { $AndroidNdk = $env:ANDROID_NDK_HOME }
  if (!$AndroidNdk) {
    $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    $localProperties = Join-Path $repoRoot 'android/local.properties'
    if (!$sdkRoot -and (Test-Path -LiteralPath $localProperties)) {
      $sdkEntry = Get-Content -LiteralPath $localProperties | Where-Object { $_ -match '^sdk.dir=' } | Select-Object -First 1
      if ($sdkEntry) { $sdkRoot = $sdkEntry.Substring(8).Replace('\\', '\').Replace('\:', ':') }
    }
    if ($sdkRoot) { $AndroidNdk = Join-Path $sdkRoot 'ndk/28.2.13676358' }
  }
  if (!$AndroidNdk) { throw 'Set ANDROID_NDK_HOME or pass -AndroidNdk (NDK 28.2.13676358).' }
  $ndkProperties = Join-Path $AndroidNdk 'source.properties'
  if (!(Test-Path -LiteralPath $ndkProperties) -or
      !(Select-String -LiteralPath $ndkProperties -Pattern '^Pkg.Revision\s*=\s*28\.2\.13676358\s*$' -Quiet)) {
    throw 'The Download mux component uses fixed Android NDK 28.2.13676358.'
  }
  $env:ANDROID_NDK_HOME = [System.IO.Path]::GetFullPath($AndroidNdk)
}
if ($IsWindows) {
  if ($cacheEnabled -and $Target.StartsWith('windows-')) {
    . (Join-Path $PSScriptRoot 'windows-mux-toolchain.ps1')
    $installed = @(Get-WindowsMuxInstalledPackages $MsysRoot)
    $toolchainProvenance = $installed -join "`n"
    try { Confirm-WindowsMuxPackages (Get-WindowsMuxToolchain $repoRoot $Target) $installed }
    catch {
      # A repository toolchain update may still build a valid component. Never
      # publish it under the old locked identity; preserve the uncached build.
      $publishCache = $false
      Write-Warning "$($_.Exception.Message) Continuing without saving a mux snapshot."
    }
  }
  $bash = Join-Path $MsysRoot 'usr/bin/bash.exe'
  if (!(Test-Path -LiteralPath $bash)) {
    throw 'Install MSYS2 and make + mingw-w64-ucrt-x86_64-gcc, or pass -MsysRoot.'
  }
  $cygpath = Join-Path $MsysRoot 'usr/bin/cygpath.exe'
  $scriptPath = & $cygpath -u $buildScript
  if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the build script path.' }
  & $bash $scriptPath $Target $scriptMode
} else {
  & bash $buildScript $Target $scriptMode
}
if ($LASTEXITCODE -ne 0) {
  $buildDirectory = Join-Path $repoRoot "build/download_mux/$Target"
  foreach ($relativeLog in @('configure.log', 'ffbuild/config.log', 'build.log', 'link.log')) {
    $logPath = Join-Path $buildDirectory $relativeLog
    if (Test-Path -LiteralPath $logPath) {
      Write-Host "Download mux build diagnostics: $relativeLog"
      Get-Content -LiteralPath $logPath -Tail 80 | Write-Host
    }
  }
  throw "Download mux component build failed. Inspect build/download_mux/$Target/*.log."
}
if ($cacheEnabled) {
  if ($IsWindows -and $Target.StartsWith('windows-')) { [IO.File]::WriteAllText((Join-Path $component 'toolchain.txt'), $toolchainProvenance + "`n") }
  if ($reuse) { Write-Output "Reused verified mux component for $Target; source archive verified." }
  $ready = if ($reuse) { $true } elseif ($publishCache) { Write-MuxSnapshot $component $Target $identity } else { $false }
  if ($ready -and $env:GITHUB_OUTPUT) { 'mux-ready=true' >> $env:GITHUB_OUTPUT }
}
