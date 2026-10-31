# Packages the built client into dist\JustKeepRemote-<version>-win-x64.zip (+ .sha256).
# Copy the zip to any Windows PC, unzip anywhere and run JustKeepRemote.exe (portable), or click
# "Install" in the app to install it as a Windows service (needed to control UAC prompts and the
# login screen, and for unattended access that starts with Windows).
#
#   powershell -ExecutionPolicy Bypass -File scripts\package-client.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$rel  = Join-Path $repo 'vendor\rustdesk\flutter\build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $rel 'rustdesk.exe'))) { throw "Build the client first (scripts\shortpath-build.ps1): $rel" }
if (Get-Process rustdesk, JustKeepRemote -ErrorAction SilentlyContinue) { throw "Close the running client first." }

# Our own version (client\VERSION), not RustDesk's 1.5.1 base version.
$ver = (Get-Content (Join-Path $repo 'client\VERSION') -Raw).Trim()
$name = "JustKeepRemote-$ver-win-x64"
$stage = Join-Path $repo "dist\$name"
$zip = Join-Path $repo "dist\$name.zip"
Remove-Item $stage, $zip, "$zip.sha256" -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item "$rel\*" $stage -Recurse -Force
# The installer renames the exe to <app name>.exe anyway; ship it under that name.
Rename-Item (Join-Path $stage 'rustdesk.exe') 'JustKeepRemote.exe'
@"
JustKeepRemote $ver (based on RustDesk 1.5.1, AGPL-3.0)
Source: https://github.com/jayarajito/ultraviewer

Run JustKeepRemote.exe. It is preconfigured for jkr.jayarajnarayanan.in; no setup is needed.
Click "Install" in the app (accept the UAC prompt) to run it as a Windows service:
  - starts with Windows, unattended access with a permanent password
  - can control UAC prompts and the login screen
"@ | Set-Content (Join-Path $stage 'README.txt') -Encoding UTF8

Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
$h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$h  $name.zip" | Set-Content "$zip.sha256" -Encoding ASCII
Remove-Item $stage -Recurse -Force
"{0}  ({1} MB)`nsha256 {2}" -f $zip, [int]((Get-Item $zip).Length / 1MB), $h
