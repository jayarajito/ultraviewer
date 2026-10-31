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
    $anchorLeft = ([regex]::Matches($text, [regex]::Escape($Anchor))).Count
    # Applied = the new text is there AND (the old text is gone, unless the new text embeds it).
    $applied = $text.Contains($Replacement) -and ($Replacement.Contains($Anchor) -or $anchorLeft -eq 0)
    if ($applied) { Write-Host "  skip  (already applied) $What"; return }
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

# ---------------------------------------------------------------------------------------------
# M2b: lock the server settings, branding text, links, icons
# ---------------------------------------------------------------------------------------------
Write-Host "== lock server settings (users cannot change server/key in Settings > Network) ==" -ForegroundColor Cyan
Edit-Line $cfg 'pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = Default::default();' `
    ("pub static ref OVERWRITE_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from([(`"custom-rendezvous-server`".to_owned(), `"$ServerHost`".to_owned()), (`"key`".to_owned(), `"$Key`".to_owned()), (`"relay-server`".to_owned(), String::new()), (`"api-server`".to_owned(), String::new())])); // JKR") 'server settings locked'

Write-Host "== branding text ==" -ForegroundColor Cyan
$ProjectUrl = 'https://github.com/jayarajito/ultraviewer'
Edit-Line 'flutter\lib\desktop\widgets\tabbar_widget.dart' '"RustDesk",' "`"$AppName`"," 'tab bar title'
$setp = 'flutter\lib\desktop\pages\desktop_setting_page.dart'
Edit-Line $setp "translate('About RustDesk')" "'About $AppName'" 'About card title'
Edit-Line $setp "launchUrlString('https://rustdesk.com/privacy.html');" "launchUrlString('$ProjectUrl');" 'privacy link'
Edit-Line $setp "launchUrlString('https://rustdesk.com');" "launchUrlString('$ProjectUrl');" 'website link'
Edit-Line 'flutter\lib\common.dart' "launchUrl(Uri.parse('https://rustdesk.com'));" "launchUrl(Uri.parse('$ProjectUrl'));" 'powered-by link'
$inst = 'flutter\lib\desktop\pages\install_page.dart'
Edit-Line $inst "'https://rustdesk.com/privacy.html')," "'$ProjectUrl')," 'install page link'
Edit-Line $inst "message: 'https://rustdesk.com/privacy.html'," "message: '$ProjectUrl'," 'install page tooltip'
Edit-Line 'flutter\lib\desktop\pages\connection_page.dart' 'const url = "https://rustdesk.com/pricing";' "const url = `"$ProjectUrl`";" 'public-server guide link'

# English UI strings: "RustDesk" -> app name (values only; keys and docs URLs are lowercase 'rustdesk').
$en = Join-Path $Vendor 'src\lang\en.rs'
$enText = [IO.File]::ReadAllText($en)
if ($enText.Contains('RustDesk')) {
    if (-not $DryRun) { [IO.File]::WriteAllText($en, $enText.Replace('RustDesk', $AppName)) }
    Write-Host "  ok    en.rs: $([regex]::Matches($enText,'RustDesk').Count) occurrences renamed"
} else { Write-Host "  skip  (already applied) en.rs strings" }

# Windows exe metadata (CompanyName/LegalCopyright keep the upstream notice: AGPL requires it).
Edit-Line 'flutter\windows\runner\Runner.rc' 'VALUE "FileDescription", "RustDesk Remote Desktop" "\0"' "VALUE `"FileDescription`", `"$AppName Remote Desktop`" `"\0`"" 'exe FileDescription'
Edit-Line 'flutter\windows\runner\Runner.rc' 'VALUE "ProductName", "RustDesk" "\0"' "VALUE `"ProductName`", `"$AppName`" `"\0`"" 'exe ProductName'
Edit-Line 'Cargo.toml' 'ProductName = "RustDesk"' "ProductName = `"$AppName`"" 'librustdesk ProductName'
Edit-Line 'Cargo.toml' 'FileDescription = "RustDesk Remote Desktop"' "FileDescription = `"$AppName Remote Desktop`"" 'librustdesk FileDescription'

Write-Host "== icons (client\branding\out, made by client\branding\make-icons.ps1) ==" -ForegroundColor Cyan
$brand = Join-Path $PSScriptRoot 'branding\out'
if (-not (Test-Path (Join-Path $brand 'icon.ico'))) { throw "Run client\branding\make-icons.ps1 first ($brand is empty)" }
$icons = @(
    @('icon.ico', 'res\icon.ico'), @('tray-icon.ico', 'res\tray-icon.ico'), @('icon.png', 'res\icon.png'),
    @('32x32.png', 'res\32x32.png'), @('64x64.png', 'res\64x64.png'), @('128x128.png', 'res\128x128.png'),
    @('128x128@2x.png', 'res\128x128@2x.png'), @('app_icon.ico', 'flutter\windows\runner\resources\app_icon.ico'),
    @('icon.png', 'flutter\assets\icon.png')
)
foreach ($i in $icons) {
    $dst = Join-Path $Vendor $i[1]
    if (-not $DryRun) { Copy-Item (Join-Path $brand $i[0]) $dst -Force }
    Write-Host "  ok    $($i[1])"
}

if ($script:failed -gt 0) { Write-Host "`n$($script:failed) edit(s) FAILED - nothing is half-applied only if -DryRun; check git -C vendor\rustdesk diff" -ForegroundColor Red; exit 1 }
Write-Host "`nAll edits $(if ($DryRun) {'verified (dry run, nothing changed)'} else {'applied'})." -ForegroundColor Green
