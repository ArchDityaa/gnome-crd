#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Install OpenCode Desktop
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 07/19] INSTALL OPENCODE DESKTOP${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Downloading OpenCode Desktop (.deb latest)...${C_NC}"
wget -q https://opencode.ai/download/stable/linux-x64-deb \
  -O /tmp/opencode-desktop.deb

echo -e "${C_YELLOW}[INFO] Installing .deb package...${C_NC}"
sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0 /tmp/opencode-desktop.deb

rm -f /tmp/opencode-desktop.deb

echo "------------------------------------------------------------"
dpkg -l | grep -i opencode || true
ls /usr/share/applications/*opencode* || true
which opencode-desktop || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] OpenCode Desktop installed.${C_NC}"
