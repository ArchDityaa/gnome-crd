#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Enable GNOME Shell Animations (software rendering fix)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 11/19] ENABLE ANIMATIONS ON SOFTWARE RENDERING${C_NC}"
echo "------------------------------------------------------------"

UUID="force-animations@software-rendering"
EXT_DIR="/usr/share/gnome-shell/extensions/$UUID"

echo -e "${C_YELLOW}[INFO] Installing GNOME Shell extension system-wide (semua user)...${C_NC}"
sudo mkdir -p "$EXT_DIR"

sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/gnome-shell/force-animations@software-rendering/metadata.json" "$EXT_DIR/metadata.json"

sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/gnome-shell/force-animations@software-rendering/extension.js" "$EXT_DIR/extension.js"

sudo chmod 0755 "$EXT_DIR"
sudo chmod 0644 "$EXT_DIR/metadata.json" "$EXT_DIR/extension.js"

echo -e "${C_YELLOW}[INFO] Writing system-wide animation slow-down env...${C_NC}"
sudo mkdir -p /etc/environment.d
printf 'GNOME_SHELL_SLOWDOWN_FACTOR=2.5\n' | sudo tee /etc/environment.d/99-gnome-animation-slow.conf > /dev/null
# Fallback untuk login via PAM (GDM/lightdm) agar env ikut tersedia.
if ! grep -q 'GNOME_SHELL_SLOWDOWN_FACTOR' /etc/environment 2>/dev/null; then
    printf '\nGNOME_SHELL_SLOWDOWN_FACTOR=2.5\n' | sudo tee -a /etc/environment > /dev/null
fi

echo -e "${C_YELLOW}[INFO] Enabling extension system-wide via dconf...${C_NC}"
sudo mkdir -p /etc/dconf/db/local.d
sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/dconf/98-force-animations" /etc/dconf/db/local.d/98-force-animations

# Profil dconf user harus membaca system-db:local (idempoten).
if ! sudo grep -qs '^system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user > /dev/null
fi
sudo dconf update || true

echo -e "${C_YELLOW}[INFO] Fallback per-user gsettings untuk 'runner'...${C_NC}"
# dbus-run-session menyediakan session dbus sementara agar gsettings
# menulis ke dconf user 'runner' (dipakai saat CRD session menyala).
sudo -u runner dbus-run-session -- gsettings set org.gnome.shell enabled-extensions "['$UUID']" || true
sudo -u runner dbus-run-session -- gsettings set org.gnome.desktop.interface enable-animations true || true
sudo chown -R runner:runner /home/runner/.config || true

echo "------------------------------------------------------------"
ls -l "$EXT_DIR" || true
echo "--- enabled-extensions (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.gnome.shell enabled-extensions || true
echo "--- enable-animations (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.gnome.desktop.interface enable-animations || true
echo "--- animation slow-down env (system) ---"
sudo cat /etc/environment.d/99-gnome-animation-slow.conf 2>/dev/null || true
echo "--- animation slow-down env (user) ---"
sudo -u runner cat /home/runner/.config/environment.d/99-gnome-animation-slow.conf 2>/dev/null || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] Animations diaktifkan lewat override global.force_animations (slow_down_factor=2.5).${C_NC}"
