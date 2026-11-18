#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Capture desktop proof (diagnostik)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "DIAG" "Capture desktop proof"

RUNNER_UID=$(id -u runner)
OUT_DIR="${GITHUB_WORKSPACE:-/tmp}"
WEBM="$OUT_DIR/desktop-proof.webm"
PNG="$OUT_DIR/desktop-proof.png"
rm -f "$WEBM" "$PNG"
PROOF_OK=1

as_runner() {
  sudo -u runner env \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
    "$@"
}

PWLOG="$CI_LOG_DIR/proof-pipewire.log"
{
  as_runner env PIPEWIRE_REMOTE=crd_audio/pipewire pw-link -l || true
  as_runner env PIPEWIRE_REMOTE=crd_audio/pipewire pw-dump > /tmp/pw-dump.json 2>/dev/null || true
  python3 "$SCRIPT_DIR/proof-pipewire.py" /tmp/pw-dump.json || true
} > "$PWLOG" 2>&1 || true

if as_runner gdbus call --session \
     --dest org.gnome.Shell.Screencast \
     --object-path /org/gnome/Shell/Screencast \
     --method org.gnome.Shell.Screencast.Screencast \
     "$WEBM" "{}" > /tmp/screencast.out 2>&1; then
  sleep 4
  as_runner gdbus call --session \
    --dest org.gnome.Shell.Screencast \
    --object-path /org/gnome/Shell/Screencast \
    --method org.gnome.Shell.Screencast.StopScreencast > /dev/null 2>&1 || true
  ok "Rekaman 4 detik dibuat ($(stat -c%s "$WEBM" 2>/dev/null || echo 0) byte)"
else
  echo "::warning::Screencast D-Bus gagal: $(tail -n1 /tmp/screencast.out 2>/dev/null)"
  PROOF_OK=0
fi

if [ -s "$WEBM" ]; then
  gst-launch-1.0 -q filesrc location="$WEBM" ! decodebin ! videoconvert ! pngenc ! filesink location="$PNG" > /tmp/gst.out 2>&1 || true
fi


if [ -f "$PNG" ]; then
  BR_RC=0
  BRIGHT="$(python3 "$SCRIPT_DIR/brightness.py" "$PNG" 2>&1)" || BR_RC=$?
  if [ "$BR_RC" -eq 3 ]; then
    warn "Frame hampir hitam: $BRIGHT"
    echo "::warning::Frame hampir hitam - compositor tidak merender atau pemandangan memang gelap."
    PROOF_OK=0
  else
    ok "Frame desktop: $BRIGHT"
  fi
else
  echo "::warning::Tidak ada frame yang berhasil diekstrak (compositor/PipeWire bermasalah)."
  PROOF_OK=0
fi

CRASH_DIR="/run/user/$RUNNER_UID/crd_crashpad/completed"
if find "$CRASH_DIR" -maxdepth 1 -name '*.dmp' 2>/dev/null | grep -q .; then
  mkdir -p "$OUT_DIR/crash-dumps"
  find "$CRASH_DIR" -maxdepth 1 -name '*.dmp' -exec cp {} "$OUT_DIR/crash-dumps/" \; 2>/dev/null || true
  warn "Crash dump disalin: $(find "$OUT_DIR/crash-dumps" -name '*.dmp' | wc -l || true) file"
  PROOF_OK=0
fi

JLOG="$CI_LOG_DIR/proof-shell-journal.log"
as_runner journalctl --user -u org.gnome.Shell@ubuntu.service -n 200 --no-pager 2>/dev/null \
  | grep -iE "pipewire|screencast|error|crash" | tail -n 15 > "$JLOG" || true

# Detail hanya dicetak bila ada anomali.
if [ "$PROOF_OK" -ne 1 ]; then
  echo "::group::PipeWire graph (gnome-shell vs host CRD)"
  cat "$PWLOG" || true
  echo "::endgroup::"
  echo "::group::Journal shell (error / screencast / pipewire)"
  cat "$JLOG" || true
  echo "::endgroup::"
fi
step_done
