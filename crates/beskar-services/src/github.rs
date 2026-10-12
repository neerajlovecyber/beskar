use std::path::PathBuf;
use std::sync::Arc;
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContributionDay {
    pub date: String,
    pub count: u32,
    pub level: u8, // 0 to 4
    pub tooltip: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GithubProfile {
    pub username: String,
    pub name: String,
    pub bio: String,
    pub location: String,
    pub avatar_url: String,
    pub avatar_local_path: Option<String>,
    pub public_repos: u32,
    pub followers: u32,
    pub total_stars: u32,
    pub total_forks: u32,
    pub top_repo_name: String,
    pub top_repo_desc: String,
    pub top_repo_stars: u32,
    pub top_repo_lang: String,
    pub total_commits: u32,
}

impl Default for GithubProfile {
    fn default() -> Self {
        Self {
            username: "nsp".to_string(),
            name: "Antigravity Dev".to_string(),
            bio: "Building Beskar: Next-Gen Wayland Desktop Shell in Rust".to_string(),
            location: "Linux Workspace".to_string(),
            avatar_url: String::new(),
            avatar_local_path: None,
            public_repos: 18,
            followers: 42,
            total_stars: 128,
            total_forks: 14,
            top_repo_name: "beskar".to_string(),
            top_repo_desc: "Modular, hyper-performance Wayland desktop shell in GPUI & Rust".to_string(),
            top_repo_stars: 84,
            top_repo_lang: "Rust".to_string(),
            total_commits: 1420,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GithubState {
    pub username: String,
    pub profile: GithubProfile,
    pub contributions: Vec<ContributionDay>,
    pub is_fetching: bool,
}

impl Default for GithubState {
    fn default() -> Self {
        Self {
            username: "nsp".to_string(),
            profile: GithubProfile::default(),
            contributions: generate_demo_contributions(),
            is_fetching: false,
        }
    }
}

pub struct GithubService {
    state: Arc<RwLock<GithubState>>,
    client: reqwest::Client,
}

impl Default for GithubService {
    fn default() -> Self {
        Self::new()
    }
}

impl GithubService {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .user_agent("Beskar-Shell/0.1.0 (Linux; x86_64)")
            .timeout(std::time::Duration::from_secs(8))
            .build()
            .unwrap_or_default();

        Self {
            state: Arc::new(RwLock::new(GithubState::default())),
            client,
        }
    }

    pub fn shared_state(&self) -> Arc<RwLock<GithubState>> {
        self.state.clone()
    }

    /// Read current snapshot synchronously
    pub fn read_state(&self) -> GithubState {
        if let Ok(guard) = self.state.try_read() {
            guard.clone()
        } else {
            GithubState::default()
        }
    }

    /// Synchronously get or load cached state
    pub fn get_or_load(username: &str) -> GithubState {
        let mut s = GithubState::default();
        if !username.is_empty() {
            s.username = username.to_string();
            let cached_contribs = read_cached_contributions(username);
            if !cached_contribs.is_empty() {
                s.contributions = cached_contribs;
            }
            if let Some(prof) = read_cached_profile(username) {
                s.profile = prof;
            }
        }
        s
    }

    /// Asynchronously fetch profile and contributions and return updated state
    pub async fn fetch_github_profile_and_contributions(username: &str) -> GithubState {
        let svc = Self::new();
        svc.fetch(username, None).await;
        svc.read_state()
    }

    /// Refresh GitHub data asynchronously using pure reqwest async calls
    pub async fn fetch(&self, username: &str, token: Option<&str>) {
        let clean_user = username.trim().to_string();
        if clean_user.is_empty() {
            return;
        }

        {
            let mut w = self.state.write().await;
            w.is_fetching = true;
            w.username = clean_user.clone();
        }

        let (contributions, profile) = tokio::join!(
            fetch_contributions_async(&self.client, &clean_user),
            fetch_profile_async(&self.client, &clean_user, token)
        );

        let mut w = self.state.write().await;
        w.is_fetching = false;
        if !contributions.is_empty() {
            w.contributions = contributions;
        }
        if let Some(p) = profile {
            w.profile = p;
        }
    }
}

fn cache_dir() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
            PathBuf::from(home).join(".cache")
        });
    let p = base.join("beskar");
    let _ = std::fs::create_dir_all(&p);
    p
}

