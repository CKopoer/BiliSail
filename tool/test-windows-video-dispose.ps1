$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousMedia = $env:BILI_TEST_MEDIA_DIR
Push-Location $repoRoot
try {
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  foreach ($test in 'windows_video_resize_test', 'windows_preview_buffer_test') {
    & flutter test --no-pub "integration_test/$test.dart" -d windows
    if ($LASTEXITCODE -ne 0) { throw "Native video lifecycle failed: $test" }
  }
} finally {
  $env:BILI_TEST_MEDIA_DIR = $previousMedia
  Pop-Location
}
