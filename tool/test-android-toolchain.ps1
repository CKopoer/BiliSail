param([Parameter(Mandatory)][string]$FlutterSdkPath)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$settings = Get-Content -LiteralPath (Join-Path $repoRoot 'android/settings.gradle.kts') -Raw
$wrapper = Get-Content -LiteralPath (Join-Path $repoRoot 'android/gradle/wrapper/gradle-wrapper.properties') -Raw
$checker = Get-Content -LiteralPath (Join-Path $FlutterSdkPath 'packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt') -Raw

# Read the pinned SDK's actual rejection thresholds. An SDK upgrade must not
# pass offline CI while leaving Android unable to configure its build.
foreach ($entry in @(
  @{ Name = 'Gradle'; Source = $wrapper; Pattern = 'gradle-(\d+\.\d+\.\d+)-bin\.zip'; Minimum = 'errorGradleVersion' }
  @{ Name = 'AGP'; Source = $settings; Pattern = 'id\("com\.android\.application"\) version "(\d+\.\d+\.\d+)"'; Minimum = 'errorAGPVersion' }
  @{ Name = 'Kotlin'; Source = $settings; Pattern = 'id\("org\.jetbrains\.kotlin\.android"\) version "(\d+\.\d+\.\d+)"'; Minimum = 'errorKGPVersion' }
)) {
  $configured = [regex]::Match($entry.Source, $entry.Pattern)
  $minimum = [regex]::Match($checker, "$($entry.Minimum):\s*\w+\s*=\s*\w+\((\d+),\s*(\d+),\s*(\d+)\)")
  if (!$configured.Success -or !$minimum.Success) { throw "Cannot determine $($entry.Name) compatibility with the pinned Flutter SDK." }
  $actualVersion = [version]$configured.Groups[1].Value
  $minimumVersion = [version](($minimum.Groups[1..3].Value) -join '.')
  if ($actualVersion -lt $minimumVersion) {
    throw "$($entry.Name) $actualVersion is below Flutter's minimum $minimumVersion."
  }
  Write-Output "$($entry.Name) $actualVersion satisfies Flutter's minimum $minimumVersion."
}
