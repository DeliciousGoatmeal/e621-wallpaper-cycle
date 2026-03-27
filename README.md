# e621 Plasma Wallpaper

A KDE Plasma wallpaper plugin + background service that dynamically rotates images and videos from **e621**.

It supports multi-monitor setups, caching, metadata overlays, blur effects, and automatic fetching.

---

## ✨ Features

- 🎞️ Image + Video wallpapers  
- 🖥️ Multi-monitor support (independent rotation per screen)  
- 🔄 Automatic rotation based on duration or video length  
- 📥 Background downloading + caching  
- 🏷️ Tag-based filtering (full e621 search syntax)  
- 🎨 Blur + dim effects for better desktop readability  
- 📊 Metadata overlay (artist, post ID, link)  
- ⚡ Live config updates from Plasma settings  
- 🔊 Optional audio playback on a specific screen  

---

## 📦 Components

This project consists of:

1. KDE Plasma Wallpaper Plugin  
2. Rust background service (handles fetching, caching, rotation)  
3. Systemd user service (runs everything automatically)  

---

## 🚀 Installation

1. Clone the repo

    git clone https://github.com/yourusername/e621-plasma-wallpaper.git  
    cd e621-plasma-wallpaper  

2. Run installer

    chmod +x install.sh  
    ./install.sh  

This will:

- Install the Plasma wallpaper plugin  
- Compile shaders (if available)  
- Install + enable a systemd user service  

3. Start the service

    systemctl --user start e621-plasma-wallpaper  

4. Apply the wallpaper

- Right-click desktop → Configure Desktop  
- Select **e621 Wallpaper**  
- Click Apply  

---

## ⚙️ Configuration

All settings are configured via:

System Settings → Wallpaper → e621 Wallpaper

### Key Options

| Setting | Description |
|--------|-------------|
| Tags | e621 search query |
| Image Duration | Seconds per image |
| Download Batch | Files per cycle |
| Fetch Limit | Posts per API call |
| Video Only | Only use videos |
| Blur Radius | Background blur |
| Background Dim | Darkens background |
| RGB Offset | Chromatic aberration |
| Show Post Info | Toggle metadata overlay |

---

## 🧠 How It Works

- The Rust service:
  - Fetches posts from e621  
  - Filters by tags and media type  
  - Downloads media into a local cache  
  - Rotates wallpapers per screen  
  - Writes metadata to Plasma via qdbus  

- The Plasma plugin:
  - Displays media  
  - Applies blur and visual effects  
  - Shows metadata overlay  

---

## 🛠 Requirements

- KDE Plasma (Wayland recommended)  
- systemd --user  
- qdbus6  
- ffprobe (for video duration)  
- qt6-shadertools (optional)  

Install on Arch:

    sudo pacman -S qt6-shadertools ffmpeg  

---

## 📁 Cache Location

Default:

    ~/.cache/e621-plasma-wallpaper  

---

## 🔧 Development

Build the service:

    cargo build --release  

---

## ⚠️ Notes

- Respects e621 API rate limits  
- Tag choice affects media type heavily  
- Shader compilation is optional  

---

## 🧹 Troubleshooting

Logs:

    journalctl --user -u e621-plasma-wallpaper -f  

Restart:

    systemctl --user restart e621-plasma-wallpaper  
    plasmashell --replace &  

---

## 📜 License

MIT  

---

## 🙌 Credits

- zombiedoggie  

---

## ⚡ Future Ideas

- Favorites / blacklist support  
- GUI preview browser  
- Better tag profiles  
- Wayland performance tuning  