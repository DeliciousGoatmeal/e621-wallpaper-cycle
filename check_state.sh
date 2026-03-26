#!/usr/bin/env bash
echo "=== Plasma wallpaper config section ==="
grep -A 30 "e621-wallpaper" ~/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null || echo "not found"

echo ""
echo "=== kreadconfig6 test ==="
kreadconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
    --group "Wallpaper" --group "e621-wallpaper" --group "General" \
    --key "VideoOnly" --default "NOT_FOUND"

echo ""
echo "=== All groups containing e621 ==="
grep -n "e621\|VideoOnly\|ForceNext\|BlurRadius" ~/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | head -30
