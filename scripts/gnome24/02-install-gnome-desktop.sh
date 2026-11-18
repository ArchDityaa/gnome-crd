#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Install GNOME Desktop
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l
export NEEDRESTART_SUSPEND=1

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 02/19] INSTALL GNOME DESKTOP${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Installing full GNOME desktop (approx 2GB, please wait)...${C_NC}"

# Slim font: metapackage fonts-noto merekomendasikan font raksasa
# (fonts-noto-cjk 61MB, cjk-extra 145MB, extra 78.5MB) yang tidak
# dibutuhkan desktop. Pin negative membuat apt melewatinya
# (safe: hanya Recommends, bukan Depends). Pin dihapus lagi setelah
# install agar install font di sesi CRD nanti tetap normal.
sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/apt/99-no-noto-heavy.pref" /etc/apt/preferences.d/99-no-noto-heavy

# Blokir snapd + deb transisi (thunderbird/firefox -> snap). Ketiganya
# hanya Recommends (bukan Depends) dari ubuntu-desktop, jadi aman
# di-skip. thunderbird transisi memaksa 'snap install thunderbird' +
# retry 30 menit ke store saat postinst (hang lama di runner). Pin
# dihapus lagi setelah install agar operasi apt lain normal.
sudo install -D -m 0644 "$REPO_ROOT/assets/gnome24/apt/99-no-snap.pref" /etc/apt/preferences.d/99-no-snap.pref

sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Use-Pty=0 \
  ubuntu-desktop \
  ubuntu-desktop-minimal \
  gnome-shell \
  gnome-control-center \
  nautilus \
  gnome-terminal \
  dbus-x11 \
  x11-xserver-utils \
  xorg \
  adwaita-icon-theme \
  fonts-cantarell \
  xclip \
  neofetch \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  virt-manager \
  gnome-boxes

sudo rm -f /etc/apt/preferences.d/99-no-snap.pref

# Hapus permanen snapd + deb transisi thunderbird/firefox. Tidak ada
# paket yang hard-Depends ke snapd di graph install ini (terverifikasi),
# jadi aman. Hold mencegah re-install oleh operasi apt berikutnya.
sudo apt-get purge -y snapd thunderbird firefox || true
sudo apt-mark hold snapd thunderbird firefox
sudo rm -rf /snap /var/snap /var/lib/snapd /root/snap /home/runner/snap 2>/dev/null || true
command -v snap >/dev/null 2>&1 && echo -e "${C_YELLOW}[WARN] snap masih ada.${C_NC}" || echo -e "${C_GREEN}[OK] snap dihapus permanen.${C_NC}"

sudo rm -f /etc/apt/preferences.d/99-no-noto-heavy
echo -e "${C_GREEN}[OK] Heavy Noto fonts (cjk / cjk-extra / extra) skipped (~285MB saved).${C_NC}"

echo -e "${C_YELLOW}[INFO] Compiling GSettings schemas...${C_NC}"
sudo glib-compile-schemas /usr/share/glib-2.0/schemas/ || true

echo "------------------------------------------------------------"
gnome-shell --version || true
gnome-control-center --version || true
ls /usr/share/xsessions/ubuntu.desktop || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] GNOME installed: $(gnome-shell --version 2>/dev/null || echo 'version check skipped')${C_NC}"
