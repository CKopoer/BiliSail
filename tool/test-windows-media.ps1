param([switch]$Online)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  foreach ($testFile in @('integration_test/windows_playback_test.dart', 'integration_test/windows_playback_diagnostics_test.dart', 'integration_test/windows_preview_buffer_test.dart')) {
    $arguments = @('test', $testFile, '-d', 'windows')
    if ($Online) { $arguments += '--dart-define=BILI_ONLINE_SMOKE=true' }
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "Windows playback validation failed ($testFile): $LASTEXITCODE" }
  }
} finally {
  Remove-Item Env:BILI_TEST_MEDIA_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
