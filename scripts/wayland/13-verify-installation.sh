#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Verify Installation
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "11/11" "Verify installation"

RUNNER_UID=$(id -u runner)
as_runner() {
  sudo -u runner env \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
    "$@"
}
gs_get() { sudo -u runner dbus-run-session -- gsettings get "$@" 2>/dev/null | tr -d "'" || true; }

DETAIL="$CI_LOG_DIR/verify-details.log"
{
  echo "## system";            uname -a
  echo "## gnome-shell";       gnome-shell --version
  echo "## CRD unit";          systemctl cat chrome-remote-desktop@runner 2>/dev/null | tail -n 40
  echo "## headless override"; cat /etc/systemd/user/org.gnome.Shell@.service.d/10-headless-beta.conf
  echo "## user environment";  as_runner systemctl --user show-environment 2>/dev/null | grep -E 'WAYLAND_DISPLAY|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP'
  echo "## shell status";      as_runner systemctl --user status org.gnome.Shell@ubuntu.service --no-pager 2>/dev/null
  echo "## shell journal";     as_runner journalctl --user -u org.gnome.Shell@ubuntu.service -n 40 --no-pager 2>/dev/null
  echo "## CRD status";        systemctl status chrome-remote-desktop@runner --no-pager
  echo "## extension";         ls -l /usr/share/gnome-shell/extensions/force-animations@software-rendering/
  echo "## kvm";               ls -l /dev/kvm; getent group kvm libvirt
  echo "## opencode";          dpkg -l | grep -i opencode
} > "$DETAIL" 2>&1 || true

verify_fail() {
  fail "$1"
  echo "::group::Diagnostik"
  tail -n 150 "$DETAIL" || true
  echo "::endgroup::"
  exit 1
}

# --- Wayland + CRD ---
if [ -e /home/runner/.chrome-remote-desktop-session ]; then
  warn ".chrome-remote-desktop-session masih ada (tidak dipakai mode Wayland)"
fi
WAYLAND_DISPLAY_VALUE=$(as_runner systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' || true)
if [ -z "$WAYLAND_DISPLAY_VALUE" ]; then
  verify_fail "WAYLAND_DISPLAY belum diekspor ke systemd user environment"
fi
if [ ! -S "/run/user/$RUNNER_UID/$WAYLAND_DISPLAY_VALUE" ]; then
  verify_fail "Socket Wayland tidak ada: /run/user/$RUNNER_UID/$WAYLAND_DISPLAY_VALUE"
fi
ok "Compositor Wayland aktif ($WAYLAND_DISPLAY_VALUE)"

if systemctl is-active --quiet chrome-remote-desktop@runner; then
  ok "Service chrome-remote-desktop@runner aktif"
else
  verify_fail "chrome-remote-desktop@runner tidak aktif"
fi

if grep -q -- "--headless" /etc/systemd/user/org.gnome.Shell@.service.d/10-headless-beta.conf 2>/dev/null &&
   grep -q -- "--virtual-monitor 1280x720" /etc/systemd/user/org.gnome.Shell@.service.d/10-headless-beta.conf 2>/dev/null; then
  ok "Headless + virtual monitor 1280x720"
else
  warn "Override headless / virtual monitor tidak sesuai"
fi

# --- Lock & animasi ---
if [ -f /etc/dconf/db/local.d/99-crd-no-lock ]; then
  ok "Lock / screensaver / suspend dinonaktifkan"
else
  warn "99-crd-no-lock tidak ditemukan"
fi
if sudo -u runner dbus-run-session -- gsettings get org.gnome.shell enabled-extensions 2>/dev/null | grep -q 'force-animations@software-rendering'; then
  ok "force-animations terdaftar (animasi aktif pada software rendering)"
else
  warn "force-animations TIDAK terdaftar di enabled-extensions"
fi

# --- Tampilan (vanilla Ubuntu · dark mode) ---
if ls -d /home/runner/.themes/catppuccin* /home/runner/.icons/catppuccin* > /dev/null 2>&1; then
  verify_fail "Masih ada sisa aset Catppuccin"
fi
if [ -n "$(ls -A /home/runner/Desktop 2>/dev/null)" ]; then
  verify_fail "Desktop tidak kosong"
fi

COLOR_SCHEME="$(gs_get org.gnome.desktop.interface color-scheme)"
[ "$COLOR_SCHEME" = "prefer-dark" ] || verify_fail "color-scheme bukan prefer-dark (dapat: ${COLOR_SCHEME:-kosong})"
GTK_THEME_VAL="$(gs_get org.gnome.desktop.interface gtk-theme)"
case "$GTK_THEME_VAL" in
  *Yaru-dark*) ;;
  *) verify_fail "gtk-theme bukan Yaru-dark (dapat: ${GTK_THEME_VAL:-kosong})" ;;
