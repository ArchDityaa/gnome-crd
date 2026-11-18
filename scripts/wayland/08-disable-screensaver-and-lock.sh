#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Disable Screensaver and Lock
set -euo pipefail


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "06/11" "Disable screensaver & lock · apply appearance"

sudo mkdir -p /etc/dconf/db/local.d || true
sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/dconf/99-crd-no-lock" /etc/dconf/db/local.d/99-crd-no-lock

# CRD memaksa XDG_CURRENT_DESKTOP=GNOME, sehingga override
# [schema:ubuntu] tidak berlaku dan wallpaper jatuh ke adwaita-*.jxl
# (tidak terpasang) -> layar biru solid. Karena itu wallpaper + tema
# di-set eksplisit lewat dconf, dengan primary-color aubergine sebagai fallback.
if ! sudo grep -qs '^system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user > /dev/null
fi

# 96 < 97, sehingga 97-crd-dark-mode menang untuk color-scheme/gtk-theme.
sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/dconf/96-crd-ubuntu-look" /etc/dconf/db/local.d/96-crd-ubuntu-look

sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/dconf/97-crd-dark-mode" /etc/dconf/db/local.d/97-crd-dark-mode
sudo dconf update > /dev/null 2>&1 || true

# Fallback gsettings per-user (abaikan bila dbus belum tersedia).
gs_set() {
  # Log ditulis oleh runner (bukan root), redirect memang di luar sudo.
  # shellcheck disable=SC2024
  sudo -u runner dbus-launch --exit-with-session gsettings set "$@" >> "$CI_LOG_DIR/appearance.log" 2>&1 || true
}
gs_set org.gnome.desktop.screensaver lock-enabled false
gs_set org.gnome.desktop.screensaver idle-activation-enabled false
gs_set org.gnome.desktop.session idle-delay 0
gs_set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gs_set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/warty-final-ubuntu.png'
gs_set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/ubuntu-wallpaper-d.png'
gs_set org.gnome.desktop.background primary-color '#2c001e'
gs_set org.gnome.desktop.background secondary-color '#2c001e'
gs_set org.gnome.desktop.background picture-options 'zoom'
gs_set org.gnome.desktop.interface icon-theme 'Yaru'
gs_set org.gnome.desktop.interface cursor-theme 'Yaru'
gs_set org.gnome.desktop.interface font-name 'Ubuntu Sans 11'
gs_set org.gnome.desktop.interface document-font-name 'Sans 11'
gs_set org.gnome.desktop.interface monospace-font-name 'Ubuntu Sans Mono 11'
gs_set org.gnome.desktop.interface color-scheme 'prefer-dark'
gs_set org.gnome.desktop.interface gtk-theme 'Yaru-dark'

sudo chown -R runner:runner /home/runner/.config || true
ok "Lock, screensaver, dan suspend dinonaktifkan"
ok "Tampilan: Ubuntu default · dark mode (prefer-dark + Yaru-dark)"
step_done
