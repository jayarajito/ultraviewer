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
    [string]$Repo       = 'jayarajito/ultraviewer',   # GitHub owner/name: update check + links
    [string]$Vendor     = '',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
if (-not $Vendor) { $Vendor = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'vendor\rustdesk' }

if ($Key -notmatch '^[A-Za-z0-9+/]{43}=$') { throw "Key is not a 32-byte base64 public key (44 chars ending in '='): '$Key'" }
if ($ServerHost -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') { throw "Bad ServerHost '$ServerHost'" }
if ($AppName -notmatch '^[A-Za-z][A-Za-z0-9]*$') { throw "AppName must be letters/digits only (it becomes a service, folder and registry name): '$AppName'" }
if (-not (Test-Path (Join-Path $Vendor 'Cargo.toml'))) { throw "RustDesk checkout not found at $Vendor" }
if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw "Repo must look like owner/name: '$Repo'" }
$JkrVersion = (Get-Content (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($JkrVersion -notmatch '^\d+\.\d+\.\d+$') { throw "client\VERSION must be MAJOR.MINOR.PATCH (got '$JkrVersion')" }

$script:failed = 0
function Edit-Line {
    param([string]$RelPath, [string]$Anchor, [string]$Replacement, [string]$What)
    $path = Join-Path $Vendor $RelPath
    $text = [IO.File]::ReadAllText($path)
    # Anchors may span lines. The checkout may have LF or CRLF endings, so try both spellings.
    $pairs = @(, @($Anchor, $Replacement))
    if ($Anchor.Contains("`n") -or $Replacement.Contains("`n")) {
        $pairs += , @($Anchor.Replace("`n", "`r`n"), $Replacement.Replace("`n", "`r`n"))
    }
    foreach ($p in $pairs) {
        $left = ([regex]::Matches($text, [regex]::Escape($p[0]))).Count
        # Applied = the new text is there AND (the old text is gone, unless the new text embeds it).
        if ($text.Contains($p[1]) -and ($p[1].Contains($p[0]) -or $left -eq 0)) { Write-Host "  skip  (already applied) $What"; return }
    }
    foreach ($p in $pairs) {
        $count = ([regex]::Matches($text, [regex]::Escape($p[0]))).Count
        if ($count -eq 1) {
            if (-not $DryRun) { [IO.File]::WriteAllText($path, $text.Replace($p[0], $p[1])) }
            Write-Host "  ok    $What"
            return
        }
    }
    $count = ([regex]::Matches($text, [regex]::Escape($Anchor))).Count
    Write-Host "  FAIL  $What : anchor found $count times in $RelPath (need exactly 1)" -ForegroundColor Red
    $script:failed++
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
               "pub async fn do_check_software_update() -> hbb_common::ResultType<()> {`n    if true { return crate::jkr_update::check().await; } // JKR: check OUR GitHub releases, never upstream" 'update check -> our releases'
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
$ProjectUrl = "https://github.com/$Repo"
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

# ---------------------------------------------------------------------------------------------
# v0.2.0: update check against OUR GitHub releases (replaces upstream's, which stays removed)
# ---------------------------------------------------------------------------------------------
# Cargo.toml's `version` feeds libs/hbb_common's gen_version() build step, which writes
# src/version.rs (crate::VERSION) - this is what the About page shows AND what RustDesk's own
# protocol code uses for peer version-compatibility checks. Keep it equal to client/VERSION so
# the app never again shows "1.5.1" while actually running our own release number.
#
# Edit-Line is keyed on a FIXED anchor/replacement pair, which doesn't fit a value that changes
# every release (after the first patch, the "1.5.1" anchor is gone, so a later version bump would
# silently no-op). Edit-VersionField below finds whatever version string is CURRENTLY there (by
# capturing it, not assuming it), and substrings it out - no regex reconstruction of surrounding
# text, so CRLF/LF and any trailing comment are preserved byte-for-byte except the version itself.
function Edit-VersionField {
    param([string]$RelPath, [string]$CapturePattern, [string]$What, [string]$RegexMode = 'Multiline')
    $path = Join-Path $Vendor $RelPath
    $text = [IO.File]::ReadAllText($path)
    $found = [regex]::Matches($text, $CapturePattern, [System.Text.RegularExpressions.RegexOptions]::$RegexMode)
    if ($found.Count -ne 1) {
        Write-Host "  FAIL  $What : matched $($found.Count) times in $RelPath (need exactly 1)" -ForegroundColor Red
        $script:failed++
        return
    }
    $group = $found[0].Groups[1]
    if ($group.Value -eq $JkrVersion) { Write-Host "  skip  (already applied) $What"; return }
    if (-not $DryRun) {
        $newText = $text.Substring(0, $group.Index) + $JkrVersion + $text.Substring($group.Index + $group.Length)
        [IO.File]::WriteAllText($path, $newText)
    }
    Write-Host "  ok    $What ($JkrVersion)"
}
Edit-VersionField 'Cargo.toml' '^version = "([^"]*)"' 'Cargo.toml version synced to client/VERSION'
# Cargo.lock pins its own copy of the "rustdesk" package version, independent of Cargo.toml.
# `cargo build --locked` (what build.py runs) refuses to update a stale lock file, so a
# Cargo.toml version bump with no matching Cargo.lock edit hard-fails the build.
Edit-VersionField 'Cargo.lock' '\[\[package\]\]\s*name = "rustdesk"\s*version = "([^"]*)"' 'Cargo.lock version synced to client/VERSION' 'Singleline'
# flutter/pubspec.yaml's `version:` is a THIRD, independent version source: it feeds the Windows
# build's FLUTTER_VERSION define, which Runner.rc uses for the exe's FileVersion/ProductVersion
# (visible in Explorer's file Properties). It keeps its own build-number suffix ("+68") -
# only the dotted part needs to track client/VERSION.
Edit-VersionField 'flutter\pubspec.yaml' '^version: ([0-9]+\.[0-9]+\.[0-9]+)\+\d+\r?$' 'flutter/pubspec.yaml version synced to client/VERSION'

Write-Host "== update check (GitHub releases of $Repo, this build is $JkrVersion) ==" -ForegroundColor Cyan
$owner, $name = $Repo.Split('/')
foreach ($m in 'jkr_update_logic', 'jkr_update') {
    $code = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "src\$m.rs")).
        Replace('@JKR_REPO_OWNER@', $owner).Replace('@JKR_REPO_NAME@', $name)
    if ($code.Contains('@JKR_')) { throw "unreplaced placeholder left in $m.rs" }
    $dst = Join-Path $Vendor "src\$m.rs"
    # Only write when the content differs: a rewrite bumps the timestamp and forces cargo to recompile the crate.
    if (-not $DryRun -and (-not (Test-Path $dst) -or [IO.File]::ReadAllText($dst) -ne $code)) { [IO.File]::WriteAllText($dst, $code) }
    Write-Host "  ok    src\$m.rs"
}
Edit-Line 'src\lib.rs' 'pub mod common;' "pub mod common;`nmod jkr_update_logic;`nmod jkr_update;" 'register update modules'
Edit-Line $com "pub fn check_software_update() {`n    if is_custom_client() {`n        return;`n    }" `
               "pub fn check_software_update() {`n    crate::jkr_update::start_periodic(); // JKR: custom clients used to skip this; we check our own releases" 'update check enabled for our build'
# UI: let the existing "new version" banner appear, and make its button open the release page.
Edit-Line 'flutter\lib\common.dart' "void checkUpdate() {`n  if (!isWeb) {`n    if (!bind.isCustomClient()) {" `
               "void checkUpdate() {`n  if (!isWeb) {`n    if (true) { // JKR: custom clients used to skip this" 'update event handler enabled'
$homePage = 'flutter\lib\desktop\pages\desktop_home_page.dart'
Edit-Line $homePage "    if (!bind.isCustomClient() &&`n        updateUrl.isNotEmpty &&`n        !isCardClosed &&`n        bind.mainUriPrefixSync().contains('rustdesk')) {`n      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();" `
                "    if (updateUrl.isNotEmpty && !isCardClosed) {`n      final isToUpdate = false; // JKR: we only open the release page, never self-update" 'update banner shown'
Edit-Line $homePage "final Uri url = Uri.parse('https://rustdesk.com/download');" 'final Uri url = Uri.parse(updateUrl);' 'update banner button opens the release page'

# ---------------------------------------------------------------------------------------------
# v0.2.0: minimize button hides the main window (installed copy only; the tray icon brings it back)
# ---------------------------------------------------------------------------------------------
# Settings > General: show the "check for updates" switch (hidden for custom clients upstream) so users can
# turn the check off, and hide upstream's "auto update" switch (we never self-update, it would do nothing).
Edit-Line $setp "      if (!isWeb && !bind.isCustomClient())`n        _OptionCheckBox(`n          context,`n          'Check for software update on startup'," `
                "      if (!isWeb)`n        _OptionCheckBox(`n          context,`n          'Check for software update on startup'," 'Settings: update-check switch visible'
Edit-Line $setp '    final showAutoUpdate = (isWindows && bind.mainIsInstalled()) ||' `
                '    final showAutoUpdate = false && (isWindows && bind.mainIsInstalled()) || // JKR: no self-update' 'Settings: upstream auto-update switch hidden'

Write-Host "== hide main window on minimize ==" -ForegroundColor Cyan
# Only when installed (that is when the tray icon exists to bring the window back), not when the
# user stopped the service, and not when they turned the option off in Settings > General.
Edit-Line 'flutter\lib\desktop\widgets\tabbar_widget.dart' 'windowManager.minimize();' `
    "(isWindows && bind.mainIsInstalled() && mainGetLocalBoolOptionSync('hide-on-minimize') && bind.mainGetOptionSync(key: kOptionStopService) != 'Y') ? windowManager.hide() : windowManager.minimize();" 'minimize button hides the window'
Edit-Line $setp "      if (!isWeb && !incomingOnly)`n        _OptionCheckBox(context, 'Confirm before closing multiple tabs'," `
    "      if (isWindows && bind.mainIsInstalled())`n        _OptionCheckBox(context, 'Hide window when minimized', 'hide-on-minimize',`n            isServer: false),`n      if (!isWeb && !incomingOnly)`n        _OptionCheckBox(context, 'Confirm before closing multiple tabs'," 'Settings > General: hide-on-minimize checkbox'

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
    $srcIcon = Join-Path $brand $i[0]
    if (-not $DryRun -and (-not (Test-Path $dst) -or (Get-FileHash $srcIcon).Hash -ne (Get-FileHash $dst).Hash)) { Copy-Item $srcIcon $dst -Force }
    Write-Host "  ok    $($i[1])"
}

if ($script:failed -gt 0) { Write-Host "`n$($script:failed) edit(s) FAILED - nothing is half-applied only if -DryRun; check git -C vendor\rustdesk diff" -ForegroundColor Red; exit 1 }
Write-Host "`nAll edits $(if ($DryRun) {'verified (dry run, nothing changed)'} else {'applied'})." -ForegroundColor Green
