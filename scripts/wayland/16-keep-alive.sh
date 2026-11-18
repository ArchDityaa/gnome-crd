#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Keep Alive
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"

RUNNER_UID=$(id -u runner)
as_runner() {
  sudo -u runner env \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
    "$@"
}

JOB_START="${JOB_START_EPOCH:-$(date +%s)}"
JOB_LIMIT=$(( 360 * 60 ))   # samakan dengan timeout-minutes
GRACE=60                    # ruang untuk cleanup job
INTERVAL=300                # pemeriksaan kesehatan tiap 5 menit
HEARTBEAT_EVERY=6           # heartbeat tiap 6 siklus (30 menit)
RESTART_MIN_GAP=120         # jeda minimum antar restart host
HOST_RESTARTS=0
SHELL_MISS=0
CYCLE=0
LAST_HOST_RESTART=0
LAST_SHELL_PID=""
LAST_EXTRA_PIDS=""
XVFB_REPORTED=0
CRASH_DIR="/run/user/$RUNNER_UID/crd_crashpad/completed"
LAST_CRASH_COUNT="$(find "$CRASH_DIR" -maxdepth 1 -name '*.dmp' 2>/dev/null | wc -l | tr -d ' ' || true)"

get_shell_pid() {
  as_runner systemctl --user show -p MainPID --value org.gnome.Shell@ubuntu.service 2>/dev/null || true
}

# Semua instans gnome-shell selain Main PID unit, plus jejak Xvfb.
# Xwayland sengaja tidak dihitung (normal untuk app X11 di Wayland).
collect_extra_processes() {
  EXTRA_PIDS=""
  EXTRA_COUNT=0
  for p in $(pgrep -x gnome-shell 2>/dev/null || true); do
    [ "$p" = "$1" ] && continue
    EXTRA_PIDS="$EXTRA_PIDS $p"
    EXTRA_COUNT=$(( EXTRA_COUNT + 1 ))
  done
  X_PROCS="$(pgrep -a -x 'Xvfb' 2>/dev/null || true)"
}

step "LIVE" "Session monitor"
ok "Chrome Remote Desktop berjalan (Wayland BETA)"
kv "Akses" "https://remotedesktop.google.com/access"
kv "Pengguna" "runner"
kv "Monitor" "cek tiap $(( INTERVAL / 60 )) menit · heartbeat tiap $(( INTERVAL * HEARTBEAT_EVERY / 60 )) menit"
warn "Jangan batalkan workflow selama sesi digunakan"

# Konfigurasi host CRD (nama file memakai hash: host#<hash>.json).
# Berguna bila versi CRD baru berhenti menghormati flag Wayland.
HOST_JSON="$(ls -1 /home/runner/.config/chrome-remote-desktop/host*.json 2>/dev/null | head -n 1 || true)"
echo "::group::Konfigurasi host CRD"
if [ -n "$HOST_JSON" ] && [ -f "$HOST_JSON" ]; then
  kv "Config" "$(basename "$HOST_JSON")"
  kv "Keys" "$(grep -oE '"[a-zA-Z_]+":' "$HOST_JSON" | tr -d '\":' | tr '\n' ' ' || true)"
  grep -oE '"[a-zA-Z_]*(wayland|experimental|x_session|display)[a-zA-Z_]*": ?[^,}]+' "$HOST_JSON" | sed 's/^/      /' || echo "      (tidak ada key wayland/experimental/x_session/display)"
  kv "Versi CRD" "$(dpkg-query -W -f='${Version}' chrome-remote-desktop 2>/dev/null || echo '?')"
else
  info "host*.json tidak ditemukan di /home/runner/.config/chrome-remote-desktop/"
fi
echo "::endgroup::"

