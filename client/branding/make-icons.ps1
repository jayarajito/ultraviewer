# Generates the placeholder JustKeepRemote icon set ("JKR" on a blue gradient rounded square)
# into client\branding\out\. Replace this script's output with real artwork later; the patch
# script (client\apply-jkr-patches.ps1) copies whatever is in client\branding\out into the client.
#
#   powershell -ExecutionPolicy Bypass -File client\branding\make-icons.ps1
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([System.Drawing.Color]::Transparent)
    $m = [Math]::Max(1, [int]($size * 0.04))          # margin
    $r = [int]($size * 0.22)                          # corner radius
    $w = $size - 2 * $m
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $path.AddArc($m, $m, $d, $d, 180, 90); $path.AddArc($m + $w - $d, $m, $d, $d, 270, 90)
    $path.AddArc($m + $w - $d, $m + $w - $d, $d, $d, 0, 90); $path.AddArc($m, $m + $w - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, ([System.Drawing.Color]::FromArgb(255, 0, 113, 255)), ([System.Drawing.Color]::FromArgb(255, 0, 191, 225)), 45
    $g.FillPath($brush, $path)
    # "JKR" centred, bold, white; shrink the font until it fits 84% of the width.
    $fs = [single]($size * 0.46)
    do {
        $font = New-Object System.Drawing.Font 'Segoe UI', $fs, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $sz = $g.MeasureString('JKR', $font)
        if ($sz.Width -le $size * 0.84) { break }
        $fs = $fs - 1
    } while ($fs -gt 4)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $g.DrawString('JKR', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 0, $size, ($size * 1.02)), $sf)
    $g.Dispose(); $brush.Dispose(); $path.Dispose()
    return $bmp
}

function Get-PngBytes($bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return ,$ms.ToArray()
}

function Write-Ico([string]$path, [int[]]$sizes) {
    $images = @(); foreach ($s in $sizes) { $b = New-IconBitmap $s; $images += ,@($s, (Get-PngBytes $b)); $b.Dispose() }
    $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter $ms
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($im in $images) {
        $s = $im[0]; $data = $im[1]
        $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s })); $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
        $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$data.Length); $bw.Write([uint32]$offset); $offset += $data.Length
    }
    foreach ($im in $images) { $bw.Write([byte[]]$im[1]) }
    $bw.Flush(); [IO.File]::WriteAllBytes($path, $ms.ToArray())
}

function Write-Png([string]$path, [int]$size) {
    $b = New-IconBitmap $size; $b.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
}

Write-Ico (Join-Path $out 'icon.ico')      @(16, 24, 32, 48, 64, 128, 256)
Write-Ico (Join-Path $out 'tray-icon.ico') @(16, 24, 32, 48, 64)
Write-Ico (Join-Path $out 'app_icon.ico')  @(16, 24, 32, 48, 64, 128, 256)
Write-Png (Join-Path $out 'icon.png')         512
Write-Png (Join-Path $out '32x32.png')        32
Write-Png (Join-Path $out '64x64.png')        64
Write-Png (Join-Path $out '128x128.png')      128
Write-Png (Join-Path $out '128x128@2x.png')   256
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize
