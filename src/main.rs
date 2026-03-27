use anyhow::{anyhow, Context, Result};
use clap::Parser;
use dirs::config_dir;
use serde::Deserialize;
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, USER_AGENT};
use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime};
use urlencoding::encode;
use walkdir::WalkDir;

const E621_POSTS_URL: &str = "https://e621.net/posts.json";

// Config

/// Runtime configuration — loaded from the Plasma wallpaper config.
/// All values are set via System Settings → Wallpaper → e621 Wallpaper.
#[derive(Debug, Clone)]
struct AppConfig {
    user_agent: String,
    cache_dir: String,
    image_duration: u64,
    fetch_limit: usize,
    download_batch: usize,
    max_cache_files: usize,
    tags: String,
    video_only: bool,
    blur_radius: f32,
    blur_multiplier: f32,
    background_dim: f32,
    force_next_at: String,
}

impl AppConfig {
    fn load_from_plasma() -> Self {
        let cfg = read_all_plasma_config();
        let r = |key: &str, default: &str| -> String {
            cfg.get(key).cloned().unwrap_or_else(|| default.to_string())
        };
        let video_only_raw = r("VideoOnly", "false");
        log_info(&format!("VideoOnly raw: '{video_only_raw}'"));
        Self {
            user_agent:      "e621-plasma-wallpaper/0.3 (by zombiedoggie)".to_string(),
            cache_dir:       "~/.cache/e621-plasma-wallpaper".to_string(),
            tags:            r("Tags",           "rating:e gay male -female"),
            image_duration:  r("ImageDuration",  "300").parse().unwrap_or(300),
            fetch_limit:     r("FetchLimit",     "40").parse().unwrap_or(40),
            download_batch:  r("DownloadBatch",  "8").parse().unwrap_or(8),
            max_cache_files: r("MaxCacheFiles",  "300").parse().unwrap_or(300),
            video_only:      matches!(video_only_raw.to_lowercase().as_str(), "true" | "1" | "yes"),
            blur_radius:     r("BlurRadius",     "64").parse().unwrap_or(64.0),
            blur_multiplier: r("BlurMultiplier", "2.0").parse().unwrap_or(2.0),
            background_dim:  r("BackgroundDim",  "0.3").parse().unwrap_or(0.3),
            force_next_at:   r("ForceNextAt",    ""),
        }
    }
}

// CLI

#[derive(Debug, Parser)]
#[command(name = "e621-plasma-wallpaper")]
#[command(about = "Rotate KDE Plasma Wayland wallpapers from e621 posts")]
struct Cli {
    /// Override the cache directory
    #[arg(long)]
    cache_dir: Option<PathBuf>,
}

// API types

#[derive(Debug, Deserialize)]
struct ApiResponse {
    posts: Vec<Post>,
}

#[derive(Debug, Deserialize)]
struct Post {
    id: u64,
    rating: String,
    file: FileData,
    sample: SampleData,
}

