#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Disable Screensaver and Lock
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 10/19] DISABLE SCREENSAVER AND LOCK${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Disabling GNOME lock/suspend system-wide...${C_NC}"
sudo mkdir -p /etc/dconf/db/local.d || true
sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/dconf/99-crd-no-lock" /etc/dconf/db/local.d/99-crd-no-lock
sudo dconf update || true

# Fallback per-user gsettings (jalan saat sesi aktif; abaikan bila dbus belum ada).
sudo -u runner dbus-launch --exit-with-session gsettings set org.gnome.desktop.screensaver lock-enabled false || true
sudo -u runner dbus-launch --exit-with-session gsettings set org.gnome.desktop.screensaver idle-activation-enabled false || true
sudo -u runner dbus-launch --exit-with-session gsettings set org.gnome.desktop.session idle-delay 0 || true
sudo -u runner dbus-launch --exit-with-session gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
sudo chown -R runner:runner /home/runner/.config || true

echo -e "${C_GREEN}[OK] Screensaver, lock, and suspend disabled.${C_NC}"
