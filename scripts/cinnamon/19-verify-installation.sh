#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Verify Installation
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 18/19] VERIFY INSTALLATION${C_NC}"
echo "------------------------------------------------------------"

echo "::group::[CHECK] System"
uname -a
echo "::endgroup::"

echo "::group::[CHECK] Cinnamon session (robust, no Xsession wrapper)"
dpkg-query -W -f='${Package} ${Version}\n' \
  cinnamon cinnamon-session cinnamon-common cinnamon-desktop-data muffin nemo 2>/dev/null || true
echo "--- xsessions ---"
ls -l /usr/share/xsessions/cinnamon*.desktop || true
echo "--- cinnamon-session components ---"
ls /usr/share/cinnamon-session/sessions/ || true
echo "--- session file ---"
cat /home/runner/.chrome-remote-desktop-session || true
echo "--- no Xsession/lightdm wrapper allowed ---"
grep -r "Xsession\|lightdm" /home/runner/.chrome-remote-desktop-session && echo "[FAIL] session file masih pakai wrapper!" && exit 1 || echo "[OK] session file direct exec, bersih"
grep -q "exec /usr/bin/cinnamon-session --session cinnamon" /home/runner/.chrome-remote-desktop-session || { echo "[FAIL] exec line tidak sesuai harapan!"; exit 1; }
if dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
  echo "[WARN] lightdm terpasang (tidak dipakai; CRD memanggil cinnamon-session langsung)."
else
  echo "[OK] lightdm tidak terpasang."
fi
echo "::endgroup::"

echo "::group::[CHECK] screensaver/lock disabled"
cat /etc/dconf/db/local.d/99-crd-no-lock || true
echo "--- gsettings (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.screensaver lock-enabled || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.screensaver idle-activation-enabled || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.session idle-delay || true
echo "::endgroup::"

echo "::group::[CHECK] Cinnamon effects (software rendering caveat)"
echo "--- enable-animations (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface enable-animations || true
echo "--- desktop-effects (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.cinnamon desktop-effects || true
# Cinnamon 6.4 mematikan animasi saat deteksi software rendering
# (llvmpipe di runner CRD). Tidak ada override setara
# global.force_animations milik GNOME Shell; ini expected.
echo "[INFO] Animasi bisa tetap off di sesi CRD karena llvmpipe/software rendering."
echo "::endgroup::"

echo "::group::[CHECK] display resolution setting (1024x768)"
grep -n "1024x768" /home/runner/.chrome-remote-desktop-session || true
grep -n "WANT=" /usr/local/bin/set-resolution.sh || true
if grep -q "1024x768" /home/runner/.chrome-remote-desktop-session &&
   grep -q "WANT=1024x768" /usr/local/bin/set-resolution.sh; then
  echo -e "${C_GREEN}[OK] target resolusi 1024x768 (mode native driver dummy, tahan reload shell).${C_NC}"
else
  echo "[WARN] target resolusi tidak konsisten."
fi
echo "::endgroup::"

echo "::group::[CHECK] Catppuccin theme (macchiato + mauve)"
ls -d /home/runner/.themes/catppuccin-macchiato-mauve-standard+default || true
ls -d /home/runner/.icons/catppuccin-macchiato-mauve-cursors || true
ls /home/runner/.config/gtk-4.0/gtk.css || true
ls /home/runner/.local/share/fonts/JetBrainsMonoNerd/ | head -n 3 || true
echo "--- gsettings (runner) ---"
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface gtk-theme || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface icon-theme || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface cursor-theme || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.theme name || true
sudo -u runner dbus-run-session -- gsettings get org.gnome.Terminal.ProfilesList default || true
if sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null | grep -q 'catppuccin-macchiato-mauve'; then
  echo -e "${C_GREEN}[OK] Catppuccin theme aktif (GTK/Cinnamon shell/ikon/kursor/font/terminal).${C_NC}"
else
  echo "[WARN] Catppuccin theme tidak terpasang."
fi
echo "::endgroup::"

echo "::group::[CHECK] timezone (Asia/Jakarta)"
cat /etc/timezone || true
ls -l /etc/localtime || true
date || true
if [ "$(cat /etc/timezone 2>/dev/null)" = "Asia/Jakarta" ] && [ "$(date +%z)" = "+0700" ]; then
  echo -e "${C_GREEN}[OK] timezone WIB (Asia/Jakarta, +0700).${C_NC}"
else
  echo "[WARN] timezone bukan Asia/Jakarta."
fi
echo "::endgroup::"

