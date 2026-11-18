$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repoRoot 'build/image-picker-test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$flutterRoot = Join-Path $repoRoot 'windows/flutter/ephemeral'
$wrapper = Join-Path $repoRoot 'build/windows/x64/flutter/Release/flutter_wrapper_app.lib'
if (!(Test-Path -LiteralPath $wrapper)) { throw 'Existing Flutter Windows wrapper test library is required; this script does not build the application.' }
$include = Join-Path $flutterRoot 'cpp_client_wrapper/include'
$test = Join-Path $repoRoot 'windows/tests/image_picker_test.cpp'
$picker = Join-Path $repoRoot 'windows/runner/image_picker.cpp'
$channel = Join-Path $repoRoot 'windows/runner/image_picker_channel.cpp'
$compileScript = Join-Path $output 'compile-test.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /MD /DNOMINMAX /DUNICODE /D_UNICODE /D_HAS_EXCEPTIONS=0 /I"$include" "$test" "$picker" "$channel" /Fo"$output/" /Fe"$output/image_picker_test.exe" /link "$wrapper" "$flutterRoot/flutter_windows.dll.lib" user32.lib comctl32.lib ole32.lib shell32.lib uuid.lib
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw 'Native image picker unit test compilation failed.' }
Copy-Item -LiteralPath (Join-Path $flutterRoot 'flutter_windows.dll') -Destination $output -Force
& (Join-Path $output 'image_picker_test.exe')
if ($LASTEXITCODE -ne 0) { throw 'Native image picker unit tests failed.' }
