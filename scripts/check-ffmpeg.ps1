# Diagnostic: is ffmpeg actually installed in the vcpkg static tree?
$root = 'C:\Users\JAYARAJ\vcpkg\vcpkg\installed\x64-windows-static'
$inc  = Join-Path $root 'include'
$lib  = Join-Path $root 'lib'

Write-Output "=== libav*/libsw* include dirs ==="
Get-ChildItem $inc -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'libav*' -or $_.Name -like 'libsw*' } |
    ForEach-Object { $_.Name }

Write-Output "=== avcodec.h present? ==="
Test-Path (Join-Path $inc 'libavcodec\avcodec.h')

Write-Output "=== ffmpeg .lib files ==="
Get-ChildItem $lib -Filter '*.lib' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'avcodec|avformat|avutil|swscale|swresample' } |
    ForEach-Object { $_.Name }

Write-Output "=== vcpkg status: is ffmpeg recorded installed? ==="
& 'C:\Users\JAYARAJ\vcpkg\vcpkg\vcpkg.exe' list 2>$null | Select-String 'ffmpeg'
