//! JustKeepRemote update check.
//!
//! Asks GitHub whether a newer release of this project exists. If so, the existing "new version"
//! banner in the main window is pointed at that release page. NOTHING is downloaded or installed
//! automatically: the user opens the page and installs the new version themselves.
//!
//! The placeholders below are filled in by `client/apply-jkr-patches.ps1`.

use crate::{common::SOFTWARE_UPDATE_URL, hbbs_http::create_http_client_async, jkr_update_logic};
use hbb_common::{anyhow::bail, log, tls::TlsType, ResultType};
use std::{sync::Once, time::Duration};

/// The version of THIS build (from client/VERSION).
pub const JKR_VERSION: &str = "@JKR_VERSION@";
const REPO_OWNER: &str = "@JKR_REPO_OWNER@";
const REPO_NAME: &str = "@JKR_REPO_NAME@";
/// How often a running app re-checks.
const RECHECK_EVERY: Duration = Duration::from_secs(12 * 60 * 60);

fn clear() {
    *SOFTWARE_UPDATE_URL.lock().unwrap() = String::new();
}

fn publish(url: &str) {
    *SOFTWARE_UPDATE_URL.lock().unwrap() = url.to_owned();
    #[cfg(feature = "flutter")]
    {
        let mut m = std::collections::HashMap::new();
        m.insert("name", "check_software_update_finish");
        m.insert("url", url);
        if let Ok(data) = serde_json::to_string(&m) {
            let _ = crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, data);
        }
    }
}

async fn fetch(url: &str, tls_type: TlsType) -> ResultType<Vec<u8>> {
    let client = create_http_client_async(tls_type, false);
    let resp = client
        .get(url)
        .header("User-Agent", format!("JustKeepRemote/{JKR_VERSION}"))
        .header("Accept", "application/vnd.github+json")
        .timeout(Duration::from_secs(20))
        .send()
        .await?;
    let status = resp.status();
    if status == reqwest::StatusCode::NOT_FOUND {
        // A private repository (or no releases at all) looks like this to an anonymous client.
        log::info!("update check: no public releases visible at {url}");
        return Ok(b"[]".to_vec());
    }
    if !status.is_success() {
        bail!("update check failed with HTTP status {status}");
    }
    Ok(resp.bytes().await?.to_vec())
}

/// One check. Called by `do_check_software_update()` (see apply-jkr-patches.ps1).
pub async fn check() -> ResultType<()> {
    let api = format!("https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases?per_page=20");
    let prefix = format!("https://github.com/{REPO_OWNER}/{REPO_NAME}/releases/");
    let body = match fetch(&api, TlsType::Rustls).await {
        Ok(b) => b,
        Err(e) => {
            log::debug!("update check with rustls failed ({e}), retrying with native TLS");
            match fetch(&api, TlsType::NativeTls).await {
                Ok(b) => b,
                Err(e) => {
                    clear();
                    return Err(e);
                }
            }
        }
    };
    match jkr_update_logic::select_update(&body, JKR_VERSION, &prefix) {
        Some(update) => {
            log::info!("update check: {} is available (running {JKR_VERSION})", update.version);
            publish(&update.url);
        }
        None => {
            log::debug!("update check: {JKR_VERSION} is up to date");
            clear();
        }
    }
    Ok(())
}

/// A long-running app (installed, living in the tray) checks again every 12 hours.
/// Safe to call repeatedly; only the first call starts the timer.
pub fn start_periodic() {
    static START: Once = Once::new();
    START.call_once(|| {
        std::thread::spawn(|| loop {
            std::thread::sleep(RECHECK_EVERY);
            // Respects the user's "check for updates" setting.
            crate::common::check_software_update();
        });
    });
}
