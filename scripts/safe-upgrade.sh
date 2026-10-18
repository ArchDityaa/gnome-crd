#!/usr/bin/env bash
#
# safe-upgrade - pengganti `sudo apt upgrade` di dalam sesi Chrome Remote Desktop.
#
# Kenapa script ini ada?
# `sudo apt upgrade -y` polos bisa men-restart chrome-remote-desktop@runner,
# gnome-shell, systemd, atau Xorg. Kalau itu terjadi, sesi CRD langsung putus
# dan sering tidak bisa kembali (kecuali re-run workflow dari nol).
#
# Script ini menjalankan apt upgrade dengan setting yang membuat service
# tidak di-restart otomatis:
#   - NEEDRESTART_MODE=l       -> needrestart hanya LIST (tidak restart apa pun)
#   - NEEDRESTART_SUSPEND=1    -> matikan needrestart sepenuhnya selama run ini
#   - Dpkg::Options --force-confold/--force-confdef -> tidak ada prompt config
#     (prompt akan hang karena tidak ada TTY di sesi remote)
#   - Dpkg::Use-Pty=0          -> hindari dpkg mengubah mode TTY
#   - --force-unsafe-io        -> unpack lebih cepat (aman untuk sesi sementara)
#
# Package yang butuh restart / reboot tetap DILAPORKAN, bukan dieksekusi diam-diam.
#
# Pemakaian:
#   safe-upgrade              # apt-get update + apt-get upgrade -y
#   safe-upgrade --full       # pakai dist-upgrade (bisa pasang/hapus paket)
#   safe-upgrade --dry-run    # hanya tampilkan apa yang akan dilakukan
#   safe-upgrade --no-autoremove
#   safe-upgrade --help
#
# Cocok juga dipanggil dari shortcut "Safe Upgrade" di Desktop sesi CRD.

set -uo pipefail

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'
  C_RED='\033[1;31m';  C_NC='\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_NC=''
fi

log()  { printf '%b\n' "${C_CYAN}[safe-upgrade]${C_NC} $*"; }
ok()   { printf '%b\n' "${C_GREEN}[OK]${C_NC} $*"; }
warn() { printf '%b\n' "${C_YELLOW}[WARN]${C_NC} $*"; }
err()  { printf '%b\n' "${C_RED}[FAIL]${C_NC} $*" >&2; }

usage() {
  cat <<'USAGE'
safe-upgrade - apt upgrade yang tidak memutus sesi Chrome Remote Desktop

Pemakaian:
  safe-upgrade [opsi]

Opsi:
  -f, --full            Gunakan dist-upgrade (default: upgrade biasa)
  -n, --dry-run         Tampilkan rencana tanpa mengeksekusi apt
      --no-autoremove   Jangan jalankan apt-get autoremove
  -h, --help            Tampilkan bantuan ini

Default (tanpa opsi): apt-get update lalu apt-get upgrade -y, ditambah
autoremove untuk paket yang sudah tidak dipakai.

Selalu jalankan dengan sudo:
  sudo safe-upgrade
USAGE
}

# ---------------------------------------------------------------------------
# Argumen
# ---------------------------------------------------------------------------
MODE="upgrade"
DRY_RUN=0
AUTOREMOVE=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f|--full|--dist-upgrade) MODE="dist-upgrade" ;;
    -n|--dry-run)             DRY_RUN=1 ;;
    --no-autoremove)          AUTOREMOVE=0 ;;
    -h|--help)                usage; exit 0 ;;
    *) err "Opsi tidak dikenal: $1"; echo; usage; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Wajib root
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  err "Harus dijalankan sebagai root. Pakai: sudo safe-upgrade"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  err "apt-get tidak ditemukan. Script ini khusus Ubuntu/Debian."
  exit 1
fi

# ---------------------------------------------------------------------------
# Environment anti-putus-sesi
# ---------------------------------------------------------------------------
# Dipasang ke seluruh proses anak (apt/dpkg/needrestart).
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l
export NEEDRESTART_SUSPEND=1
export UCF_FORCE_CONFFOLD=1
export DEBCONF_NONINTERACTIVE_SEEN=true

