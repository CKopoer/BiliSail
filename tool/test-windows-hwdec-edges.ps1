param(
  [string]$OutputDirectory,
  [ValidateSet('1002', '10de', '8086')]
  [string]$VendorHex = '1002',
  [string]$MpvSdkDirectory,
  [switch]$RequireCleanDirect,
  [switch]$IncludeTransforms
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$OutputDirectory) {
  $OutputDirectory = Join-Path $repoRoot ("build/validation/hwdec-edges-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Use a new output directory: $output" }
New-Item -ItemType Directory -Path $output | Out-Null

# Use the exact SDKs selected by the application's last Windows build. Copying
# them to this probe's own directory does not modify a running application.
$cache = Get-Content -LiteralPath (Join-Path $repoRoot 'build/windows/x64/CMakeCache.txt')
function Get-Sdk([string]$Name) {
  $entries = @($cache | Select-String "^${Name}:INTERNAL=(.+)$")
  if ($entries.Count -ne 1) { throw "Build Windows first: missing $Name" }
  $path = $entries[0].Matches.Groups[1].Value.Trim()
  if (!(Test-Path -LiteralPath $path -PathType Container)) { throw "Missing SDK: $path" }
  return $path
}
$angle = Get-Sdk 'MEDIA_KIT_ANGLE_SDK'
$mpv = if ($MpvSdkDirectory) { (Resolve-Path -LiteralPath $MpvSdkDirectory).Path } else { Get-Sdk 'MEDIA_KIT_MPV_SDK' }
foreach ($sdkFile in @('libmpv-2.dll', 'include/mpv/client.h', 'include/mpv/render_gl.h')) {
  if (!(Test-Path -LiteralPath (Join-Path $mpv $sdkFile) -PathType Leaf)) { throw "Incomplete probe SDK: $sdkFile" }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$visualStudio) { throw 'Visual Studio C++ tools are required.' }
$environment = Join-Path $visualStudio 'VC/Auxiliary/Build/vcvars64.bat'
$source = Join-Path $PSScriptRoot 'native_tests/hwdec_edge_probe.cpp'
$shader = Join-Path $PSScriptRoot 'validation/hwdec_plane_bounds.glsl'
$compile = Join-Path $output 'compile.cmd'
@"
@echo off
call "$environment" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /MT /DUNICODE /D_UNICODE /I"$angle/include" /I"$mpv/include" "$source" /Fe"$output/hwdec_edge_probe.exe" /Fo"$output/" /link "$angle/lib/libEGL.dll.lib" "$angle/lib/libGLESv2.dll.lib" d3d11.lib dxgi.lib user32.lib
"@ | Set-Content -LiteralPath $compile -Encoding utf8
& cmd /d /c $compile
if ($LASTEXITCODE -ne 0) { throw 'Edge probe compilation failed.' }
Get-ChildItem -LiteralPath $angle -Filter *.dll | Copy-Item -Destination $output
Copy-Item -LiteralPath (Join-Path $mpv 'libmpv-2.dll') -Destination $output

$fixtures = @()
foreach ($codec in @('hevc', 'av1', 'h264')) {
  foreach ($orientation in @('landscape', 'portrait')) {
    $width = if ($orientation -eq 'landscape') { 1920 } else { 1080 }
    $height = if ($orientation -eq 'landscape') { 1080 } else { 1920 }
    $depths = if ($codec -eq 'h264') { @(8) } else { @(8, 10) }
    foreach ($depth in $depths) {
      $fixtures += @{ Name = "$codec-$orientation-$depth"; Codec = $codec; Width = $width; Height = $height; Depth = $depth }
    }
  }
}
$fixtures += @{ Name = 'av1-landscape-aligned'; Codec = 'av1'; Width = 1920; Height = 1152; Depth = 8 }
$fixtures += @{ Name = 'av1-portrait-aligned'; Codec = 'av1'; Width = 1152; Height = 1920; Depth = 8 }
if ($IncludeTransforms) {
  $fixtures += @{ Name = 'av1-landscape-color'; Codec = 'av1'; Width = 1920; Height = 1080; Depth = 10; ColorEdges = $true }
  $fixtures += @{ Name = 'av1-portrait-color'; Codec = 'av1'; Width = 1080; Height = 1920; Depth = 10; ColorEdges = $true }
  $fixtures += @{ Name = 'av1-landscape-4k'; Codec = 'av1'; Width = 3840; Height = 2160; Depth = 10 }
  $fixtures += @{ Name = 'av1-portrait-4k'; Codec = 'av1'; Width = 2160; Height = 3840; Depth = 10 }
}

$results = @()
foreach ($fixture in $fixtures) {
  $media = Join-Path $output ($fixture.Name + '.mp4')
  $pixelFormat = if ($fixture.Depth -eq 10) { 'yuv420p10le' } else { 'yuv420p' }
  $encoder = switch ($fixture.Codec) {
    'hevc' { @('-c:v', 'libx265', '-preset', 'ultrafast', '-crf', '18', '-x265-params', 'log-level=error:pools=2', '-tag:v', 'hvc1') }
    'av1' { @('-c:v', 'libsvtav1', '-preset', '12', '-crf', '18', '-svtav1-params', 'lp=2') }
    'h264' { @('-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18') }
  }
  $encode = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', "color=c=gray:s=$($fixture.Width)x$($fixture.Height):r=24", '-t', '1', '-an', '-pix_fmt', $pixelFormat) + $encoder + @($media)
  if ($fixture.ColorEdges) {
    $encode = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', "color=c=gray:s=$($fixture.Width)x$($fixture.Height):r=24,drawbox=x=0:y=0:w=iw:h=8:c=red:t=fill,drawbox=x=iw-8:y=0:w=8:h=ih:c=blue:t=fill,drawbox=x=0:y=ih-8:w=iw:h=8:c=yellow:t=fill", '-t', '1', '-an', '-pix_fmt', $pixelFormat) + $encoder + @($media)
  }
  & ffmpeg @encode 2> "$media.encode.log"
  if ($LASTEXITCODE -ne 0) { throw "Encoding failed: $media" }
  $streamJson = & ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,pix_fmt -of json $media
  if ($LASTEXITCODE -ne 0) { throw "Cannot inspect fixture: $media" }
  $stream = ($streamJson | ConvertFrom-Json).streams[0]
  if ($stream.codec_name -ne $fixture.Codec -or $stream.width -ne $fixture.Width -or $stream.height -ne $fixture.Height -or $stream.pix_fmt -ne $pixelFormat) {
    throw "Encoded fixture does not match its declared identity: $media"
  }
  $views = @(
    @{ Name = ''; Width = $fixture.Width; Height = $fixture.Height; Options = @() },
    @{ Name = ''; Width = $fixture.Width / 2; Height = $fixture.Height / 2; Options = @() }
  )
  if ($IncludeTransforms -and $fixture.Name -match '^av1-(landscape|portrait)-(8|10)$') {
    foreach ($rotation in @(90, 180, 270)) {
      $swap = $rotation -ne 180
      $views += @{ Name = "rotate-$rotation"; Width = $(if ($swap) { $fixture.Height / 2 } else { $fixture.Width / 2 }); Height = $(if ($swap) { $fixture.Width / 2 } else { $fixture.Height / 2 }); Options = @("video-rotate=$rotation") }
    }
    $cropWidth = [int]($fixture.Width * 2 / 3)
    $cropHeight = [int]($fixture.Height * 2 / 3)
    $cropX = $fixture.Width - $cropWidth
    $cropY = $fixture.Height - $cropHeight
    $views += @{ Name = 'crop-edge'; Width = $cropWidth / 2; Height = $cropHeight / 2; Options = @("video-crop=${cropWidth}x${cropHeight}+${cropX}+${cropY}") }
    foreach ($scaler in @('lanczos', 'spline36')) {
      $views += @{ Name = "cscale-$scaler"; Width = $fixture.Width / 2; Height = $fixture.Height / 2; Options = @("cscale=$scaler") }
    }
  }
  foreach ($view in $views) {
    $size = @([int]$view.Width, [int]$view.Height)
    $modes = @(
      @{ Name = 'direct'; Decoder = 'd3d11va'; Options = @() },
      @{ Name = 'copy'; Decoder = 'd3d11va-copy'; Options = @() },
      @{ Name = 'software'; Decoder = 'no'; Options = @() },
      @{ Name = 'plane-bounds'; Decoder = 'd3d11va'; Options = @("glsl-shaders=$shader") }
    )
    if ($view.Name) { $modes = @($modes | Where-Object Name -ne 'plane-bounds') }
    foreach ($mode in $modes) {
      $label = "$($fixture.Name)-$($size[0])x$($size[1])-$($mode.Name)"
      if ($view.Name) { $label += "-$($view.Name)" }
      $pixels = Join-Path $output ($label + '.rgba')
      $stdout = Join-Path $output ($label + '.txt')
      $stderr = Join-Path $output ($label + '.log')
      $probeArgs = @($media, $mode.Decoder, $size[0], $size[1], $pixels, $VendorHex) + $mode.Options + $view.Options
      & (Join-Path $output 'hwdec_edge_probe.exe') @probeArgs 1> $stdout 2> $stderr
      if ($LASTEXITCODE -ne 0) { throw "Probe failed: $label (see $stderr)" }
      $lines = Get-Content -LiteralPath $stdout
      $edges = @{}
      foreach ($line in $lines) {
        if ($line -match '^(gl_bottom|gl_top|left|right|center) rgb=([^,]+),([^,]+),([^ ]+) max_green=(\d+) green_pixels=(\d+)/(\d+)$') {
          $edges[$Matches[1]] = @{
            Rgb = @([double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture), [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture), [double]::Parse($Matches[4], [Globalization.CultureInfo]::InvariantCulture))
            MaximumGreenExcess = [int]$Matches[5]; GreenPixels = [int]$Matches[6]; Pixels = [int]$Matches[7]
          }
        }
      }
      if ($edges.Count -ne 5) { throw "Incomplete edge measurements: $label" }
      $properties = @{}
      foreach ($line in $lines) {
        if ($line -match '^(mpv-version|ffmpeg-version|hwdec-current|video-format|video-params|video-out-params|gl_renderer)=(.*)$') { $properties[$Matches[1]] = $Matches[2] }
      }
      if ($properties['hwdec-current'] -ne $mode.Decoder) { throw "Unverified decoder: $label" }
      $results += @{
        Label = $label; Fixture = $fixture.Name; FixtureSha256 = (Get-FileHash -LiteralPath $media -Algorithm SHA256).Hash.ToLowerInvariant()
        Width = $size[0]; Height = $size[1]; Mode = $mode.Name; Transform = $view.Name; Properties = $properties; Edges = $edges
      }
      Write-Output ("{0}: maximum edge green excess={1}" -f $label, (($edges.Values | ForEach-Object MaximumGreenExcess | Measure-Object -Maximum).Maximum))
    }
  }
}
$summary = @{
  VendorHex = $VendorHex
  LibmpvSha256 = (Get-FileHash -LiteralPath (Join-Path $output 'libmpv-2.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
  AngleEglSha256 = (Get-FileHash -LiteralPath (Join-Path $output 'libEGL.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
  AngleGlesSha256 = (Get-FileHash -LiteralPath (Join-Path $output 'libGLESv2.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
  ShaderSha256 = (Get-FileHash -LiteralPath $shader -Algorithm SHA256).Hash.ToLowerInvariant()
  RequireCleanDirect = [bool]$RequireCleanDirect
  IncludeTransforms = [bool]$IncludeTransforms
  Cases = $results
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding utf8
foreach ($group in $results | Group-Object Fixture, Width, Height, Transform) {
  $reference = @($group.Group | Where-Object Mode -eq 'software')[0]
  $checkedModes = @('copy', 'plane-bounds')
  if ($RequireCleanDirect) { $checkedModes += 'direct' }
  foreach ($case in $group.Group | Where-Object Mode -in $checkedModes) {
    foreach ($edge in @('gl_bottom', 'gl_top', 'left', 'right', 'center')) {
      for ($channel = 0; $channel -lt 3; $channel++) {
        if ([Math]::Abs($case.Edges[$edge].Rgb[$channel] - $reference.Edges[$edge].Rgb[$channel]) -gt 2) {
          throw "Output differs from software gray reference: $($case.Label), $edge"
        }
      }
    }
  }
}
Write-Output "PASS: $($results.Count) verified captures; checked paths match the software reference. Results: $output/results.json"
