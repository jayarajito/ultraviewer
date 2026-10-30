# JustKeepRemote — generate the Flutter-Rust bridge (NOT shipped in the repo).
# RustDesk's CI regenerates these gitignored files; we must do the same before
# building the Flutter client, or `mod bridge_generated;` fails (E0583).
#
# Versions pinned to match RustDesk CI (.github/workflows/bridge.yml):
#   cargo-expand 1.0.95, flutter_rust_bridge_codegen 1.80.1 (features: uuid)
#
# Produces: src/bridge_generated.rs, src/bridge_generated.io.rs,
#           flutter/lib/generated_bridge.dart (+ .freezed.dart)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'env.ps1')

$rustdesk = Join-Path $repo 'vendor\rustdesk'
Set-Location $rustdesk

Write-Host "=== cargo install cargo-expand 1.0.95 ===" -ForegroundColor Cyan
cargo install cargo-expand --version 1.0.95 --locked
if ($LASTEXITCODE -ne 0) { Write-Host "cargo-expand install FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== cargo install flutter_rust_bridge_codegen 1.80.1 ===" -ForegroundColor Cyan
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked
if ($LASTEXITCODE -ne 0) { Write-Host "codegen install FAILED" -ForegroundColor Red; exit 1 }

Write-Host "=== generating bridge ===" -ForegroundColor Cyan
$codegen = Join-Path $env:USERPROFILE '.cargo\bin\flutter_rust_bridge_codegen.exe'
& $codegen --rust-input ./src/flutter_ffi.rs `
           --dart-output ./flutter/lib/generated_bridge.dart `
           --c-output ./flutter/macos/Runner/bridge_generated.h
$code = $LASTEXITCODE

$gen = Join-Path $rustdesk 'src\bridge_generated.rs'
if ((Test-Path $gen) -and $code -eq 0) {
    Write-Host "BRIDGE GENERATED OK -> src/bridge_generated.rs" -ForegroundColor Green
} else {
    Write-Host "bridge generation exit=$code; bridge_generated.rs present: $(Test-Path $gen)" -ForegroundColor Yellow
}
exit $code
