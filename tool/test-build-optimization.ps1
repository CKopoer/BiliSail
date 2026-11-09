$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mux-cache.ps1')
. (Join-Path $PSScriptRoot 'build-stage.ps1')
$testRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) "bilisail-build-optimization-$([guid]::NewGuid().ToString('N'))"))

function Assert-BuildRejected([scriptblock]$Action, [string]$Message) {
  $errorText = $null
  try { & $Action | Out-Null } catch { $errorText = $_.Exception.Message }
  if (!$errorText -or !$errorText.Contains($Message)) { throw "Expected '$Message', got '$errorText'." }
}

try {
  $source = Join-Path $testRoot 'source'
  $native = Join-Path $source 'packages/bili_mux/native'
  New-Item -ItemType Directory -Path $native -Force | Out-Null
  foreach ($path in @('packages/bili_mux/tool/build.sh', 'packages/bili_mux/tool/package-apple-framework.sh',
      'tool/build-download-mux.ps1', 'tool/mux-cache.ps1', 'packages/bili_mux/native/bili_mux.cpp')) {
    $file = Join-Path $source $path
    New-Item -ItemType Directory -Path (Split-Path $file -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($file, 'source-v1')
  }
  $identity = Get-MuxCacheIdentity $source 'linux-x64' 'compiler-v1/sdk-v1'
  if ($identity -cne (Get-MuxCacheIdentity $source 'linux-x64' 'compiler-v1/sdk-v1')) { throw 'Mux identity is not deterministic.' }
  foreach ($different in @(
    (Get-MuxCacheIdentity $source 'linux-x64' 'compiler-v2/sdk-v1'),
    (Get-MuxCacheIdentity $source 'linux-x64' 'compiler-v1/sdk-v2'),
    (Get-MuxCacheIdentity $source 'android-arm64' 'compiler-v1/sdk-v1'))) {
    if ($different -ceq $identity) { throw 'An incompatible mux toolchain or target reused the same key.' }
  }
  [IO.File]::WriteAllText((Join-Path $native 'bili_mux.cpp'), 'source-v2')
  if ((Get-MuxCacheIdentity $source 'linux-x64' 'compiler-v1/sdk-v1') -ceq $identity) { throw 'Native source changes did not invalidate mux.' }

  $snapshot = Join-Path $native 'prebuilt/linux-x64'
  New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
  foreach ($name in @('configure.log', 'COPYING.LGPLv2.1', 'source.txt')) { [IO.File]::WriteAllText((Join-Path $snapshot $name), $name) }
  $elf = [byte[]]::new(24)
  [BitConverter]::GetBytes([uint32]0x464c457f).CopyTo($elf, 0)
  $elf[4] = 2; $elf[5] = 1
  [BitConverter]::GetBytes([uint16]62).CopyTo($elf, 18)
  $binary = Join-Path $snapshot 'libbili_mux.so'
  [IO.File]::WriteAllBytes($binary, $elf)
  if (!(Write-MuxSnapshot $snapshot 'linux-x64' $identity)) { throw 'Valid mux snapshot was not sealed.' }
  Confirm-MuxSnapshot $snapshot 'linux-x64' $identity
  Assert-BuildRejected { Confirm-MuxSnapshot $snapshot 'linux-x64' ('0' * 64) } 'identity mismatch'
  $elf[23] = 1
  [IO.File]::WriteAllBytes($binary, $elf)
  Assert-BuildRejected { Confirm-MuxSnapshot $snapshot 'linux-x64' $identity } 'digest mismatch'
  $elf[23] = 0
  [IO.File]::WriteAllBytes($binary, $elf)
  $license = Join-Path $snapshot 'COPYING.LGPLv2.1'
  Remove-Item -LiteralPath $license
  Assert-BuildRejected { Confirm-MuxSnapshot $snapshot 'linux-x64' $identity } 'file set mismatch'
  [IO.File]::WriteAllText($license, 'COPYING.LGPLv2.1')
  $extra = Join-Path $snapshot 'unexpected.dll'
  [IO.File]::WriteAllText($extra, 'foreign file')
  Assert-BuildRejected { Confirm-MuxSnapshot $snapshot 'linux-x64' $identity } 'file set mismatch'
  Remove-Item -LiteralPath $extra
  [BitConverter]::GetBytes([uint16]183).CopyTo($elf, 18)
  [IO.File]::WriteAllBytes($binary, $elf)
  Assert-BuildRejected { Write-MuxSnapshot $snapshot 'linux-x64' $identity } 'ELF architecture mismatch'
  Assert-BuildRejected { Clear-MuxSnapshot $source '../outside' } 'Invalid mux target'
  Clear-MuxSnapshot $source 'linux-x64'
  if (Test-Path -LiteralPath $snapshot) { throw 'Invalid snapshot was not removed.' }

  foreach ($target in @('windows-x64', 'windows-arm64', 'linux-x64', 'android-arm64', 'macos-arm64', 'macos-x64', 'ios-arm64')) {
    $directory = Join-Path $testRoot "formats/$target"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    foreach ($name in @('configure.log', 'COPYING.LGPLv2.1', 'source.txt')) { [IO.File]::WriteAllText((Join-Path $directory $name), $name) }
    $isX64 = $target.EndsWith('-x64')
    if ($target.StartsWith('windows-')) {
      $bytes = [byte[]]::new(134)
      [BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes, 0)
      [BitConverter]::GetBytes([uint32]128).CopyTo($bytes, 60)
      [BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes, 128)
      $machine = if ($isX64) { 0x8664 } else { 0xaa64 }
      [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 132)
      $binaryName = 'bili_mux.dll'
      foreach ($name in @('bili_mux.LGPL.txt', 'bili_mux.source.txt', 'bili_mux.configuration.txt', 'toolchain.txt')) { [IO.File]::WriteAllText((Join-Path $directory $name), $name) }
    } elseif ($target.StartsWith('macos-') -or $target.StartsWith('ios-')) {
      $bytes = [byte[]]::new(24)
      [BitConverter]::GetBytes([uint32]4277009103).CopyTo($bytes, 0)
      $cpu = if ($isX64) { 0x01000007 } else { 0x0100000c }
      [BitConverter]::GetBytes([uint32]$cpu).CopyTo($bytes, 4)
      $binaryName = 'BiliMux.framework/BiliMux'
      New-Item -ItemType Directory -Path (Join-Path $directory 'BiliMux.framework') | Out-Null
      [IO.File]::WriteAllText((Join-Path $directory 'BiliMux.framework/Info.plist'), 'fixture plist')
    } else {
      $bytes = [byte[]]::new(24)
      [BitConverter]::GetBytes([uint32]0x464c457f).CopyTo($bytes, 0)
      $bytes[4] = 2; $bytes[5] = 1
      $machine = if ($isX64) { 62 } else { 183 }
      [BitConverter]::GetBytes([uint16]$machine).CopyTo($bytes, 18)
      $binaryName = 'libbili_mux.so'
    }
    [IO.File]::WriteAllBytes((Join-Path $directory $binaryName), $bytes)
    if (!(Write-MuxSnapshot $directory $target $identity)) { throw "Could not seal $target fixture." }
    Confirm-MuxSnapshot $directory $target $identity
  }

  $script:BuildTimingFile = Join-Path $testRoot 'timings.json'
  $result = Invoke-BuildStage 'success fixture' { 'preserved return value' }
  if ($result -cne 'preserved return value') { throw 'Timing wrapper changed command output.' }
  Assert-BuildRejected { Invoke-BuildStage 'failure fixture' { throw 'original build failure' } } 'original build failure'
  $timings = @(Get-Content -LiteralPath $script:BuildTimingFile -Raw | ConvertFrom-Json)
  if ($timings.Count -ne 2 -or $timings[0].stage -cne 'success fixture' -or
      $timings[1].stage -cne 'failure fixture' -or !$timings[0].success -or
      $timings[1].success -or $timings[1].seconds -lt 0) {
    throw 'Stage timings did not preserve success/failure results.'
  }

  # Run the production archive stage against tiny sources. A wrapper parameter
  # must not shadow the caller's package name when the scriptblock reads it.
  $releaseAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'build-release.ps1'), [ref]$null, [ref]$null)
  $archiveStages = @($releaseAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.CommandAst] -and
      $node.GetCommandName() -eq 'Invoke-BuildStage' -and
      $node.CommandElements[1].Value -eq 'Mux source archive'
  }, $true))
  if ($archiveStages.Count -ne 1) { throw 'Expected one production mux archive stage.' }
  $archiveAction = $archiveStages[0].CommandElements[2].ScriptBlock.GetScriptBlock()
  foreach ($relativePath in @('packages/bili_mux/README.md', 'packages/bili_mux/LICENSE-FFmpeg.txt',
      'build/download_mux/n9.0.2.tar.gz')) {
    $fixtureFile = Join-Path $source $relativePath
    New-Item -ItemType Directory -Path (Split-Path $fixtureFile -Parent) -Force | Out-Null
    [IO.File]::WriteAllText($fixtureFile, 'archive fixture')
  }
  $mergedArchives = Join-Path $testRoot 'release-assets'
  New-Item -ItemType Directory -Path $mergedArchives | Out-Null
  $archiveTargets = @('android-arm64', 'windows-x64', 'windows-arm64', 'macos-arm64', 'macos-x64', 'ios-arm64', 'linux-x64')
  Push-Location $source
  try {
    foreach ($archiveTarget in $archiveTargets) {
      & {
        param($Target)
        $Version = '1.2.9+0'
        $name = "BiliSail-$Version-$Target"
        $outputRoot = Join-Path $testRoot "archives/$Target"
        $releaseDir = Join-Path $outputRoot 'release'
        $isWindowsTarget = $Target.StartsWith('windows-')
        $configuration = Join-Path $native "prebuilt/$Target/configure.log"
        New-Item -ItemType Directory -Path $releaseDir, (Split-Path $configuration -Parent) -Force | Out-Null
        [IO.File]::WriteAllText($configuration, $Target)
        Invoke-BuildStage 'Mux source archive' $archiveAction
        $expectedName = "$name.mux-source.zip"
        $files = @(Get-ChildItem -LiteralPath $releaseDir -File)
        if ($files.Count -ne 1 -or $files[0].Name -cne $expectedName) {
          throw "Incorrect mux archive name for ${Target}: $($files.Name -join ', '). Expected $expectedName."
        }
        $archive = [IO.Compression.ZipFile]::OpenRead($files[0].FullName)
        try {
          $reader = [IO.StreamReader]::new($archive.GetEntry('configure.log').Open())
          try {
            if ($reader.ReadToEnd() -cne $Target) { throw 'Mux archive contains another target configuration.' }
          } finally { $reader.Dispose() }
        } finally { $archive.Dispose() }
        if (Test-Path -LiteralPath (Join-Path $mergedArchives $expectedName)) { throw 'Platform mux archives collide.' }
        Move-Item -LiteralPath $files[0].FullName -Destination $mergedArchives
      } $archiveTarget
    }
  } finally { Pop-Location }
  if (@(Get-ChildItem -LiteralPath $mergedArchives -File).Count -ne $archiveTargets.Count) {
    throw 'Release merge lost a platform mux archive.'
  }

  # Exercise the real early-exit path in an isolated checkout. A stub ensures a
  # regression cannot invoke the installed Flutter SDK or change real assets.
  $fixtureTool = Join-Path $testRoot 'early-exit/tool'
  New-Item -ItemType Directory -Path $fixtureTool -Force | Out-Null
  Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | Copy-Item -Destination $fixtureTool
  $target = if ($IsWindows) { 'windows-' + [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant() }
    elseif ($IsMacOS) { if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'macos-arm64' } else { 'macos-x64' } }
    else { 'linux-x64' }
  New-Item -ItemType Directory -Path (Join-Path $testRoot "early-exit/artifacts/$target") -Force | Out-Null
  function flutter { throw 'Flutter must not run before the existing-output check.' }
  Assert-BuildRejected { & (Join-Path $fixtureTool 'build-release.ps1') -Target $target -Version '1.2.9+0' } 'already exists'
  Write-Output 'Build optimization behavior checks passed.'
} finally {
  if ((Split-Path $testRoot -Leaf) -notlike 'bilisail-build-optimization-*' -or [IO.Path]::GetFullPath($testRoot) -cne $testRoot) { throw 'Unsafe build test cleanup path.' }
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
