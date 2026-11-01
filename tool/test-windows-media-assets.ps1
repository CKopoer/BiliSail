param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Join-Path $repoRoot 'windows/native/media-assets.cmake'
$fixture = Join-Path $repoRoot 'build/windows-media-assets-test'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$cmakeManifest = $manifest.Replace('\', '/')
$cmakeFixture = $fixture.Replace('\', '/')
$sourceUri = [Uri]::new((Join-Path $fixture 'source.bin')).AbsoluteUri
$probe = Join-Path $fixture 'verify.cmake'
@'
include("@MANIFEST@")
if(CASE STREQUAL "good")
  bilisail_verify_mpv_sdk("${SDK}")
elseif(CASE STREQUAL "mixed-sdk")
  # A nonempty SDK directory with the old library must not count as usable.
  bilisail_verify_mpv_sdk("@FIXTURE@/mixed")
elseif(CASE STREQUAL "missing-import")
  bilisail_verify_mpv_sdk("@FIXTURE@/missing")
elseif(CASE STREQUAL "modified-header")
  bilisail_verify_mpv_sdk("@FIXTURE@/modified")
elseif(CASE STREQUAL "modified-archive")
  bilisail_fetch_media_archive("@FIXTURE@/archive.7z" "https://invalid.example/unused" "${BILISAIL_MPV_SHA256}")
elseif(CASE STREQUAL "download-good")
  file(SHA256 "@FIXTURE@/source.bin" expected)
  bilisail_fetch_media_archive("@FIXTURE@/downloaded.bin" "@SOURCE_URI@" "${expected}")
  if(EXISTS "@FIXTURE@/downloaded.bin.partial")
    message(FATAL_ERROR "Published download left a partial file")
  endif()
elseif(CASE STREQUAL "download-bad")
  bilisail_fetch_media_archive("@FIXTURE@/rejected.bin" "@SOURCE_URI@" "${BILISAIL_MPV_SHA256}")
else()
  message(FATAL_ERROR "Unknown test case")
endif()
'@.Replace('@MANIFEST@', $cmakeManifest).Replace('@FIXTURE@', $cmakeFixture).Replace('@SOURCE_URI@', $sourceUri) |
  Set-Content -LiteralPath $probe -Encoding utf8
# SDK filenames/hashes come from the same manifest as the real build, via CMake.
$pathsProbe = Join-Path $fixture 'paths.cmake'
@'
include("@MANIFEST@")
file(WRITE "@FIXTURE@/sdk-path.txt" "${BILISAIL_MPV_SHA256}")
'@.Replace('@MANIFEST@', $cmakeManifest).Replace('@FIXTURE@', $cmakeFixture) |
  Set-Content -LiteralPath $pathsProbe -Encoding utf8
& cmake -P $pathsProbe
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Windows media manifest.' }
$sdk = Join-Path $repoRoot "build/windows/x64/bilisail_native/$(Get-Content -Raw (Join-Path $fixture 'sdk-path.txt'))"
if (!(Test-Path -LiteralPath $sdk)) { throw 'Build Windows once before running the SDK integrity regression.' }
foreach ($name in @('mixed', 'missing', 'modified')) {
  $target = Join-Path $fixture $name
  New-Item -ItemType Directory -Path "$target/include/mpv" -Force | Out-Null
  Copy-Item -LiteralPath "$sdk/libmpv-2.dll", "$sdk/libmpv.dll.a" -Destination $target -Force
  Copy-Item -Path "$sdk/include/mpv/*.h" -Destination "$target/include/mpv" -Force
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'build/windows/x64/libmpv/libmpv-2.dll') -Destination "$fixture/mixed/libmpv-2.dll" -Force
Remove-Item -LiteralPath "$fixture/missing/libmpv.dll.a" -Force
Add-Content -LiteralPath "$fixture/modified/include/mpv/render.h" -Value '// mismatched render API'
Set-Content -LiteralPath "$fixture/archive.7z" -Value 'invalid cached archive'
Set-Content -LiteralPath "$fixture/source.bin" -Value 'local download integrity fixture'
Remove-Item -LiteralPath "$fixture/downloaded.bin" -ErrorAction SilentlyContinue
foreach ($case in @('good', 'mixed-sdk', 'missing-import', 'modified-header', 'modified-archive', 'download-good', 'download-bad')) {
  $result = & cmake "-DCASE=$case" "-DSDK=$sdk" -P $probe 2>&1
  $passed = $LASTEXITCODE -eq 0
  if ($passed -ne ($case -in @('good', 'download-good'))) {
    throw "Unexpected Windows SDK integrity result for ${case}: $result"
  }
  Write-Output "PASS Windows media SDK integrity: $case"
}
if (Test-Path -LiteralPath "$fixture/rejected.bin") { throw 'An invalid download was published.' }
