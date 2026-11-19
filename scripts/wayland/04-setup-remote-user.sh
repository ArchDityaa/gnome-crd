#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Setup Remote User
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "03/11" "Setup remote user"

sudo useradd -m -s /bin/bash runner || true
echo "runner:root" | sudo chpasswd
sudo usermod -aG sudo runner

# Akses KVM + libvirt. Pola resmi GitHub: udev rule agar /dev/kvm
# dapat dibuka tanpa grup 'kvm'. No-op bila KVM tidak tersedia.
# Ref: https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/
echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
  | sudo tee /etc/udev/rules.d/99-kvm4all.rules > /dev/null
sudo udevadm control --reload-rules || true
sudo udevadm trigger --name-match=kvm || true
sudo usermod -aG kvm runner || warn "grup 'kvm' tidak ada di runner ini (KVM nonaktif)"
sudo usermod -aG libvirt runner || true

# Bila daemon CRD sudah berjalan (mis. re-run), restart agar systemd
# membaca ulang grup (kvm, libvirt); tanpa ini virt-manager gagal di
# libvirt-sock dan /dev/kvm tak terbaca.
if systemctl is-active --quiet chrome-remote-desktop@runner 2>/dev/null; then
  sudo systemctl restart chrome-remote-desktop@runner 2>/dev/null || true
fi
if sudo -u runner test -r /dev/kvm && sudo -u runner test -w /dev/kvm; then
  ok "KVM tersedia untuk runner"
else
  warn "/dev/kvm belum dapat diakses runner (perlu re-login)"
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
ok "Default URI libvirt = qemu:///session (GNOME Boxes)"

echo 'export NEEDRESTART_MODE=l' | sudo tee -a /home/runner/.bashrc > /dev/null
echo 'export NEEDRESTART_SUSPEND=1' | sudo tee -a /home/runner/.bashrc > /dev/null
sudo mkdir -p /home/runner/Desktop
sudo chown -R runner:runner /home/runner

ok "User siap: $(id runner)"
step_done
