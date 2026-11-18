#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Authorize & Register Chrome Remote Desktop (Wayland BETA)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "10/11" "Authorize & register Chrome Remote Desktop"

STATE_DIR=/tmp/crd-web-auth
SERVER="$GITHUB_WORKSPACE/scripts/crd-web-auth.py"
PORT=8787
TIMEOUT_MINUTES=30
RUNNER_UID=$(id -u runner)

as_runner() {
  sudo -u runner env \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
    "$@"
}

if [ ! -f "$SERVER" ]; then
  fail "scripts/crd-web-auth.py tidak ditemukan (checkout gagal)"
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

python3 "$SERVER" > "$STATE_DIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 1
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  fail "Server form gagal dijalankan"
  cat "$STATE_DIR/server.log" || true
  exit 1
fi
ok "Form server aktif di 127.0.0.1:$PORT"

# cloudflared biasanya sudah diunduh di background pada step 02.
CLOUDFLARED=/tmp/cloudflared
if [ ! -x "$CLOUDFLARED" ]; then
  run_quiet "Unduh cloudflared" \
    curl -fsSL --retry 3 --retry-delay 2 -o "$CLOUDFLARED" \
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
  ok "Form otorisasi siap · berlaku ${TIMEOUT_MINUTES} menit"
  kv "URL" "${url}/${TOKEN}/"
  echo ""
  echo "    1. Buka URL di atas (error Cloudflare? tunggu ~15 detik lalu refresh)."
  echo "    2. Buka https://remotedesktop.google.com/headless -> Begin -> Next -> Authorize."
  echo "    3. Salin perintah \"Debian Linux\", tempel di form, lalu submit."
  echo ""
  echo "::notice title=CRD Authorization::Buka ${url}/${TOKEN}/ lalu tempel perintah Chrome Remote Desktop."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## 🔐 Otorisasi Chrome Remote Desktop"
      echo ""
      echo "Desktop sudah siap. Buka URL berikut, lalu tempel perintah dari"
      echo "<https://remotedesktop.google.com/headless> (berlaku ±${TIMEOUT_MINUTES} menit):"
      echo ""
      echo "**<${url}/${TOKEN}/>**"
      echo ""
      echo "_Jika muncul error Cloudflare (1033/502), tunggu ~15 detik lalu refresh._"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

register_command() {
  local cmd="$1"
  local attempt rc
  local clean

  # Bersihkan input dan buang --name lama; device selalu bernama "gnome".
  clean="$(printf '%s' "$cmd" | tr -d '\r' | sed -E 's/--name=("[^"]*"|[^ ]*)//g' | sed 's/[[:space:]]*$//')"
  echo "::add-mask::$clean"

  if ! printf '%s' "$clean" | grep -q 'start-host'; then
    fail "Perintah tidak mengandung 'start-host'"
    return 1
  fi
  # Defense in depth: server sudah memvalidasi, tetapi perintah
  # dieksekusi lewat `bash -c`.
  if printf '%s' "$clean" | grep -qE '\\|\$\(|`|;|&|\||>|<'; then
    fail "Perintah mengandung karakter yang tidak diizinkan"
    return 1
  fi
  clean="$clean --name=\"gnome\""

  # RQ_NOCMD: command line (berisi kode OAuth + PIN) tidak ditulis ke log.
  rc=1
  for attempt in 1 2 3; do
    python3 "$SERVER" set-status registering \
      "Mendaftarkan perangkat... (percobaan ${attempt}/3)" --attempts "$attempt" || true
    if RQ_SOFT=1 RQ_NOCMD=1 run_quiet "Registrasi perangkat (percobaan ${attempt}/3)" \
         sudo -u runner env CRD_PIN="$CRD_PIN" bash -c "$clean --pin=\"$CRD_PIN\""; then
      rc=0
      break
    fi
    if [ "$attempt" -lt 3 ]; then
      info "Kode mungkin kedaluwarsa/terpakai atau error transien · coba lagi dalam $((attempt * 5))s"
      sleep $((attempt * 5))
    fi
  done
  return "$rc"
}

RESULT=""

if ! start_tunnel; then
  warn "Tunnel QUIC gagal · mencoba http2"
  cleanup_tunnel
  start_tunnel http2 || true
fi

if [ -z "$PUBLIC_URL" ]; then
  fail "Cloudflare quick tunnel tidak dapat dibuat"
  tail -n 40 "$TUNNEL_LOG" || true

  # Fallback opsional: input crd_host_command dari workflow_dispatch.
  if [ -n "$FALLBACK_CMD" ]; then
    info "Menggunakan crd_host_command sebagai fallback"
    if register_command "$FALLBACK_CMD"; then
      RESULT=success
    fi
  fi

  if [ "$RESULT" != "success" ]; then
    python3 "$SERVER" set-status failed \
      "Tunnel gagal dibuat. Jalankan ulang workflow." \
      --error "cloudflared tidak menghasilkan URL publik" || true
    fail "Tidak ada form web maupun fallback command yang berhasil"
    exit 1
  fi
