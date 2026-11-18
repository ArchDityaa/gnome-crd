#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Install Desktop & Applications
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l
export NEEDRESTART_SUSPEND=1
step "02/11" "Install desktop & applications"

# Lewati font Noto raksasa (Recommends saja, ±285 MB) dan blokir
# snapd/thunderbird/firefox (paket transisi snap yang membuat
# postinst menunggu snap store). Pin dihapus setelah install.
sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/apt/99-no-noto-heavy.pref" /etc/apt/preferences.d/99-no-noto-heavy

sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/apt/99-no-snap.pref" /etc/apt/preferences.d/99-no-snap.pref

# Unduhan background (berjalan paralel dengan transaksi apt).
mkdir -p /tmp/dl
( RQ_SOFT=1 run_quiet "Unduh OpenCode Desktop" \
    wget -q https://opencode.ai/download/stable/linux-x64-deb -O /tmp/dl/opencode-desktop.deb
) > "$CI_LOG_DIR/bg-opencode.out" 2>&1 &
BG_OPENCODE=$!
( RQ_SOFT=1 run_quiet "Unduh cloudflared" \
    curl -fsSL --retry 3 --retry-delay 2 -o /tmp/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  && chmod +x /tmp/cloudflared
) > "$CI_LOG_DIR/bg-cloudflared.out" 2>&1 &
BG_CLOUDFLARED=$!

run_quiet "Pasang GNOME, Chrome, VS Code & CRD (±2 GB)" \
  sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Use-Pty=0 \
    ubuntu-desktop \
    ubuntu-desktop-minimal \
    ubuntu-session \
    gnome-session \
    gnome-shell \
    gnome-control-center \
    nautilus \
    gnome-terminal \
    dbus-x11 \
    dbus-user-session \
    x11-xserver-utils \
    xwayland \
    pipewire \
    pipewire-pulse \
    wireplumber \
    xdg-desktop-portal \
    xdg-desktop-portal-gnome \
    xorg \
    adwaita-icon-theme \
    fonts-cantarell \
    fonts-ubuntu \
    yaru-theme-icon \
    ubuntu-wallpapers \
    qemu-system-x86 \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    virtinst \
    xclip \
    fastfetch \
    virt-manager \
    gnome-boxes \
    google-chrome-stable \
    code \
    chrome-remote-desktop

# Hasil unduhan background (kegagalan tidak fatal: OpenCode Desktop
# diunduh ulang di step 04, cloudflared di step 10).
wait "$BG_OPENCODE" || true
wait "$BG_CLOUDFLARED" || true
cat "$CI_LOG_DIR/bg-opencode.out" "$CI_LOG_DIR/bg-cloudflared.out" 2>/dev/null || true

sudo rm -f /etc/apt/preferences.d/99-no-snap.pref /etc/apt/preferences.d/99-no-noto-heavy

# Tidak ada paket yang hard-depends ke snapd di install graph ini.
RQ_SOFT=1 run_quiet "Hapus snapd & paket transisi snap" \
  sudo apt-get purge -y -qq snapd thunderbird firefox || true
sudo apt-mark hold snapd thunderbird firefox > /dev/null
sudo rm -rf /snap /var/snap /var/lib/snapd /root/snap /home/runner/snap 2>/dev/null || true
if command -v snap >/dev/null 2>&1; then warn "snap masih terdeteksi"; fi

run_quiet "Kompilasi GSettings schemas" sudo glib-compile-schemas /usr/share/glib-2.0/schemas/ || true

# CRD menjalankan instance PipeWire sendiri (crd_audio). Template
# bawaan hanya memetakan audio.convert; tanpa video.convert PipeWire
# gagal menyisipkan adapter ("no more input formats") dan layar hitam.
# Idempoten; file vendor dapat berubah saat paket CRD di-upgrade.
PW_TEMPLATE=/opt/google/chrome-remote-desktop/pipewire.conf.template
if [ -f "$PW_TEMPLATE" ] && ! sudo grep -q 'video\.convert' "$PW_TEMPLATE"; then
  sudo sed -i '/audio\.convert\.\*/a\    video.convert.* = videoconvert/libspa-videoconvert' "$PW_TEMPLATE"
  ok "Template PipeWire CRD: video.convert ditambahkan"
fi

ok "GNOME: $(gnome-shell --version 2>/dev/null || echo '?')"
ok "Chrome: $(google-chrome --version 2>/dev/null || echo '?')"
ok "VS Code: $(code --version 2>/dev/null | head -n 1 || echo '?')"
ok "CRD: $(dpkg-query -W -f='${Version}' chrome-remote-desktop 2>/dev/null || echo '?')"

step_done
