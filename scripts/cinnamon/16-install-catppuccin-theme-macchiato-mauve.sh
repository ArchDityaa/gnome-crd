#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Install Catppuccin Theme (Macchiato + Mauve)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 15/19] INSTALL CATPPUCCIN THEME (MACCHIATO + MAUVE)${C_NC}"
echo "------------------------------------------------------------"

FLAVOR="macchiato"
ACCENT="mauve"
GTK_THEME="catppuccin-${FLAVOR}-${ACCENT}-standard+default"
CURSOR_THEME="catppuccin-${FLAVOR}-${ACCENT}-cursors"
RUSER="runner"
RHOME="/home/${RUSER}"

# ---- 1. Ikon Papirus + folder warna Catppuccin ----
echo -e "${C_YELLOW}[INFO] Installing Papirus icon theme + Catppuccin folders...${C_NC}"
sudo NEEDRESTART_MODE=l apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Use-Pty=0 \
  papirus-icon-theme

rm -rf /tmp/papirus-folders
git clone --depth 1 https://github.com/catppuccin/papirus-folders.git /tmp/papirus-folders
wget -qO /tmp/papirus-folders-bin \
  https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders
sudo install -m 0755 /tmp/papirus-folders-bin /usr/local/bin/papirus-folders
sudo cp -r /tmp/papirus-folders/src/. /usr/share/icons/Papirus/
sudo papirus-folders -C "cat-${FLAVOR}-${ACCENT}" --theme Papirus || true
sudo papirus-folders -C "cat-${FLAVOR}-${ACCENT}" --theme Papirus-Dark || true

# ---- 2. Tema GTK (GTK2/3/4 + cinnamon + css libadwaita) ----
# Nama aset mengandung '+', jadi di URL di-encode ke %2B.
echo -e "${C_YELLOW}[INFO] Downloading Catppuccin GTK theme ($GTK_THEME)...${C_NC}"
sudo -u "$RUSER" mkdir -p "$RHOME/.themes" "$RHOME/.icons"
wget -qO /tmp/cat-gtk.zip \
  "https://github.com/catppuccin/gtk/releases/download/v1.0.3/${GTK_THEME//+/%2B}.zip"
sudo -u "$RUSER" unzip -qo /tmp/cat-gtk.zip -d "$RHOME/.themes/"

# Override libadwaita: gtk.css + assets ke ~/.config/gtk-4.0 supaya
# aplikasi GTK4/libadwaita (Files, Settings, dll) ikut bertema.
sudo -u "$RUSER" mkdir -p "$RHOME/.config/gtk-4.0"
sudo -u "$RUSER" cp -r "$RHOME/.themes/$GTK_THEME/gtk-4.0/." "$RHOME/.config/gtk-4.0/"

# ---- 3. Kursor Catppuccin ----
echo -e "${C_YELLOW}[INFO] Downloading Catppuccin cursors...${C_NC}"
wget -qO /tmp/cat-cursors.zip \
  "https://github.com/catppuccin/cursors/releases/download/v2.0.0/${CURSOR_THEME}.zip"
sudo -u "$RUSER" unzip -qo /tmp/cat-cursors.zip -d "$RHOME/.icons/"

# ---- 4. Font JetBrainsMono Nerd Font ----
echo -e "${C_YELLOW}[INFO] Downloading JetBrainsMono Nerd Font...${C_NC}"
sudo -u "$RUSER" mkdir -p "$RHOME/.local/share/fonts/JetBrainsMonoNerd"
wget -qO /tmp/cat-font.zip \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip"
sudo -u "$RUSER" unzip -qo /tmp/cat-font.zip -d "$RHOME/.local/share/fonts/JetBrainsMonoNerd"
sudo -u "$RUSER" fc-cache -f "$RHOME/.local/share/fonts" >/dev/null 2>&1 || true

# ---- 5. Terapkan tema via gsettings (dconf user runner) ----
echo -e "${C_YELLOW}[INFO] Applying theme via gsettings (user: $RUSER)...${C_NC}"
set_gs() { sudo -u "$RUSER" dbus-run-session -- gsettings set "$@" || true; }
set_gs org.cinnamon.desktop.interface gtk-theme    "$GTK_THEME"
set_gs org.cinnamon.desktop.interface icon-theme   "Papirus-Dark"
set_gs org.cinnamon.desktop.interface cursor-theme "$CURSOR_THEME"
set_gs org.cinnamon.desktop.interface font-name    "JetBrainsMono Nerd Font 11"

