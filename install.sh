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

cp "$SRC/metadata.json"                "$DEST/metadata.json"
cp "$SRC/contents/ui/main.qml"         "$DEST/contents/ui/main.qml"
cp "$SRC/contents/ui/config.qml"       "$DEST/contents/ui/config.qml"
cp "$SRC/contents/config/main.xml"     "$DEST/contents/config/main.xml"

# ── Compile shaders ───────────────────────────────────────────────────────────
QSB=$(which qsb 2>/dev/null || find /usr -name "qsb" -type f 2>/dev/null | head -1)

if [ -n "$QSB" ]; then
    echo "Compiling shaders with: $QSB"
    # --qt6 embeds GLSL 100es/120/150 variants so the OpenGL backend can use them.
    # -b (batchable) rewrites the vertex shader for Qt Quick scene graph batching.
    "$QSB" --qt6 -b -o "$DEST/contents/shaders/chromab.vert.qsb" "$SRC/contents/shaders/chromab.vert"
    "$QSB" --qt6    -o "$DEST/contents/shaders/chromab.frag.qsb" "$SRC/contents/shaders/chromab.frag"
    echo "✓ Shaders compiled"
else
    echo "WARNING: qsb not found — chromatic aberration effect will be disabled."
    echo "  Install with: sudo pacman -S qt6-shadertools"
    echo "  Then re-run install.sh to compile the shaders."
    # Copy placeholder empty files so QML doesn't crash (chromab is only active when rgbOffset > 0)
    touch "$DEST/contents/shaders/chromab.vert.qsb"
    touch "$DEST/contents/shaders/chromab.frag.qsb"
fi

echo ""
echo "Plugin installed:"
find "$DEST" -type f | sort

# ── Systemd user service ──────────────────────────────────────────────────────
mkdir -p "$SERVICE_DIR"
cp "$SCRIPT_DIR/e621-plasma-wallpaper.service" "$SERVICE_DIR/$SERVICE_NAME.service"
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME.service"
echo ""
echo "Systemd service installed and enabled."
echo ""
echo "To start now:      systemctl --user start $SERVICE_NAME"
echo "To check logs:     journalctl --user -u $SERVICE_NAME -f"
echo ""
echo "=== Done ==="
echo ""
echo "Reload plasmashell:  plasmashell --replace &"
echo "Reapply wallpaper:   right-click desktop → Configure Desktop → e621 Wallpaper → Apply"