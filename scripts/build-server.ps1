# JustKeepRemote — build the server (hbbs + hbbr + rustdesk-utils) from source.
# Pure Rust, no vcpkg/ffmpeg/Flutter. Needs the MSVC Rust toolchain (env.ps1).
# Produces: vendor/rustdesk-server/target/release/{hbbs.exe, hbbr.exe, rustdesk-utils.exe}

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'env.ps1')

$srv = Join-Path $repo 'vendor\rustdesk-server'
Set-Location $srv

Write-Host "=== cargo build --release (hbbs, hbbr, rustdesk-utils) ===" -ForegroundColor Cyan
cargo build --release
$code = $LASTEXITCODE

$rel = Join-Path $srv 'target\release'
foreach ($b in 'hbbs.exe','hbbr.exe','rustdesk-utils.exe') {
    $p = Join-Path $rel $b
    if (Test-Path $p) {
        $f = Get-Item $p
        Write-Host ("  OK  {0}  ({1} MB)" -f $b, [int]($f.Length/1MB)) -ForegroundColor Green
    } else {
        Write-Host ("  MISSING  {0}" -f $b) -ForegroundColor Red
    }
}
exit $code
