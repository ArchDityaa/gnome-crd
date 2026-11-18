#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Configure GNOME Wayland Session (BETA)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "05/11" "Configure GNOME Wayland session (BETA)"

test -x /usr/bin/gnome-session || { fail "/usr/bin/gnome-session tidak ditemukan"; exit 1; }
test -x /usr/bin/gnome-shell   || { fail "/usr/bin/gnome-shell tidak ditemukan"; exit 1; }
test -f /usr/share/gnome-session/sessions/ubuntu.session || {
  fail "ubuntu.session tidak ditemukan (paket ubuntu-session belum terpasang)"
  ls /usr/share/gnome-session/sessions/ || true
  exit 1
}

RUNNER_UID=$(id -u runner)

# User manager + D-Bus session bus harus hidup agar GNOME Shell dapat
# berjalan sebagai systemd user service dan mengekspor WAYLAND_DISPLAY.
sudo loginctl enable-linger runner || true
sudo mkdir -p "/run/user/$RUNNER_UID"
sudo chown runner:runner "/run/user/$RUNNER_UID"
sudo chmod 700 "/run/user/$RUNNER_UID"

as_runner() {
  sudo -u runner env \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
    "$@"
}

for i in {1..30}; do
  if [ -S "/run/user/$RUNNER_UID/systemd/private" ] && [ -S "/run/user/$RUNNER_UID/bus" ]; then
    break
  fi
  sleep 1
done
if [ ! -S "/run/user/$RUNNER_UID/systemd/private" ]; then
  fail "systemd --user milik runner tidak aktif"
  sudo loginctl list-sessions || true
  exit 1
fi
if [ ! -S "/run/user/$RUNNER_UID/bus" ]; then
  fail "D-Bus session bus runner tidak ditemukan: /run/user/$RUNNER_UID/bus"
  ls -la "/run/user/$RUNNER_UID" || true
  exit 1
fi
ok "systemd --user + D-Bus session bus aktif"

# Paksa environment user manager ke Wayland (org.gnome.Shell@.service
# memiliki AssertEnvironment=XDG_SESSION_TYPE=wayland).
# XDG_CURRENT_DESKTOP tidak menentukan session mode: CRD selalu
# memaksa "GNOME" untuk sesi Wayland, sehingga wallpaper/tema di-set
# eksplisit lewat dconf (step 06).
as_runner systemctl --user set-environment \
  XDG_SESSION_TYPE=wayland \
  XDG_CURRENT_DESKTOP=GNOME \
  XDG_SESSION_DESKTOP=ubuntu
as_runner systemctl --user unset-environment \
  WAYLAND_DISPLAY DISPLAY XAUTHORITY GNOME_SETUP_DISPLAY 2>/dev/null || true

# CRD memanggil `gnome-session` tanpa argumen, sementara satu-satunya
# mode GNOME Shell yang tersedia adalah "ubuntu". Wrapper memaksanya.
sudo install -D -m 0755 "$REPO_ROOT/scripts/wayland/gnome-session-wrapper.sh" /usr/local/bin/gnome-session
sudo chmod 0755 /usr/local/bin/gnome-session

# Jalur kedua bila CRD memanggil /usr/bin/gnome-session secara absolut.
sudo -u runner env HOME=/home/runner \
  dbus-run-session -- \
  gsettings set org.gnome.desktop.session session-name ubuntu > /dev/null 2>&1 || true

# GNOME Shell 50 tidak punya backend X11; pada runner tanpa GPU shell
# dijalankan sebagai compositor headless dengan satu virtual monitor.
sudo mkdir -p /etc/systemd/user/org.gnome.Shell@.service.d
sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/systemd/10-headless-beta.conf" /etc/systemd/user/org.gnome.Shell@.service.d/10-headless-beta.conf

# Mode Wayland CRD dipilih lewat environment service. Drop-in ini juga
# menyediakan bus address yang dibutuhkan gnome-session (crbug.com/432108529).
sudo mkdir -p /etc/systemd/system/chrome-remote-desktop@.service.d
sed -e "s|@RUNNER_UID@|$RUNNER_UID|g" \
  "$REPO_ROOT/assets/wayland/systemd/20-wayland-beta.conf.in" \
  | sudo tee /etc/systemd/system/chrome-remote-desktop@.service.d/20-wayland-beta.conf > /dev/null

sudo systemctl daemon-reload
as_runner systemctl --user daemon-reload

# Sisa konfigurasi X11 lama tidak dipakai pada mode Wayland.
sudo -u runner rm -f /home/runner/.chrome-remote-desktop-session
sudo -u runner rm -f /home/runner/.config/autostart/set-resolution.desktop
sudo rm -f /usr/local/bin/set-resolution.sh

# Detail konfigurasi disimpan ke log (ikut artifact bila job gagal).
{
  echo "--- CRD service drop-in ---"
  systemctl cat chrome-remote-desktop@runner.service | tail -n 20 || true
  echo "--- GNOME Shell user override ---"
  as_runner systemctl --user cat org.gnome.Shell@.service 2>/dev/null | tail -n 20 || true
  echo "--- systemd user environment ---"
  as_runner systemctl --user show-environment | grep -E '^(XDG|DBUS)' || true
} > "$CI_LOG_DIR/wayland-config.log" 2>&1 || true

if ! as_runner systemctl --user show-environment | grep -q '^XDG_SESSION_TYPE=wayland$'; then
  fail "Environment systemd user bukan wayland"
  tail -n 60 "$CI_LOG_DIR/wayland-config.log" || true
  exit 1
fi
if ! systemctl cat chrome-remote-desktop@runner.service | grep -q 'CHROME_REMOTE_DESKTOP_USE_WAYLAND=GNOME'; then
  fail "Drop-in CRD Wayland tidak terbaca"
  tail -n 60 "$CI_LOG_DIR/wayland-config.log" || true
  exit 1
fi

ok "Environment user manager: Wayland"
ok "GNOME Shell headless (virtual monitor 1280x720) · CRD drop-in Wayland"
step_done
