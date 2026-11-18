#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Install Safe Upgrade Helper
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "08/11" "Install safe-upgrade helper"

if [ ! -f "$GITHUB_WORKSPACE/scripts/safe-upgrade.sh" ]; then
  fail "scripts/safe-upgrade.sh tidak ditemukan (checkout gagal)"
  exit 1
fi
sudo cp "$GITHUB_WORKSPACE/scripts/safe-upgrade.sh" /usr/local/bin/safe-upgrade
sudo chmod +x /usr/local/bin/safe-upgrade || true
sudo ln -sf /usr/local/bin/safe-upgrade /usr/bin/safe-upgrade || true

# Tanpa shortcut desktop (konsisten dengan gnome24.yml); cukup MOTD.
echo 'Gunakan `safe-upgrade` sebagai pengganti `sudo apt upgrade` di sesi Chrome Remote Desktop.' \
  | sudo tee /etc/motd > /dev/null || true

safe-upgrade --help > /dev/null 2>&1 || true
ok "safe-upgrade terpasang: /usr/local/bin/safe-upgrade"
step_done