#[derive(Debug, Deserialize)]
struct FileData {
    url: Option<String>,
    ext: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SampleData {
    url: Option<String>,
}

// Internal types

#[derive(Debug, Clone)]
struct DownloadCandidate {
    post_id: u64,
    url: String,
}

#[derive(Debug, Clone)]
struct DisplayTarget {
    name: String,
    width: u32,
    height: u32,
}

#[derive(Debug, Deserialize)]
struct KScreenConfig {
    outputs: Vec<KScreenOutput>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct KScreenOutput {
    name: String,
    enabled: bool,
    connected: bool,
    scale: Option<f32>,
    current_mode_id: Option<String>,
    modes: Option<Vec<KScreenMode>>,
}

#[derive(Debug, Deserialize)]
struct KScreenMode {
    id: String,
    size: KScreenSize,
}

#[derive(Debug, Deserialize)]
struct KScreenSize {
    width: u32,
    height: u32,
}

// Helpers

fn is_image_url(url: &str) -> bool {
    let l = url.to_ascii_lowercase();
    l.ends_with(".jpg") || l.ends_with(".jpeg") || l.ends_with(".png") || l.ends_with(".webp")
}

fn is_video_url(url: &str) -> bool {
    let l = url.to_ascii_lowercase();
    l.ends_with(".mp4") || l.ends_with(".webm")
}

fn is_video_path(path: &Path) -> bool {
    path.extension().and_then(OsStr::to_str)
        .map(|e| matches!(e.to_ascii_lowercase().as_str(), "mp4" | "webm"))
        .unwrap_or(false)
}

fn is_image_path(path: &Path) -> bool {
    path.extension().and_then(OsStr::to_str)
        .map(|e| matches!(e.to_ascii_lowercase().as_str(), "jpg" | "jpeg" | "png" | "webp"))
        .unwrap_or(false)
}

/// Returns the duration of a video file in seconds via ffprobe, or None on failure.
fn ffprobe_duration(path: &Path) -> Option<f64> {
    #[derive(Deserialize)]
    struct Fmt { duration: Option<String> }
    #[derive(Deserialize)]
    struct Out { format: Fmt }

    let raw = Command::new("ffprobe")
        .args(["-v", "quiet", "-print_format", "json", "-show_format",
               path.to_str().unwrap_or("")])
        .output().ok()?;
    let parsed: Out = serde_json::from_slice(&raw.stdout).ok()?;
    parsed.format.duration?.parse::<f64>().ok()
}

fn expand_tilde(input: &str) -> Result<PathBuf> {
    if let Some(rest) = input.strip_prefix("~/") {
        let home = dirs::home_dir().ok_or_else(|| anyhow!("could not resolve home dir"))?;
        return Ok(home.join(rest));
    }
    Ok(PathBuf::from(input))
}

fn filename_from_url(url: &str) -> Option<String> {
    url.split('/').last().map(|s| s.to_string())
}

// Logging

fn log_info(msg: &str)  { eprintln!("[info]  {msg}"); }
fn log_warn(msg: &str)  { eprintln!("[warn]  {msg}"); }

// Config loading





// HTTP

fn build_client(user_agent: &str) -> Result<Client> {
    let mut headers = HeaderMap::new();
    headers.insert(USER_AGENT, HeaderValue::from_str(user_agent)?);
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    Client::builder().default_headers(headers).build().context("failed to build HTTP client")
}

fn fetch_candidates(client: &Client, config: &AppConfig, video_only: bool) -> Result<Vec<DownloadCandidate>> {
    let mut tag_set: Vec<String> = config.tags
        .split_whitespace()
        .map(|s| s.to_string())
        .collect();

    if !tag_set.iter().any(|t| t.starts_with("rating:")) {
        tag_set.push("rating:e".to_string());
    }
    if video_only && !tag_set.iter().any(|t| t.starts_with("type:")) {
        tag_set.push("type:webm".to_string());
    } else if !video_only && !tag_set.iter().any(|t| t.starts_with("type:")) {
        // Exclude video types so we actually get images for the QML plugin.
        // Without this, tags like "long_playtime" cause e621 to return mostly webms.
        tag_set.retain(|t| t != "-type:webm" && t != "-type:mp4");
        tag_set.push("-type:webm".to_string());
        tag_set.push("-type:mp4".to_string());
        tag_set.push("-type:swf".to_string());
    }

    let tags_joined = tag_set.join(" ");
    log_info(&format!("fetching with tags: {}", tags_joined));

    let expected_rating = if tag_set.iter().any(|t| t == "rating:e") { "e" }
        else if tag_set.iter().any(|t| t == "rating:q") { "q" }
        else { "s" };

    let encoded_tags = encode(&tags_joined).into_owned();

    use rand::Rng;
    let mut rng = rand::thread_rng();
    let num_pages = 3usize;   // how many pages of results to collect
    let max_page  = 200usize; // upper bound for random page selection
    let page_size = 320usize; // e621 maximum per page

    let mut out: Vec<DownloadCandidate> = Vec::new();
    let mut tried: std::collections::HashSet<usize> = std::collections::HashSet::new();
    let mut found   = 0usize; // pages that returned content
    let mut attempts = 0usize;
    let max_attempts = num_pages * 6; // cap retries so we don't loop forever

    while found < num_pages && attempts < max_attempts {
        // Pick a random page we haven't tried yet this run.
        let page = loop {
            let p = rng.gen_range(1..=max_page);
            if !tried.contains(&p) { break p; }
        };
        tried.insert(page);
        attempts += 1;

        let url = format!(
            "{}?limit={}&page={}&tags={}",
            E621_POSTS_URL, page_size, page, encoded_tags
        );

        let posts = match client
            .get(&url)
            .send()
            .and_then(|r| r.error_for_status())
            .and_then(|r| r.json::<ApiResponse>())
        {
            Ok(r) => r.posts,
            Err(e) => {
                log_warn(&format!("page {page} fetch failed: {e}"));
                thread::sleep(Duration::from_millis(500));
                continue;
            }
        };

        if posts.is_empty() {
            log_info(&format!("page {page} empty, trying another random page"));
            thread::sleep(Duration::from_millis(500));
            continue;
        }

        let page_total = posts.len();
        let candidates: Vec<DownloadCandidate> = posts
            .into_iter()
            .filter(|p| p.rating == expected_rating)
            .filter_map(|p| {
                // Always prefer the full file URL
                let url = p.file.url.clone().or(p.sample.url)?;
                let ext = p.file.ext.unwrap_or_default().to_ascii_lowercase();
                let valid = if video_only {
                    matches!(ext.as_str(), "mp4" | "webm") || is_video_url(&url)
                } else {
                    matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "webp" | "mp4" | "webm")
                        || is_image_url(&url) || is_video_url(&url)
                };
                if !valid { return None; }
                Some(DownloadCandidate { post_id: p.id, url })
            })
            .collect();

        log_info(&format!("page {page}: {page_total} posts, {} usable", candidates.len()));
        out.extend(candidates);
        found += 1;

        // e621 requests max 2 req/sec.
        thread::sleep(Duration::from_millis(500));
    }

