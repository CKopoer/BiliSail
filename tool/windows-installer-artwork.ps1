# Build installer artwork from the existing app icon; no downloaded assets or fonts.
function New-WindowsInstallerArtwork([string]$Destination) {
  Add-Type -AssemblyName System.Drawing
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  $iconPath = Join-Path $PSScriptRoot '../assets/branding/app_icon.png'
  $icon = [System.Drawing.Image]::FromFile($iconPath)
  try {
    foreach ($layout in @(
      @{ Name = 'sidebar.png'; Width = 440; Height = 960; Sidebar = 440; IconSize = 156; IconX = 56; IconY = 64 },
      @{ Name = 'dialog.bmp'; Width = 304; Height = 600; Sidebar = 304; IconSize = 116; IconX = 40; IconY = 44 },
      @{ Name = 'banner.bmp'; Width = 740; Height = 88; Sidebar = 0; IconSize = 60; IconX = 660; IconY = 14 }
    )) {
      $bitmap = [System.Drawing.Bitmap]::new($layout.Width, $layout.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.Clear([System.Drawing.Color]::White)
        if ($layout.Sidebar) {
          $bounds = [System.Drawing.Rectangle]::new(0, 0, $layout.Sidebar, $layout.Height)
          $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new($bounds, [System.Drawing.ColorTranslator]::FromHtml('#F3F8FD'), [System.Drawing.ColorTranslator]::FromHtml('#DCECF7'), 90.0)
          $wave = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#CFE3F1'))
          $accent = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#D94B68'))
          try {
            $graphics.FillRectangle($gradient, $bounds)
            $graphics.SetClip($bounds)
            $graphics.FillEllipse($wave, -$layout.Sidebar, [int]($layout.Height * 0.75), $layout.Sidebar * 3, $layout.Height)
            $graphics.FillRectangle($accent, $layout.IconX, [int]($layout.Height * 0.48), 36, 5)
            $graphics.ResetClip()
          } finally { $gradient.Dispose(); $wave.Dispose(); $accent.Dispose() }
        }
        $graphics.DrawImage($icon, $layout.IconX, $layout.IconY, $layout.IconSize, $layout.IconSize)
        $format = if ($layout.Name.EndsWith('.bmp')) { [System.Drawing.Imaging.ImageFormat]::Bmp } else { [System.Drawing.Imaging.ImageFormat]::Png }
        $bitmap.Save((Join-Path $Destination $layout.Name), $format)
      } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
  } finally { $icon.Dispose() }
}
