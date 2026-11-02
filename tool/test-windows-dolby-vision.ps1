param([switch]$PrepareSample, [switch]$WithoutVulkan)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtures = Join-Path $repoRoot 'build/validation/dolby-vision'
$previousFixtures = $env:BILI_TEST_DOVI_DIR
$previousWithoutVulkan = $env:BILI_TEST_DOVI_NO_VULKAN
$previousDriverFiles = $env:VK_DRIVER_FILES
$previousIcdFiles = $env:VK_ICD_FILENAMES
. (Join-Path $PSScriptRoot 'dolby-vision-fixtures.ps1')
Push-Location $repoRoot
try {
  if ($PrepareSample) {
    Initialize-DolbyVisionFixture $fixtures
  }
  foreach ($name in @('video.mp4', 'reference.png')) {
    if (!(Test-Path -LiteralPath (Join-Path $fixtures $name))) {
      throw 'Run this script with -PrepareSample once to download and prepare the public Dolby sample.'
    }
  }
  $env:BILI_TEST_DOVI_DIR = $fixtures
  if ($WithoutVulkan) {
    $env:BILI_TEST_DOVI_NO_VULKAN = 'true'
    # Make the loader expose no ICD, without changing the machine's drivers.
    $env:VK_DRIVER_FILES = Join-Path $fixtures 'unavailable-vulkan-icd.json'
    $env:VK_ICD_FILENAMES = $env:VK_DRIVER_FILES
    if (Test-Path -LiteralPath $env:VK_DRIVER_FILES) { throw 'The unavailable-ICD fixture path must not exist.' }
  } else { $env:BILI_TEST_DOVI_NO_VULKAN = 'false' }
  & flutter test integration_test/windows_dolby_vision_test.dart -d windows
  if ($LASTEXITCODE -ne 0) { throw 'Windows Dolby Vision validation failed.' }
} finally {
  $env:BILI_TEST_DOVI_DIR = $previousFixtures
  $env:BILI_TEST_DOVI_NO_VULKAN = $previousWithoutVulkan
  $env:VK_DRIVER_FILES = $previousDriverFiles
  $env:VK_ICD_FILENAMES = $previousIcdFiles
  Pop-Location
}
