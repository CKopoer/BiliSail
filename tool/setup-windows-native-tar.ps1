param(
  [Parameter(Mandatory)][string]$MsysRoot,
  [string]$ToolsDirectory = (Join-Path $PSScriptRoot '../build/tools/windows-native-tar')
)
$ErrorActionPreference = 'Stop'
$bin = [IO.Path]::GetFullPath((Join-Path $MsysRoot 'ucrt64/bin'))
$source = Join-Path $bin 'bsdtar.exe'
if (!(Test-Path -LiteralPath $source)) {
  throw 'Install mingw-w64-ucrt-x86_64-libarchive with the Windows mux toolchain.'
}
# The Windows Server 2022 inbox tar lacks the LZMA codec used by the pinned
# libmpv .7z. Give the unmodified Native Assets hook a codec-enabled tar.exe.
$tools = [IO.Path]::GetFullPath($ToolsDirectory)
New-Item -ItemType Directory -Path $tools -Force | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $tools 'tar.exe') -Force
$env:PATH = "$tools;$bin;$env:PATH"
if ($env:GITHUB_PATH) {
  $bin >> $env:GITHUB_PATH
  $tools >> $env:GITHUB_PATH
}
$version = & tar --version
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch 'liblzma') {
  throw "The selected native archive tool must support LZMA: $version"
}
Write-Output "Native Assets archive tool: $((Get-Command tar).Source)"
Write-Output $version
