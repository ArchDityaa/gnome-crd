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

echo 'export NEEDRESTART_MODE=l' | sudo tee -a /home/runner/.bashrc > /dev/null
echo 'export NEEDRESTART_SUSPEND=1' | sudo tee -a /home/runner/.bashrc > /dev/null
sudo mkdir -p /home/runner/Desktop
sudo chown -R runner:runner /home/runner

ok "User siap: $(id runner)"
step_done
