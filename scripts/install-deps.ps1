# JustKeepRemote — install native C/C++ dependencies via vcpkg (manifest mode).
# Reads vendor/rustdesk/vcpkg.json and builds the full static dependency set
# (aom, libvpx, libyuv, opus, libjpeg-turbo, ffmpeg w/ nvenc+qsv+amf).
# This is the longest build step. Safe to re-run; vcpkg caches completed deps.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'env.ps1')

$rustdesk = Join-Path $repo 'vendor\rustdesk'
$vcpkgExe = Join-Path $env:VCPKG_ROOT 'vcpkg.exe'

Write-Host "Installing vcpkg dependencies (manifest mode, x64-windows-static)..." -ForegroundColor Cyan
Write-Host "Working dir: $rustdesk"
Write-Host "vcpkg:       $vcpkgExe"

Push-Location $rustdesk
try {
    & $vcpkgExe install --triplet x64-windows-static --x-install-root="$env:VCPKG_ROOT\installed"
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($code -eq 0) {
    Write-Host "vcpkg dependencies installed OK." -ForegroundColor Green
} else {
    Write-Host "vcpkg install FAILED with exit code $code." -ForegroundColor Red
}
exit $code
