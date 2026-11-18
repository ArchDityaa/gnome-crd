#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Install OpenCode CLI
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 06/19] INSTALL OPENCODE CLI${C_NC}"
echo "------------------------------------------------------------"

sudo apt-get update

sudo apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0 curl

# NOTE: installer opencode.ai/install mengabaikan
# OPENCODE_INSTALL_DIR dan selalu install ke $HOME/.opencode/bin.
# $GITHUB_PATH dari installer hanya berlaku untuk step berikutnya,
# jadi export PATH manual untuk step yang sama.
echo -e "${C_YELLOW}[INFO] Running official OpenCode installer...${C_NC}"
curl -fsSL https://opencode.ai/v2/install | bash

export PATH="$HOME/.opencode/bin:$PATH"

# Salin system-wide agar tersedia untuk root + runner +
# GNOME Terminal via CRD (yang tidak selalu load ~/.bashrc baru).
sudo cp "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode || true
sudo chmod +x /usr/local/bin/opencode || true

echo -e "${C_GREEN}[OK] OpenCode CLI installed: $(opencode --version)${C_NC}"
echo -e "${C_GREEN}[OK] Binary location: $(which opencode)${C_NC}"
