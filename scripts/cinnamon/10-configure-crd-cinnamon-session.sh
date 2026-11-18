#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Configure CRD Cinnamon Session
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 09/19] CONFIGURE CINNAMON SESSION${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Detecting available Cinnamon session...${C_NC}"
ls /usr/share/xsessions/cinnamon*.desktop || true
grep -h "^Exec=" /usr/share/xsessions/cinnamon*.desktop || true
ls -l /usr/bin/cinnamon-session* /usr/bin/cinnamon2d 2>/dev/null || true
ls /usr/share/cinnamon-session/sessions/ || true

echo -e "${C_YELLOW}[INFO] Fail-fast: binary + session file wajib ada...${C_NC}"
test -x /usr/bin/cinnamon-session || { echo -e "${C_RED}[FAIL] /usr/bin/cinnamon-session missing.${C_NC}"; exit 1; }
test -f /usr/share/cinnamon-session/sessions/cinnamon.session || { echo -e "${C_RED}[FAIL] cinnamon.session missing.${C_NC}"; exit 1; }

RUNNER_UID=$(id -u runner)
echo -e "${C_YELLOW}[INFO] runner UID=$RUNNER_UID${C_NC}"
sudo mkdir -p "/run/user/$RUNNER_UID"
sudo chown runner:runner "/run/user/$RUNNER_UID"
sudo chmod 700 "/run/user/$RUNNER_UID"

echo -e "${C_YELLOW}[INFO] Writing .chrome-remote-desktop-session (direct exec + retry xrandr)...${C_NC}"
sed -e "s|@RUNNER_UID@|$RUNNER_UID|g" \
  "$REPO_ROOT/assets/cinnamon/session/chrome-remote-desktop-session.in" \
  | sudo -u runner tee /home/runner/.chrome-remote-desktop-session > /dev/null

sudo chown runner:runner \
  /home/runner/.chrome-remote-desktop-session

sudo chmod +x \
  /home/runner/.chrome-remote-desktop-session

echo -e "${C_YELLOW}[INFO] Creating autostart fallback (set-resolution.sh re-apply 1024x768 after Cinnamon/Muffin start)...${C_NC}"
sudo install -D -m 0755 "$REPO_ROOT/scripts/cinnamon/set-resolution.sh" /usr/local/bin/set-resolution.sh
sudo chmod +x /usr/local/bin/set-resolution.sh
sudo -u runner mkdir -p /home/runner/.config/autostart
sudo install -D -m 0644 -o runner -g runner "$REPO_ROOT/assets/cinnamon/autostart/set-resolution.desktop" /home/runner/.config/autostart/set-resolution.desktop

echo "------------------------------------------------------------"
cat /home/runner/.chrome-remote-desktop-session || true
echo "------------------------------------------------------------"
echo -e "${C_YELLOW}[INFO] Final check: no Xsession/lightdm wrapper allowed...${C_NC}"
if grep -q "Xsession\|lightdm" /home/runner/.chrome-remote-desktop-session; then
  echo -e "${C_RED}[FAIL] session file masih mengandung Xsession/lightdm.${C_NC}"
  exit 1
fi
grep -q "exec /usr/bin/cinnamon-session --session cinnamon" \
  /home/runner/.chrome-remote-desktop-session \
  || { echo -e "${C_RED}[FAIL] exec line bukan cinnamon-session.${C_NC}"; exit 1; }

echo -e "${C_GREEN}[OK] Cinnamon session configured for CRD (X11, direct exec).${C_NC}"
