#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Install Safe Upgrade Helper
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 12/19] INSTALL SAFE-UPGRADE HELPER${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Copying repo scripts/safe-upgrade.sh...${C_NC}"
if [ ! -f "$GITHUB_WORKSPACE/scripts/safe-upgrade.sh" ]; then
  echo -e "${C_RED}[FAIL] scripts/safe-upgrade.sh tidak ditemukan (checkout gagal).${C_NC}"
  exit 1
fi
sudo cp "$GITHUB_WORKSPACE/scripts/safe-upgrade.sh" /usr/local/bin/safe-upgrade
sudo chmod +x /usr/local/bin/safe-upgrade || true
sudo ln -sf /usr/local/bin/safe-upgrade /usr/bin/safe-upgrade || true

# Shortcut Desktop + MOTD warning agar user tidak `apt upgrade` polos.
sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/SafeUpgrade.desktop" /home/runner/Desktop/SafeUpgrade.desktop
sudo chmod +x /home/runner/Desktop/SafeUpgrade.desktop || true
sudo chown runner:runner /home/runner/Desktop/SafeUpgrade.desktop || true

echo 'JANGAN jalankan `sudo apt upgrade -y` polos di sesi CRD (memutus koneksi). Pakai: safe-upgrade' \
  | sudo tee /etc/motd > /dev/null || true

echo "------------------------------------------------------------"
ls -l /usr/local/bin/safe-upgrade || true
safe-upgrade --help || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] safe-upgrade installed. Gunakan \`safe-upgrade\` pengganti \`apt upgrade\`.${C_NC}"
