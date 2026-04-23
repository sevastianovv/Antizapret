#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/AdminAntizapret"
REPO_URL="https://github.com/Kirito0098/AdminAntizapret.git"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y git ca-certificates wget

# Clone or update repo
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git fetch --all --prune
  git checkout -f main 2>/dev/null || true
  git pull --ff-only 2>/dev/null || git pull
else
  if [[ -d "$INSTALL_DIR" ]]; then
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# Prefer upstream installer if present
if [[ -x "./install.sh" || -f "./install.sh" ]]; then
  chmod +x ./install.sh || true
  echo "[i] Running upstream installer: $INSTALL_DIR/install.sh"
  exec bash ./install.sh --install
fi

# Fallback to adminpanel entrypoint
ADMINPANEL_SH="$INSTALL_DIR/script_sh/adminpanel.sh"
if [[ ! -f "$ADMINPANEL_SH" ]]; then
  echo "Error: not found $ADMINPANEL_SH" >&2
  exit 1
fi
chmod +x "$ADMINPANEL_SH" || true

echo "[i] Running adminpanel installer entrypoint (may be interactive): $ADMINPANEL_SH"
exec bash "$ADMINPANEL_SH" --install
