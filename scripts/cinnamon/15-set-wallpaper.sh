#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Set Wallpaper
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 14/19] SET WALLPAPER${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Downloading Catppuccin 'black unicat' wallpaper...${C_NC}"
sudo -u runner mkdir -p /home/runner/Pictures
sudo -u runner wget -q -O /home/runner/Pictures/wallpaper.png \
  "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/refs/heads/main/minimalistic/black5_unicat.png" \
  || { echo -e "${C_RED}[FAIL] Gagal mengunduh wallpaper.${C_NC}"; exit 1; }
sudo chown runner:runner /home/runner/Pictures/wallpaper.png

echo -e "${C_YELLOW}[INFO] Setting wallpaper via gsettings (Cinnamon schema)...${C_NC}"
# dbus-run-session menyediakan session dbus sementara agar gsettings
# menulis ke dconf user 'runner', yang dipakai saat CRD session menyala.
sudo -u runner dbus-run-session -- gsettings set org.cinnamon.desktop.background picture-uri "file:///home/runner/Pictures/wallpaper.png" || true
sudo -u runner dbus-run-session -- gsettings set org.cinnamon.desktop.background picture-options "zoom" || true
# Fallback untuk aplikasi GTK/GNOME yang membaca schema GNOME.
sudo -u runner dbus-run-session -- gsettings set org.gnome.desktop.background picture-uri "file:///home/runner/Pictures/wallpaper.png" || true
sudo -u runner dbus-run-session -- gsettings set org.gnome.desktop.background picture-uri-dark "file:///home/runner/Pictures/wallpaper.png" || true
sudo -u runner dbus-run-session -- gsettings set org.gnome.desktop.background picture-options "zoom" || true

# Fallback autostart: set ulang wallpaper saat session mulai,
# meng-cover kasus dconf belum tercatat sebelum desktop jalan.
sudo -u runner mkdir -p /home/runner/.config/autostart
sudo install -D -m 0644 -o runner -g runner "$REPO_ROOT/assets/cinnamon/autostart/set-wallpaper.desktop" /home/runner/.config/autostart/set-wallpaper.desktop

echo "------------------------------------------------------------"
ls -l /home/runner/Pictures/wallpaper.png || true
sudo -u runner file /home/runner/Pictures/wallpaper.png || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] Wallpaper installed and set for runner.${C_NC}"
