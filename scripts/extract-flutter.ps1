# Robust extraction of the Flutter 3.24.5 zip using tar.exe (bsdtar, bundled in
# Windows 10/11). Expand-Archive on PS 5.1 chokes on the huge Flutter archive.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repo 'tools'
$dest = Join-Path $toolsDir 'flutter-3.24.5'
$zip  = Join-Path $toolsDir 'flutter-3.24.5.zip'

if (-not (Test-Path $zip)) {
    Write-Host "Zip not found at $zip" -ForegroundColor Red; exit 1
}

# Clean any partial extraction.
if (Test-Path $dest) {
    Write-Host "Removing partial extraction..." -ForegroundColor Yellow
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "Extracting with tar.exe (this is much faster)..." -ForegroundColor Cyan
& tar.exe -x -f $zip -C $dest
if ($LASTEXITCODE -ne 0) { Write-Host "tar extraction FAILED ($LASTEXITCODE)" -ForegroundColor Red; exit 1 }

$fb = Join-Path $dest 'flutter\bin\flutter.bat'
if (Test-Path $fb) {
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Write-Host "FLUTTER 3.24.5 EXTRACTED OK -> $fb" -ForegroundColor Green
} else {
    Write-Host "flutter.bat still missing after extraction." -ForegroundColor Red
    exit 1
}