esac

# CRD memaksa XDG_CURRENT_DESKTOP=GNOME, jadi override
# [org.gnome.desktop.background:ubuntu] tidak berlaku; nilai di-set
# eksplisit oleh dconf 96-crd-ubuntu-look. Bila file gambar tidak
# ada, shell hanya menggambar primary-color.
EXPECT_LIGHT='file:///usr/share/backgrounds/warty-final-ubuntu.png'
EXPECT_DARK='file:///usr/share/backgrounds/ubuntu-wallpaper-d.png'
check_wallpaper() {
  local key="$1" want="$2" got path
  got="$(gs_get org.gnome.desktop.background "$key")"
  if [ "$got" != "$want" ]; then
    verify_fail "$key bukan wallpaper Ubuntu yang diharapkan (diharapkan: $want, dapat: ${got:-kosong})"
  fi
  path="${got#file://}"
  if [ ! -f "$path" ]; then
    verify_fail "File wallpaper tidak ada: $path (layar hanya akan menampilkan primary-color)"
  fi
}
check_wallpaper picture-uri "$EXPECT_LIGHT"
check_wallpaper picture-uri-dark "$EXPECT_DARK"

for pair in "icon-theme:Yaru" "cursor-theme:Yaru" "font-name:Ubuntu Sans 11"; do
  key="${pair%%:*}"
  want="${pair#*:}"
  got="$(gs_get org.gnome.desktop.interface "$key")"
  [ "$got" = "$want" ] || verify_fail "$key bukan default Ubuntu yang diharapkan ($want, dapat: ${got:-kosong})"
done
ok "Tampilan: Ubuntu default · dark mode (Yaru-dark) · wallpaper · desktop bersih"

# --- Sistem & aplikasi ---
if [ "$(cat /etc/timezone 2>/dev/null)" = "Asia/Jakarta" ] && [ "$(date +%z)" = "+0700" ]; then
  ok "Timezone WIB (Asia/Jakarta, +0700)"
else
  warn "Timezone bukan Asia/Jakarta"
fi
command -v safe-upgrade > /dev/null || warn "safe-upgrade tidak ditemukan"
ok "Aplikasi: Chrome $(google-chrome --version 2>/dev/null | awk '{print $3}') · VS Code $(code --version 2>/dev/null | head -n 1) · OpenCode $(opencode --version 2>/dev/null)"

# --- KVM & virtualisasi ---
if sudo -u runner test -r /dev/kvm && sudo -u runner test -w /dev/kvm; then
  ok "runner dapat mengakses /dev/kvm"
else
  warn "runner tidak dapat mengakses /dev/kvm (instalasi tetap OK; KVM nonaktif di runner ini)"
fi
for bin in qemu-system-x86_64 virsh virt-manager gnome-boxes; do
  command -v "$bin" > /dev/null || warn "$bin tidak ditemukan"
done

# --- Snap ---
if command -v snap >/dev/null 2>&1; then warn "snap masih terpasang"; fi
if dpkg -l thunderbird 2>/dev/null | grep -q ^ii; then warn "thunderbird (transisi snap) masih terpasang"; fi
if apt-mark showhold | grep -qx snapd; then
  ok "snap / snapd dihapus dan di-hold"
else
  warn "snapd tidak di-hold"
fi

step_done
