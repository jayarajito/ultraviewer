# Applies the JustKeepRemote (M2) source patches to the RustDesk 1.5.1 checkout in vendor/rustdesk.
#
#   powershell -ExecutionPolicy Bypass -File client\apply-jkr-patches.ps1 -Key '<prod public key>'
#   ... -DryRun    only verify that every anchor is found exactly once; change nothing
#
# Why a script of anchored edits and not a .patch file: it fails LOUDLY when an anchor line moved
# (e.g. after a RustDesk upgrade) instead of half-applying, and it is independent of CRLF/LF.
# Re-running is safe: an edit whose replacement text is already present is skipped.
#
# What it does (see .kiro/steering/progress-log.md, M2):
#   1. bakes our server + public key as the client defaults (no setup script, no public server)
#   2. renames the app (APP_NAME) -> separate config dir, service, install dir, window title
#   3. removes the client phone-home: update check (api.rustdesk.com, sends a hardware
#      fingerprint), the default admin.rustdesk.com API server, and the heartbeat/sysinfo/audit
#      uploads (which would otherwise be POSTed to <our host>:21114 every few seconds).
param(
    [Parameter(Mandatory = $true)][string]$Key,
    [string]$ServerHost = 'jkr.jayarajnarayanan.in',
    [string]$AppName    = 'JustKeepRemote',
    [string]$Vendor     = '',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not $Vendor) { $Vendor = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'vendor\rustdesk' }

if ($Key -notmatch '^[A-Za-z0-9+/]{43}=$') { throw "Key is not a 32-byte base64 public key (44 chars ending in '='): '$Key'" }
if ($ServerHost -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') { throw "Bad ServerHost '$ServerHost'" }
if ($AppName -notmatch '^[A-Za-z][A-Za-z0-9]*$') { throw "AppName must be letters/digits only (it becomes a service, folder and registry name): '$AppName'" }
if (-not (Test-Path (Join-Path $Vendor 'Cargo.toml'))) { throw "RustDesk checkout not found at $Vendor" }

$script:failed = 0
function Edit-Line {
    param([string]$RelPath, [string]$Anchor, [string]$Replacement, [string]$What)
    $path = Join-Path $Vendor $RelPath
    $text = [IO.File]::ReadAllText($path)
    if ($text.Contains($Replacement)) { Write-Host "  skip  (already applied) $What"; return }
    $count = ([regex]::Matches($text, [regex]::Escape($Anchor))).Count
    if ($count -ne 1) { Write-Host "  FAIL  $What : anchor found $count times in $RelPath (need exactly 1)" -ForegroundColor Red; $script:failed++; return }
    if (-not $DryRun) { [IO.File]::WriteAllText($path, $text.Replace($Anchor, $Replacement)) }
    Write-Host "  ok    $What"
}

Write-Host "== libs/hbb_common/src/config.rs ==" -ForegroundColor Cyan
$cfg = 'libs\hbb_common\src\config.rs'
Edit-Line $cfg 'pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new("".to_owned());' `
               "pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new(`"$ServerHost`".to_owned()); // JKR" 'default ID/rendezvous server'
Edit-Line $cfg 'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());' `
               "pub static ref APP_NAME: RwLock<String> = RwLock::new(`"$AppName`".to_owned()); // JKR" 'app name'
Edit-Line $cfg 'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];' `
               "pub const RENDEZVOUS_SERVERS: &[&str] = &[`"$ServerHost`"]; // JKR" 'fallback server list (no public server)'
Edit-Line $cfg 'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";' `
               "pub const RS_PUB_KEY: &str = `"$Key`"; // JKR" 'server public key'

Write-Host "== libs/hbb_common/src/lib.rs (update-check URL) ==" -ForegroundColor Cyan
Edit-Line 'libs\hbb_common\src\lib.rs' 'const URL: &str = "https://api.rustdesk.com/version/latest";' `
          'const URL: &str = ""; // JKR: no phone-home' 'version-check URL emptied'

Write-Host "== src/common.rs ==" -ForegroundColor Cyan
$com = 'src\common.rs'
Edit-Line $com 'pub async fn do_check_software_update() -> hbb_common::ResultType<()> {' `
               "pub async fn do_check_software_update() -> hbb_common::ResultType<()> {`n    if true { return Ok(()); } // JKR: never contact a update server" 'update check disabled'
Edit-Line $com 'pub fn get_api_server(api: String, custom: String) -> String {' `
               "pub fn get_api_server(api: String, custom: String) -> String {`n    if true { return String::new(); } // JKR: no heartbeat/sysinfo/audit/account uploads" 'API server disabled'
Edit-Line $com '    "https://admin.rustdesk.com".to_owned()' `
               '    String::new() // JKR: no default admin.rustdesk.com' 'default admin API host removed'

if ($script:failed -gt 0) { Write-Host "`n$($script:failed) edit(s) FAILED - nothing is half-applied only if -DryRun; check git -C vendor\rustdesk diff" -ForegroundColor Red; exit 1 }
Write-Host "`nAll edits $(if ($DryRun) {'verified (dry run, nothing changed)'} else {'applied'})." -ForegroundColor Green