    if attempts >= max_attempts && found == 0 {
        log_warn(&format!("gave up after {max_attempts} attempts finding non-empty pages"));
    }

    if out.is_empty() {
        return Err(anyhow!("no usable posts returned from e621"));
    }

    log_info(&format!("total candidates: {}", out.len()));
    Ok(out)
}


fn download_file(client: &Client, candidate: &DownloadCandidate, dir: &Path) -> Result<PathBuf> {
    let filename = filename_from_url(&candidate.url)
        .unwrap_or_else(|| format!("post-{}.bin", candidate.post_id));
    let path = dir.join(filename);
    if path.exists() { return Ok(path); }

    let bytes = client
        .get(&candidate.url)
        .send().with_context(|| format!("failed to download {}", candidate.url))?
        .error_for_status().with_context(|| format!("bad response for {}", candidate.url))?
        .bytes().context("failed reading bytes")?;

    fs::File::create(&path)
        .with_context(|| format!("failed creating {}", path.display()))?
        .write_all(&bytes)
        .with_context(|| format!("failed writing {}", path.display()))?;

    Ok(path)
}

// Display detection

fn detect_display_targets() -> Result<Vec<DisplayTarget>> {
    let output = Command::new("kscreen-doctor")
        .arg("-j")
        .output()
        .context("failed to run kscreen-doctor -j")?;

    if !output.status.success() {
        return Err(anyhow!("kscreen-doctor -j returned non-zero status"));
    }

    let parsed: KScreenConfig = serde_json::from_slice(&output.stdout)
        .context("failed to parse kscreen-doctor JSON")?;

    let displays: Vec<DisplayTarget> = parsed.outputs
        .into_iter()
        .filter(|o| o.enabled && o.connected)
        .filter_map(|o| {
            let mode_id = o.current_mode_id.as_ref()?;
            let mode = o.modes.as_ref()?.iter().find(|m| &m.id == mode_id)?;
            Some(DisplayTarget {
                name: o.name,
                width: mode.size.width,
                height: mode.size.height,
            })
        })
        .collect();

    if displays.is_empty() {
        return Err(anyhow!("no active displays detected"));
    }
    Ok(displays)
}

// Cache management






// Main loop

/// Tell the QML plugin which file to display by setting the wallpaper configuration
/// key "MediaPath" via qdbus. The QML reads wallpaper.configuration.MediaPath live.
fn write_current_file(cache_dir: &Path, screen_index: usize, screen_name: &str, media_path: &Path) {
    // Also write the txt file as a fallback/debug aid
    let state_path = cache_dir.join(format!("current-screen{screen_index}.txt"));
    let _ = fs::write(&state_path, media_path.to_string_lossy().as_bytes());

    let path_str = media_path.to_string_lossy();
    log_info(&format!("screen{screen_index} ({screen_name}) -> {path_str}"));

    // Set MediaPath via qdbus on the correct desktop containment.
    // desktops() in Plasma KJS is indexed the same way as screen index.
    // writeConfig pushes live into wallpaper.configuration.MediaPath.
    // No reloadConfig — that destroys/recreates QML and races the write.
    let script = format!(
        r#"var d = desktops()[{screen_index}];
if (d) {{
    d.currentConfigGroup = ["Wallpaper", "e621-wallpaper", "General"];
    d.writeConfig("MediaPath", "{}");
}}"#,
        path_str
    );

    // Retry a few times — plasmashell may not be fully ready on startup
    for attempt in 0..3u32 {
        let result = Command::new("qdbus6")
            .args(["org.kde.plasmashell", "/PlasmaShell",
                   "org.kde.PlasmaShell.evaluateScript", &script])
            .output();

        match result {
            Ok(out) => {
                let stdout = String::from_utf8_lossy(&out.stdout);
                let stderr = String::from_utf8_lossy(&out.stderr);
                // Success — no error output means the script ran
                if stderr.is_empty() && !stdout.contains("error") {
                    break;
                }
                if attempt < 2 {
                    log_warn(&format!("qdbus attempt {attempt} failed, retrying..."));
                    thread::sleep(Duration::from_secs(2));
                } else {
                    if !stderr.is_empty() { log_warn(&format!("qdbus stderr: {}", stderr.trim())); }
                    if !stdout.trim().is_empty() { log_warn(&format!("qdbus stdout: {}", stdout.trim())); }
                }
            }
            Err(e) => {
                log_warn(&format!("qdbus failed: {e}"));
                break;
            }
        }
    }
}

/// Tell Plasma to use our wallpaper plugin on a given screen via qdbus.
fn activate_plugin(screen_index: usize) {
    let script = format!(
        r#"var d = desktops()[{screen_index}];
d.wallpaperPlugin = "e621-wallpaper";
d.reloadConfig();"#
    );
    let ok = Command::new("qdbus6")
        .args(["org.kde.plasmashell", "/PlasmaShell",
               "org.kde.PlasmaShell.evaluateScript", &script])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    if ok {
        log_info(&format!("activated e621-wallpaper plugin on desktop {screen_index}"));
    } else {
        log_warn(&format!("failed to activate plugin on desktop {screen_index} — is it installed?"));
    }
}

fn plasma_config_path() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("plasma-org.kde.plasma.desktop-appletsrc")
}

