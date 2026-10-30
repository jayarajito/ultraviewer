# Run the FROM-SOURCE server binaries natively (no Docker).
# Starts hbbr (relay) then hbbs (rendezvous), reusing the SAME keypair as the
# Docker setup so existing clients keep working. Data/keys live in server\data.
#
# Stop with: Get-Process hbbs,hbbr | Stop-Process

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bin  = Join-Path $repo 'vendor\rustdesk-server\target\release'
$data = Join-Path $repo 'server\data'   # reuse the existing key + db

New-Item -ItemType Directory -Force -Path $data | Out-Null
Set-Location $data

Write-Host "Starting hbbr (relay) ..." -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $bin 'hbbr.exe') -WorkingDirectory $data -WindowStyle Minimized

Start-Sleep -Seconds 1
Write-Host "Starting hbbs (rendezvous, relay=127.0.0.1) ..." -ForegroundColor Cyan
Start-Process -FilePath (Join-Path $bin 'hbbs.exe') -WorkingDirectory $data -ArgumentList '-r','127.0.0.1' -WindowStyle Minimized

Start-Sleep -Seconds 2
$running = Get-Process hbbs,hbbr -ErrorAction SilentlyContinue
Write-Host ("Running: {0}" -f (($running | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Green
Write-Host "Key (clients must use this):" -ForegroundColor Yellow
Get-Content (Join-Path $data 'id_ed25519.pub') -ErrorAction SilentlyContinue
Write-Host "`nNOTE: stop the Docker server first if it's using the same ports (docker compose down in server/)."
