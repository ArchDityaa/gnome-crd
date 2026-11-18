#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Install Google Chrome
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 04/19] INSTALL GOOGLE CHROME${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Downloading Google Chrome stable...${C_NC}"
wget -q \
  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
  -O /tmp/google-chrome.deb

echo -e "${C_YELLOW}[INFO] Installing .deb package...${C_NC}"
sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0 /tmp/google-chrome.deb

rm -f /tmp/google-chrome.deb

echo -e "${C_GREEN}[OK] Google Chrome installed: $(google-chrome --version)${C_NC}"
