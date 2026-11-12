param(
  [Parameter(Mandatory)][string]$DeviceId,
  [Parameter(Mandatory)][string]$ConfigPath,
  [Parameter(Mandatory)][ValidatePattern('^[a-z0-9_-]+$')][string]$Label,
  [switch]$SkipReleaseBuild,
  [switch]$EnableHcpp,
  [switch]$Online,
  [switch]$SkipMuxBuild
)
$ErrorActionPreference = 'Stop'
if (!$Online) {
  foreach ($scenario in @(Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json)) {
    foreach ($source in @($scenario.video, $scenario.audio)) {
      if ($source -and ([Uri]$source).Scheme -in @('http','https') -and !([Uri]$source).IsLoopback) {
        throw 'Public network fixtures require -Online.'
      }
    }
  }
}
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'android-development.ps1')
Push-Location $repoRoot
$manifestBackup = $null
$manifest = Join-Path $repoRoot 'android/app/src/main/AndroidManifest.xml'
try {
  if (!$SkipReleaseBuild) {
    & "$PSScriptRoot/build-android-development.ps1" -Mode Release -SkipMuxBuild:$SkipMuxBuild
  }
  $ordinary = 'build/development/android-arm64/BiliSail-test-arm64-release.apk'
  Confirm-AndroidDevelopmentApk $ordinary 'Release' | Out-Null
  New-Item -ItemType Directory -Force 'build/validation/android-4k60' | Out-Null
  Copy-Item -LiteralPath $ordinary -Destination 'build/validation/android-4k60/ordinary-release.apk'
  $version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\S+)\s*$').Matches.Groups[1].Value
  if ($EnableHcpp) {
    $manifestBackup = [IO.File]::ReadAllBytes($manifest)
    $text = [IO.File]::ReadAllText($manifest)
    if ($text.Contains('EnableHcpp')) { throw 'Benchmark manifest already configures HCPP' }
    [IO.File]::WriteAllText($manifest, $text.Replace('</application>',
      '<meta-data android:name="io.flutter.embedding.android.EnableHcpp" android:value="true" /></application>'))
  }
  # Pub is required to regenerate mode-specific native plugin registration.
  & flutter build apk --profile --target-platform android-arm64 --split-per-abi `
    --target tool/validation/android_surface_probe.dart $AndroidDevelopmentBuildArgument `
    "--dart-define=BILISAIL_RELEASE_VERSION=$version"
  if ($LASTEXITCODE -ne 0) { throw 'Surface probe Profile build failed' }
  if ($null -ne $manifestBackup) { [IO.File]::WriteAllBytes($manifest, $manifestBackup); $manifestBackup = $null }
  Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-arm64-v8a-profile.apk' `
    -Destination 'build/validation/android-4k60/probe-profile.apk'
  & "$PSScriptRoot/test-android-4k60.ps1" -DeviceId $DeviceId -ConfigPath $ConfigPath `
    -Label $Label -UsePreparedApks
} finally {
  if ($null -ne $manifestBackup) { [IO.File]::WriteAllBytes($manifest, $manifestBackup) }
  Pop-Location
}
