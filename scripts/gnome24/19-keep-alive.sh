#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Keep Alive
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

JOB_START="${JOB_START_EPOCH:-$(date +%s)}"
JOB_LIMIT=$(( 360 * 60 ))   # samakan dengan timeout-minutes: 360
GRACE=60                    # ruang untuk cleanup job
INTERVAL=300                # heartbeat + health check tiap 5 menit
RESTART_MIN_GAP=120         # anti- tighten: min jeda antar restart
RESTARTS=0                  # jumlah restart daemon CRD
SHELL_MISS=0                # cek gnome-shell hilang berturut-turut
LAST_RESTART=0              # epoch restart terakhir

echo ""
echo "=============================================================="
echo -e "${C_GREEN}  [OK] CHROME REMOTE DESKTOP IS RUNNING${C_NC}"
echo "=============================================================="
echo -e "  ${C_YELLOW}[INFO] Keep-alive: monitor tiap ${INTERVAL}s sampai batas job 360 menit. Jangan cancel workflow.${C_NC}"
echo -e "  [INFO] Access : https://remotedesktop.google.com/access"
echo -e "  [INFO] User   : runner"
echo "=============================================================="

while :; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - JOB_START ))
  REMAIN=$(( JOB_LIMIT - GRACE - ELAPSED ))

  if [ "$REMAIN" -le 0 ]; then
    echo -e "  [INFO] Batas job tercapai (elapsed $((ELAPSED / 60)) menit). Keep-alive berakhir."
    break
  fi

  # ---- Tentukan apakah daemon/sesi perlu di-restart ----
  NEED_RESTART=0
  REASON=""
  if ! systemctl is-active --quiet chrome-remote-desktop@runner 2>/dev/null; then
    NEED_RESTART=1
    REASON="chrome-remote-desktop@runner tidak aktif"
    SHELL_MISS=0
  elif ! pgrep -u runner -x gnome-shell > /dev/null 2>&1; then
    # Service "aktif" tapi tidak ada proses gnome-shell = sesi
    # desktop user runner mati (crash Mutter/X). Beri 2 cek
    # berturut-turut supaya respawn alami service tidak terburu-buru
    # di-restart paksa.
    SHELL_MISS=$(( SHELL_MISS + 1 ))
    if [ "$SHELL_MISS" -ge 2 ]; then
      NEED_RESTART=1
      REASON="gnome-shell (user runner) tidak terlihat $SHELL_MISS cek berturut-turut"
    fi
  else
    SHELL_MISS=0
  fi

  if [ "$NEED_RESTART" -eq 1 ]; then
    echo -e "  ${C_YELLOW}[WARN] $REASON.${C_NC}"
    if [ $(( NOW - LAST_RESTART )) -ge "$RESTART_MIN_GAP" ]; then
      RESTARTS=$(( RESTARTS + 1 ))
      LAST_RESTART=$NOW
      echo -e "  ${C_YELLOW}[INFO] Restart chrome-remote-desktop@runner (ke-${RESTARTS})...${C_NC}"
      sudo systemctl restart chrome-remote-desktop@runner 2>/dev/null || \
        sudo systemctl start chrome-remote-desktop@runner 2>/dev/null || true
      sleep 5
    else
      echo -e "  ${C_YELLOW}[INFO] Restart terbaru baru saja terjadi; tunggu siklus berikutnya.${C_NC}"
    fi
  fi

  # ---- Konfirmasi status setelah (potensi) restart ----
  if systemctl is-active --quiet chrome-remote-desktop@runner 2>/dev/null; then
    echo -e "  ${C_GREEN}[OK] chrome-remote-desktop@runner aktif.${C_NC}"
  else
    echo -e "  ${C_YELLOW}[WARN] chrome-remote-desktop@runner masih tidak aktif; akan dicoba lagi siklus berikutnya.${C_NC}"
  fi

  # ---- Heartbeat ----
  echo -e "  ${C_CYAN}[HEARTBEAT] up $(( ELAPSED / 60 ))m | sisa ~$(( REMAIN / 60 ))m | restart CRD: ${RESTARTS}x${C_NC}"

  # ---- Tidur satu interval (tidak melebihi sisa waktu) ----
  SLEEP_NOW="$INTERVAL"
  if [ "$SLEEP_NOW" -gt "$REMAIN" ]; then
    SLEEP_NOW="$REMAIN"
  fi
  sleep "$SLEEP_NOW"
done

echo ""
echo "=============================================================="
echo -e "  ${C_GREEN}[INFO] Sesi CRD dijaga sampai akhir batas job.${C_NC}"
echo -e "  [INFO] Total restart daemon CRD : ${RESTARTS}x"
echo -e "  [INFO] Connect  : https://remotedesktop.google.com/access (user: runner)"
echo "=============================================================="