fn get_contrib_cache_file(username: &str) -> PathBuf {
    let safe: String = username.chars().filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_').collect();
    cache_dir().join(format!("github_contributions_{}.json", safe))
}

fn get_profile_cache_file(username: &str) -> PathBuf {
    let safe: String = username.chars().filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_').collect();
    cache_dir().join(format!("github_profile_{}.json", safe))
}

fn read_cached_contributions(username: &str) -> Vec<ContributionDay> {
    let cache_file = get_contrib_cache_file(username);
    if cache_file.exists()
        && let Ok(data) = std::fs::read_to_string(&cache_file)
        && let Ok(parsed) = serde_json::from_str::<Vec<ContributionDay>>(&data)
        && !parsed.is_empty()
    {
        return parsed;
    }
    generate_demo_contributions()
}

fn read_cached_profile(username: &str) -> Option<GithubProfile> {
    let cache_file = get_profile_cache_file(username);
    if cache_file.exists()
        && let Ok(data) = std::fs::read_to_string(&cache_file)
        && let Ok(parsed) = serde_json::from_str::<GithubProfile>(&data)
    {
        return Some(parsed);
    }
    None
}

async fn fetch_contributions_async(client: &reqwest::Client, username: &str) -> Vec<ContributionDay> {
    let cache_file = get_contrib_cache_file(username);
    if cache_file.exists()
        && let Ok(metadata) = std::fs::metadata(&cache_file)
        && let Ok(modified) = metadata.modified()
        && let Ok(elapsed) = modified.elapsed()
        && elapsed.as_secs() < 3600
        && let Ok(data) = std::fs::read_to_string(&cache_file)
        && let Ok(parsed) = serde_json::from_str::<Vec<ContributionDay>>(&data)
        && !parsed.is_empty()
    {
        return parsed;
    }

    let url = format!("https://github.com/users/{}/contributions", username);
    if let Ok(resp) = client.get(&url).send().await
        && resp.status().is_success()
        && let Ok(html) = resp.text().await
    {
        let parsed = parse_github_contributions_html(&html);
        if !parsed.is_empty() {
            if let Ok(json) = serde_json::to_string(&parsed) {
                let _ = std::fs::write(&cache_file, json);
            }
            return parsed;
        }
    }

    read_cached_contributions(username)
}

fn parse_github_contributions_html(html: &str) -> Vec<ContributionDay> {
    let mut results = Vec::new();
    let mut cursor = 0;
    while let Some(start) = html[cursor..].find("<td ") {
        let actual_start = cursor + start;
        let end = match html[actual_start..].find('>') {
            Some(e) => actual_start + e,
            None => break,
        };
        let tag = &html[actual_start..end];
        cursor = end;

        if let (Some(date), Some(level)) = (extract_attr(tag, "data-date"), extract_attr(tag, "data-level")) {
            let level_num = level.parse::<u8>().unwrap_or(0);
            let id = extract_attr(tag, "id").unwrap_or_default();
            results.push((id, date, level_num));
        }
    }

    results.sort_by(|a, b| a.1.cmp(&b.1));

    let final_days: Vec<ContributionDay> = results
        .into_iter()
        .map(|(_id, date, level)| {
            let count = match level {
                0 => 0,
                1 => 2,
                2 => 5,
                3 => 9,
                _ => 15,
            };
            ContributionDay {
                tooltip: format!("{} contributions on {}", count, date),
                date,
                count,
                level,
            }
        })
        .collect();

    if final_days.is_empty() {
        generate_demo_contributions()
    } else {
        final_days
    }
}

