#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Authorize & Register Chrome Remote Desktop (Web UI)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 17/19] AUTHORIZE & REGISTER CHROME REMOTE DESKTOP${C_NC}"
echo "------------------------------------------------------------"

STATE_DIR=/tmp/crd-web-auth
SERVER="$GITHUB_WORKSPACE/scripts/crd-web-auth.py"
PORT=8787
TIMEOUT_MINUTES=30

if [ ! -f "$SERVER" ]; then
  echo -e "${C_RED}[FAIL] scripts/crd-web-auth.py tidak ditemukan (checkout gagal).${C_NC}"
  exit 1
fi

rm -rf "$STATE_DIR"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

CRD_WEB_TOKEN="$(openssl rand -hex 16)"
export CRD_WEB_STATE="$STATE_DIR"
export CRD_WEB_PORT="$PORT"
export CRD_WEB_TOKEN
TOKEN="$CRD_WEB_TOKEN"
DEADLINE=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))

python3 "$SERVER" set-status waiting \
  "Menunggu perintah Chrome Remote Desktop..." --deadline "$DEADLINE"

echo -e "${C_YELLOW}[INFO] Starting form server on 127.0.0.1:$PORT ...${C_NC}"
python3 "$SERVER" > "$STATE_DIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo -e "${C_RED}[FAIL] Server form gagal start.${C_NC}"
  cat "$STATE_DIR/server.log" || true
  exit 1
fi

CLOUDFLARED=/tmp/cloudflared
if [ ! -x "$CLOUDFLARED" ]; then
  echo -e "${C_YELLOW}[INFO] Downloading cloudflared...${C_NC}"
  curl -fsSL --retry 3 --retry-delay 2 \
    -o "$CLOUDFLARED" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x "$CLOUDFLARED"
fi

TUNNEL_LOG="$STATE_DIR/tunnel.log"
TUNNEL_PID=""
PUBLIC_URL=""
TUNNEL_RESTARTS=0

start_tunnel() {
  local proto="${1:-}"
  : > "$TUNNEL_LOG"
  if [ -n "$proto" ]; then
    nohup "$CLOUDFLARED" tunnel --no-autoupdate --protocol "$proto" \
      --url "http://127.0.0.1:$PORT" >> "$TUNNEL_LOG" 2>&1 &
  else
    nohup "$CLOUDFLARED" tunnel --no-autoupdate \
      --url "http://127.0.0.1:$PORT" >> "$TUNNEL_LOG" 2>&1 &
  fi
  TUNNEL_PID=$!
  PUBLIC_URL=""
  local _i
  for _i in {1..30}; do
    PUBLIC_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n1 || true)"
    if [ -n "$PUBLIC_URL" ]; then
      return 0
    fi
    kill -0 "$TUNNEL_PID" 2>/dev/null || return 1
    sleep 1
  done
  return 1
}

stop_process() {
  local pid="$1"
  local _i
  [ -z "$pid" ] && return 0
  kill "$pid" 2>/dev/null || true
  for _i in {1..10}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -9 "$pid" 2>/dev/null || true
}

cleanup_tunnel() {
  stop_process "$TUNNEL_PID"
}

cleanup() {
  cleanup_tunnel
  stop_process "$SERVER_PID"
}
trap cleanup EXIT

