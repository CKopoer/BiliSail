# Native, static-CRT UI helper shared by MSI and Burn. SDKs are build-only.
function Build-WindowsInstallerNative([string]$WorkingDirectory) {
  if (!$IsWindows) { throw 'Installer native UI requires Windows.' }
  $sdk = Join-Path $WorkingDirectory 'sdk'
  New-Item -ItemType Directory -Path $sdk -Force | Out-Null
  $packages = @{
    'wixtoolset.bootstrapperapplicationapi' = '899a3d88db31098d87fbb24c2e72fa1d2dbacf9b38af73a91dae762b0653e6f5'
    'wixtoolset.wixstandardbootstrapperapplicationfunctionapi' = 'c5d5d3ce835859cd9cfce8428f9111e052e0358334b7cef7000b8099a78e7742'
  }
  foreach ($name in $packages.Keys) {
    $archive = Join-Path $sdk "$name.6.0.2.nupkg"
    if (!(Test-Path -LiteralPath $archive -PathType Leaf)) {
      Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$name/6.0.2/$name.6.0.2.nupkg" -OutFile $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $packages[$name]) {
      throw "Installer SDK hash mismatch: $name."
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, (Join-Path $sdk $name), $true)
  }
  $source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../windows/packaging/native'))
  $build = Join-Path $WorkingDirectory 'build'
  & cmake -S $source -B $build -A x64 "-DBILISAIL_WIX_SDK_DIR=$sdk" | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'Installer native UI configuration failed.' }
  & cmake --build $build --config Release | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'Installer native UI compilation failed.' }
  return (Join-Path $build 'Release/BiliSailInstallerUI.dll')
}