/// Read all e621-wallpaper config values by directly parsing the INI file.
/// Merges ALL matching [Containments][N][Wallpaper][e621-wallpaper][General]
/// sections so values from any screen are picked up (later sections override).
fn read_all_plasma_config() -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    let path = plasma_config_path();
    let Ok(contents) = fs::read_to_string(&path) else {
        return map;
    };

    let target_suffix = "][Wallpaper][e621-wallpaper][General]";
    let mut in_section = false;

    for line in contents.lines() {
        if line.starts_with('[') {
            in_section = line.contains(target_suffix);
            continue;
        }
        if !in_section { continue; }
        if let Some((k, v)) = line.split_once('=') {
            let key = k.trim().to_string();
            let val = v.trim().to_string();
            // ForceNextAt: keep the most recent non-empty value
            if key == "ForceNextAt" {
                if !val.is_empty() {
                    map.insert(key, val);
                }
            } else {
                // For other keys, first section wins (primary screen settings)
                map.entry(key).or_insert(val);
            }
        }
    }
    map
}

/// Get the last-modified time of the Plasma config file.
fn plasma_config_mtime() -> Option<SystemTime> {
    fs::metadata(plasma_config_path()).and_then(|m| m.modified()).ok()
}

/// Push visual config values to the QML plugin via qdbus so the blur/dim
/// settings from System Settings take effect immediately.
fn push_visual_config(screen_index: usize, blur_radius: f32, blur_mult: f32, bg_dim: f32) {
    let script = format!(
        r#"var d = desktops()[{screen_index}];
if (d) {{
    d.currentConfigGroup = ["Wallpaper", "e621-wallpaper", "General"];
    d.writeConfig("BlurRadius",     {blur_radius});
    d.writeConfig("BlurMultiplier", {blur_mult});
    d.writeConfig("BackgroundDim",  {bg_dim});
}}"#
    );
    let _ = Command::new("qdbus6")
        .args(["org.kde.plasmashell", "/PlasmaShell",
               "org.kde.PlasmaShell.evaluateScript", &script])
        .output();
}

