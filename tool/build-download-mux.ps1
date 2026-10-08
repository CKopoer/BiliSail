param(
  [Parameter(Mandatory)][ValidateSet('windows-x64', 'android-arm64', 'macos-arm64', 'linux-x64')][string]$Target,
  [string]$MsysRoot = 'C:\msys64',
  [string]$AndroidNdk
)
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildScript = Join-Path $repoRoot 'packages/bili_mux/tool/build.sh'
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
    throw 'The MP4 component uses fixed Android NDK 28.2.13676358.'
  }
  $env:ANDROID_NDK_HOME = [System.IO.Path]::GetFullPath($AndroidNdk)
}
if ($IsWindows) {
  $bash = Join-Path $MsysRoot 'usr/bin/bash.exe'
  if (!(Test-Path -LiteralPath $bash)) {
    throw 'Install MSYS2 and make + mingw-w64-ucrt-x86_64-gcc, or pass -MsysRoot.'
  }
  $cygpath = Join-Path $MsysRoot 'usr/bin/cygpath.exe'
  $scriptPath = & $cygpath -u $buildScript
  if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the build script path.' }
  & $bash $scriptPath $Target
} else {
  & bash $buildScript $Target
}
if ($LASTEXITCODE -ne 0) {
  $buildDirectory = Join-Path $repoRoot "build/download_mux/$Target"
  foreach ($relativeLog in @('configure.log', 'ffbuild/config.log', 'build.log', 'link.log')) {
    $logPath = Join-Path $buildDirectory $relativeLog
    if (Test-Path -LiteralPath $logPath) {
      Write-Host "MP4 build diagnostics: $relativeLog"
      Get-Content -LiteralPath $logPath -Tail 80 | Write-Host
    }
  }
  throw "MP4 component build failed. Inspect build/download_mux/$Target/*.log."
}
