param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Join-Path $repoRoot 'windows/native/media-assets.cmake'
$fixture = Join-Path $repoRoot ("build/validation/windows-media-assets-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$cmakeManifest = $manifest.Replace('\', '/')
$cmakeFixture = $fixture.Replace('\', '/')
$sourceUri = [Uri]::new((Join-Path $fixture 'source.bin')).AbsoluteUri
$probe = Join-Path $fixture 'verify.cmake'
@'
include("@MANIFEST@")
bilisail_media_manifest(owner)
include("${owner}")
function(verify_sdk root)
  list(LENGTH MEDIA_KIT_MPV_FILES count)
  math(EXPR last "${count} - 1")
  foreach(index RANGE 0 ${last})
    list(GET MEDIA_KIT_MPV_FILES ${index} name)
    list(GET MEDIA_KIT_MPV_HASHES ${index} expected)
    media_kit_verify_file("${root}/${name}" "${expected}")
  endforeach()
endfunction()
if(CASE STREQUAL "good")
  verify_sdk("${SDK}")
elseif(CASE STREQUAL "mixed-sdk")
  # A nonempty SDK directory with the old library must not count as usable.
  verify_sdk("@FIXTURE@/mixed")
elseif(CASE STREQUAL "missing-import")
  verify_sdk("@FIXTURE@/missing")
elseif(CASE STREQUAL "modified-header")
  verify_sdk("@FIXTURE@/modified")
elseif(CASE STREQUAL "modified-archive")
  media_kit_fetch_archive("@FIXTURE@/archive.bin" "https://invalid.example/unused" "${MEDIA_KIT_MPV_SHA256}")
elseif(CASE STREQUAL "download-good")
  file(SHA256 "@FIXTURE@/source.bin" expected)
  media_kit_fetch_archive("@FIXTURE@/downloaded.bin" "@SOURCE_URI@" "${expected}")
  if(EXISTS "@FIXTURE@/downloaded.bin.partial")
    message(FATAL_ERROR "Published download left a partial file")
  endif()
elseif(CASE STREQUAL "download-bad")
  media_kit_fetch_archive("@FIXTURE@/rejected.bin" "@SOURCE_URI@" "${MEDIA_KIT_MPV_SHA256}")
else()
  message(FATAL_ERROR "Unknown test case")
endif()
'@.Replace('@MANIFEST@', $cmakeManifest).Replace('@FIXTURE@', $cmakeFixture).Replace('@SOURCE_URI@', $sourceUri) |
  Set-Content -LiteralPath $probe -Encoding utf8
# SDK filenames/hashes come from the same manifest as the real build, via CMake.
$pathsProbe = Join-Path $fixture 'paths.cmake'
@'
include("@MANIFEST@")
bilisail_media_manifest(owner)
include("${owner}")
file(WRITE "@FIXTURE@/sdk-files.txt" "${MEDIA_KIT_MPV_FILES}")
'@.Replace('@MANIFEST@', $cmakeManifest).Replace('@FIXTURE@', $cmakeFixture) |
  Set-Content -LiteralPath $pathsProbe -Encoding utf8
& cmake -P $pathsProbe
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Windows media manifest.' }
$nativeCache = Join-Path $repoRoot 'build/windows/x64/CMakeCache.txt'
$sdkEntries = @(Select-String -LiteralPath $nativeCache -Pattern '^MEDIA_KIT_MPV_SDK:INTERNAL=(.+)$')
if ($sdkEntries.Count -ne 1) { throw 'Build Windows before checking the selected SDK.' }
$sdk = $sdkEntries[0].Matches.Groups[1].Value.Trim()
if (!(Test-Path -LiteralPath $sdk)) { throw 'Build Windows once before running the SDK integrity regression.' }
foreach ($name in @('mixed', 'missing', 'modified')) {
  $target = Join-Path $fixture $name
  foreach ($relativePath in (Get-Content -Raw (Join-Path $fixture 'sdk-files.txt')).Split(';')) {
    $destination = Join-Path $target $relativePath
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sdk $relativePath) -Destination $destination
  }
}
# Alter only disposable copies, never a cached or currently loaded player DLL.
Add-Content -LiteralPath "$fixture/mixed/libmpv-2.dll" -Value 'invalid SDK library'
Remove-Item -LiteralPath "$fixture/missing/libmpv.dll.a" -Force
Add-Content -LiteralPath "$fixture/modified/include/mpv/render.h" -Value '// mismatched render API'
Set-Content -LiteralPath "$fixture/archive.bin" -Value 'invalid cached archive'
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
# The last native invocation is an expected rejection; return success for the
# completed regression rather than exposing that invocation's nonzero status.
exit 0
