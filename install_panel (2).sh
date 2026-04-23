#!/usr/bin/env bash
set -euo pipefail

URL="https://raw.githubusercontent.com/sevastianovv/Antizapret/main/install_adminantizapret_noprompt.sh"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" | bash
else
  wget -qO- "$URL" | bash
fi
