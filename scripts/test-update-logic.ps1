# Runs the unit tests of client\src\jkr_update_logic.rs in a throw-away cargo project
# (the full RustDesk crate takes far too long to test-compile for 8 pure-logic tests).
#   powershell -ExecutionPolicy Bypass -File scripts\test-update-logic.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$t = Join-Path $env:TEMP 'jkr-logic-test'
Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory (Join-Path $t 'src') | Out-Null
$src = (Join-Path $repo 'client\src\jkr_update_logic.rs').Replace('\', '/')
@'
[package]
name = "t"
version = "0.1.0"
edition = "2021"
[dependencies]
serde_json = "1.0"
'@ | Set-Content (Join-Path $t 'Cargo.toml')
"#[path = `"$src`"]`npub mod jkr_update_logic;" | Set-Content (Join-Path $t 'src\lib.rs')
$ErrorActionPreference = 'Continue'
cargo test --manifest-path (Join-Path $t 'Cargo.toml') 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue
exit $code
