# Open Windows Firewall for the self-hosted JustKeepRemote (RustDesk) server.
# RUN AS ADMINISTRATOR.
#
# The server (hbbs+hbbr) runs on THIS machine. These inbound rules let LAN clients
# reach it. Opens for Private, Domain AND Public so it works regardless of how
# Windows categorized the current network (your LAN is currently "Public").
#
# NOTE: Opening on the Public profile is acceptable on a trusted home/office LAN.
# Better long-term: set the network to Private (see set-network-private.ps1).
#
# Ports: hbbs 21115/tcp,21116/tcp,21116/udp,21118/tcp ; hbbr 21117/tcp,21119/tcp

$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $admin) {
    Write-Host "This script must be run AS ADMINISTRATOR." -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as administrator, then re-run it." -ForegroundColor Yellow
    exit 1
}

$name = 'JustKeepRemote Server'
Get-NetFirewallRule -DisplayName "$name*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

# Open for all profiles so the current network category (Public/Private/Domain) is covered.
New-NetFirewallRule -DisplayName "$name (TCP)" -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort 21115,21116,21117,21118,21119 `
    -Profile Any | Out-Null

New-NetFirewallRule -DisplayName "$name (UDP)" -Direction Inbound -Action Allow `
    -Protocol UDP -LocalPort 21116 `
    -Profile Any | Out-Null

Write-Host "Firewall opened for JustKeepRemote server (TCP 21115-21119, UDP 21116) on ALL profiles." -ForegroundColor Green
Get-NetFirewallRule -DisplayName "$name*" | Select-Object DisplayName, Enabled, Profile, Action | Format-Table -AutoSize

$prof = Get-NetConnectionProfile | Select-Object -First 1
Write-Host ("Active network: {0} (category: {1})" -f $prof.Name, $prof.NetworkCategory) -ForegroundColor Cyan
