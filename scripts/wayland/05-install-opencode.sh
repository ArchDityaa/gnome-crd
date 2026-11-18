#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Install OpenCode
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "04/11" "Install OpenCode"

if ! command -v curl > /dev/null 2>&1; then
  run_quiet "Pasang curl" sudo apt-get install -y -qq curl
fi

# Installer selalu memasang ke $HOME/.opencode/bin (mengabaikan
# OPENCODE_INSTALL_DIR); PATH diekspor manual untuk step ini.
install_opencode_cli() { ( set -o pipefail; curl -fsSL https://opencode.ai/v2/install | bash ); }
run_quiet "OpenCode CLI" install_opencode_cli
export PATH="$HOME/.opencode/bin:$PATH"

# Salin system-wide agar tersedia untuk root, runner, dan GNOME Terminal.
sudo cp "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode || true
sudo chmod +x /usr/local/bin/opencode || true
ok "OpenCode CLI $(opencode --version)"

# .deb sudah diunduh di background pada step 02; unduh ulang bila belum ada.
mkdir -p /tmp/dl
if [ ! -s /tmp/dl/opencode-desktop.deb ]; then
  run_quiet "Unduh OpenCode Desktop" \
    wget -q https://opencode.ai/download/stable/linux-x64-deb -O /tmp/dl/opencode-desktop.deb
fi
run_quiet "OpenCode Desktop" \
  sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    -o Dpkg::Use-Pty=0 /tmp/dl/opencode-desktop.deb
rm -f /tmp/dl/opencode-desktop.deb

step_done
