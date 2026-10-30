# Run this ON THE OTHER MACHINE (the one you want to control / connect from).
# Usage:  powershell -ExecutionPolicy Bypass -File client-setup.ps1 192.168.0.108
#
# 1) Tests whether this machine can reach the server's hbbs(21116)+hbbr(21117).
# 2) Writes the RustDesk client config directly (the Settings UI often fails to
#    persist), pointing at the given server with our key. Closes rustdesk first.

# -Key defaults to the DEV server key. For production pass the key read from the
# cluster:  kubectl -n justkeepremote exec deploy/jkr-server -c hbbs -- cat /data/id_ed25519.pub
param(
    [string]$Server = '192.168.0.108',
    [string]$Key    = 'rKb+EardRcZ3Ugu3+76zh+vqvwMj67z8O+zNnKi8TtM='
)
$ErrorActionPreference = 'Stop'
$key = $Key

Write-Host "=== Reachability test to $Server ===" -ForegroundColor Cyan
foreach ($p in 21115,21116,21117,21118,21119) {
    $r = Test-NetConnection -ComputerName $Server -Port $p -WarningAction SilentlyContinue
    Write-Host ("  {0}:{1}  reachable = {2}" -f $Server,$p,$r.TcpTestSucceeded)
}

Write-Host "=== Writing client config ===" -ForegroundColor Cyan
Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$dir = Join-Path $env:APPDATA 'RustDesk\config'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cfg = Join-Path $dir 'RustDesk2.toml'

$content = @"
rendezvous_server = '$Server`:21116'
nat_type = 1
serial = 0
unlock_pin = ''

[options]
custom-rendezvous-server = '$Server'
relay-server = '$Server'
key = '$key'
"@
Set-Content -Path $cfg -Value $content -Encoding UTF8
Write-Host "Config written -> $cfg" -ForegroundColor Green
Get-Content $cfg
Write-Host "`nNow launch rustdesk.exe on this machine; it should show 'Ready' against $Server." -ForegroundColor Yellow