echo "::group::[CHECK] safe-upgrade helper"
which safe-upgrade || true
ls -l /usr/local/bin/safe-upgrade || true
safe-upgrade --help || true
ls -l /home/runner/Desktop/SafeUpgrade.desktop || true
echo "::endgroup::"

echo "::group::[CHECK] Google Chrome"
google-chrome --version || true
echo "::endgroup::"

echo "::group::[CHECK] VS Code"
code --version || true
echo "::endgroup::"

echo "::group::[CHECK] OpenCode CLI"
opencode --version || true
which opencode || true
echo "::endgroup::"

echo "::group::[CHECK] OpenCode Desktop"
dpkg -l | grep -i opencode || true
ls /usr/share/applications/*opencode* || true
ls /home/runner/Desktop/*pencode*.desktop || true
echo "::endgroup::"

echo "::group::[CHECK] Chrome Remote Desktop service"
systemctl status \
  chrome-remote-desktop@runner.service \
  --no-pager \
  || true
echo "::endgroup::"

echo "::group::[CHECK] Remote user"
id runner
echo "::endgroup::"

echo "::group::[CHECK] KVM / Virtualization"
ls -l /dev/kvm || true
getent group kvm libvirt || true
if sudo -u runner test -r /dev/kvm && sudo -u runner test -w /dev/kvm; then
  echo -e "${C_GREEN}[OK] runner dapat mengakses /dev/kvm.${C_NC}"
else
  echo -e "${C_YELLOW}[WARN] runner tidak bisa akses /dev/kvm - instalasi tetap OK; KVM off di runner ini (lihat README, bagian KVM).${C_NC}"
fi
command -v qemu-system-x86_64 || echo "[WARN] qemu-system-x86_64 missing"
command -v virsh || echo "[WARN] virsh missing"
command -v virt-manager || echo "[WARN] virt-manager missing"
command -v nemo || echo "[WARN] nemo missing"
command -v cinnamon-session || echo "[WARN] cinnamon-session missing"
command -v cinnamon-settings || echo "[WARN] cinnamon-settings missing"

# Default URI libvirt: Boxes menjalankan `virsh capabilities` TANPA `-c`.
# Ubuntu 26.04 mem-patch default ke qemu:///system (LP: #2027838); override
# per-user (~/.config/libvirt/libvirt.conf) harus membuatnya kembali ke sesi.
if sudo -u runner env HOME=/home/runner XDG_RUNTIME_DIR="/run/user/$(id -u runner)" \
     virsh capabilities 2>/dev/null | grep -q "domain type='kvm'"; then
  echo -e "${C_GREEN}[OK] libvirt default URI: KVM guest tersedia.${C_NC}"
else
  echo -e "${C_YELLOW}[WARN] virsh capabilities tidak menemukan KVM guest (cek uri_default).${C_NC}"
fi
if command -v gnome-boxes > /dev/null 2>&1; then
  if sudo -u runner env HOME=/home/runner XDG_RUNTIME_DIR="/run/user/$(id -u runner)" \
       timeout 90 gnome-boxes --checks 2>/dev/null | grep -q "Libvirt KVM guest available: yes"; then
    echo -e "${C_GREEN}[OK] GNOME Boxes: Libvirt KVM guest available.${C_NC}"
  else
    echo -e "${C_YELLOW}[WARN] GNOME Boxes --checks: Libvirt KVM guest tidak tersedia.${C_NC}"
  fi
fi

systemctl is-enabled libvirtd 2>/dev/null || true
systemctl is-active libvirtd 2>/dev/null || true
echo "::endgroup::"

echo "::group::[CHECK] Snap removed"
command -v snap >/dev/null 2>&1 && echo -e "${C_YELLOW}[WARN] snap masih terpasang.${C_NC}" || echo -e "${C_GREEN}[OK] snap / snapd removed.${C_NC}"
dpkg -l thunderbird 2>/dev/null | grep -q ^ii && echo -e "${C_YELLOW}[WARN] thunderbird transisi masih terpasang.${C_NC}" || echo -e "${C_GREEN}[OK] thunderbird (snap transitional) removed.${C_NC}"
apt-mark showhold | grep -qx snapd && echo -e "${C_GREEN}[OK] snapd held (tidak akan re-install).${C_NC}" || echo -e "${C_YELLOW}[WARN] snapd tidak di-hold.${C_NC}"
echo "::endgroup::"

echo ""
echo -e "${C_GREEN}[OK] Installation verification completed.${C_NC}"
