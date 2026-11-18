#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome24.yml -- step: Configure CRD PIN
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

C_CYAN='\033[1;36m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_NC='\033[0m'

echo ""
echo "------------------------------------------------------------"
echo -e "${C_CYAN}[STEP 16/19] CONFIGURE CRD PIN${C_NC}"
echo "------------------------------------------------------------"

if [ -n "$CUSTOM_CRD_PIN" ]; then
  CRD_PIN="$CUSTOM_CRD_PIN"
  echo -e "${C_YELLOW}[INFO] Using custom CRD PIN from secret CRD_PIN.${C_NC}"
else
  CRD_PIN="123456"
  echo -e "${C_YELLOW}[INFO] No CRD_PIN secret found.${C_NC}"
  echo -e "${C_YELLOW}[INFO] Using default PIN: 123456${C_NC}"
fi

# Validate PIN
if ! [[ "$CRD_PIN" =~ ^[0-9]{6,}$ ]]; then
  echo -e "${C_RED}[FAIL] CRD_PIN must contain at least 6 digits.${C_NC}"
  exit 1
fi

echo "::add-mask::$CRD_PIN"

echo "CRD_PIN=$CRD_PIN" >> "$GITHUB_ENV"

echo -e "${C_GREEN}[OK] CRD PIN configured.${C_NC}"
