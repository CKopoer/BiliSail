param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.dart_tool/package_config.json') | ConvertFrom-Json
$package = $config.packages | Where-Object name -eq 'media_kit_video'
$configUri = [Uri]::new((Join-Path $repoRoot '.dart_tool/package_config.json'))
$source = [Uri]::new($configUri, $package.rootUri).LocalPath
$output = Join-Path $repoRoot 'build/gpu-queue-test'
$patched = Join-Path $output 'patched'
$angle = Join-Path $repoRoot 'build/windows/x64/ANGLE'
$patch = Join-Path $repoRoot 'windows/patches/media_kit_video'
& cmake "-DBILISAIL_VIDEO_TEST_SOURCE=$source/windows" "-DBILISAIL_VIDEO_TEST_OUTPUT=$patched" -P "$patch/apply.cmake"
if ($LASTEXITCODE -ne 0) { throw 'Native source patch validation failed.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $PSScriptRoot 'native_tests/angle_gpu_queue_test.cpp'
$resizeTest = Join-Path $PSScriptRoot 'native_tests/video_output_resize_test.cpp'
$flutterHeaders = Join-Path $repoRoot 'windows/flutter/ephemeral'
$mpvHeaders = Join-Path $repoRoot 'build/windows/x64/libmpv/include'
$compile = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DUNICODE /D_UNICODE /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$patched" /I"$angle/include" "$test" "$patched/angle_surface_manager.cc" "$patched/utils.cc" /Fe"$output/angle_gpu_queue_test.exe" /Fo"$output/" /link "$angle/lib/libEGL.dll.lib" "$angle/lib/libGLESv2.dll.lib" user32.lib
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DUNICODE /D_UNICODE /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$patched" /I"$flutterHeaders" /I"$flutterHeaders/cpp_client_wrapper/include" /I"$mpvHeaders" /I"$angle/include" "$resizeTest" "$patched/angle_surface_manager.cc" "$patched/utils.cc" /Fe"$output/video_output_resize_test.exe" /Fo"$output/" /link "$angle/lib/libEGL.dll.lib" "$angle/lib/libGLESv2.dll.lib" user32.lib
"@ | Set-Content -LiteralPath $compile -Encoding utf8
& cmd /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'GPU queue test compilation failed.' }
$oldPath = $env:PATH
try {
  $env:PATH = "$angle;$oldPath"
  & "$output/angle_gpu_queue_test.exe"
  if ($LASTEXITCODE -ne 0) { throw 'Real GPU queue tests failed.' }
  & "$output/video_output_resize_test.exe"
  if ($LASTEXITCODE -ne 0) { throw 'Video resize descriptor tests failed.' }
} finally { $env:PATH = $oldPath }
