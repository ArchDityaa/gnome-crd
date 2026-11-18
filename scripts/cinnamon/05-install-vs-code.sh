#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Install VS Code
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 05/19] INSTALL VS CODE${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Adding Microsoft repository...${C_NC}"
wget -qO- \
  https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor \
  | sudo tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

sudo apt-get update

echo -e "${C_YELLOW}[INFO] Installing VS Code...${C_NC}"
sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0 code

echo -e "${C_GREEN}[OK] VS Code installed: $(code --version | head -n 1)${C_NC}"
