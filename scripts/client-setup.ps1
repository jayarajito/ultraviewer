# Run this ON EACH MACHINE (the one you want to control and the one you connect from).
# Usage (prod, standard ports):
#   powershell -ExecutionPolicy Bypass -File client-setup.ps1 -Server jkr.jayarajnarayanan.in -Key '<public key>'
# Usage (int, ports 22116/22117):
#   powershell -ExecutionPolicy Bypass -File client-setup.ps1 -Server jkr.jayarajnarayanan.in -IdPort 22116 -RelayPort 22117 -Key '<public key>'
#
# 1) Tests whether this machine can reach the server's TCP ports.
# 2) Writes the RustDesk client config directly (the Settings UI often fails to
#    persist), pointing at the given server with our key. Closes rustdesk first.
# The public key is printed in the deploy workflow run summary ("Server public key"), or:
#   kubectl -n jkr-int exec deploy/jkr-server -c hbbs -- cat /data/id_ed25519.pub
# -Key defaults to the DEV (local Docker) server key.
param(
    [string]$Server    = '192.168.0.108',
    [string]$Key       = 'rKb+EardRcZ3Ugu3+76zh+vqvwMj67z8O+zNnKi8TtM=',
    [int]$IdPort       = 21116,
    [int]$RelayPort    = 21117
)
$ErrorActionPreference = 'Stop'
$key = $Key
# hbbs: IdPort-1 (NAT test), IdPort, IdPort+2 (ws); hbbr: RelayPort, RelayPort+2 (ws)
$ports = @(($IdPort - 1), $IdPort, $RelayPort, ($IdPort + 2), ($RelayPort + 2))
Write-Host "=== Reachability test to $Server ===" -ForegroundColor Cyan
foreach ($p in $ports) {
    $r = Test-NetConnection -ComputerName $Server -Port $p -WarningAction SilentlyContinue
    Write-Host ("  {0}:{1}  reachable = {2}" -f $Server,$p,$r.TcpTestSucceeded)
}
# Standard ports need no ':port' suffix; others do.
$idAddr    = if ($IdPort -eq 21116)    { $Server } else { "$Server`:$IdPort" }
$relayAddr = if ($RelayPort -eq 21117) { $Server } else { "$Server`:$RelayPort" }
Write-Host "=== Writing client config ===" -ForegroundColor Cyan
Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$dir = Join-Path $env:APPDATA 'RustDesk\config'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cfg = Join-Path $dir 'RustDesk2.toml'
$content = @"
rendezvous_server = '$Server`:$IdPort'
nat_type = 1
serial = 0
unlock_pin = ''
[options]
custom-rendezvous-server = '$idAddr'
relay-server = '$relayAddr'
key = '$key'
"@
Set-Content -Path $cfg -Value $content -Encoding UTF8
Write-Host "Config written -> $cfg" -ForegroundColor Green
Get-Content $cfg
Write-Host "`nNow launch rustdesk.exe on this machine; it should show 'Ready' against $idAddr." -ForegroundColor Yellow
