# Fix: hwcodec needs ffmpeg (+libmfx) in the x64-windows-static triplet.
# The manifest install placed ffmpeg only in x64-windows (dynamic). Install the
# static variant in CLASSIC mode (run from a neutral dir so vcpkg doesn't switch
# to manifest mode due to vendor/rustdesk/vcpkg.json).
#
# Features must match RustDesk's manifest: amf, nvcodec, qsv.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'env.ps1')

$vcpkgExe = Join-Path $env:VCPKG_ROOT 'vcpkg.exe'

# Use RustDesk's overlay ports/triplets so the ffmpeg port matches their build.
$overlayPorts    = Join-Path $repo 'vendor\rustdesk\res\vcpkg'
$overlayTriplets = Join-Path $repo 'vendor\rustdesk\res\vcpkg-triplets'

# Run from a neutral directory (NOT vendor/rustdesk) to force classic mode.
Set-Location $env:VCPKG_ROOT

Write-Host "Installing ffmpeg[amf,nvcodec,qsv] + libmfx for x64-windows-static..." -ForegroundColor Cyan

& $vcpkgExe install `
    "ffmpeg[amf,nvcodec,qsv]:x64-windows-static" `
    "mfx-dispatch:x64-windows-static" `
    --overlay-ports="$overlayPorts" `
    --overlay-triplets="$overlayTriplets" `
    --x-install-root="$env:VCPKG_ROOT\installed"

$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Host "ffmpeg static install OK." -ForegroundColor Green
    $h = Join-Path $env:VCPKG_ROOT 'installed\x64-windows-static\include\libavcodec\avcodec.h'
    Write-Host "avcodec.h present: $(Test-Path $h)"
} else {
    Write-Host "ffmpeg static install FAILED ($code)." -ForegroundColor Red
}
exit $code
