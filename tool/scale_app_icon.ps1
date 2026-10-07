# Keep the selected artwork and canvas; regenerate the 10% enlargement on Windows.
$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Add-Type -AssemblyName System.Drawing
$sourcePath = Join-Path $repoRoot 'assets/branding/candidates-v2/c-sail-corner.png'
$outputPath = Join-Path $repoRoot 'assets/branding/app_icon.png'
$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
  $bitmap = [System.Drawing.Bitmap]::new(
    $source.Width, $source.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
  )
  try {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      # Scale about the canvas center; retain the original square pixel dimensions.
      $scale = 1.10
      $width = [single]($source.Width * $scale)
      $height = [single]($source.Height * $scale)
      $rectangle = [System.Drawing.RectangleF]::new(
        [single](($source.Width - $width) / 2),
        [single](($source.Height - $height) / 2), $width, $height
      )
      $graphics.DrawImage($source, $rectangle)
    } finally { $graphics.Dispose() }
    $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $bitmap.Dispose() }
} finally { $source.Dispose() }
