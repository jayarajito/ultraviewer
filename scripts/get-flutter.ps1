# Download Flutter 3.24.5 (stable) project-locally to tools\flutter-3.24.5.
# RustDesk 1.5.1's Dart code targets this Flutter; our global 3.47.8 is too new.
# Keeps the global Flutter untouched. Reproducible for the K8s build image.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $repo 'tools'
$dest = Join-Path $toolsDir 'flutter-3.24.5'

if (Test-Path (Join-Path $dest 'flutter\bin\flutter.bat')) {
    Write-Host "Flutter 3.24.5 already present at $dest" -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
$url = 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip'
$zip = Join-Path $toolsDir 'flutter-3.24.5.zip'

Write-Host "Downloading Flutter 3.24.5 (~1 GB)..." -ForegroundColor Cyan
$ProgressPreference = 'SilentlyContinue'   # faster, avoids progress-bar overhead
Invoke-WebRequest -Uri $url -OutFile $zip

Write-Host "Extracting to $dest ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip

$fb = Join-Path $dest 'flutter\bin\flutter.bat'
if (Test-Path $fb) {
    Write-Host "FLUTTER 3.24.5 READY -> $fb" -ForegroundColor Green
} else {
    Write-Host "Extraction problem: flutter.bat not found under $dest" -ForegroundColor Red
    exit 1
}
