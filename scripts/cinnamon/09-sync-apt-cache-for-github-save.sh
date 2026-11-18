#!/usr/bin/env bash
# Extracted 1:1 from .github/workflows/cinnamon.yml -- step: Sync apt cache for GitHub save
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

sudo mkdir -p /home/runner/apt-archives
sudo cp -a /var/cache/apt/archives/. /home/runner/apt-archives/ || true
sudo chown -R runner:runner /home/runner/apt-archives || true
