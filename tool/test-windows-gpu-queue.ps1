param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.dart_tool/package_config.json') | ConvertFrom-Json
$package = $config.packages | Where-Object name -eq 'media_kit_video'
$configUri = [Uri]::new((Join-Path $repoRoot '.dart_tool/package_config.json'))
$source = [Uri]::new($configUri, $package.rootUri).LocalPath
$output = Join-Path $repoRoot 'build/gpu-queue-test'
$patched = Join-Path $output 'patched'
$patch = Join-Path $repoRoot 'windows/patches/media_kit_video'
& cmake "-DBILISAIL_VIDEO_TEST_SOURCE=$source/windows" "-DBILISAIL_VIDEO_TEST_OUTPUT=$patched" -P "$patch/apply.cmake"
if ($LASTEXITCODE -ne 0) { throw 'Native source patch validation failed.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $PSScriptRoot 'native_tests/d3d11_mailbox_test.cpp'
$resizeTest = Join-Path $PSScriptRoot 'native_tests/video_output_resize_test.cpp'
$flutterHeaders = Join-Path $repoRoot 'windows/flutter/ephemeral'
if (!(Test-Path -LiteralPath (Join-Path $flutterHeaders 'flutter_texture_registrar.h'))) {
  throw 'Prepare the Windows Flutter headers with flutter build windows before running descriptor checks.'
}
$compile = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /MT /DUNICODE /D_UNICODE /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$patched" "$test" "$patched/d3d11_renderer.cc" "$patched/mailbox_swap_chain.cc" "$patched/utils.cc" /Fe"$output/d3d11_mailbox_test.exe" /Fo"$output/" /link d3d11.lib dxgi.lib user32.lib
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /MT /DUNICODE /D_UNICODE /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$patched" /I"$flutterHeaders" /I"$flutterHeaders/cpp_client_wrapper/include" "$resizeTest" "$patched/d3d11_renderer.cc" "$patched/mailbox_swap_chain.cc" "$patched/utils.cc" /Fe"$output/video_output_resize_test.exe" /Fo"$output/" /link d3d11.lib dxgi.lib user32.lib
"@ | Set-Content -LiteralPath $compile -Encoding utf8
& cmd /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'GPU queue test compilation failed.' }
& "$output/d3d11_mailbox_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Real D3D11 mailbox tests failed.' }
& "$output/video_output_resize_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Video texture resize and descriptor tests failed.' }
