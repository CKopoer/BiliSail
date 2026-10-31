$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/window-geometry-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required for the geometry unit test.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $repoRoot 'windows/tests/playback_window_geometry_test.cpp'
$nativeTest = Join-Path $repoRoot 'windows/tests/playback_window_first_show_test.cpp'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT "$test" /Fo"$output/" /Fe"$output/playback_window_geometry_test.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DNOMINMAX "$nativeTest" /Fo"$output/" /Fe"$output/playback_window_first_show_test.exe" user32.lib comctl32.lib dwmapi.lib advapi32.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Geometry unit test compilation failed.' }
& "$output/playback_window_geometry_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Geometry unit test failed.' }
& "$output/playback_window_first_show_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Native first-show test failed.' }