APT_OPTS=(
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
  -o Dpkg::Options::=--force-unsafe-io
  -o Dpkg::Use-Pty=0
  -o Acquire::Retries=5
  -o Acquire::http::Timeout=60
)

# ---------------------------------------------------------------------------
# Snapshot status sebelum upgrade (untuk laporan)
# ---------------------------------------------------------------------------
CRD_UNITS=()
while IFS= read -r u; do
  [ -n "$u" ] && CRD_UNITS+=("$u")
done < <(systemctl list-units --type=service --no-legend --plain \
         'chrome-remote-desktop*' 2>/dev/null | awk '{print $1}')

log "Unit CRD terdeteksi: ${CRD_UNITS[*]:-<tidak ada>}"

# ---------------------------------------------------------------------------
# 1. Update index
# ---------------------------------------------------------------------------
log "Menjalankan apt-get update ..."
if [ "$DRY_RUN" -eq 1 ]; then
  log "[dry-run] apt-get update ${APT_OPTS[*]}"
else
  if ! apt-get update "${APT_OPTS[@]}"; then
    err "apt-get update gagal. Cek koneksi jaringan / sumber apt."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 2. Daftar upgrade (dan tampilkan)
# ---------------------------------------------------------------------------
log "Paket yang akan di-upgrade:"
if ! apt-get --simulate "$MODE" 2>/dev/null | sed -n '/^Inst /p' | sed 's/^/    /'; then
  warn "Tidak bisa membuat simulasi upgrade (lanjut saja)."
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  log "[dry-run] Selesai. Tidak ada perubahan yang diterapkan."
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Upgrade
# ---------------------------------------------------------------------------
log "Menjalankan apt-get $MODE -y (tanpa restart service) ..."
if ! apt-get "$MODE" -y "${APT_OPTS[@]}"; then
  err "apt-get $MODE gagal. Sesi CRD TIDAK di-restart oleh script ini."
  err "Perbaiki error dpkg di atas, lalu jalankan ulang: sudo safe-upgrade"
  exit 1
fi
ok "Upgrade selesai."

# ---------------------------------------------------------------------------
# 4. Autoremove (opsional)
# ---------------------------------------------------------------------------
if [ "$AUTOREMOVE" -eq 1 ]; then
  log "Membersihkan paket yang tidak diperlukan (autoremove) ..."
  apt-get autoremove -y "${APT_OPTS[@]}" || warn "autoremove gagal (tidak fatal)."
fi

# ---------------------------------------------------------------------------
# 5. Laporan: service yang butuh restart + reboot
# ---------------------------------------------------------------------------
echo
log "Ringkasan:"
if [ -f /var/run/reboot-required ]; then
  warn "File /var/run/reboot-required ada -> ada update (kernel/libc) yang"
  warn "idealnya butuh reboot. JANGAN reboot dari sesi CRD: reboot akan"
  warn "mematikan VM runner dan sesi hilang. Abaikan sampai sesi berakhir."
  [ -f /var/run/reboot-required.pkgs ] && sed 's/^/    /' /var/run/reboot-required.pkgs
else
  ok "Tidak ada permintaan reboot."
fi

if command -v needrestart >/dev/null 2>&1; then
  log "Service yang memakai library lama (informasi saja, TIDAK di-restart):"
  needrestart -b 2>/dev/null | sed 's/^/    /' || true
fi

# ---------------------------------------------------------------------------
# 6. Pastikan sesi CRD masih hidup
# ---------------------------------------------------------------------------
if [ "${#CRD_UNITS[@]}" -gt 0 ]; then
  for u in "${CRD_UNITS[@]}"; do
    if systemctl is-active --quiet "$u"; then
      ok "Service $u masih aktif."
    else
      warn "Service $u TIDAK aktif. Coba connect sekali dari"
      warn "https://remotedesktop.google.com/access (service akan autostart)."
    fi
  done
fi

echo
ok "Selesai. Jika ada paket yang memakai library lama, restart aplikasinya"
ok "satu per satu (mis. tutup-buka Chrome), BUKAN lewat reboot."
