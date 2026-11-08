$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/fvp-audio-clock-test'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $PSScriptRoot 'native_tests/fvp_audio_clock_test.cpp'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /MT "$test" /Fo"$output/test.obj" /Fe"$output/test.exe"
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Audio clock test compilation failed.' }
& "$output/test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Audio clock tests failed.' }