else
  announce_url "$PUBLIC_URL"
  info "Menunggu perintah dari form (maks. ${TIMEOUT_MINUTES} menit)"

  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    # Cek ringan tanpa spawn proses Python tiap 2 detik.
    if grep -q '"state": "success"' "$STATE_DIR/status.json" 2>/dev/null; then
      RESULT=success
      break
    fi

    if [ -f "$STATE_DIR/command" ]; then
      if mv "$STATE_DIR/command" "$STATE_DIR/command.processing" 2>/dev/null; then
        SUBMITTED="$(cat "$STATE_DIR/command.processing" 2>/dev/null || true)"
        ok "Perintah diterima dari form"
        if register_command "$SUBMITTED"; then
          rm -f "$STATE_DIR/command.processing"
          RESULT=success
          break
        fi
        rm -f "$STATE_DIR/command.processing"
        python3 "$SERVER" set-status failed \
          "Registrasi gagal. Ambil kode BARU di halaman headless lalu submit lagi." \
          --error "Kode OAuth kemungkinan sudah terpakai/kedaluwarsa, atau error jaringan. Detail ada di log workflow." || true
        warn "Registrasi gagal · menunggu kode baru dari form (tanpa re-run)"
      fi
    fi

    # Restart tunnel bila cloudflared mati (URL publik akan berubah).
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
      TUNNEL_RESTARTS=$((TUNNEL_RESTARTS + 1))
      warn "Tunnel berhenti · restart ${TUNNEL_RESTARTS}/3"
      if [ "$TUNNEL_RESTARTS" -gt 3 ] || ! start_tunnel; then
        python3 "$SERVER" set-status failed \
          "Tunnel bermasalah. Jalankan ulang workflow." \
          --error "cloudflared berhenti berulang kali" || true
        fail "Tunnel tidak dapat dipertahankan"
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
    fail "Tidak ada perintah dari form dalam ${TIMEOUT_MINUTES} menit · jalankan ulang workflow (cache .deb mempercepat re-run)"
    exit 1
  fi
fi

ok "Perangkat terdaftar"

# `start-host` mencoba `systemctl enable --now` lewat sudo/pkexec,
# tetapi tanpa TTY (stdin = /dev/null) dapat gagal senyap. Pastikan
# service aktif agar device langsung bisa di-connect.
sudo systemctl enable chrome-remote-desktop@runner >/dev/null 2>&1 || true
sudo systemctl start chrome-remote-desktop@runner >/dev/null 2>&1 || true
sleep 2
if ! systemctl is-active --quiet chrome-remote-desktop@runner; then
  fail "chrome-remote-desktop@runner tidak aktif"
  systemctl status chrome-remote-desktop@runner --no-pager || true
  sudo journalctl -u chrome-remote-desktop@runner -n 150 --no-pager || true
  # Kirim status gagal saat tunnel masih hidup agar browser menerimanya.
  python3 "$SERVER" set-status failed \
    "Service CRD tidak aktif. Lihat log workflow (Wayland BETA)." \
    --error "chrome-remote-desktop@runner inactive" || true
  exit 1
fi
ok "Service chrome-remote-desktop@runner aktif"

# Kirim status success SAAT tunnel masih hidup, lalu beri jeda agar
# polling browser (2-10 dtk + warm-up tunnel) sempat menerimanya.
python3 "$SERVER" set-status success \
  "Berhasil! Buka https://remotedesktop.google.com/access dan pilih device 'gnome'." || true
sleep 20
cleanup_tunnel
info "Form otorisasi ditutup"

# Pastikan GNOME Shell benar-benar menjadi compositor Wayland headless;
# tanpa WAYLAND_DISPLAY di systemd user env, CRD tidak dapat men-stream desktop.
WAYLAND_READY=0
WAYLAND_SOCKET=""
for i in {1..45}; do
  WAYLAND_SOCKET="$(as_runner systemctl --user show-environment 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -n1 || true)"
  if [ -n "$WAYLAND_SOCKET" ] && [ -S "/run/user/$RUNNER_UID/$WAYLAND_SOCKET" ]; then
    WAYLAND_READY=1
    break
  fi
  sleep 2
done

if [ "$WAYLAND_READY" -ne 1 ]; then
  fail "Compositor Wayland tidak siap dalam ~90 detik (gejala umum mode BETA: shell headless / portal / PipeWire)"
  echo "::group::Debug · chrome-remote-desktop@runner"
  systemctl status chrome-remote-desktop@runner --no-pager || true
  sudo journalctl -u chrome-remote-desktop@runner -n 200 --no-pager || true
  echo "::endgroup::"
  echo "::group::Debug · GNOME Shell user service"
  as_runner systemctl --user status org.gnome.Shell@ubuntu.service --no-pager || true
  as_runner journalctl --user -n 200 --no-pager || true
  echo "::endgroup::"
  echo "::group::Debug · proses & runtime"
  pgrep -a -x gnome-shell || true
  pgrep -a -x gnome-session || true
  pgrep -a chrome-remote || true
  ls -la "/run/user/$RUNNER_UID" | head -n 40 || true
  echo "::endgroup::"
  # Status "success" sudah terkirim ke browser sebelum tunnel ditutup;
  # jangan menimpanya dengan "failed".
  if [ "$(python3 "$SERVER" get-state)" != "success" ]; then
    python3 "$SERVER" set-status failed \
      "GNOME Wayland gagal start. Workflow BETA ini belum berhasil di runner." \
      --error "WAYLAND_DISPLAY tidak muncul / socket tidak ada" || true
  fi
  exit 1
fi

ok "Compositor Wayland aktif ($WAYLAND_SOCKET)"
{
  as_runner systemctl --user status org.gnome.Shell@ubuntu.service --no-pager || true
  pgrep -a -x gnome-shell || true
  pgrep -a -x gnome-session || true
  sudo journalctl -u chrome-remote-desktop@runner -n 40 --no-pager || true
} > "$CI_LOG_DIR/crd-ready-detail.log" 2>&1 || true

echo ""
ok "Chrome Remote Desktop siap (Wayland BETA)"
kv "Akses" "https://remotedesktop.google.com/access"
kv "Perangkat" "gnome"
kv "Pengguna" "runner"
kv "PIN" "default 123456, atau secret CRD_PIN"
echo "::notice::CRD siap - connect lewat https://remotedesktop.google.com/access (device: gnome, user: runner)"
step_done
