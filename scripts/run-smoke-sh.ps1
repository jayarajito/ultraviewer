# Run the bash smoke test locally via Git-Bash (MSYS path conversion disabled so
# docker volume specs like "name:/data" are not mangled).
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) { Write-Output "Git Bash not found at $bash"; exit 2 }
$env:MSYS_NO_PATHCONV = '1'
& $bash scripts/smoke-test-server-image.sh jkr-server:dev 2>&1 | ForEach-Object { "$_" }
Write-Output ("smoke exit={0}" -f $LASTEXITCODE)
