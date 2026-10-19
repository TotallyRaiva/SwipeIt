use serde::Deserialize;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const CURRENT_APP_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubRelease {
    pub tag_name: String,
    pub name: Option<String>,
    pub body: Option<String>,
    pub html_url: String,
    pub assets: Vec<GitHubAsset>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubAsset {
    pub name: String,
    pub browser_download_url: String,
    pub size: Option<u64>,
}

#[derive(Debug, Clone, Default)]
pub struct UpdateState {
    pub is_checking: bool,
    pub update_available: bool,
    pub latest_version: Option<String>,
    pub release_title: Option<String>,
    pub release_notes: Option<String>,
    pub download_url: Option<String>,
    pub release_page_url: Option<String>,
    pub status_message: Option<String>,
}

/// Asynchronous GitHub Releases update checker compatible with Windows, Linux, and macOS.
#[derive(Clone)]
pub struct UpdateChecker {
    state: Arc<Mutex<UpdateState>>,
    repo_owner: String,
    repo_name: String,
}

impl Default for UpdateChecker {
    fn default() -> Self {
        Self::new("TotallyRaiva", "SwipeIt")
    }
}

impl UpdateChecker {
    pub fn new(repo_owner: &str, repo_name: &str) -> Self {
        Self {
            state: Arc::new(Mutex::new(UpdateState::default())),
            repo_owner: repo_owner.to_string(),
            repo_name: repo_name.to_string(),
        }
    }

    pub fn snapshot(&self) -> UpdateState {
        self.state.lock().map(|g| g.clone()).unwrap_or_default()
    }

    pub fn dismiss(&self) {
        if let Ok(mut guard) = self.state.lock() {
            guard.update_available = false;
            guard.status_message = None;
        }
    }

    /// Compares two semver version strings (e.g., `"1.0.2"` vs `"1.0.1"`).
    /// Returns true if `candidate` is strictly newer than `current`.
    pub fn is_version_newer(candidate: &str, current: &str) -> bool {
        let clean_cand = candidate.trim_matches(|c| c == 'v' || c == 'V' || c == ' ' || c == '.');
        let clean_curr = current.trim_matches(|c| c == 'v' || c == 'V' || c == ' ' || c == '.');

        let cand_parts: Vec<u32> = clean_cand
            .split('.')
            .filter_map(|p| p.parse::<u32>().ok())
            .collect();
        let curr_parts: Vec<u32> = clean_curr
            .split('.')
            .filter_map(|p| p.parse::<u32>().ok())
            .collect();

        let max_len = cand_parts.len().max(curr_parts.len());
        for i in 0..max_len {
            let cand_val = *cand_parts.get(i).unwrap_or(&0);
            let curr_val = *curr_parts.get(i).unwrap_or(&0);
            if cand_val > curr_val {
                return true;
            } else if cand_val < curr_val {
                return false;
            }
        }
        false
    }

    /// Selects the appropriate release asset download URL for the current OS.
    pub fn select_asset_download_url(
        release: &GitHubRelease,
        repo_owner: &str,
        repo_name: &str,
    ) -> String {
        let target_suffix = if cfg!(target_os = "windows") {
            ".exe"
        } else if cfg!(target_os = "linux") {
            "Linux"
        } else {
            ".dmg"
        };

        if let Some(asset) = release
            .assets
            .iter()
            .find(|a| a.name.contains(target_suffix) || a.name.ends_with(".dmg"))
        {
            return asset.browser_download_url.clone();
        }

        format!(
            "https://github.com/{}/{}/releases/latest",
            repo_owner, repo_name
        )
    }

    /// Launches a non-blocking background thread to query GitHub Releases.
    pub fn check_for_updates(&self, manual: bool, last_check_ts: u64) -> Option<u64> {
        let now_secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or(Duration::ZERO)
            .as_secs();

        if !manual {
            let four_hours = 4 * 60 * 60;
            if now_secs.saturating_sub(last_check_ts) < four_hours {
                return None;
            }
        }

        {
            let mut guard = self.state.lock().ok()?;
            if guard.is_checking {
                return None;
            }
            guard.is_checking = true;
            if manual {
                guard.status_message = Some("Checking for updates…".to_string());
            }
        }

        let state_arc = Arc::clone(&self.state);
        let owner = self.repo_owner.clone();
        let repo = self.repo_name.clone();

        thread::spawn(move || {
            let url = format!(
                "https://api.github.com/repos/{}/{}/releases/latest",
                owner, repo
            );
            let agent = ureq::AgentBuilder::new()
                .timeout(Duration::from_secs(10))
                .build();

            let resp = agent
                .get(&url)
                .set("Accept", "application/vnd.github.v3+json")
                .set(
                    "User-Agent",
                    &format!("SwipeIt-CrossPlatform/{}", CURRENT_APP_VERSION),
                )
                .call();

            let mut guard = match state_arc.lock() {
                Ok(g) => g,
                Err(_) => return,
            };
            guard.is_checking = false;

            match resp {
                Ok(response) => {
                    if let Ok(release) = response.into_json::<GitHubRelease>() {
                        let remote_ver = release
                            .tag_name
                            .trim_matches(|c| c == 'v' || c == 'V' || c == ' ')
                            .to_string();
                        let newer = Self::is_version_newer(&remote_ver, CURRENT_APP_VERSION);
                        let dl_url = Self::select_asset_download_url(&release, &owner, &repo);

                        guard.latest_version = Some(remote_ver.clone());
                        guard.release_title =
                            Some(release.name.unwrap_or_else(|| release.tag_name.clone()));
                        guard.release_notes = release.body;
                        guard.download_url = Some(dl_url);
                        guard.release_page_url = Some(release.html_url);

                        if newer {
                            guard.update_available = true;
                            guard.status_message =
                                Some(format!("New version v{} available!", remote_ver));
                        } else {
                            guard.update_available = false;
                            if manual {
                                guard.status_message = Some(format!(
                                    "SwipeIt is up to date (v{}).",
                                    CURRENT_APP_VERSION
                                ));
                            } else {
                                guard.status_message = None;
                            }
                        }
                    } else if manual {
                        guard.status_message =
                            Some("Could not parse release metadata.".to_string());
                    }
                }
                Err(_) => {
                    if manual {
                        guard.status_message = Some(
                            "Update check failed. Check your internet connection.".to_string(),
                        );
                    }
                }
            }
        });

        Some(now_secs)
    }

    pub fn open_url(url: &str) {
        #[cfg(target_os = "windows")]
        {
            let _ = std::process::Command::new("cmd")
                .args(["/C", "start", "", url])
                .spawn();
        }
        #[cfg(target_os = "linux")]
        {
            let _ = std::process::Command::new("xdg-open").arg(url).spawn();
        }
        #[cfg(target_os = "macos")]
        {
            let _ = std::process::Command::new("open").arg(url).spawn();
        }
    }
}
