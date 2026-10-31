//! JustKeepRemote update check: the pure decision logic (no I/O, so it is unit-tested on its own).
//!
//! Input is the JSON array returned by `GET /repos/{owner}/{repo}/releases`. The newest
//! non-draft release that is newer than the running version wins. Only release pages under
//! `url_prefix` are ever returned, so a hostile or odd response cannot point the UI elsewhere.

use serde_json::Value;

/// "v1.2.3", "1.2.3-rc1" or "1.2.3+build" -> (1, 2, 3). Anything else -> None.
pub fn parse_version(s: &str) -> Option<(u64, u64, u64)> {
    let s = s.trim().trim_start_matches(|c| c == 'v' || c == 'V');
    let core = s.split(|c| c == '-' || c == '+').next()?;
    let mut parts = core.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let patch = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

/// True only when both versions parse and `candidate` is strictly greater than `current`.
pub fn is_newer(candidate: &str, current: &str) -> bool {
    match (parse_version(candidate), parse_version(current)) {
        (Some(a), Some(b)) => a > b,
        _ => false,
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct Update {
    /// The release tag, e.g. "v0.2.0".
    pub version: String,
    /// The release page, always starting with the caller's `url_prefix`.
    pub url: String,
}

pub fn select_update(releases_json: &[u8], current: &str, url_prefix: &str) -> Option<Update> {
    let value: Value = serde_json::from_slice(releases_json).ok()?;
    let releases = value.as_array()?;
    let mut best: Option<((u64, u64, u64), Update)> = None;
    for r in releases {
        if r.get("draft").and_then(Value::as_bool).unwrap_or(false) {
            continue;
        }
        let (Some(tag), Some(url)) = (
            r.get("tag_name").and_then(Value::as_str),
            r.get("html_url").and_then(Value::as_str),
        ) else {
            continue;
        };
        if !url.starts_with(url_prefix) || url.chars().any(|c| c.is_whitespace() || c.is_control()) {
            continue;
        }
        if !is_newer(tag, current) {
            continue;
        }
        let Some(ver) = parse_version(tag) else {
            continue;
        };
        if best.as_ref().map_or(true, |(b, _)| ver > *b) {
            best = Some((
                ver,
                Update {
                    version: tag.to_owned(),
                    url: url.to_owned(),
                },
            ));
        }
    }
    best.map(|(_, u)| u)
}

#[cfg(test)]
mod tests {
    use super::*;

    const PREFIX: &str = "https://github.com/o/r/releases/";

    #[test]
    fn parses_versions() {
        assert_eq!(parse_version("v0.2.0"), Some((0, 2, 0)));
        assert_eq!(parse_version("1.10.3"), Some((1, 10, 3)));
        assert_eq!(parse_version("v1.2.3-rc1"), Some((1, 2, 3)));
        assert_eq!(parse_version("1.2.3+b5"), Some((1, 2, 3)));
        assert_eq!(parse_version("1.2"), None);
        assert_eq!(parse_version("1.2.3.4"), None);
        assert_eq!(parse_version("latest"), None);
        assert_eq!(parse_version(""), None);
    }

    #[test]
    fn compares_numerically_not_lexically() {
        assert!(is_newer("v0.10.0", "0.9.0"));
        assert!(is_newer("0.2.0", "0.1.9"));
        assert!(!is_newer("0.2.0", "0.2.0"));
        assert!(!is_newer("0.1.0", "0.2.0"));
        assert!(!is_newer("garbage", "0.2.0"));
        assert!(!is_newer("0.3.0", "garbage"));
    }

    fn rel(tag: &str, draft: bool, url: &str) -> String {
        format!(r#"{{"tag_name":"{tag}","draft":{draft},"prerelease":false,"html_url":"{url}"}}"#)
    }

    #[test]
    fn picks_the_newest_non_draft() {
        let json = format!(
            "[{},{},{},{}]",
            rel("v0.3.0", true, &format!("{PREFIX}tag/v0.3.0")), // draft: ignored
            rel("v0.2.0", false, &format!("{PREFIX}tag/v0.2.0")),
            rel("v0.2.5", false, &format!("{PREFIX}tag/v0.2.5")),
            rel("v0.1.0", false, &format!("{PREFIX}tag/v0.1.0")),
        );
        let u = select_update(json.as_bytes(), "0.2.0", PREFIX).unwrap();
        assert_eq!(u.version, "v0.2.5");
        assert_eq!(u.url, format!("{PREFIX}tag/v0.2.5"));
    }

    #[test]
    fn nothing_when_up_to_date() {
        let json = format!("[{}]", rel("v0.2.0", false, &format!("{PREFIX}tag/v0.2.0")));
        assert_eq!(select_update(json.as_bytes(), "0.2.0", PREFIX), None);
        assert_eq!(select_update(json.as_bytes(), "0.3.0", PREFIX), None);
    }

    #[test]
    fn refuses_urls_outside_the_prefix() {
        let json = format!("[{}]", rel("v9.0.0", false, "https://evil.example/releases/tag/v9.0.0"));
        assert_eq!(select_update(json.as_bytes(), "0.1.0", PREFIX), None);
        let json = format!("[{}]", rel("v9.0.0", false, &format!("{PREFIX}tag/v9 .0.0")));
        assert_eq!(select_update(json.as_bytes(), "0.1.0", PREFIX), None);
    }

    #[test]
    fn tolerates_junk() {
        assert_eq!(select_update(b"", "0.1.0", PREFIX), None);
        assert_eq!(select_update(b"not json", "0.1.0", PREFIX), None);
        assert_eq!(select_update(br#"{"message":"Not Found"}"#, "0.1.0", PREFIX), None);
        assert_eq!(select_update(br#"[{"tag_name":5},{"draft":false},null,{}]"#, "0.1.0", PREFIX), None);
    }
}
