# Build the Flutter client via a SHORT path to dodge Windows MAX_PATH (260) and
# OneDrive symlink issues. The repo lives under a long OneDrive path:
#   C:\Users\JAYARAJ\OneDrive\Development\Projects\UltraviewerClone\ultraviewer
# Flutter's plugin build creates very deep paths (.dir\Release\*.tlog) that blow
# past MAX_PATH there. We create a directory JUNCTION C:\jkr -> repo so the build
# sees short paths without moving any files, then run build.py from the junction.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$short = 'C:\jkr'

# Create junction C:\jkr -> repo (idempotent).
if (-not (Test-Path $short)) {
    Write-Host "Creating junction $short -> $repo" -ForegroundColor Cyan
    New-Item -ItemType Junction -Path $short -Target $repo | Out-Null
} else {
    Write-Host "Junction/path $short already exists" -ForegroundColor Yellow
}

# A running client locks Release\rustdesk.exe and the linker fails with LNK1104 (the old exe
# then makes the log look like a success). Stop it first.
Get-Process rustdesk, JustKeepRemote -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
# Enable long paths for MSBuild/CMake in this session as a belt-and-suspenders.
$env:LongPathsEnabled = '1'

# Run the build using the SHORT path for everything.
. (Join-Path $short 'scripts\env.ps1')

$rustdesk = Join-Path $short 'vendor\rustdesk'
Set-Location $rustdesk

# Clean stale flutter build (generator/path cache from the long-path attempts).
$flutterBuild = Join-Path $rustdesk 'flutter\build'
if (Test-Path $flutterBuild) {
    Write-Host "=== removing stale flutter/build ===" -ForegroundColor Cyan
    Remove-Item $flutterBuild -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "=== flutter pub get (short path) ===" -ForegroundColor Cyan
Push-Location (Join-Path $rustdesk 'flutter')
flutter pub get
$pg = $LASTEXITCODE
Pop-Location
if ($pg -ne 0) { Write-Host "pub get FAILED ($pg)" -ForegroundColor Red; exit $pg }

Write-Host "=== python build.py --flutter --hwcodec --skip-portable-pack (short path) ===" -ForegroundColor Cyan
python build.py --flutter --hwcodec --skip-portable-pack
$code = $LASTEXITCODE

$exe = Join-Path $rustdesk 'flutter\build\windows\x64\runner\Release\rustdesk.exe'
if (Test-Path $exe) {
    $f = Get-Item $exe
    Write-Host ("BUILD OK -> {0} ({1} MB)" -f $exe, [int]($f.Length/1MB)) -ForegroundColor Green
} else {
    Write-Host "build.py exit=$code; rustdesk.exe not found." -ForegroundColor Yellow
}
exit $code
