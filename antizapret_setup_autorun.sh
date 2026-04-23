#!/usr/bin/env bash
set -euo pipefail

# Auto-run installer for GubernievS/AntiZapret-VPN with predefined answers.
# NOTE: the upstream setup.sh is intrusive (purges packages, edits sysctl, disables IPv6, etc.).

REPO_URL="https://github.com/GubernievS/AntiZapret-VPN"
WORKDIR="/root/antizapret-installer"
SETUP_SH="$WORKDIR/setup.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: run as root" >&2
  exit 1
fi

export LC_ALL=C

LOG="/root/antizapret-setup.log"
exec > >(tee -a "$LOG") 2>&1
echo "== AntiZapret autorun started at $(date -Is) =="
echo "Logging to: $LOG"

apt-get update -y

# setup.sh иногда собирает/патчит компоненты из исходников (OpenVPN и др.)
apt-get install -y \
  git ca-certificates wget curl lsb-release iproute2 \
  make gcc build-essential linux-headers-$(uname -r) \
  autoconf automake libtool pkg-config \
  libssl-dev liblzo2-dev liblz4-dev libcap-ng-dev \
  openvpn

rm -rf "$WORKDIR"
git clone --depth 1 "$REPO_URL" "$WORKDIR"

if [[ ! -f "$SETUP_SH" ]]; then
  echo "ERROR: setup.sh not found at $SETUP_SH" >&2
  exit 1
fi
chmod +x "$SETUP_SH"

# Predefined answers (as requested)
OPENVPN_PATCH=1
OPENVPN_DCO=y
ANTIZAPRET_WARP=n
VPN_WARP=n
ANTIZAPRET_DNS=1
VPN_DNS=1
BLOCK_ADS=n
ALTERNATIVE_CLIENT_IP=y
ALTERNATIVE_FAKE_IP=y
OPENVPN_BACKUP_TCP=y
OPENVPN_BACKUP_UDP=y
WIREGUARD_BACKUP=y
OPENVPN_DUPLICATE=y
OPENVPN_LOG=y
SSH_PROTECTION=y
ATTACK_PROTECTION=y
TORRENT_GUARD=y
RESTRICT_FORWARD=n
CLIENT_ISOLATION=n
OPENVPN_HOST=""
WIREGUARD_HOST=""
ROUTE_ALL=n

# IP pools (include)
DISCORD_INCLUDE=y
CLOUDFLARE_INCLUDE=y
TELEGRAM_INCLUDE=y
WHATSAPP_INCLUDE=y
ROBLOX_INCLUDE=y

export OPENVPN_PATCH OPENVPN_DCO ANTIZAPRET_WARP VPN_WARP \
  ANTIZAPRET_DNS VPN_DNS BLOCK_ADS ALTERNATIVE_CLIENT_IP ALTERNATIVE_FAKE_IP \
  OPENVPN_BACKUP_TCP OPENVPN_BACKUP_UDP WIREGUARD_BACKUP OPENVPN_DUPLICATE OPENVPN_LOG \
  SSH_PROTECTION ATTACK_PROTECTION TORRENT_GUARD RESTRICT_FORWARD CLIENT_ISOLATION \
  OPENVPN_HOST WIREGUARD_HOST ROUTE_ALL DISCORD_INCLUDE CLOUDFLARE_INCLUDE \
  TELEGRAM_INCLUDE WHATSAPP_INCLUDE ROBLOX_INCLUDE

# Upstream setup.sh checks whether variables match regex; if already set, prompts are skipped.
# Domain prompts are while-read loops; by pre-setting empty string, they will be skipped.

exec "$SETUP_SH"
