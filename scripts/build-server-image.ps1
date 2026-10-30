# Build the JustKeepRemote server container image FROM SOURCE.
#   powershell -ExecutionPolicy Bypass -File scripts\build-server-image.ps1 [-Tag 0.1.0]
#
# Context = vendor/rustdesk-server (Dockerfile + Dockerfile.dockerignore live in server/).
# Produces: jkr-server:<Tag> and jkr-server:dev
# First build is slow (downloads + compiles the whole dep tree inside Linux);
# later builds reuse BuildKit cache mounts.

param(
    [string]$Tag = '0.1.0',
    [int]$DisableUpdateCheck = 1   # 1 = strip upstream's daily api.rustdesk.com phone-home
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ctx  = Join-Path $repo 'vendor\rustdesk-server'
$df   = Join-Path $repo 'server\Dockerfile'

# Wait for the Docker engine (Docker Desktop may still be starting).
Write-Host "Waiting for Docker engine..." -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $ok) { Write-Host "Docker engine not reachable. Start Docker Desktop and retry." -ForegroundColor Red; exit 1 }
Write-Host "Docker engine is up." -ForegroundColor Green

$env:DOCKER_BUILDKIT = '1'
Write-Host "=== docker build jkr-server:$Tag (context: $ctx) ===" -ForegroundColor Cyan
docker build --progress=plain `
    --build-arg "DISABLE_UPDATE_CHECK=$DisableUpdateCheck" `
    -f $df `
    -t "jkr-server:$Tag" -t "jkr-server:dev" `
    $ctx
$code = $LASTEXITCODE

if ($code -eq 0) {
    Write-Host "IMAGE BUILT: jkr-server:$Tag" -ForegroundColor Green
    docker image ls jkr-server
} else {
    Write-Host "docker build FAILED (exit $code)" -ForegroundColor Red
}
exit $code
