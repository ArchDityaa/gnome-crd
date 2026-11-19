#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Setup Remote User
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 03/19] SETUP REMOTE USER${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Creating user 'runner'...${C_NC}"
sudo useradd \
  -m \
  -s /bin/bash \
  runner || true

echo "runner:root" | sudo chpasswd

sudo usermod -aG sudo runner

echo -e "${C_YELLOW}[INFO] Gibah akses KVM + libvirt ke runner...${C_NC}"
# Runner x86 ubuntu-26.04 punya /dev/kvm, tapi default-nya hanya
# dapat dibuka grup 'kvm' (crw-rw---- root:kvm). Pola resmi GitHub
# adalah udev rule berikut (world-writable) supaya QEMU/virt-manager
# tidak "permission denied" saat -enable-kvm. Aman kalau /dev/kvm
# tidak ada (mis. ARM atau VM tanpa nested virtualization): udev
# trigger hanya no-op.
# Ref: https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
  | sudo tee /etc/udev/rules.d/99-kvm4all.rules > /dev/null
sudo udevadm control --reload-rules || true
sudo udevadm trigger --name-match=kvm || true
sudo usermod -aG kvm runner || echo -e "${C_YELLOW}[WARN] group 'kvm' tidak ada di runner ini (KVM off).${C_NC}"
sudo usermod -aG libvirt runner || true
# Restart CRD daemon agar systemd re-init supplementary groups (kvm,
# libvirt) dari /etc/group. Tanpa ini, daemon yang hidup SEBELUM usermod
# mewariskan grup stale ke semua sesi -> virt-manager gagal di
# libvirt-sock ("Permission denied") dan /dev/kvm tak terbaca.
sudo systemctl restart chrome-remote-desktop@runner 2>/dev/null || true
getent group kvm libvirt || true
if sudo -u runner test -r /dev/kvm && sudo -u runner test -w /dev/kvm; then
  echo -e "${C_GREEN}[OK] runner dapat mengakses /dev/kvm (KVM enabled).${C_NC}"
else
  echo -e "${C_YELLOW}[WARN] /dev/kvm belum bisa diakses runner (butuh re-login).${C_NC}"
fi

# Default URI libvirt = qemu:///session untuk user runner.
# Ubuntu 26.04 mem-patch libvirt agar default-nya qemu:///system
# (LP: #2027838). GNOME Boxes memanggil `virsh capabilities` TANPA `-c`,
# jadi bila runner belum punya akses ke socket libvirt system (grup
# 'libvirt' baru ditambahkan / sesi belum login ulang), Boxes salah
# menyimpulkan "No KVM!" dan membatalkan pembuatan VM. Config per-user
# ini membuat default selalu sesi, sama dengan koneksi yang dipakai Boxes
# (qemu+unix:///session). Idempoten bila file sudah ada.
LIBVIRT_CONF=/home/runner/.config/libvirt/libvirt.conf
sudo install -d -o runner -g runner -m 0700 /home/runner/.config/libvirt
if sudo grep -qE '^[[:space:]]*uri_default[[:space:]]*=' "$LIBVIRT_CONF" 2>/dev/null; then
  sudo sed -i 's|^[[:space:]]*uri_default[[:space:]]*=.*|uri_default = "qemu:///session"|' "$LIBVIRT_CONF"
else
  echo 'uri_default = "qemu:///session"' | sudo tee -a "$LIBVIRT_CONF" > /dev/null
fi
sudo chown runner:runner "$LIBVIRT_CONF"
sudo chmod 0644 "$LIBVIRT_CONF"
echo -e "${C_GREEN}[OK] Default URI libvirt = qemu:///session (GNOME Boxes).${C_NC}"

echo -e "${C_YELLOW}[INFO] Setting NEEDRESTART_MODE=l for runner (prevents service restart during apt)...${C_NC}"
echo 'export NEEDRESTART_MODE=l' | sudo tee -a /home/runner/.bashrc > /dev/null
echo 'export NEEDRESTART_SUSPEND=1' | sudo tee -a /home/runner/.bashrc > /dev/null

sudo mkdir -p /home/runner/Desktop

sudo chown -R runner:runner /home/runner

echo -e "${C_GREEN}[OK] Remote user 'runner' created: $(id runner)${C_NC}"
