#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Publish job summary
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC2155
# Versi komponen boleh kosong; kegagalan query sudah ditangani `|| true`.
# shellcheck disable=SC2155
export GNOME_V="$(gnome-shell --version 2>/dev/null || true)"
# shellcheck disable=SC2155
export CHROME_V="$(google-chrome --version 2>/dev/null || true)"
# shellcheck disable=SC2155
export CODE_V="$(code --version 2>/dev/null | head -n 1 || true)"
# shellcheck disable=SC2155
export OC_V="$(opencode --version 2>/dev/null || true)"
# shellcheck disable=SC2155
export CRD_V="$(dpkg-query -W -f='${Version}' chrome-remote-desktop 2>/dev/null || true)"
python3 "$SCRIPT_DIR/publish-summary.py"