fn flush_cache(cache_dir: &Path) {
    log_info("flushing cache on startup...");
    let mut count = 0usize;
    let entries: Vec<_> = WalkDir::new(cache_dir)
        .min_depth(1).max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .filter(|e| is_image_path(e.path()) || is_video_path(e.path()))
        .collect();
    for entry in entries {
        if fs::remove_file(entry.path()).is_ok() { count += 1; }
    }
    log_info(&format!("flushed {count} files"));
}

fn prune_played(cache_dir: &Path, min_age: Duration, active: &[PathBuf]) {
    let now = SystemTime::now();
    let mut pruned = 0usize;
    let entries: Vec<_> = WalkDir::new(cache_dir)
        .min_depth(1).max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .filter(|e| is_image_path(e.path()) || is_video_path(e.path()))
        .collect();
    for entry in entries {
        let path = entry.path().to_path_buf();
        // Never prune a file that is currently being displayed.
        if active.iter().any(|a| a == &path) {
            continue;
        }
        let accessed = fs::metadata(&path)
            .and_then(|m| m.accessed())
            .unwrap_or(SystemTime::UNIX_EPOCH);
        let age = now.duration_since(accessed).unwrap_or(Duration::ZERO);
        if age > min_age {
            if fs::remove_file(&path).is_ok() {
                pruned += 1;
                log_info(&format!("pruned played: {}", path.display()));
            }
        }
    }
    if pruned > 0 { log_info(&format!("pruned {pruned} played files")); }
}

fn pick_next(cache_dir: &Path, video_only: bool, last: Option<&PathBuf>) -> Option<PathBuf> {
    use rand::seq::SliceRandom;
    let mut candidates: Vec<PathBuf> = WalkDir::new(cache_dir)
        .min_depth(1).max_depth(1)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_file())
        .filter(|e| {
            if video_only { is_video_path(e.path()) }
            else { is_image_path(e.path()) || is_video_path(e.path()) }
        })
        .map(|e| e.path().to_path_buf())
        .filter(|p| last.map_or(true, |l| l != p))
        .collect();
    candidates.shuffle(&mut rand::thread_rng());
    candidates.into_iter().next()
}

