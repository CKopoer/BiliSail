param()
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$config = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.dart_tool/package_config.json') | ConvertFrom-Json
$package = $config.packages | Where-Object { $_.name -eq 'media_kit_video' }
if (!$package) { throw 'Run flutter pub get before the native disposal checks.' }
$configUri = [Uri]::new((Join-Path $repoRoot '.dart_tool/package_config.json'))
$sourceRoot = [Uri]::new($configUri, $package.rootUri).LocalPath
$output = Join-Path $repoRoot 'build/video-dispose-test'
$patched = Join-Path $output 'patched'
$patch = Join-Path $repoRoot 'windows/patches/media_kit_video'
& cmake "-DBILISAIL_VIDEO_TEST_SOURCE=$sourceRoot/windows" "-DBILISAIL_VIDEO_TEST_OUTPUT=$patched" -P "$patch/apply.cmake"
if ($LASTEXITCODE -ne 0) { throw 'Native source patch validation failed.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required for the native disposal tests.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $PSScriptRoot 'native_tests/video_output_dispose_test.cpp'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR /I"$patched" /I"$patch" "$test" /Fo"$output/video_output_dispose_test.obj" /Fe"$output/video_output_dispose_test.exe"
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Native disposal test compilation failed.' }
& "$output/video_output_dispose_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Native disposal tests failed.' }
