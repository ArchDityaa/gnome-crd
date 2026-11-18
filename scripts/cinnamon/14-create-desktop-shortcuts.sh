#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Create Desktop Shortcuts
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 13/19] CREATE DESKTOP SHORTCUTS${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Creating Antigravity shortcut...${C_NC}"
sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/Antigravity.desktop" /home/runner/Desktop/Antigravity.desktop

echo -e "${C_YELLOW}[INFO] Creating VS Code shortcut...${C_NC}"
sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/VSCode.desktop" /home/runner/Desktop/VSCode.desktop

# OpenCode Desktop (.deb sudah menyediakan .desktop di
# /usr/share/applications, tinggal salin ke Desktop).
# Fallback: buat manual jika file tidak ditemukan.
echo -e "${C_YELLOW}[INFO] Linking OpenCode shortcut...${C_NC}"
if ls /usr/share/applications/*opencode*.desktop 1> /dev/null 2>&1; then
  cp /usr/share/applications/*opencode*.desktop /home/runner/Desktop/ || true
else
  sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/OpenCode.desktop" /home/runner/Desktop/OpenCode.desktop
fi

# Nemo adalah file manager default Cinnamon (bukan Nautilus).
echo -e "${C_YELLOW}[INFO] Creating Nemo shortcut...${C_NC}"
sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/Nemo.desktop" /home/runner/Desktop/Nemo.desktop

echo -e "${C_YELLOW}[INFO] Creating Terminal shortcut...${C_NC}"
sudo install -D -m 0755 -o runner -g runner "$REPO_ROOT/assets/cinnamon/desktop/Terminal.desktop" /home/runner/Desktop/Terminal.desktop

sudo chmod +x /home/runner/Desktop/*.desktop

# Cinnamon/Nemo meminta penanda trusted sebelum .desktop bisa
# dijalankan dengan klik ganda. gio metadata disimpan per-user.
for f in /home/runner/Desktop/*.desktop; do
  sudo -u runner gio set "$f" metadata::trusted true 2>/dev/null || true
done

sudo chown -R runner:runner /home/runner/Desktop

echo "------------------------------------------------------------"
ls -l /home/runner/Desktop/*.desktop || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] Desktop shortcuts created.${C_NC}"
