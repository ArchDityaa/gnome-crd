#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Configure CRD GNOME Session
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 09/19] CONFIGURE GNOME SESSION${C_NC}"
echo "------------------------------------------------------------"

echo -e "${C_YELLOW}[INFO] Detecting available GNOME session...${C_NC}"
ls /usr/share/xsessions/*.desktop || true
grep -h "^Exec=" /usr/share/xsessions/*.desktop || true
ls -l /usr/bin/gnome-session* || true
ls /usr/share/gnome-session/sessions/ || true

echo -e "${C_YELLOW}[INFO] Fail-fast: binary wajib harus ada...${C_NC}"
test -x /usr/bin/gnome-session || { echo -e "${C_RED}[FAIL] /usr/bin/gnome-session missing.${C_NC}"; exit 1; }

# Pilih nama session yang benar-benar ada: ubuntu > gnome > gnome-xorg.
GNOME_SESSION_NAME=""
if [ -f /usr/share/gnome-session/sessions/ubuntu.session ]; then
  GNOME_SESSION_NAME="ubuntu"
elif [ -f /usr/share/gnome-session/sessions/gnome.session ]; then
  GNOME_SESSION_NAME="gnome"
elif [ -f /usr/share/gnome-session/sessions/gnome-xorg.session ]; then
  GNOME_SESSION_NAME="gnome-xorg"
else
  echo -e "${C_RED}[FAIL] tidak ada *.session yang dikenal di /usr/share/gnome-session/sessions/.${C_NC}"
  ls /usr/share/gnome-session/sessions/ || true
  exit 1
fi
echo -e "${C_YELLOW}[INFO] Using gnome-session --session=$GNOME_SESSION_NAME${C_NC}"

RUNNER_UID=$(id -u runner)
echo -e "${C_YELLOW}[INFO] runner UID=$RUNNER_UID${C_NC}"
sudo mkdir -p "/run/user/$RUNNER_UID"
sudo chown runner:runner "/run/user/$RUNNER_UID"
sudo chmod 700 "/run/user/$RUNNER_UID"

echo -e "${C_YELLOW}[INFO] Writing .chrome-remote-desktop-session (direct absolute-path exec + retry xrandr)...${C_NC}"
sed -e "s|@GNOME_SESSION_NAME@|$GNOME_SESSION_NAME|g" \
  -e "s|@RUNNER_UID@|$RUNNER_UID|g" \
  "$REPO_ROOT/assets/gnome24/session/chrome-remote-desktop-session.in" \
  | sudo -u runner tee /home/runner/.chrome-remote-desktop-session > /dev/null

sudo chown runner:runner \
  /home/runner/.chrome-remote-desktop-session

sudo chmod +x \
  /home/runner/.chrome-remote-desktop-session

echo -e "${C_YELLOW}[INFO] Creating autostart fallback (set-resolution.sh re-apply 1024x768 after Mutter start)...${C_NC}"
sudo install -D -m 0755 "$REPO_ROOT/scripts/gnome24/set-resolution.sh" /usr/local/bin/set-resolution.sh
sudo chmod +x /usr/local/bin/set-resolution.sh
sudo -u runner mkdir -p /home/runner/.config/autostart
sudo install -D -m 0644 -o runner -g runner "$REPO_ROOT/assets/gnome24/autostart/set-resolution.desktop" /home/runner/.config/autostart/set-resolution.desktop

echo "------------------------------------------------------------"
cat /home/runner/.chrome-remote-desktop-session || true
echo "------------------------------------------------------------"
echo -e "${C_YELLOW}[INFO] Final check: no Xsession/lightdm wrapper allowed...${C_NC}"
if grep -q "Xsession\|lightdm" /home/runner/.chrome-remote-desktop-session; then
  echo -e "${C_RED}[FAIL] session file masih mengandung Xsession/lightdm.${C_NC}"
  exit 1
fi

echo -e "${C_GREEN}[OK] GNOME session configured for CRD (session=$GNOME_SESSION_NAME).${C_NC}"
