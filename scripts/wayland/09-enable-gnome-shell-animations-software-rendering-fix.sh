#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Enable GNOME Shell Animations (software rendering fix)
set -euo pipefail


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "07/11" "Enable animations on software rendering"

UUID="force-animations@software-rendering"
EXT_DIR="/usr/share/gnome-shell/extensions/$UUID"
sudo mkdir -p "$EXT_DIR"

sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/gnome-shell/force-animations@software-rendering/metadata.json" "$EXT_DIR/metadata.json"

sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/gnome-shell/force-animations@software-rendering/extension.js" "$EXT_DIR/extension.js"

sudo chmod 0755 "$EXT_DIR"
sudo chmod 0644 "$EXT_DIR/metadata.json" "$EXT_DIR/extension.js"

sudo mkdir -p /etc/environment.d
printf 'GNOME_SHELL_SLOWDOWN_FACTOR=2.5\n' | sudo tee /etc/environment.d/99-gnome-animation-slow.conf > /dev/null
# Fallback untuk login via PAM (GDM/lightdm).
if ! grep -q 'GNOME_SHELL_SLOWDOWN_FACTOR' /etc/environment 2>/dev/null; then
  printf '\nGNOME_SHELL_SLOWDOWN_FACTOR=2.5\n' | sudo tee -a /etc/environment > /dev/null
fi

sudo mkdir -p /etc/dconf/db/local.d
sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/dconf/98-force-animations" /etc/dconf/db/local.d/98-force-animations

if ! sudo grep -qs '^system-db:local' /etc/dconf/profile/user 2>/dev/null; then
  printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user > /dev/null
fi
sudo dconf update > /dev/null 2>&1 || true

# Fallback gsettings per-user untuk 'runner'.
# shellcheck disable=SC2024
sudo -u runner dbus-run-session -- gsettings set org.gnome.shell enabled-extensions "['$UUID']" >> "$CI_LOG_DIR/appearance.log" 2>&1 || true
# shellcheck disable=SC2024
sudo -u runner dbus-run-session -- gsettings set org.gnome.desktop.interface enable-animations true >> "$CI_LOG_DIR/appearance.log" 2>&1 || true
sudo chown -R runner:runner /home/runner/.config || true

ok "Extension terpasang: $UUID"
ok "Animasi aktif via global.force_animations (slow-down 2.5×)"
step_done
