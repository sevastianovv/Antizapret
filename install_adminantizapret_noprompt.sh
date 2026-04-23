#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/AdminAntizapret"
REPO_URL="https://github.com/Kirito0098/AdminAntizapret.git"
ADMINPANEL_SH="$INSTALL_DIR/script_sh/adminpanel.sh"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y git ca-certificates wget python3

# Clone or update repo
if [[ -d "$INSTALL_DIR/.git" ]]; then
  cd "$INSTALL_DIR"
  git fetch --all --prune
  git checkout -f main || true
  git pull --ff-only || git pull
else
  if [[ -d "$INSTALL_DIR" ]]; then
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
  fi
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

if [[ ! -f "$ADMINPANEL_SH" ]]; then
  echo "Error: not found $ADMINPANEL_SH" >&2
  exit 1
fi

# Backup original
cp -a "$ADMINPANEL_SH" "$ADMINPANEL_SH.bak.$(date +%Y%m%d-%H%M%S)"

# Patch: remove "Хотите установить? (y/n)" prompt and always install when service is missing
python3 - <<'PY'
from pathlib import Path
import re

path = Path("/opt/AdminAntizapret/script_sh/adminpanel.sh")
s = path.read_text(encoding="utf-8", errors="ignore")

# If already patched, skip.
if "Запускаю установку без запроса" in s:
    print("adminpanel.sh already patched — skipping")
    raise SystemExit(0)

pattern = re.compile(
    r"""(?s)
\t\*\)
\t\tif \[ ! -f \"/etc/systemd/system/\$SERVICE_NAME\.service\" \]; then
\t\t\tprintf \"%s\\n\" \"\$\{YELLOW\}AdminAntizapret не установлен\.\$\{NC\}\"
\t\t\twhile true; do
\t\t\t\tprintf \"Хотите установить\? \(y/n\) \"
\t\t\t\tread -r answer
\t\t\t\tanswer=\$\(echo \"\$answer\" \| tr -d '\\[:space:\\]' \| tr '\\[:upper:\\]' '\\[:lower:\\]'\)
\t\t\t\tcase \$answer in
\t\t\t\t\[Yy\]\*\)
\t\t\t\t\tinstall
\t\t\t\t\tmain_menu
\t\t\t\t\tbreak
\t\t\t\t\t;;
\t\t\t\t\[Nn\]\*\)
\t\t\t\t\texit 0
\t\t\t\t\t;;
\t\t\t\t\*\)
\t\t\t\t\tprintf \"%s\\n\" \"\$\{RED\}Пожалуйста, введите только 'y' или 'n'\$\{NC\}\"
\t\t\t\t\t;;
\t\t\t\tesac
\t\t\tdone
\t\telse
\t\t\tmain_menu
\t\tfi
\t\t;;
""",
)

replacement = """\t*)
\t\tif [ ! -f \"/etc/systemd/system/$SERVICE_NAME.service\" ]; then
\t\t\tprintf \"%s\\n\" \"${YELLOW}AdminAntizapret не установлен. Запускаю установку без запроса...${NC}\"
\t\t\tinstall
\t\t\tmain_menu
\t\telse
\t\t\tmain_menu
\t\tfi
\t\t;;
"""

ns, n = pattern.subn(replacement, s)
if n != 1:
    raise SystemExit(f"Patch failed: expected 1 match, got {n}")

path.write_text(ns, encoding="utf-8")
print("Patched adminpanel.sh OK")
PY

chmod +x "$ADMINPANEL_SH"

# Run install
bash "$ADMINPANEL_SH" --install
