#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Install Chrome Remote Desktop
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 08/19] INSTALL CHROME REMOTE DESKTOP${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Adding Google CRD repository...${C_NC}"

wget -qO- \
  https://dl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/google-linux.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome-remote-desktop/deb/ stable main" \
  | sudo tee /etc/apt/sources.list.d/chrome-remote-desktop.list > /dev/null

sudo apt-get update

echo -e "${C_YELLOW}[INFO] Installing chrome-remote-desktop...${C_NC}"
sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Use-Pty=0 \
  chrome-remote-desktop

echo -e "${C_GREEN}[OK] Chrome Remote Desktop installed.${C_NC}"
