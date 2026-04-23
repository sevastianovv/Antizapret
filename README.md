───

Установка

Репозиторий содержит 3 установщика: меню, VPN и AdminAntizapret panel.

1) Меню (выбор 1/2)

bash <(wget -qO- https://raw.githubusercontent.com/sevastianovv/Antizapret/main/install.sh)

2) Установка AntiZapret-VPN (автоответы)

bash <(wget -qO- https://raw.githubusercontent.com/sevastianovv/Antizapret/main/install_vpn.sh)

3) Установка AdminAntizapret panel (без вопроса “y/n”)

bash <(wget -qO- https://raw.githubusercontent.com/sevastianovv/Antizapret/main/install_panel.sh)

Альтернатива через curl

Если на сервере нет wget:

bash <(curl -fsSL https://raw.githubusercontent.com/sevastianovv/Antizapret/main/install.sh)

───

Важно

• Скрипт установки VPN агрессивно меняет систему (удаляет некоторые пакеты, правит sysctl, отключает IPv6 и т.п.). Рекомендуется запускать на чистом VPS или после снапшота.