fn main() -> Result<()> {
    use rand::Rng;
    use rand::seq::SliceRandom;

    let cli = Cli::parse();

    // Load config from Plasma — no config.toml needed
    let mut config = AppConfig::load_from_plasma();

    // CLI override for cache dir only
    if let Some(d) = &cli.cache_dir {
        config.cache_dir = d.display().to_string();
    }

    let cache_dir = expand_tilde(&config.cache_dir)?;
    fs::create_dir_all(&cache_dir)
        .with_context(|| format!("failed to create cache dir {}", cache_dir.display()))?;

    let client = build_client(&config.user_agent)?;

    log_info("started");
    log_info(&format!("cache dir: {}", cache_dir.display()));

    // Give plasmashell a moment to fully initialize before we start calling qdbus.
    // Without this, writeConfig calls on startup often fail silently.
    log_info("waiting for plasmashell to initialize...");
    thread::sleep(Duration::from_secs(3));
    log_info(&format!("tags: {}", config.tags));
    log_info(&format!("video_only: {}", config.video_only));
    log_info(&format!("image_duration: {}s", config.image_duration));

    flush_cache(&cache_dir);

    // Download initial batch
    let targets = detect_display_targets()?;
    log_info(&format!("{} display(s) detected", targets.len()));

    let blur_radius = config.blur_radius;
    let blur_mult   = config.blur_multiplier;
    let bg_dim      = config.background_dim;
    log_info(&format!("blur={blur_radius} mult={blur_mult} dim={bg_dim}"));

    let mut last_shown: Vec<Option<PathBuf>> = vec![None; targets.len()];

    for (i, target) in targets.iter().enumerate() {
        activate_plugin(i);
        push_visual_config(i, blur_radius, blur_mult, bg_dim);
    }

    let mut rng = rand::thread_rng();
    let mut screen_durations: Vec<Duration> = vec![Duration::from_secs(config.image_duration); targets.len()];
    let mut screen_timers: Vec<std::time::Instant> = vec![std::time::Instant::now(); targets.len()];

    log_info("fetching initial batch...");
    match fetch_candidates(&client, &config, config.video_only) {
        Ok(candidates) => {
            let mut downloaded = 0usize;
            let mut first_shown = vec![false; targets.len()];
            for candidate in candidates {
                if downloaded >= config.download_batch { break; }
                match download_file(&client, &candidate, &cache_dir) {
                    Ok(path) => {
                        downloaded += 1;
                        log_info(&format!("cached {}", path.display()));
                        // Show on each screen as soon as first file is ready
                        for (i, target) in targets.iter().enumerate() {
                            if !first_shown[i] {
                                if path.exists() {
                                    write_current_file(&cache_dir, i, &target.name, &path);
                                    last_shown[i] = Some(path.clone());
                                    first_shown[i] = true;
                                    if is_video_path(&path) {
                                        if let Some(dur) = ffprobe_duration(&path) {
                                            log_info(&format!("screen{i} initial video duration: {dur:.1}s"));
                                            screen_durations[i] = Duration::from_secs_f64(dur);
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => log_warn(&format!("download failed: {e}")),
                }
                thread::sleep(Duration::from_millis(500));
            }
            log_info(&format!("initial batch: {downloaded} files"));

        // Stagger screen timers so monitors rotate independently of each other
        for i in 0..targets.len() {
            if first_shown[i] {
                let max_offset = screen_durations[i].as_secs().saturating_sub(5);
                if max_offset > 0 {
                    let offset = rng.gen_range(0..max_offset);
                    screen_timers[i] = std::time::Instant::now() - Duration::from_secs(offset);
                }
            }
        }
        }
        Err(e) => log_warn(&format!("initial fetch failed: {e}")),
    }

    let tick              = Duration::from_secs(2);  // config + rotation check interval
    let download_every   = 8u32;                     // download every N ticks (~16s)
    let played_age       = Duration::from_secs(600);
    let prune_interval   = Duration::from_secs(120);
    let mut last_prune   = std::time::Instant::now();
    let mut fetch_cursor: Vec<DownloadCandidate> = Vec::new();
    let mut ticks_since_download = download_every;   // trigger a download on first tick

    // Track Plasma config mtime for hot-reload
    let mut last_config_mtime = plasma_config_mtime();

    loop {
        thread::sleep(tick);

        // ── Hot-reload config when System Settings changes it ─────────────────
        let current_mtime = plasma_config_mtime();
        if current_mtime != last_config_mtime {
            let new_config = AppConfig::load_from_plasma();
            last_config_mtime = current_mtime;

            // Check if "Force Next" button was pressed
            if new_config.force_next_at != config.force_next_at
                && !new_config.force_next_at.is_empty() {
                log_info("Force next triggered from System Settings");
                for (i, target) in targets.iter().enumerate() {
                    let last = last_shown[i].as_ref();
                    if let Some(path) = pick_next(&cache_dir, new_config.video_only, last) {
                        if path.exists() {
                            write_current_file(&cache_dir, i, &target.name, &path);
                            screen_durations[i] = if is_video_path(&path) {
                                ffprobe_duration(&path)
                                    .map(|d| Duration::from_secs_f64(d))
                                    .unwrap_or(Duration::from_secs(new_config.image_duration))
                            } else {
                                Duration::from_secs(new_config.image_duration)
                            };
                            last_shown[i] = Some(path);
                            screen_timers[i] = std::time::Instant::now();
                        }
                    }
                }
            }

            // Reload settings if anything else changed
            if new_config.tags != config.tags
                || new_config.video_only != config.video_only
                || new_config.image_duration != config.image_duration
                || new_config.blur_radius != config.blur_radius {
                log_info(&format!("tags: {}  video_only: {}  image_duration: {}s",
                    new_config.tags, new_config.video_only, new_config.image_duration));
                // Push updated visual config to QML
                for i in 0..targets.len() {
                    push_visual_config(i, new_config.blur_radius, new_config.blur_multiplier, new_config.background_dim);
                }
                // Clear fetch cursor so next download uses new tags
                fetch_cursor.clear();
            }
            config = new_config;
        }

        // ── Rotate screens ────────────────────────────────────────────────────
        for (i, target) in targets.iter().enumerate() {
            if screen_timers[i].elapsed() >= screen_durations[i] {
                let last = last_shown[i].as_ref();
                if let Some(path) = pick_next(&cache_dir, config.video_only, last) {
                    if path.exists() {
                        write_current_file(&cache_dir, i, &target.name, &path);
                        screen_durations[i] = if is_video_path(&path) {
                            ffprobe_duration(&path)
                                .map(|d| { log_info(&format!("screen{i} video {d:.1}s")); Duration::from_secs_f64(d) })
                                .unwrap_or(Duration::from_secs(config.image_duration))
                        } else {
                            Duration::from_secs(config.image_duration)
                        };
                        last_shown[i] = Some(path);
                    } else {
                        log_warn(&format!("picked file vanished: {}", path.display()));
                    }
                }
                screen_timers[i] = std::time::Instant::now();
            }
        }

        // ── Prune played files ────────────────────────────────────────────────
        if last_prune.elapsed() >= prune_interval {
            let active: Vec<PathBuf> = last_shown.iter().filter_map(|p| p.clone()).collect();
            prune_played(&cache_dir, played_age, &active);
            last_prune = std::time::Instant::now();
        }

        // ── Download one file (every N ticks) ────────────────────────────────
        ticks_since_download += 1;
        if ticks_since_download >= download_every {
            ticks_since_download = 0;
            if fetch_cursor.is_empty() {
                match fetch_candidates(&client, &config, config.video_only) {
                    Ok(mut candidates) => {
                        candidates.shuffle(&mut rng);
                        fetch_cursor = candidates;
                        log_info(&format!("refilled cursor: {} candidates", fetch_cursor.len()));
                    }
                    Err(e) => { log_warn(&format!("fetch failed: {e}")); continue; }
                }
            }

            if let Some(candidate) = fetch_cursor.pop() {
                match download_file(&client, &candidate, &cache_dir) {
                    Ok(path) => log_info(&format!("downloaded {}", path.display())),
                    Err(e)   => log_warn(&format!("download failed: {e}")),
                }
            }
        }
    }
}
