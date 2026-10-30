# JustKeepRemote — build environment setup (dot-source this before building)
#   . .\scripts\env.ps1
# Assembles all tool paths/vars needed to build the RustDesk (Flutter) client
# from source WITHOUT permanently modifying the system environment.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# --- vcpkg (C/C++ deps: libvpx, libyuv, opus, aom) ---
# Note: real vcpkg root is the nested folder on this machine.
$vcpkgRoot = 'C:\Users\JAYARAJ\vcpkg\vcpkg'

# --- libclang (required by Rust bindgen) ---
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'

# --- NASM (assembly for aom/libvpx) — project-local install ---
$nasmDir = Join-Path $repo 'tools\nasm-2.16.03'

# --- Flutter 3.24.5 (project-local) — RustDesk 1.5.1's Dart targets this.
# Global Flutter (3.47.8) is too new for 1.5.1's UI. Prefer the local one if present.
$flutterLocalBin = Join-Path $repo 'tools\flutter-3.24.5\flutter\bin'
$flutterDir = if (Test-Path (Join-Path $flutterLocalBin 'flutter.bat')) { $flutterLocalBin } else { $null }

# --- Prepend tool dirs to PATH for this session only ---
# Flutter FIRST so the pinned 3.24.5 shadows the global install.
$prepend = (@(
    $flutterDir,
    $vcpkgRoot,
    $env:LIBCLANG_PATH,
    $nasmDir
) | Where-Object { $_ }) -join ';'
$env:PATH = "$prepend;$env:PATH"

# --- Bring in the Visual Studio Developer environment (MSVC, Ninja, Win SDK) ---
# Locate vswhere, find VS, import its dev shell module.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ($vsPath) {
        $devShell = Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
        if (Test-Path $devShell) {
            Import-Module $devShell
            Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation `
                -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
        }
    }
}

# Set VCPKG_ROOT AFTER the VS dev shell so our explicit vcpkg wins.
$env:VCPKG_ROOT = $vcpkgRoot

Write-Host "Build environment ready:" -ForegroundColor Green
Write-Host "  VCPKG_ROOT    = $env:VCPKG_ROOT"
Write-Host "  LIBCLANG_PATH = $env:LIBCLANG_PATH"
Write-Host "  NASM          = $nasmDir"
if ($flutterDir) {
    Write-Host "  FLUTTER       = $flutterDir (project-local 3.24.5)"
} else {
    Write-Host "  FLUTTER       = global (3.24.5 not installed locally yet)" -ForegroundColor Yellow
}
