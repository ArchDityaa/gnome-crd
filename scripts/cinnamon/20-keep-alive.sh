#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Keep Alive
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_NC='\033[0m'

# Hitung sisa waktu dari batas job 360 menit, bukan sleep 21600 fix.
# Install + tunggu form web + verify memakan waktu, jadi sleep fix
# akan menabrak timeout job dan mematikan sesi lebih cepat dari 6 jam.
JOB_START="${JOB_START_EPOCH:-$(date +%s)}"
ELAPSED=$(( $(date +%s) - JOB_START ))
SLEEP_SECONDS=$(( 360 * 60 - ELAPSED - 60 ))
if [ "$SLEEP_SECONDS" -lt 60 ]; then
  SLEEP_SECONDS=60
fi

echo ""
echo "=============================================================="
echo -e "${C_GREEN}  [OK] CHROME REMOTE DESKTOP IS RUNNING${C_NC}"
echo "=============================================================="
echo -e "  ${C_YELLOW}[INFO] Keep-alive ${SLEEP_SECONDS}s (elapsed ${ELAPSED}s). Jangan cancel workflow.${C_NC}"
echo -e "  [INFO] Access : https://remotedesktop.google.com/access"
echo -e "  [INFO] User   : runner"
echo "=============================================================="

sleep "$SLEEP_SECONDS"
