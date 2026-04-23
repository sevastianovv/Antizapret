#!/usr/bin/env bash
set -euo pipefail

BASE_RAW="https://raw.githubusercontent.com/sevastianovv/Antizapret/main"

run_remote() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | bash
  else
    wget -qO- "$url" | bash
  fi
}

echo "Что установить?"
echo "  1) AntiZapret-VPN (автоответы)"
echo "  2) AdminAntizapret panel (без вопроса y/n на установку)"
echo
echo "Подсказка: скрипты рассчитаны на запуск от root (sudo -i) на чистой VPS."
echo
read -rp "Выбор [1-2]: " CHOICE

case "${CHOICE:-}" in
  1) run_remote "${BASE_RAW}/antizapret_setup_autorun.sh" ;;
  2) run_remote "${BASE_RAW}/install_adminantizapret_noprompt.sh" ;;
  *) echo "Неверный выбор. Введи 1 или 2." >&2; exit 1 ;;
esac
