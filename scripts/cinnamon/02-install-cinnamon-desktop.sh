#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Install Cinnamon Desktop
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l
export NEEDRESTART_SUSPEND=1

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 02/19] INSTALL CINNAMON DESKTOP${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Installing Cinnamon desktop (approx 2GB, please wait)...${C_NC}"

# Cinnamon ada di universe. Image runner biasanya sudah punya
# universe, tetapi guard ini membuat workflow tetap jalan di image
# minimal yang hanya mengaktifkan main.
if ! apt-cache show cinnamon >/dev/null 2>&1; then
  echo -e "${C_YELLOW}[INFO] Paket cinnamon belum terlihat; mengaktifkan universe...${C_NC}"
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y universe
  sudo apt-get update
fi

# Slim font: beberapa metapackage desktop merekomendasikan font
# raksasa (fonts-noto-cjk 61MB, cjk-extra 145MB, extra 78.5MB) yang
# tidak dibutuhkan. Pin negative membuat apt melewatinya (safe:
# hanya Recommends, bukan Depends). Pin dihapus setelah install.
sudo install -D -m 0644 "$REPO_ROOT/assets/cinnamon/apt/99-no-noto-heavy.pref" /etc/apt/preferences.d/99-no-noto-heavy

# Cinnamon tidak membutuhkan snap. Blokir snapd + deb transisi
# (thunderbird/firefox -> snap) agar apt tidak menariknya lewat
# Recommends paket lain. Pin dihapus setelah install.
sudo install -D -m 0644 "$REPO_ROOT/assets/cinnamon/apt/99-no-snap.pref" /etc/apt/preferences.d/99-no-snap.pref

sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y \
  --no-install-recommends \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Use-Pty=0 \
  cinnamon \
  cinnamon-session \
  cinnamon-control-center \
  cinnamon-screensaver \
  cinnamon-settings-daemon \
  cinnamon-l10n \
  cinnamon-common \
  cinnamon-desktop-data \
  muffin \
  nemo \
  gnome-terminal \
  xorg \
  x11-xserver-utils \
  x11-utils \
  dbus-x11 \
  dbus-user-session \
  dconf-cli \
  libgl1-mesa-dri \
  libglx-mesa0 \
  mesa-utils \
  xdg-desktop-portal \
  xdg-desktop-portal-gtk \
  xdg-desktop-portal-xapp \
  xapp-sn-watcher \
  libxapp-gtk3-module \
  libcanberra-pulse \
  metacity-common \
  pipewire \
  pipewire-pulse \
  wireplumber \
  adwaita-icon-theme \
  fonts-cantarell \
  fonts-liberation \
  papirus-icon-theme \
  eog \
  evince \
  gnome-calculator \
  gnome-screenshot \
  gnome-text-editor \
  xdg-user-dirs-gtk \
  gvfs-backends \
  gvfs-fuse \
  nemo-fileroller \
  xclip \
  qemu-system-x86 \
  qemu-utils \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  virt-manager

sudo rm -f /etc/apt/preferences.d/99-no-snap.pref

# Hapus permanen snapd + deb transisi thunderbird/firefox. Cinnamon
# tidak membutuhkannya; hold mencegah re-install oleh apt berikutnya.
sudo apt-get purge -y snapd thunderbird firefox || true
sudo apt-mark hold snapd thunderbird firefox
sudo rm -rf /snap /var/snap /var/lib/snapd /root/snap /home/runner/snap 2>/dev/null || true
command -v snap >/dev/null 2>&1 && echo -e "${C_YELLOW}[WARN] snap masih ada.${C_NC}" || echo -e "${C_GREEN}[OK] snap dihapus permanen.${C_NC}"

sudo rm -f /etc/apt/preferences.d/99-no-noto-heavy
echo -e "${C_GREEN}[OK] Heavy Noto fonts (cjk / cjk-extra / extra) skipped (~285MB saved).${C_NC}"

echo -e "${C_YELLOW}[INFO] Compiling GSettings schemas...${C_NC}"
sudo glib-compile-schemas /usr/share/glib-2.0/schemas/ || true

echo "------------------------------------------------------------"
dpkg-query -W -f='${Package} ${Version}\n' \
  cinnamon cinnamon-session cinnamon-screensaver cinnamon-control-center \
  cinnamon-settings-daemon cinnamon-common cinnamon-desktop-data \
  muffin nemo || true
ls /usr/share/xsessions/cinnamon*.desktop || true
ls /usr/share/cinnamon-session/sessions/ || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] Cinnamon installed: $(dpkg-query -W -f='${Version}' cinnamon 2>/dev/null || echo 'version check skipped')${C_NC}"
