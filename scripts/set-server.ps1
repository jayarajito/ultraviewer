# Force the RustDesk client to use OUR self-hosted server by writing the config
# directly (the Settings UI silently failed to persist it). Closes the app first.
#
# Sets in [options]:
#   custom-rendezvous-server = <IP>
#   relay-server             = <IP>
#   key                      = <our hbbs public key>
# and sets rendezvous_server to our server so the public rs-ny is not used.

$ErrorActionPreference = 'Stop'

$server = if ($args.Count -ge 1) { $args[0] } else { '127.0.0.1' }
$key    = 'rKb+EardRcZ3Ugu3+76zh+vqvwMj67z8O+zNnKi8TtM='

# 1. Close any running client so it won't overwrite our edit on exit.
Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

$cfg = Join-Path $env:APPDATA 'RustDesk\config\RustDesk2.toml'
if (-not (Test-Path $cfg)) { Write-Host "Config not found: $cfg" -ForegroundColor Red; exit 1 }

# 2. Read, strip old server/option lines we manage, rebuild cleanly.
$lines = Get-Content $cfg
$keep = New-Object System.Collections.Generic.List[string]
$inOptions = $false
foreach ($line in $lines) {
    $t = $line.Trim()
    if ($t -eq '[options]') { $inOptions = $true; continue }        # we rebuild [options] below
    if ($t.StartsWith('[') -and $t -ne '[options]') { $inOptions = $false }
    if ($t.StartsWith('rendezvous_server')) { continue }            # replace below
    if ($inOptions) {
        if ($t.StartsWith('custom-rendezvous-server') -or
            $t.StartsWith('relay-server') -or
            $t.StartsWith('key ') -or $t -eq 'key' -or $t.StartsWith('key=') -or $t.StartsWith('key =')) { continue }
        # keep other option lines; collect them
    }
    $keep.Add($line)
}

# Collect existing [options] body (non-[section] lines after we removed managed ones).
# Simpler: rebuild file = top-level kept lines (minus any [options] body) + fresh [options].
# Re-parse: separate top-level (before first section body we manage).
# To keep it robust, just: take kept lines, drop any existing [options] body lines by
# removing lines that were under options. We already skipped the managed ones; other
# option lines (like av1-test, local-ip-addr) are harmless to preserve under a new [options].

# Build new content:
$top = @()
$optBody = @()
$inOpt = $false
foreach ($line in $keep) {
    $t = $line.Trim()
    if ($t -eq '[options]') { $inOpt = $true; continue }
    if ($t.StartsWith('[') -and $t -ne '[options]') { $inOpt = $false; $top += $line; continue }
    if ($inOpt) { if ($t -ne '') { $optBody += $line } } else { $top += $line }
}

$new = New-Object System.Collections.Generic.List[string]
$new.Add("rendezvous_server = '$server`:21116'")
foreach ($l in $top) { if ($l.Trim() -ne '') { $new.Add($l) } }
$new.Add('[options]')
$new.Add("custom-rendezvous-server = '$server'")
$new.Add("relay-server = '$server'")
$new.Add("key = '$key'")
foreach ($l in $optBody) { $new.Add($l) }

Set-Content -Path $cfg -Value $new -Encoding UTF8
Write-Host "Config updated. Server = $server, key pinned." -ForegroundColor Green
Write-Host "----- new RustDesk2.toml -----"
Get-Content $cfg
