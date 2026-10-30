# Windows wrapper: runs the SAME bash script CI runs (scripts/helm-verify.sh) via Git-Bash.
# MSYS_NO_PATHCONV stops Git-Bash from mangling docker "-v host:/work" arguments.
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) { Write-Output "Git Bash not found at $bash"; exit 2 }
$env:MSYS_NO_PATHCONV = '1'
& $bash scripts/helm-verify.sh 2>&1 | ForEach-Object { "$_" }
exit $LASTEXITCODE
