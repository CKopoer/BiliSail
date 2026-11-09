$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows-mux-toolchain.ps1')
. (Join-Path $PSScriptRoot 'mux-source.ps1')
. (Join-Path $PSScriptRoot 'mux-cache.ps1')
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$work = Join-Path $temporaryRoot "bilisail-windows-mux-$([guid]::NewGuid().ToString('N'))"
$previousExit = $global:LASTEXITCODE
$previousFlags = $env:CFLAGS

function Assert-MuxRejected([scriptblock]$Action, [string]$Message) {
  $failure = $null
  try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
  if (!$failure -or !$failure.Contains($Message)) { throw "Expected '$Message', got '$failure'." }
}

try {
  New-Item -ItemType Directory -Path (Join-Path $work 'tool'), (Join-Path $work 'packages/bili_mux/tool'),
    (Join-Path $work 'packages/bili_mux/native') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'tool/windows-mux-toolchains.json') -Destination (Join-Path $work 'tool')
  foreach ($target in @('windows-x64', 'windows-arm64')) {
    $spec = Get-WindowsMuxToolchain $work $target
    $installed = @($spec.packages.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" })
    Confirm-WindowsMuxPackages $spec $installed
    Assert-MuxRejected { Confirm-WindowsMuxPackages $spec ($installed | Where-Object { $_ -notlike 'make *' }) } 'toolchain drift'
    Assert-MuxRejected { Confirm-WindowsMuxPackages $spec ($installed -replace '^make .+$', 'make 0.0-1') } 'toolchain drift'
    $identity = Get-WindowsMuxCacheToolchain $work $target
    if ($identity -cne (Get-WindowsMuxCacheToolchain $work $target)) { throw 'Windows mux identity is not deterministic.' }
    $env:CFLAGS = "$previousFlags -DFIXTURE_CHANGED"
    if ($identity -ceq (Get-WindowsMuxCacheToolchain $work $target)) { throw 'Compiler flag changes reused the old mux identity.' }
    $env:CFLAGS = $previousFlags
  }
  if ((Get-WindowsMuxCacheToolchain $work 'windows-x64') -ceq (Get-WindowsMuxCacheToolchain $work 'windows-arm64')) {
    throw 'Windows mux architectures share a toolchain identity.'
  }
  $identity = Get-MuxCacheIdentity $repo 'windows-x64' (Get-WindowsMuxCacheToolchain $repo 'windows-x64')
  foreach ($relative in @('packages/bili_mux/tool/build.sh', 'packages/bili_mux/tool/package-apple-framework.sh',
      'tool/build-download-mux.ps1', 'tool/mux-cache.ps1', 'tool/mux-source.ps1', 'tool/windows-mux-toolchain.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination (Join-Path $work $relative)
  }
  Get-ChildItem -LiteralPath (Join-Path $repo 'packages/bili_mux/native') -File |
    Copy-Item -Destination (Join-Path $work 'packages/bili_mux/native')
  if ((Get-MuxCacheIdentity $work 'windows-x64' (Get-WindowsMuxCacheToolchain $work 'windows-x64')) -cne $identity) {
    throw 'The mux key depends on the checkout path.'
  }
  $lockPath = Join-Path $work 'tool/windows-mux-toolchains.json'
  $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable
  $lock.toolchains['windows-x64'].packages.make = '0.0-1'
  [IO.File]::WriteAllText($lockPath, ($lock | ConvertTo-Json -Depth 5))
  if ((Get-MuxCacheIdentity $work 'windows-x64' (Get-WindowsMuxCacheToolchain $work 'windows-x64')) -ceq $identity) {
    throw 'Changing the toolchain lock did not invalidate mux.'
  }

  # Exercise download, reuse and integrity failures without a shell/compiler.
  $payload = [Text.Encoding]::UTF8.GetBytes('fixed source fixture')
  $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
  [IO.File]::WriteAllText((Join-Path $work 'packages/bili_mux/tool/build.sh'), "version=n9.0.2`narchive_sha=$digest`n")
  $script:downloads = 0
  $script:downloadExit = 0
  $script:downloadBytes = $payload
  function curl.exe {
    $script:downloads++
    $outputIndex = [Array]::IndexOf($args, '--output')
    if ($outputIndex -lt 0) { throw 'Source download must use an explicit output file.' }
    [IO.File]::WriteAllBytes($args[$outputIndex + 1], $script:downloadBytes)
    $global:LASTEXITCODE = $script:downloadExit
  }
  $archive = Save-VerifiedMuxSourceArchive $work
  if ($script:downloads -ne 1 -or !(Test-Path -LiteralPath $archive)) { throw 'Verified source was not published.' }
  if ((Save-VerifiedMuxSourceArchive $work) -cne $archive -or $script:downloads -ne 1) { throw 'Source cache hit downloaded again.' }
  [IO.File]::WriteAllText($archive, 'corrupt')
  Assert-MuxRejected { Save-VerifiedMuxSourceArchive $work } 'hash mismatch'
  Remove-Item -LiteralPath $archive
  $script:downloadBytes = [byte[]]@(1, 2, 3)
  Assert-MuxRejected { Save-VerifiedMuxSourceArchive $work } 'hash mismatch'
  $script:downloadExit = 22
  Assert-MuxRejected { Save-VerifiedMuxSourceArchive $work } 'Could not download'
  if ((Test-Path -LiteralPath $archive) -or @(Get-ChildItem (Join-Path $work 'build/download_mux') -Filter '*.tmp').Count) {
    throw 'A failed source download left published or temporary bytes.'
  }
  Write-Output 'Windows mux toolchain and shell-free source checks passed.'
} finally {
  $env:CFLAGS = $previousFlags
  $global:LASTEXITCODE = $previousExit
  if (Test-Path Function:curl.exe) { Remove-Item Function:curl.exe }
  if ([IO.Path]::GetFullPath($work) -cne $work -or (Split-Path $work -Parent) -cne $temporaryRoot.TrimEnd([char[]]'\/') -or
      (Split-Path $work -Leaf) -notlike 'bilisail-windows-mux-*') { throw 'Unsafe mux test cleanup path.' }
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
