#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Configure Cinnamon Effects and Favorites
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 11/19] CONFIGURE CINNAMON EFFECTS + FAVORITES${C_NC}"
echo "------------------------------------------------------------"

set_gs() { sudo -u runner dbus-run-session -- gsettings set "$@" || true; }

echo -e "${C_YELLOW}[INFO] Enabling Cinnamon effects (best-effort; software rendering tetap membatasi animasi)...${C_NC}"
set_gs org.cinnamon.desktop.interface enable-animations true
set_gs org.cinnamon desktop-effects true
set_gs org.cinnamon desktop-effects-workspace true
set_gs org.cinnamon desktop-effects-on-menus true
set_gs org.cinnamon desktop-effects-on-dialogs true
set_gs org.cinnamon desktop-effects-change-size true
set_gs org.cinnamon.desktop.interface clock-use-24h true

echo -e "${C_YELLOW}[INFO] Setting favorite apps ke aplikasi yang benar-benar terpasang...${C_NC}"
FAVORITES="['google-chrome.desktop', 'code.desktop', 'org.gnome.Terminal.desktop', 'nemo.desktop'"
if [ -f /usr/share/applications/cinnamon-settings.desktop ]; then
  FAVORITES="$FAVORITES, 'cinnamon-settings.desktop'"
fi
for f in /usr/share/applications/*opencode*.desktop; do
  [ -e "$f" ] || continue
  FAVORITES="$FAVORITES, '$(basename "$f")'"
done
FAVORITES="$FAVORITES]"
set_gs org.cinnamon favorite-apps "$FAVORITES"

sudo chown -R runner:runner /home/runner/.config || true

echo "------------------------------------------------------------"
sudo -u runner dbus-run-session -- gsettings get org.cinnamon favorite-apps || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon desktop-effects || true
sudo -u runner dbus-run-session -- gsettings get org.cinnamon.desktop.interface enable-animations || true
echo "------------------------------------------------------------"

echo -e "${C_GREEN}[OK] Cinnamon effects/favorites configured. Animasi bisa tetap instan di llvmpipe (batasan Cinnamon).${C_NC}"
