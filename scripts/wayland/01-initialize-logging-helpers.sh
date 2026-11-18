#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/gnome26-wayland-beta.yml -- step: Initialize logging helpers
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

rm -rf /tmp/ci-logs /tmp/ci-steps.tsv /tmp/dl
mkdir -p /tmp/ci-logs /tmp/dl
# shellcheck source=lib/logging.sh
source "$SCRIPT_DIR/lib/logging.sh"

rm -rf "$CI_LOG_DIR" "$CI_STEPS" /tmp/dl
mkdir -p "$CI_LOG_DIR" /tmp/dl
