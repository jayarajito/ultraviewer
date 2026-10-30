# Who has registered with the DEV server (our from-source image)?
Write-Output "=== containers ==="
docker ps --filter name=jkr- --format "{{.Names}}  {{.Status}}  {{.Image}}"
Write-Output "=== hbbs: client registrations / problems (last 15) ==="
docker logs jkr-hbbs 2>&1 | Select-String -Pattern 'update_pk|rror|eject|Fail' | Select-Object -Last 15 | ForEach-Object {
    $l = $_.Line; if ($l.Length -gt 150) { $l = $l.Substring(0,150) }; $l
}
Write-Output "=== hbbr: relay requests (last 5) ==="
docker logs jkr-hbbr 2>&1 | Select-String -Pattern 'relay request' | Select-Object -Last 5 | ForEach-Object {
    $l = $_.Line; if ($l.Length -gt 150) { $l = $l.Substring(0,150) }; $l
}
Write-Output "=== local RustDesk client running? ==="
if (Get-Process rustdesk -ErrorAction SilentlyContinue) { "yes" } else { "no" }
Write-Output "=== end ==="
