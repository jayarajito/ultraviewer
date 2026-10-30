# Start the DEV server from our own image, keeping the EXISTING dev keypair so the
# clients already configured with it keep working.
#   - creates volume jkr-dev-data if missing
#   - if the volume has no key yet, seeds it from server\data (id_ed25519 + .pub),
#     chmod 600 / chown 10001 (the server insists on 0600)
#   - docker compose up -d
param([string]$RelayHost = '192.168.0.108')
# 'Continue' on purpose: in Windows PowerShell 5.1 a native command's stderr (e.g.
# "no such volume") becomes a terminating error under 'Stop'. We check exit codes.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$srv  = Join-Path $repo 'server'
$vol  = 'jkr-dev-data'
$img  = 'jkr-server:dev'

if (-not (docker image ls -q $img)) { Write-Host "Image $img missing. Run scripts\build-server-image.ps1 first." -ForegroundColor Red; exit 1 }

if (-not (docker volume ls -q --filter "name=^${vol}$")) { docker volume create $vol | Out-Null; Write-Host "created volume $vol" }

$has = docker run --rm -v "${vol}:/data" --entrypoint sh $img -c 'test -s /data/id_ed25519 && echo yes || echo no'
if ($has.Trim() -ne 'yes') {
    $seed = Join-Path $srv 'data'
    if (-not (Test-Path (Join-Path $seed 'id_ed25519'))) {
        Write-Host "No existing dev key in $seed - the server will generate a NEW key on first start." -ForegroundColor Yellow
    } else {
        Write-Host "Seeding $vol with the existing dev keypair from server\data ..." -ForegroundColor Cyan
        docker run --rm --user 0 -v "${vol}:/data" -v "${seed}:/seed:ro" --entrypoint sh $img -c `
            'cp /seed/id_ed25519 /seed/id_ed25519.pub /data/ && chmod 600 /data/id_ed25519 && chmod 644 /data/id_ed25519.pub && chown -R 10001:10001 /data && ls -l /data'
    }
}

$env:RELAY_HOST = $RelayHost
Push-Location $srv
docker compose up -d
Pop-Location
Start-Sleep -Seconds 6
docker ps --filter name=jkr- --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
Write-Host "`n--- hbbs log ---"; docker logs jkr-hbbs 2>&1 | Select-Object -Last 14
Write-Host "`n--- hbbr log ---"; docker logs jkr-hbbr 2>&1 | Select-Object -Last 6