# Schema GNOME tetap dipakai aplikasi GTK4/libadwaita, dan Cinnamon
# memakai schema GNOME untuk document-font-name/monospace-font-name.
set_gs org.gnome.desktop.interface gtk-theme           "$GTK_THEME"
set_gs org.gnome.desktop.interface icon-theme          "Papirus-Dark"
set_gs org.gnome.desktop.interface cursor-theme        "$CURSOR_THEME"
set_gs org.gnome.desktop.interface color-scheme        "prefer-dark"
set_gs org.gnome.desktop.interface font-name           "JetBrainsMono Nerd Font 11"
set_gs org.gnome.desktop.interface document-font-name  "JetBrainsMono Nerd Font 11"
set_gs org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font 12"

# ---- 6. Cinnamon shell theme (cinnamon.css di ~/.themes) ----
# ZIP Catppuccin GTK v1.0.3 sudah berisi cinnamon/cinnamon.css +
# assets, jadi nama tema yang sama dipakai GTK dan shell Cinnamon.
# Kalau CSS tidak kompatibel dengan Cinnamon 6.4, fallback ke tema
# bawaan dengan: gsettings set org.cinnamon.theme name ''
echo -e "${C_YELLOW}[INFO] Setting Cinnamon shell theme...${C_NC}"
set_gs org.cinnamon.theme name "$GTK_THEME"

# ---- 7. GNOME Terminal (profil Catppuccin Macchiato) ----
echo -e "${C_YELLOW}[INFO] Installing Catppuccin GNOME Terminal profile...${C_NC}"
rm -rf /tmp/cat-gnome-terminal
git clone --depth 1 https://github.com/catppuccin/gnome-terminal.git /tmp/cat-gnome-terminal
sudo -u "$RUSER" dbus-run-session -- bash -c \
  'cd /tmp/cat-gnome-terminal && python3 install.py' || true
# Set profil Catppuccin Macchiato (uuid tetap dari skrip) sebagai default.
sudo -u "$RUSER" dbus-run-session -- dconf write \
  /org/gnome/terminal/legacy/profiles:/default \
  "'5083e06b-024e-46be-9cd2-892b814f1fc8'" || true

sudo chown -R "$RUSER:$RUSER" \
  "$RHOME/.themes" "$RHOME/.icons" "$RHOME/.config" "$RHOME/.local" 2>/dev/null || true

# ---- 8. Bersihkan unduhan sementara ----
rm -f /tmp/cat-gtk.zip /tmp/cat-cursors.zip /tmp/cat-font.zip /tmp/papirus-folders-bin

echo "------------------------------------------------------------"
echo "--- themes (runner) ---"; ls "$RHOME/.themes" || true
echo "--- cursors (runner) ---"; ls "$RHOME/.icons" || true
echo "--- gsettings (runner) ---"
sudo -u "$RUSER" dbus-run-session -- gsettings get org.cinnamon.desktop.interface gtk-theme || true
sudo -u "$RUSER" dbus-run-session -- gsettings get org.cinnamon.desktop.interface icon-theme || true
sudo -u "$RUSER" dbus-run-session -- gsettings get org.cinnamon.desktop.interface cursor-theme || true
sudo -u "$RUSER" dbus-run-session -- gsettings get org.cinnamon.theme name || true
sudo -u "$RUSER" dbus-run-session -- gsettings get org.gnome.Terminal.ProfilesList default || true
echo "------------------------------------------------------------"

sudo -u "$RUSER" dbus-run-session -- gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null \
  | grep -q 'catppuccin-macchiato-mauve' \
  || { echo -e "${C_RED}[FAIL] Tema Cinnamon/GTK Catppuccin tidak aktif.${C_NC}"; exit 1; }

echo -e "${C_GREEN}[OK] Catppuccin $FLAVOR + $ACCENT terpasang (GTK, Cinnamon shell, libadwaita, ikon, kursor, font, terminal).${C_NC}"
