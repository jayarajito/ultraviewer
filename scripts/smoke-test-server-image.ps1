# Smoke-test jkr-server:dev exactly the way the K8s manifest runs it:
#   non-root, read-only root fs, tmpfs /tmp, one volume at /data, `-k _`.
# Publishes NO host ports, so it cannot disturb the running dev server.
param([string]$Image = 'jkr-server:dev')
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$vol  = 'jkr-smoke-data'
$fail = 0
function Check($name, $ok, $detail = '') {
    if ($ok) { Write-Host ("  PASS  {0} {1}" -f $name, $detail) -ForegroundColor Green }
    else     { Write-Host ("  FAIL  {0} {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

docker rm -f jkr-smoke-hbbs jkr-smoke-hbbr 2>$null | Out-Null
docker volume rm -f $vol 2>$null | Out-Null
docker volume create $vol | Out-Null

Write-Host "== 1. image + runtime user ==" -ForegroundColor Cyan
$uid = (docker run --rm --entrypoint id $Image -u).Trim()
Check "runs as uid 10001" ($uid -eq '10001') "(got $uid)"

Write-Host "== 2. shared libraries ==" -ForegroundColor Cyan
foreach ($b in 'hbbs','hbbr','rustdesk-utils') {
    $out = docker run --rm --entrypoint sh $Image -c "ldd /usr/local/bin/$b 2>&1"
    $missing = ($out | Select-String 'not found')
    Check "$b : no missing libs" (-not $missing) ($(if ($missing) { $missing } else { '' }))
}

Write-Host "== 3. privacy patch (before/after) ==" -ForegroundColor Cyan
$win = Join-Path $repo 'vendor\rustdesk-server\target\release\hbbs.exe'
if (Test-Path $win) {
    $hasWin = Select-String -Path $win -Pattern 'api.rustdesk.com' -SimpleMatch -Quiet
    Check "UNpatched Windows hbbs.exe contains api.rustdesk.com (control)" $hasWin
}
docker run --rm --entrypoint sh $Image -c "grep -c 'api.rustdesk.com' /usr/local/bin/hbbs" *> $null
Check "patched Linux hbbs has NO api.rustdesk.com" ($LASTEXITCODE -ne 0)

Write-Host "== 4. hbbs: read-only fs, non-root, -k _ ==" -ForegroundColor Cyan
docker run -d --name jkr-smoke-hbbs --read-only --tmpfs /tmp `
    --cap-drop ALL --security-opt no-new-privileges `
    -v "${vol}:/data" $Image hbbs -r 127.0.0.1:21117 -k _ | Out-Null
Start-Sleep -Seconds 6
$logs = docker logs jkr-smoke-hbbs 2>&1 | Out-String
# This source version logs the bind address too, e.g. "Listening on tcp/udp [::]:21116",
# older ones logged ":21116" - accept both.
Check "hbbs listening on 21116"      ($logs -match 'Listening on tcp/udp \S*:21116')
Check "hbbs listening on 21115"      ($logs -match 'Listening on tcp \S*:21115')
Check "hbbs advertises relay 127.0.0.1:21117" ($logs -match 'relay-servers=\["127.0.0.1:21117"\]')
Check "hbbs generated/loaded a key"  ($logs -match 'Key: ')
Check "container still running"      ((docker inspect -f '{{.State.Running}}' jkr-smoke-hbbs) -eq 'true')
$key1 = (docker run --rm -v "${vol}:/data" --entrypoint cat $Image /data/id_ed25519.pub).Trim()
$mode = (docker run --rm -v "${vol}:/data" --entrypoint stat $Image -c '%a %u' /data/id_ed25519).Trim()
Check "private key mode 600, owner 10001" ($mode -eq '600 10001') "(got '$mode')"
Write-Host "      public key: $key1"

Write-Host "== 5. hbbr: starts after key exists, -k _ ==" -ForegroundColor Cyan
docker run -d --name jkr-smoke-hbbr --read-only --tmpfs /tmp `
    --cap-drop ALL --security-opt no-new-privileges `
    -v "${vol}:/data" $Image sh -c 'until [ -s /data/id_ed25519 ]; do sleep 1; done; exec hbbr -k _' | Out-Null
Start-Sleep -Seconds 5
$rlogs = docker logs jkr-smoke-hbbr 2>&1 | Out-String
Check "hbbr listening on 21117" ($rlogs -match 'Listening on tcp \S*:21117')
Check "hbbr still running" ((docker inspect -f '{{.State.Running}}' jkr-smoke-hbbr) -eq 'true')

Write-Host "== 6. persistence: restart keeps the SAME key ==" -ForegroundColor Cyan
docker restart jkr-smoke-hbbs | Out-Null
Start-Sleep -Seconds 5
$key2 = (docker run --rm -v "${vol}:/data" --entrypoint cat $Image /data/id_ed25519.pub).Trim()
Check "key unchanged after restart" ($key1 -eq $key2 -and $key1.Length -gt 0)
$l2 = docker logs jkr-smoke-hbbs 2>&1 | Out-String
Check "restart log says key loaded from file" ($l2 -match 'Private key comes from')

docker rm -f jkr-smoke-hbbs jkr-smoke-hbbr 2>$null | Out-Null
docker volume rm -f $vol 2>$null | Out-Null
if ($fail -eq 0) { Write-Host "`nALL SMOKE TESTS PASSED" -ForegroundColor Green } else { Write-Host "`n$fail CHECK(S) FAILED" -ForegroundColor Red }
exit $fail
