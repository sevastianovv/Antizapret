#!/usr/bin/env bash
set -euo pipefail

BASE_RAW="https://raw.githubusercontent.com/sevastianovv/Antizapret/main"

echo "Что установить?"
echo "  1) AntiZapret-VPN (автоответы)"
echo "  2) AdminAntizapret panel (без вопроса y/n на установку)"
echo
read -rp "Выбор [1-2]: " CHOICE

case "${CHOICE:-}" in
  1) exec bash <(wget -qO- "${BASE_RAW}/antizapret_setup_autorun.sh") ;;
  2) exec bash <(wget -qO- "${BASE_RAW}/install_adminantizapret_noprompt.sh") ;;
  *) echo "Неверный выбор. Введи 1 или 2." >&2; exit 1 ;;
esac
