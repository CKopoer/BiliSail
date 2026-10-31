$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/app-icon-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$test = Join-Path $repoRoot 'windows/tests/shell_app_icon_test.cpp'
$implementation = Join-Path $repoRoot 'windows/runner/shell_app_icon.cpp'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DUNICODE /D_UNICODE /DNOMINMAX "$test" "$implementation" /Fo"$output/" /Fe"$output/shell_app_icon_test.exe" /link user32.lib ole32.lib oleaut32.lib uuid.lib propsys.lib shell32.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Native app icon test compilation failed.' }
# No real Start menu, pins, or user settings are touched by this regression.
$fixture = Join-Path $output ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $fixture | Out-Null
& (Join-Path $output 'shell_app_icon_test.exe') $fixture
if ($LASTEXITCODE -ne 0) { throw 'Native app icon tests failed.' }
