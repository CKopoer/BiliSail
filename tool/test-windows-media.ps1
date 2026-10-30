param([switch]$Online)
$ErrorActionPreference = 'Stop'
$previousSystemMediaScript = $env:BILI_TEST_SYSTEM_MEDIA_SCRIPT
Push-Location (Join-Path $PSScriptRoot '..')
try {
  $env:BILI_TEST_MEDIA_DIR = (Resolve-Path 'test/fixtures/media').Path
  $env:BILI_TEST_SYSTEM_MEDIA_SCRIPT = (Resolve-Path 'tool/windows-system-media-command.ps1').Path
  foreach ($testFile in @('integration_test/windows_playback_test.dart', 'integration_test/windows_playback_diagnostics_test.dart', 'integration_test/windows_playback_startup_test.dart', 'integration_test/native_video_readiness_test.dart', 'integration_test/audio_only_playback_test.dart', 'integration_test/windows_system_media_test.dart', 'integration_test/windows_video_stall_test.dart', 'integration_test/windows_preview_buffer_test.dart', 'integration_test/windows_audio_normalization_test.dart')) {
    $arguments = @('test', $testFile, '-d', 'windows')
    if ($Online) { $arguments += '--dart-define=BILI_ONLINE_SMOKE=true' }
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "Windows playback validation failed ($testFile): $LASTEXITCODE" }
  }
  & (Join-Path $PSScriptRoot 'test-windows-buffer.ps1')
} finally {
  $env:BILI_TEST_SYSTEM_MEDIA_SCRIPT = $previousSystemMediaScript
  Remove-Item Env:BILI_TEST_MEDIA_DIR -ErrorAction SilentlyContinue
  Pop-Location
}
