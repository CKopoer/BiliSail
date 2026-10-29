param(
  [Parameter(Mandatory)][string]$MsysRoot
)
$ErrorActionPreference = 'Stop'
$bin = [IO.Path]::GetFullPath((Join-Path $MsysRoot 'ucrt64/bin'))
$source = Join-Path $bin 'bsdtar.exe'
if (!(Test-Path -LiteralPath $source)) {
  throw 'Install mingw-w64-ucrt-x86_64-libarchive with the Windows mux toolchain.'
}
# Windows process lookup can select System32 before PATH. Use an absolute path
# to warm the verified hook cache; never replace the inbox tar or the Dart SDK.
$env:BILISAIL_NATIVE_TAR = $source
if ($env:GITHUB_ENV) { "BILISAIL_NATIVE_TAR=$source" >> $env:GITHUB_ENV }
$version = & $source --version
if ($LASTEXITCODE -ne 0 -or "$version" -notmatch 'liblzma') {
  throw "The selected native archive tool must support LZMA: $version"
}
Write-Output "Native Assets archive tool: $source"
Write-Output $version