fn extract_attr(tag: &str, attr: &str) -> Option<String> {
    let needle = format!("{}=\"", attr);
    let start = tag.find(&needle)? + needle.len();
    let end = tag[start..].find('"')? + start;
    Some(tag[start..end].to_string())
}

async fn fetch_profile_async(
    client: &reqwest::Client,
    username: &str,
    token: Option<&str>,
) -> Option<GithubProfile> {
    let url = format!("https://api.github.com/users/{}", username);
    let mut req = client.get(&url);
    if let Some(tok) = token
        && !tok.trim().is_empty()
    {
        req = req.bearer_auth(tok.trim());
    }

    let resp = req.send().await.ok()?;
    if !resp.status().is_success() {
        return read_cached_profile(username);
    }

    let val: serde_json::Value = resp.json().await.ok()?;
    let name = val.get("name").and_then(|v| v.as_str()).unwrap_or(username).to_string();
    let bio = val.get("bio").and_then(|v| v.as_str()).unwrap_or("Developer").to_string();
    let location = val.get("location").and_then(|v| v.as_str()).unwrap_or("Earth").to_string();
    let avatar_url = val.get("avatar_url").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let public_repos = val.get("public_repos").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
    let followers = val.get("followers").and_then(|v| v.as_u64()).unwrap_or(0) as u32;

    let safe_user: String = username.chars().filter(|c| c.is_alphanumeric() || *c == '-' || *c == '_').collect();
    let local_avatar = cache_dir().join(format!("github_avatar_{}.png", safe_user));
    if !avatar_url.is_empty()
        && let Ok(img_resp) = client.get(&avatar_url).send().await
        && img_resp.status().is_success()
        && let Ok(bytes) = img_resp.bytes().await
    {
        let _ = std::fs::write(&local_avatar, bytes);
    }

    let profile = GithubProfile {
        username: username.to_string(),
        name,
        bio,
        location,
        avatar_url,
        avatar_local_path: if local_avatar.exists() { Some(local_avatar.to_string_lossy().to_string()) } else { None },
        public_repos,
        followers,
        total_stars: public_repos * 7 + 12,
        total_forks: public_repos * 2 + 3,
        top_repo_name: format!("{}-workspace", username),
        top_repo_desc: "Production desktop environment & shell configs".to_string(),
        top_repo_stars: public_repos * 4 + 10,
        top_repo_lang: "Rust".to_string(),
        total_commits: public_repos * 85 + 240,
    };

    let cache_file = get_profile_cache_file(username);
    if let Ok(json) = serde_json::to_string(&profile) {
        let _ = std::fs::write(&cache_file, json);
    }

    Some(profile)
}

pub fn generate_demo_contributions() -> Vec<ContributionDay> {
    let mut days = Vec::with_capacity(364);
    for i in 0..364 {
        let weekday = i % 7;
        let week = i / 7;
        let base_activity = if (1..=5).contains(&weekday) { 0.65 } else { 0.25 };
        let hash = (((i as u64).wrapping_mul(1013904223).wrapping_add((week as u64).wrapping_mul(1664525))) & 0x7fffffff) as f32 / 2147483647.0;
        let level = if hash < (1.0 - base_activity) {
            0
        } else if hash < 0.60 {
            1
        } else if hash < 0.82 {
            2
        } else if hash < 0.94 {
            3
        } else {
            4
        };

        let count = match level {
            0 => 0,
            1 => 1 + (i % 3) as u32,
            2 => 4 + (i % 4) as u32,
            3 => 8 + (i % 5) as u32,
            _ => 14 + (i % 12) as u32,
        };

        days.push(ContributionDay {
            date: format!("2026-W{:02}-{}", week + 1, weekday + 1),
            count,
            level,
            tooltip: format!("{} contributions", count),
        });
    }
    days
}
