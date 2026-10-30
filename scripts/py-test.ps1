$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
python -m py_compile scripts/whitelist-public-ip/whitelist-runner-ip-and-rm.py
Write-Output ("py_compile exit={0}" -f $LASTEXITCODE)
python -m unittest discover -s scripts/whitelist-public-ip -v 2>&1 | ForEach-Object { "$_" }
Write-Output ("unittest exit={0}" -f $LASTEXITCODE)
