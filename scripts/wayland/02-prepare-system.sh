#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Prepare System
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "01/11" "Prepare system"

# Waktu mulai job; dipakai Keep Alive & Summary untuk sisa/total waktu.
echo "JOB_START_EPOCH=$(date +%s)" >> "$GITHUB_ENV"

# Timezone Asia/Jakarta (WIB). timedatectl tidak memperbarui
# /etc/timezone, jadi keduanya disamakan agar tidak kembali ke UTC.
TZ_TARGET="Asia/Jakarta"
if [ ! -e "/usr/share/zoneinfo/$TZ_TARGET" ]; then
  fail "zoneinfo $TZ_TARGET tidak tersedia"
  exit 1
fi
sudo timedatectl set-timezone "$TZ_TARGET" 2>/dev/null || true
echo "$TZ_TARGET" | sudo tee /etc/timezone > /dev/null
sudo ln -sf "/usr/share/zoneinfo/$TZ_TARGET" /etc/localtime
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive tzdata > /dev/null 2>&1 || true
sudo ln -sf "/usr/share/zoneinfo/$TZ_TARGET" /etc/localtime
if [ "$(cat /etc/timezone 2>/dev/null)" != "$TZ_TARGET" ] || [ "$(date +%z)" != "+0700" ]; then
  fail "Timezone tidak ter-set ke $TZ_TARGET"
  exit 1
fi
ok "Timezone: $(date +'%Z %z')"

# Nonaktifkan needrestart (hook apt 99needrestart / 20needrestart)
# agar apt tidak memindai proses atau me-restart service CRD.
sudo rm -f /etc/apt/apt.conf.d/99needrestart /etc/apt/apt.conf.d/20needrestart || true
sudo mkdir -p /etc/needrestart/needrestart.conf.d || true
printf '%s\n' \
  "\$nrconf{restart} = 'l';" \
  '$nrconf{kernelhints} = 0;' \
  '$nrconf{check} = 0;' \
  | sudo tee /etc/needrestart/needrestart.conf.d/99-no-restart.conf > /dev/null

sudo install -D -m 0644 "$REPO_ROOT/assets/wayland/apt/99-speed.conf" /etc/apt/apt.conf.d/99-speed
ok "needrestart dinonaktifkan · apt dioptimalkan"

# Seed cache .deb dari GitHub cache (hemat ~GB saat re-run).
sudo mkdir -p /var/cache/apt/archives/partial
sudo cp -a /home/runner/apt-archives/. /var/cache/apt/archives/ 2>/dev/null || true

# Repo pihak ketiga: VS Code, Google Chrome, Chrome Remote Desktop.
# Kunci Google yang sama dipakai Chrome dan CRD. File
# /etc/default/google-chrome mencegah paket Chrome menambah repo-nya
# sendiri (menghindari sumber ganda).
add_repos() {
  sudo mkdir -p /etc/apt/keyrings || return 1
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null || return 1
  wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/google-linux.gpg > /dev/null || return 1
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null || return 1
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null || return 1
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] http://dl.google.com/linux/chrome-remote-desktop/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/chrome-remote-desktop.list > /dev/null || return 1
  echo 'repo_add_once="false"' | sudo tee /etc/default/google-chrome > /dev/null || return 1
}
run_quiet "Tambah repo VS Code, Chrome, CRD" add_repos

run_quiet "Perbarui daftar paket" sudo apt-get update -qq

RQ_SOFT=1 run_quiet "Hapus paket tidak diperlukan" \
  sudo apt-get remove -y -qq --purge man-db firewalld ufw || true
RQ_SOFT=1 run_quiet "Autoremove" sudo apt-get autoremove -y -qq || true

# Hapus snapd + paket transisi snap SEBELUM upgrade agar apt tidak
# menunggu snap store; hold mencegah terpasang kembali.
sudo systemctl stop snapd.service snapd.socket 2>/dev/null || true
RQ_SOFT=1 run_quiet "Hapus snapd & paket transisi snap" \
  sudo apt-get purge -y -qq snapd thunderbird firefox || true
sudo apt-mark hold snapd thunderbird firefox > /dev/null
sudo rm -rf /snap /var/snap /var/lib/snapd /root/snap /home/runner/snap 2>/dev/null || true

# Full upgrade hanya saat build. Dari dalam sesi CRD gunakan `safe-upgrade`.
run_quiet "Full upgrade sistem" \
  sudo NEEDRESTART_MODE=l DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-unsafe-io" \
    -o Dpkg::Use-Pty=0

step_done