announce_url() {
  local url="$1"
  echo ""
  echo "=============================================================="
  echo -e "${C_GREEN}      [OK] FORM OTORISASI SIAP${C_NC}"
  echo "=============================================================="
  echo -e "      [INFO] URL   : ${url}/${TOKEN}/"
  echo -e "      [INFO] Batas : ${TIMEOUT_MINUTES} menit"
  echo ""
  echo "      Langkah:"
  echo "      1. Buka URL di atas (bisa dari HP / jaringan lain)."
  echo "         Jika muncul error Cloudflare, tunggu ~15 detik lalu refresh."
  echo "      2. Buka https://remotedesktop.google.com/headless di tab lain,"
  echo "         login, Begin -> Next -> Authorize."
  echo "      3. Copy SELURUH perintah Debian Linux, paste ke form, submit."
  echo "=============================================================="
  echo ""
  echo "::notice title=CRD Authorization::Buka ${url}/${TOKEN}/ lalu paste perintah Chrome Remote Desktop."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## 🔐 Otorisasi Chrome Remote Desktop"
      echo ""
      echo "Desktop sudah siap. Buka URL berikut lalu paste perintah dari"
      echo "<https://remotedesktop.google.com/headless> (berlaku ±${TIMEOUT_MINUTES} menit):"
      echo ""
      echo "**<${url}/${TOKEN}/>**"
      echo ""
      echo "_Jika URL menampilkan error Cloudflare (1033/502), tunggu ~15 detik lalu refresh._"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

register_command() {
  local cmd="$1"
  local attempt rc
  local clean

  # Bersihkan input + buang --name lama; device selalu dinamai "gnome".
  clean="$(printf '%s' "$cmd" | tr -d '\r' | sed -E 's/--name=("[^"]*"|[^ ]*)//g' | sed 's/[[:space:]]*$//')"
  echo "::add-mask::$clean"

  if ! printf '%s' "$clean" | grep -q 'start-host'; then
    echo -e "${C_RED}[FAIL] Perintah tidak mengandung 'start-host'.${C_NC}"
    return 1
  fi
  # Defense in depth: server sudah memvalidasi, tapi jangan percaya
  # mentah-mentah karena perintah dieksekusi lewat `bash -c`.
  if printf '%s' "$clean" | grep -qE '\\|\$\(|`|;|&|\||>|<'; then
    echo -e "${C_RED}[FAIL] Perintah mengandung karakter berbahaya.${C_NC}"
    return 1
  fi
  clean="$clean --name=\"gnome\""

  echo -e "${C_YELLOW}[INFO] Registering host as user 'runner' (retry 3x jika OAuth transien)...${C_NC}"
  rc=1
  for attempt in 1 2 3; do
    python3 "$SERVER" set-status registering \
      "Mendaftarkan perangkat... (percobaan ${attempt}/3)" --attempts "$attempt" || true
    echo -e "${C_YELLOW}[INFO] Registration attempt ${attempt}/3 ...${C_NC}"
    if sudo -u runner \
      env CRD_PIN="$CRD_PIN" \
      bash -c "$clean --pin=\"$CRD_PIN\""; then
      rc=0
      break
    fi
    if [ "$attempt" -lt 3 ]; then
      echo -e "${C_YELLOW}[WARN] Registrasi gagal (mungkin kode single-use kadaluarsa/terpakai, atau error transien). Retry dalam $((attempt * 5))s...${C_NC}"
      sleep $((attempt * 5))
    fi
  done
  return "$rc"
}

RESULT=""

if ! start_tunnel; then
  echo -e "${C_YELLOW}[WARN] Tunnel QUIC gagal, mencoba protocol http2...${C_NC}"
  cleanup_tunnel
  start_tunnel http2 || true
fi

if [ -z "$PUBLIC_URL" ]; then
  echo -e "${C_RED}[FAIL] Cloudflare quick tunnel tidak bisa dibuat.${C_NC}"
  tail -n 40 "$TUNNEL_LOG" || true

  # Fallback opsional: input crd_host_command dari workflow_dispatch.
  if [ -n "$FALLBACK_CMD" ]; then
    echo -e "${C_YELLOW}[INFO] Memakai crd_host_command dari workflow_dispatch sebagai fallback.${C_NC}"
    if register_command "$FALLBACK_CMD"; then
      RESULT=success
    fi
  fi

  if [ "$RESULT" != "success" ]; then
    python3 "$SERVER" set-status failed \
      "Tunnel gagal dibuat. Jalankan ulang workflow." \
      --error "cloudflared tidak menghasilkan URL publik" || true
    echo -e "${C_RED}[FAIL] Tidak ada form web maupun fallback command yang berhasil.${C_NC}"
    exit 1
  fi
else
  announce_url "$PUBLIC_URL"

  echo -e "${C_YELLOW}[INFO] Menunggu perintah dari form web (maks ${TIMEOUT_MINUTES} menit)...${C_NC}"

  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    # Cek ringan tanpa spawn proses Python tiap 2 detik.
    if grep -q '"state": "success"' "$STATE_DIR/status.json" 2>/dev/null; then
      RESULT=success
      break
    fi

    if [ -f "$STATE_DIR/command" ]; then
      if mv "$STATE_DIR/command" "$STATE_DIR/command.processing" 2>/dev/null; then
        SUBMITTED="$(cat "$STATE_DIR/command.processing" 2>/dev/null || true)"
        echo -e "${C_GREEN}[OK] Perintah diterima dari form web.${C_NC}"
        if register_command "$SUBMITTED"; then
          rm -f "$STATE_DIR/command.processing"
          RESULT=success
          break
        fi
        rm -f "$STATE_DIR/command.processing"
        python3 "$SERVER" set-status failed \
          "Registrasi gagal. Ambil kode BARU di halaman headless lalu submit lagi." \
          --error "Kode OAuth kemungkinan sudah terpakai/kadaluarsa, atau error jaringan. Detail ada di log workflow." || true
        echo -e "${C_YELLOW}[WARN] Registrasi gagal; menunggu kode baru dari form (tanpa re-run).${C_NC}"
      fi
    fi

    # Restart tunnel kalau cloudflared mati (URL publik akan berubah).
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
      TUNNEL_RESTARTS=$((TUNNEL_RESTARTS + 1))
      echo -e "${C_YELLOW}[WARN] Tunnel berhenti. Restart ${TUNNEL_RESTARTS}/3...${C_NC}"
      if [ "$TUNNEL_RESTARTS" -gt 3 ] || ! start_tunnel; then
        python3 "$SERVER" set-status failed \
          "Tunnel bermasalah. Jalankan ulang workflow." \
          --error "cloudflared berhenti berulang kali" || true
        echo -e "${C_RED}[FAIL] Tunnel tidak bisa dipertahankan.${C_NC}"
        exit 1
      fi
      announce_url "$PUBLIC_URL"
    fi

    sleep 2
  done

  if [ "$RESULT" != "success" ]; then
    python3 "$SERVER" set-status failed \
      "Waktu tunggu ${TIMEOUT_MINUTES} menit habis. Jalankan ulang workflow." \
      --error "Tidak ada perintah valid yang diterima" || true
    echo ""
    echo -e "${C_RED}[FAIL] Tidak ada perintah dari form dalam ${TIMEOUT_MINUTES} menit.${C_NC}"
    echo -e "${C_RED}  Re-run workflow ini; cache .deb membuat re-run jauh lebih cepat.${C_NC}"
    exit 1
  fi
fi

python3 "$SERVER" set-status success \
  "Berhasil! Buka https://remotedesktop.google.com/access dan pilih device 'gnome'." || true
echo -e "${C_GREEN}[OK] Perintah berhasil didaftarkan.${C_NC}"

# Beri browser window polling yang memadai sebelum tunnel dimatikan
# (interval polling form 2-10s + jeda warm-up jaringan).
sleep 20
cleanup_tunnel
echo -e "${C_YELLOW}[INFO] Form otorisasi ditutup.${C_NC}"

# Fallback: `start-host` mencoba `sudo`/`pkexec systemctl enable --now
# chrome-remote-desktop@<user>`. Tapi tanpa TTY (seperti di runner
# ini, stdin diarahkan ke /dev/null) metode itu bisa gagal senyap,
# sehingga host terdaftar tapi service tidak pernah jalan. Pastikan
# di sini supaya device langsung bisa di-connect.
echo -e "${C_YELLOW}[INFO] Memastikan chrome-remote-desktop@runner.service aktif...${C_NC}"
sudo systemctl enable chrome-remote-desktop@runner >/dev/null 2>&1 || true
sudo systemctl start chrome-remote-desktop@runner >/dev/null 2>&1 || true
sleep 2
if systemctl is-active --quiet chrome-remote-desktop@runner; then
  echo -e "${C_GREEN}[OK] chrome-remote-desktop@runner aktif.${C_NC}"
else
  echo -e "${C_YELLOW}[WARN] chrome-remote-desktop@runner belum aktif; cukup connect sekali dari https://remotedesktop.google.com/access, service akan autostart.${C_NC}"
fi

echo ""
echo "=============================================================="
echo -e "${C_GREEN}      [OK] CHROME REMOTE DESKTOP READY${C_NC}"
echo "=============================================================="
echo -e "      [INFO] Access    : https://remotedesktop.google.com/access"
echo -e "      [INFO] User      : runner"
echo -e "      [INFO] PIN       : default 123456 (or custom via secret CRD_PIN)"
echo "=============================================================="
echo ""
echo "::notice::CRD ready - connect via https://remotedesktop.google.com/access as user runner"