while :; do
  NOW=$(date +%s)
  ELAPSED=$(( NOW - JOB_START ))
  REMAIN=$(( JOB_LIMIT - GRACE - ELAPSED ))
  INCIDENT=0

  if [ "$REMAIN" -le 0 ]; then
    info "Batas job tercapai (elapsed $(( ELAPSED / 60 )) menit) · monitor berakhir"
    break
  fi

  # ---- 1. Snapshot komponen sesi ----
  if systemctl is-active --quiet chrome-remote-desktop@runner 2>/dev/null; then
    HOST_STATE="active"
  else
    HOST_STATE="inactive"
  fi
  SHELL_STATE="$(as_runner systemctl --user is-active org.gnome.Shell@ubuntu.service 2>/dev/null || echo unknown)"
  SHELL_PID="$(get_shell_pid)"
  PORTAL_STATE="$(as_runner systemctl --user is-active xdg-desktop-portal-gnome.service 2>/dev/null || echo unknown)"

  # ---- 2. gnome-shell PID berubah (crash + respawn) ----
  if [ -n "$LAST_SHELL_PID" ] && [ -n "$SHELL_PID" ] && [ "$SHELL_PID" != "$LAST_SHELL_PID" ]; then
    INCIDENT=1
    echo "::warning::GNOME Shell restart di tengah sesi (PID ${LAST_SHELL_PID} -> ${SHELL_PID}); gejala layar hitam + kursor."
    warn "gnome-shell PID berubah: ${LAST_SHELL_PID} → ${SHELL_PID}"
    echo "::group::Insiden · journal org.gnome.Shell@ubuntu.service (60 baris terakhir)"
    as_runner journalctl --user -u org.gnome.Shell@ubuntu.service -n 60 --no-pager || true
    echo "::endgroup::"
    SHELL_MISS=0
  fi
  LAST_SHELL_PID="$SHELL_PID"

  # ---- 2b. Crash host CRD (dump baru di crashpad) ----
  # Host dapat crash walau service tetap "active"; client hanya
  # melihat layar hitam. Dump baru -> restart host (rate-limited).
  HOST_RESTARTED=""
  CRASH_COUNT="$(find "$CRASH_DIR" -maxdepth 1 -name '*.dmp' 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ "${CRASH_COUNT:-0}" -gt "${LAST_CRASH_COUNT:-0}" ]; then
    INCIDENT=1
    echo "::warning::Crash host CRD terdeteksi (dump ${LAST_CRASH_COUNT} -> ${CRASH_COUNT})."
    warn "Host CRD crash · client dapat melihat layar hitam"
    ls -lt "$CRASH_DIR" 2>/dev/null | head -n 5 || true
    echo "::group::Insiden · journal chrome-remote-desktop@runner (80 baris terakhir)"
    sudo journalctl -u chrome-remote-desktop@runner -n 80 --no-pager 2>/dev/null || true
    echo "::endgroup::"
    if [ $(( NOW - LAST_HOST_RESTART )) -ge "$RESTART_MIN_GAP" ]; then
      HOST_RESTARTS=$(( HOST_RESTARTS + 1 ))
      LAST_HOST_RESTART=$NOW
      info "Restart host CRD setelah crash (ke-${HOST_RESTARTS})"
      sudo systemctl restart chrome-remote-desktop@runner 2>/dev/null || \
        sudo systemctl start chrome-remote-desktop@runner 2>/dev/null || true
      sleep 5
      HOST_RESTARTED=1
    fi
  fi
  LAST_CRASH_COUNT="$CRASH_COUNT"

  if [ "$SHELL_STATE" != "active" ]; then
    INCIDENT=1
    SHELL_MISS=$(( SHELL_MISS + 1 ))
    warn "org.gnome.Shell@ubuntu.service tidak aktif (${SHELL_MISS}x berturut-turut) · capture akan hitam"
    if [ "$SHELL_MISS" -le 1 ]; then
      echo "::group::Insiden · status + journal gnome-shell"
      as_runner systemctl --user status org.gnome.Shell@ubuntu.service --no-pager || true
      as_runner journalctl --user -u org.gnome.Shell@ubuntu.service -n 60 --no-pager || true
      echo "::endgroup::"
    fi
  else
    SHELL_MISS=0
  fi

  # ---- 3. Auto-restart HANYA host CRD (bukan shell) ----
  if [ "$HOST_STATE" != "active" ]; then
    INCIDENT=1
    warn "chrome-remote-desktop@runner tidak aktif"
    if [ $(( NOW - LAST_HOST_RESTART )) -ge "$RESTART_MIN_GAP" ]; then
      HOST_RESTARTS=$(( HOST_RESTARTS + 1 ))
      LAST_HOST_RESTART=$NOW
      info "Restart chrome-remote-desktop@runner (ke-${HOST_RESTARTS})"
      sudo systemctl restart chrome-remote-desktop@runner 2>/dev/null || \
        sudo systemctl start chrome-remote-desktop@runner 2>/dev/null || true
      sleep 5
      HOST_RESTARTED=1
    else
      info "Restart terakhir baru saja terjadi · menunggu siklus berikutnya"
    fi
  fi

  # ---- 4. Status pasca (potensi) restart ----
  if systemctl is-active --quiet chrome-remote-desktop@runner 2>/dev/null; then
    HOST_NOW="active${HOST_RESTARTED:+ (baru di-restart)}"
  else
    HOST_NOW="inactive"
    INCIDENT=1
    warn "Host CRD masih tidak aktif · coba lagi pada siklus berikutnya"
  fi

  # ---- 4b. gnome-shell / X di LUAR unit systemd ----
  # Indikasi daemon CRD memulai sesi X sendiri (anak proses CRD);
  # parentage dibongkar agar sumbernya terlihat. Dilaporkan hanya
  # saat daftar PID berubah.
  collect_extra_processes "$SHELL_PID"
  if [ "$EXTRA_COUNT" -gt 0 ]; then
    if [ "$EXTRA_PIDS " != "$LAST_EXTRA_PIDS " ]; then
      INCIDENT=1
      warn "gnome-shell ${EXTRA_COUNT}x di luar unit systemd (unit=$SHELL_PID):${EXTRA_PIDS:-}"
      echo "::group::Insiden · gnome-shell ekstra (parentage + args)"
      for p in $EXTRA_PIDS; do
        PPID_X="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ' || true)"
        echo "  shell PID ${p} (parent ${PPID_X:-?}):"
        ps -o pid,ppid,comm,args -p "$p" --no-headers 2>/dev/null | sed 's/^/      /'
        if [ -n "$PPID_X" ] && [ "$PPID_X" != "1" ]; then
          echo "    parent ${PPID_X}:"
          ps -o pid,ppid,comm,args -p "$PPID_X" --no-headers 2>/dev/null | sed 's/^/        /'
        fi
      done
      echo "::endgroup::"
      LAST_EXTRA_PIDS="$EXTRA_PIDS"
    fi
  else
    LAST_EXTRA_PIDS=""
  fi
  if [ -n "$X_PROCS" ] && [ "$XVFB_REPORTED" -eq 0 ]; then
    INCIDENT=1
    XVFB_REPORTED=1
    warn "Xvfb aktif (sesi X legacy, bukan Wayland headless):"
    printf '%s\n' "$X_PROCS" | sed 's/^/      /'
  fi

  # ---- 5. Journal error ringkas ----
  JOURNAL_ERRORS="$(as_runner journalctl --user -u org.gnome.Shell@ubuntu.service -n 200 --no-pager --since "-$(( INTERVAL / 60 ))min" 2>/dev/null | grep -iE "error|segfault|crash|abort|screencast" | tail -n 5 || true)"
  if [ -n "$JOURNAL_ERRORS" ]; then
    INCIDENT=1
    warn "Journal shell ($(( INTERVAL / 60 )) menit terakhir):"
    printf '%s\n' "$JOURNAL_ERRORS" | sed 's/^/      /'
  fi

  # ---- 5b. Journal host CRD (system journal) ----
  CRD_JOURNAL="$(sudo journalctl -u chrome-remote-desktop@runner -n 60 --no-pager --since "-$(( INTERVAL / 60 ))min" 2>/dev/null | grep -iE 'session|wayland|display|x11|xvfb|fail|error' | tail -n 8 || true)"
  if [ -n "$CRD_JOURNAL" ]; then
    INCIDENT=1
    warn "Journal host CRD ($(( INTERVAL / 60 )) menit terakhir):"
    printf '%s\n' "$CRD_JOURNAL" | sed 's/^/      /'
  fi

  # ---- 6. Heartbeat: tiap 30 menit, atau segera saat ada insiden ----
  if [ "$INCIDENT" -eq 1 ] || [ $(( CYCLE % HEARTBEAT_EVERY )) -eq 0 ]; then
    printf '  %s%s%s  up %sm · sisa ~%sm · host %s · shell %s (pid %s) · portal %s · extra-shell %sx · restart %sx\n' \
      "$C_D" "$(date +%H:%M)" "$C_N" \
      "$(( ELAPSED / 60 ))" "$(( REMAIN / 60 ))" "$HOST_NOW" \
      "$SHELL_STATE" "${SHELL_PID:-?}" "$PORTAL_STATE" "$EXTRA_COUNT" "$HOST_RESTARTS"
  fi
  CYCLE=$(( CYCLE + 1 ))

  # ---- 7. Tidur satu interval (tidak melebihi sisa waktu) ----
  SLEEP_NOW="$INTERVAL"
  if [ "$SLEEP_NOW" -gt "$REMAIN" ]; then
    SLEEP_NOW="$REMAIN"
  fi
  sleep "$SLEEP_NOW"
done

echo ""
ok "Sesi CRD dijaga sampai akhir batas job"
kv "Restart host" "${HOST_RESTARTS}x"
kv "Akses" "https://remotedesktop.google.com/access (user: runner)"
