# Set the active network to PRIVATE (recommended for a trusted home/office LAN).
# Public profile blocks most inbound traffic; Private lets LAN peers reach our
# server. RUN AS ADMINISTRATOR.

$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $admin) {
    Write-Host "Run AS ADMINISTRATOR." -ForegroundColor Red; exit 1
}

Get-NetConnectionProfile | ForEach-Object {
    if ($_.NetworkCategory -eq 'Public') {
        Write-Host ("Setting '{0}' from Public -> Private" -f $_.Name) -ForegroundColor Cyan
        Set-NetConnectionProfile -Name $_.Name -NetworkCategory Private
    } else {
        Write-Host ("'{0}' already {1}" -f $_.Name, $_.NetworkCategory) -ForegroundColor Yellow
    }
}
Get-NetConnectionProfile | Select-Object Name, NetworkCategory | Format-Table -AutoSize
