#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Configure CRD PIN
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"
step "09/11" "Configure CRD PIN"

if [ -n "$CUSTOM_CRD_PIN" ]; then
  CRD_PIN="$CUSTOM_CRD_PIN"
  PIN_SOURCE="secret"
else
  CRD_PIN="123456"
  PIN_SOURCE="default"
fi

if ! [[ "$CRD_PIN" =~ ^[0-9]{6,}$ ]]; then
  fail "CRD_PIN harus berisi minimal 6 digit angka"
  exit 1
fi

echo "::add-mask::$CRD_PIN"
echo "CRD_PIN=$CRD_PIN" >> "$GITHUB_ENV"
echo "CRD_PIN_SOURCE=$PIN_SOURCE" >> "$GITHUB_ENV"

if [ "$PIN_SOURCE" = "secret" ]; then
  ok "PIN dikonfigurasi (secret CRD_PIN)"
else
  ok "PIN dikonfigurasi (default, belum ada secret CRD_PIN)"
fi
step_done
