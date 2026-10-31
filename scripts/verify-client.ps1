# Static checks on a built client folder. Fails (exit 1) if the build is not what we intend to ship:
#   - our server + public key are compiled in
#   - none of the upstream phone-home hosts / the upstream public key are present
#   - the exe is branded
# Used by the client-build workflow and runnable locally:
#   powershell -ExecutionPolicy Bypass -File scripts\verify-client.ps1 [-Dir <Release folder>]
param(
    [string]$Dir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'vendor\rustdesk\flutter\build\windows\x64\runner\Release'),
    [string]$ServerHost = 'jkr.jayarajnarayanan.in',
    [string]$Key = 'WBQWPJXUFJcOp+ndfi9d6B+IOh719m5PNsa+45G6H0s=',
    [string]$AppName = 'JustKeepRemote'
)
$ErrorActionPreference = 'Stop'
$bad = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "  PASS  $what" } else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:bad++ }
}
function Count([string]$text, [string]$needle) {
    $c = 0; $i = 0
    while (($i = $text.IndexOf($needle, $i, [StringComparison]::Ordinal)) -ge 0) { $c++; $i += $needle.Length }
    $c
}

$dll = Join-Path $Dir 'librustdesk.dll'
$exe = @('rustdesk.exe', "$AppName.exe") | ForEach-Object { Join-Path $Dir $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not (Test-Path $dll) -or -not $exe) { throw "librustdesk.dll / client exe not found in $Dir" }
$s = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dll))

Write-Host "== $dll ==" -ForegroundColor Cyan
Check ((Count $s $ServerHost) -ge 1) "contains our server $ServerHost"
Check ((Count $s $Key) -ge 1) "contains our server public key"
foreach ($n in 'api.rustdesk.com', 'admin.rustdesk.com', 'rs-ny.rustdesk.com', 'OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=') {
    Check ((Count $s $n) -eq 0) "does NOT contain $n"
}
Write-Host "== $exe ==" -ForegroundColor Cyan
$vi = (Get-Item $exe).VersionInfo
Check ($vi.ProductName -eq $AppName) "ProductName is '$($vi.ProductName)' (want $AppName)"
Check ($vi.FileDescription -like "$AppName*") "FileDescription is '$($vi.FileDescription)'"
if ($bad -gt 0) { Write-Host "`n$bad CHECK(S) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "`nALL CLIENT CHECKS PASSED" -ForegroundColor Green
