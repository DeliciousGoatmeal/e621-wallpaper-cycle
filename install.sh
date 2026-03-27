#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="e621-wallpaper"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/plugin/$PLUGIN_ID"
DEST="$HOME/.local/share/plasma/wallpapers/$PLUGIN_ID"
SERVICE_NAME="e621-plasma-wallpaper"
SERVICE_DIR="$HOME/.config/systemd/user"

echo "=== Installing $PLUGIN_ID ==="
echo ""

# ── Plasma wallpaper plugin ───────────────────────────────────────────────────
rm -rf "$DEST"
mkdir -p "$DEST/contents/ui"
mkdir -p "$DEST/contents/config"
mkdir -p "$DEST/contents/shaders"

cp "$SRC/metadata.json"                             "$DEST/metadata.json"
cp "$SRC/contents/ui/main.qml"                      "$DEST/contents/ui/main.qml"
cp "$SRC/contents/ui/config.qml"                    "$DEST/contents/ui/config.qml"
cp "$SRC/contents/config/main.xml"                  "$DEST/contents/config/main.xml"
cp "$SRC/contents/shaders/chromab.vert.qsb"         "$DEST/contents/shaders/chromab.vert.qsb"
cp "$SRC/contents/shaders/chromab.frag.qsb"         "$DEST/contents/shaders/chromab.frag.qsb"

echo "Plugin installed:"
find "$DEST" -type f | sort

# ── Systemd user service ──────────────────────────────────────────────────────
mkdir -p "$SERVICE_DIR"
cp "$SCRIPT_DIR/e621-plasma-wallpaper.service" "$SERVICE_DIR/$SERVICE_NAME.service"
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME.service"
echo ""
echo "Systemd service installed and enabled."
echo "It will start automatically after plasmashell on next login."
echo ""
echo "To start it now:"
echo "  systemctl --user start $SERVICE_NAME"
echo ""
echo "To check status / logs:"
echo "  systemctl --user status $SERVICE_NAME"
echo "  journalctl --user -u $SERVICE_NAME -f"
echo ""
echo "=== Done ==="
echo ""
echo "Reload plasmashell:  plasmashell --replace &"
echo "Reapply wallpaper:   right-click desktop → Configure Desktop → e621 Wallpaper → Apply"
