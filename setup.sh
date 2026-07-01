#!/bin/bash
#
# РЎРєСЂРёРїС‚ РґР»СЏ СѓСЃС‚Р°РЅРѕРІРєРё РЅР° СЃРІРѕС‘Рј СЃРµСЂРІРµСЂРµ AntiZapret VPN + РїРѕР»РЅС‹Р№ VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#

export LC_ALL=C

# РџСЂРѕРІРµСЂРєР° РЅРµРѕР±С…РѕРґРёРјРѕСЃС‚Рё РїРµСЂРµР·Р°РіСЂСѓР·РёС‚СЊ
if [[ -f /var/run/reboot-required ]] || pidof apt apt-get dpkg unattended-upgrades &>/dev/null; then
	echo 'Error: You need to reboot this server before installation!'
	exit 2
fi

# РџСЂРѕРІРµСЂРєР° РїСЂР°РІ root
if [[ "$EUID" -ne 0 ]]; then
	echo 'Error: You need to run this as root!'
	exit 3
fi

cd /root

# РџСЂРѕРІРµСЂРєР° РЅР° OpenVZ Рё LXC
if [[ "$(systemd-detect-virt)" == 'openvz' || "$(systemd-detect-virt)" == 'lxc' ]]; then
	echo 'Error: OpenVZ and LXC are not supported!'
	exit 4
fi

# РџСЂРѕРІРµСЂРєР° РІРµСЂСЃРёРё СЃРёСЃС‚РµРјС‹
OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -rs | cut -d '.' -f1)"
CODENAME="$(lsb_release -cs)"
ARCH="$(dpkg --print-architecture)"

if [[ "$OS" == 'debian' ]]; then
	if (( VERSION < 13 )); then
		echo "Error: Debian $VERSION is not supported! Minimal supported version is 13"
		exit 5
	fi
elif [[ "$OS" == 'ubuntu' ]]; then
	if (( VERSION < 24 )); then
		echo "Error: Ubuntu $VERSION is not supported! Minimal supported version is 24"
		exit 6
	fi
else
	echo "Error: Your Linux distribution ($OS) is not supported!"
	exit 7
fi

# РћС‡РёСЃС‚РєР° РґРёСЃРєР°
journalctl --vacuum-size=1B -q
find /var/log -name "*.gz" -delete
find /var/log -name "*.1" -delete
find /var/log -type f -exec truncate -s 0 {} +
dpkg --configure -a
apt-get install -f
apt-get clean
apt-get autoremove --purge -y >/dev/null

# РџСЂРѕРІРµСЂРєР° СЃРІРѕР±РѕРґРЅРѕРіРѕ РјРµСЃС‚Р° (РјРёРЅРёРјСѓРј 2Р“Р±)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo 'Error: Low disk space! You need 2GB of free space!'
	exit 8
fi

# РџСЂРѕРІРµСЂРєР° РЅР°Р»РёС‡РёСЏ СЃРµС‚РµРІРѕРіРѕ РёРЅС‚РµСЂС„РµР№СЃР° Рё IPv4-Р°РґСЂРµСЃР°
DEFAULT_INTERFACE="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'dev \K\S+')"
if [[ -z "$DEFAULT_INTERFACE" ]]; then
	echo 'Default network interface not found!'
	exit 9
fi

DEFAULT_IP="$(ip route get 1.2.3.4 2>/dev/null | grep -oP 'src \K\S+')"
if [[ -z "$DEFAULT_IP" ]]; then
	echo 'Default IPv4 address not found!'
	exit 10
fi

echo
echo -e '\e[1;32mInstalling AntiZapret VPN + full VPN...\e[0m'
echo 'OpenVPN + WireGuard + AmneziaWG'
echo 'More details: https://github.com/GubernievS/AntiZapret-VPN'
echo

PHYSICAL_MTU=$(< /sys/class/net/$DEFAULT_INTERFACE/mtu)
MTU=1420
if (( PHYSICAL_MTU < 1500 )); then
	echo "Warning! Low MTU on $DEFAULT_INTERFACE: $PHYSICAL_MTU"
	SUGGESTED_MTU=$((PHYSICAL_MTU - 80))
	echo "Suggested MTU for VPN is $SUGGESTED_MTU (default is 1420)."
	echo
	until [[ "$CHANGE_MTU" =~ (y|n) ]]; do
		read -rp "Change MTU in OpenVPN and WireGuard configs to $SUGGESTED_MTU? [y/n]: " -e -i y CHANGE_MTU
	done
	echo
	if [[ "$CHANGE_MTU" == 'y' ]]; then
		MTU=$SUGGESTED_MTU
	fi
fi

# РЎРїСЂР°С€РёРІР°РµРј Рѕ РЅР°СЃС‚СЂРѕР№РєР°С…
until [[ "$OPENVPN_UDP_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN UDP? [y/n]: ' -e -i y OPENVPN_UDP_ENABLE
done
echo
until [[ "$OPENVPN_TCP_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable OpenVPN TCP? [y/n]: ' -e -i n OPENVPN_TCP_ENABLE
done
echo
until [[ "$WIREGUARD_ENABLE" =~ (y|n) ]]; do
	read -rp 'Enable WireGuard/AmneziaWG? [y/n]: ' -e -i y WIREGUARD_ENABLE
done
echo
echo 'Choose anti-censorship patch for OpenVPN (UDP only):'
echo '    0) None        - Do not install anti-censorship patch, or remove if already installed'
echo '    1) Strong      - Recommended by default'
echo '    2) Error-free  - Use if Strong patch causes connection error, recommended for Mikrotik routers'
until [[ "$OPENVPN_PATCH" =~ ^[0-2]$ ]]; do
	read -rp 'Version choice [0-2]: ' -e -i 1 OPENVPN_PATCH
done
echo
echo 'OpenVPN DCO lowers CPU load, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption'
until [[ "$OPENVPN_DCO" =~ (y|n) ]]; do
	read -rp 'Turn on OpenVPN DCO? [y/n]: ' -e -i y OPENVPN_DCO
done
echo
until [[ "$ANTIZAPRET_WARP" =~ (y|n) ]]; do
	read -rp $'Use Cloudflare WARP for \001\e[1;32m\002AntiZapret VPN\e[0m\002 (antizapret-*) outbound traffic? [y/n]: ' -e -i n ANTIZAPRET_WARP
done
echo
until [[ "$VPN_WARP" =~ (y|n) ]]; do
	read -rp $'Use Cloudflare WARP for \001\e[1;32m\002full VPN\e[0m\002 (vpn-*) outbound traffic? [y/n]: ' -e -i n VPN_WARP
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mAntiZapret VPN\e[0m (antizapret-*):'
echo '    1) Cloudflare+Quad9  - Recommended by default'
echo '        +MSK-IX+NSDI *'
echo '    2) Cloudflare+Quad9  - Use if default choice fails to resolve domains'
echo '        +SkyDNS *          Need register account (Family plan) & add this server IP at https://skydns.ru'
echo '    3) Cloudflare+Quad9  - Use if previous choice fails to resolve domains'
echo '    4) Comss **          - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    5) XBox **           - More details: https://xbox-dns.ru'
echo '    6) Malw **           - More details: https://info.dns.malw.link'
echo
echo '  * - DNS resolvers optimized for users located in Russia'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$ANTIZAPRET_DNS" =~ ^[1-6]$ ]]; do
	read -rp 'DNS choice [1-6]: ' -e -i 1 ANTIZAPRET_DNS
done
echo
echo -e 'Choose DNS resolvers for \e[1;32mfull VPN\e[0m (vpn-*):'
echo '    1) Self-hosted  - Use previous choice for AntiZapret VPN, recommended by default'
echo '    2) Cloudflare   - Use if default choice fails to resolve domains'
echo '    3) Quad9        - Use if previous choice fails to resolve domains'
echo '    4) Google *     - Use if previous choice fails to resolve domains'
echo '    5) AdGuard *    - Use for blocking ads, trackers, malware and phishing websites'
echo '    6) Comss **     - More details: https://comss.ru/disqus/page.php?id=7315'
echo '    7) XBox **      - More details: https://xbox-dns.ru'
echo '    8) Malw **      - More details: https://info.dns.malw.link'
echo
echo '  * - DNS resolvers support EDNS Client Subnet'
echo ' ** - Enable additional proxying and hide this server IP on some internet resources'
echo '      Use only if this server is geolocated in Russia or problems accessing some internet resources'
until [[ "$VPN_DNS" =~ ^[1-8]$ ]]; do
	read -rp 'DNS choice [1-8]: ' -e -i 1 VPN_DNS
done
echo
until [[ "$BLOCK_ADS" =~ (y|n) ]]; do
	read -rp $'Enable blocking ads, trackers, malware and phishing websites in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 (antizapret-*) based on AdGuard and OISD rules? [y/n]: ' -e -i y BLOCK_ADS
done
echo
echo 'Default CLIENT IP address range:     10.28.0.0/15'
echo 'Alternative CLIENT IP address range: 172.28.0.0/15'
until [[ "$ALTERNATIVE_CLIENT_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative CLIENT IP address range? [y/n]: ' -e -i n ALTERNATIVE_CLIENT_IP
done
echo
[[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]] && IP=172 || IP=10
echo "Default FAKE IP address range:     $IP.30.0.0/15"
echo 'Alternative FAKE IP address range: 198.18.0.0/15'
until [[ "$ALTERNATIVE_FAKE_IP" =~ (y|n) ]]; do
	read -rp 'Use alternative range of FAKE IP addresses? [y/n]: ' -e -i y ALTERNATIVE_FAKE_IP
done
echo
until [[ "$OPENVPN_BACKUP_TCP" =~ (y|n) ]]; do
	read -rp 'Use TCP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i n OPENVPN_BACKUP_TCP
done
echo
until [[ "$OPENVPN_BACKUP_UDP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 80, 443, 504, 508 as backup for OpenVPN connections? [y/n]: ' -e -i y OPENVPN_BACKUP_UDP
done
echo
until [[ "$WIREGUARD_BACKUP" =~ (y|n) ]]; do
	read -rp 'Use UDP ports 540, 580 as backup for WireGuard/AmneziaWG connections? [y/n]: ' -e -i y WIREGUARD_BACKUP
done
echo
until [[ "$OPENVPN_DUPLICATE" =~ (y|n) ]]; do
	read -rp 'Allow multiple clients connecting to OpenVPN using same profile file (*.ovpn)? [y/n]: ' -e -i y OPENVPN_DUPLICATE
done
echo
until [[ "$OPENVPN_LOG" =~ (y|n) ]]; do
	read -rp 'Enable detailed logs in OpenVPN? [y/n]: ' -e -i n OPENVPN_LOG
done
echo
echo 'Warning! SSH protection may block your IP after 5 logins/minute!'
until [[ "$SSH_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable SSH brute-force protection? [y/n]: ' -e -i y SSH_PROTECTION
done
echo
echo 'Warning! Attack protection may block VPN or third-party applications!'
until [[ "$ATTACK_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network attack protection? [y/n]: ' -e -i y ATTACK_PROTECTION
done
echo
echo 'Warning! Scan protection blocks ping and closed-port replies!'
until [[ "$SCAN_PROTECTION" =~ (y|n) ]]; do
	read -rp 'Enable network scan protection? [y/n]: ' -e -i y SCAN_PROTECTION
done
echo
echo 'Warning! Torrent guard blocks VPN traffic for 1 minute on torrent detection!'
until [[ "$TORRENT_GUARD" =~ (y|n) ]]; do
	read -rp $'Enable torrent guard for \001\e[1;32m\002full VPN\001\e[0m\002? [y/n]: ' -e -i y TORRENT_GUARD
done
echo
until [[ "$RESTRICT_FORWARD" =~ (y|n) ]]; do
	read -rp $'Restrict forwarding in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002 to IPs from config/forward-ips.txt and result/route-ips.txt? [y/n]: ' -e -i y RESTRICT_FORWARD
done
echo
until [[ "$CLIENT_ISOLATION" =~ (y|n) ]]; do
	read -rp $'Enable \001\e[1;32m\002all VPN\001\e[0m\002 client and server isolation? [y/n]: ' -e -i y CLIENT_ISOLATION
done
echo
while read -rp 'Enter valid domain name for this OpenVPN server or press Enter to skip: ' -e OPENVPN_HOST
do
	[[ -z "$OPENVPN_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$OPENVPN_HOST") ]] && break
done
echo
while read -rp 'Enter valid domain name for this WireGuard/AmneziaWG server or press Enter to skip: ' -e WIREGUARD_HOST
do
	[[ -z "$WIREGUARD_HOST" ]] && break
	[[ -n $(getent ahostsv4 "$WIREGUARD_HOST") ]] && break
done
echo
until [[ "$ROUTE_ALL" =~ (y|n) ]]; do
	read -rp $'Route all traffic for domains via \001\e[1;32m\002AntiZapret VPN\001\e[0m\002, excluding Russian domains and domains from config/exclude-hosts.txt? [y/n]: ' -e -i n ROUTE_ALL
done
echo
until [[ "$DISCORD_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Obsolete! Include Discord voice IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DISCORD_INCLUDE
done
echo
until [[ "$CLOUDFLARE_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Cloudflare IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y CLOUDFLARE_INCLUDE
done
echo
until [[ "$TELEGRAM_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Telegram IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y TELEGRAM_INCLUDE
done
echo
until [[ "$WHATSAPP_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include WhatsApp IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i y WHATSAPP_INCLUDE
done
echo
until [[ "$ROBLOX_INCLUDE" =~ (y|n) ]]; do
	read -rp $'Include Roblox IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n ROBLOX_INCLUDE
done
echo
#until [[ "$AMAZON_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Amazon IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AMAZON_INCLUDE
#done
#echo
#until [[ "$HETZNER_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Hetzner IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n HETZNER_INCLUDE
#done
#echo
#until [[ "$DIGITALOCEAN_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include DigitalOcean IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n DIGITALOCEAN_INCLUDE
#done
#echo
#until [[ "$OVH_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include OVH IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n OVH_INCLUDE
#done
#echo
#until [[ "$GOOGLE_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Google IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n GOOGLE_INCLUDE
#done
#echo
#until [[ "$AKAMAI_INCLUDE" =~ (y|n) ]]; do
#	read -rp $'Include Akamai IPs in \001\e[1;32m\002AntiZapret VPN\001\e[0m\002? [y/n]: ' -e -i n AKAMAI_INCLUDE
#done
#echo
echo 'Installation, please wait...'

# РћС‚РєР»СЋС‡РёРј С„РѕРЅРѕРІС‹Рµ РѕР±РЅРѕРІР»РµРЅРёСЏ СЃРёСЃС‚РµРјС‹
systemctl stop unattended-upgrades
systemctl stop apt-daily.timer
systemctl stop apt-daily-upgrade.timer

# РћСЃС‚Р°РЅРѕРІРёРј Рё РІС‹РєР»СЋС‡РёРј РѕР±РЅРѕРІР»СЏРµРјС‹Рµ СЃР»СѓР¶Р±С‹
systemctl disable --now kresd@1
systemctl disable --now kresd@2
systemctl disable --now antizapret
systemctl disable --now antizapret-update.timer
systemctl disable --now antizapret-update
systemctl disable --now openvpn-server@antizapret-udp
systemctl disable --now openvpn-server@vpn-udp
systemctl disable --now openvpn-server@antizapret-tcp
systemctl disable --now openvpn-server@vpn-tcp
systemctl disable --now wg-quick@antizapret
systemctl disable --now wg-quick@vpn

# РЈРґР°Р»РёРј РЅРµРЅСѓР¶РЅС‹Рµ СЃР»СѓР¶Р±С‹
apt-get purge -y ufw
apt-get purge -y firewalld
apt-get purge -y apparmor
apt-get purge -y apport
apt-get purge -y modemmanager
apt-get purge -y snapd
apt-get purge -y upower
apt-get purge -y multipath-tools
apt-get purge -y rsyslog
apt-get purge -y udisks2
apt-get purge -y qemu-guest-agent
apt-get purge -y tuned
apt-get purge -y sysstat
apt-get purge -y acpid
apt-get purge -y fwupd
apt-get purge -y watchdog
apt-get purge -y pcscd
apt-get purge -y packagekit

# SSH protection РІРєР»СЋС‡С‘РЅ
if [[ "$SSH_PROTECTION" == 'y' ]]; then
	apt-get purge -y fail2ban || true
	apt-get purge -y sshguard || true
fi

# РЈРґР°Р»СЏРµРј РєСЌС€ Knot Resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /var/cache/knot-resolver2/*

# РЈРґР°Р»СЏРµРј СЃС‚Р°СЂС‹Рµ С„Р°Р№Р»С‹ OpenVPN Рё WireGuard
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*
rm -rf /etc/wireguard/templates/*

# РЈРґР°Р»СЏРµРј СЃРєРѕРјРїРёР»РёСЂРѕРІР°РЅРЅС‹Р№ РїР°С‚С‡РµРЅРЅС‹Р№ OpenVPN
make -C /usr/local/src/openvpn uninstall
rm -rf /usr/local/src/openvpn

# РћС‚РєР»СЋС‡РёРј IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

# РЈРґР°Р»СЏРµРј РїРµСЂРµРѕРїСЂРµРґРµР»С‘РЅРЅС‹Рµ РїР°СЂР°РјРµС‚СЂС‹ СЏРґСЂР°
sed -i '/^$/!{/^#/!d}' /etc/sysctl.conf

# РџСЂРёРЅСѓРґРёС‚РµР»СЊРЅР°СЏ Р·Р°РіСЂСѓР·РєР° РјРѕРґСѓР»СЏ nf_conntrack
echo 'nf_conntrack' > /etc/modules-load.d/nf_conntrack.conf

# Р—Р°РІРµСЂС€РёРј РІС‹РїРѕР»РЅРµРЅРёРµ СЃРєСЂРёРїС‚Р° РїСЂРё РѕС€РёР±РєРµ
set -e

# РћР±СЂР°Р±РѕС‚РєР° РѕС€РёР±РѕРє
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

# РћР±РЅРѕРІР»СЏРµРј СЃРёСЃС‚РµРјСѓ
rm -rf /etc/apt/sources.list.d/cznic-labs-knot-resolver.list
rm -rf /etc/apt/sources.list.d/openvpn-aptrepo.list
rm -rf /etc/apt/sources.list.d/backports.list
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get dist-upgrade -y
apt-get install -y curl gpg

# РџР°РїРєР° РґР»СЏ РєР»СЋС‡РµР№
mkdir -p /etc/apt/keyrings

# Р”РѕР±Р°РІРёРј СЂРµРїРѕР·РёС‚РѕСЂРёР№ Knot Resolver
curl -fL --connect-timeout 30 https://pkg.labs.nic.cz/gpg -o /etc/apt/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/etc/apt/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $CODENAME main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

# Р”РѕР±Р°РІРёРј СЂРµРїРѕР·РёС‚РѕСЂРёР№ OpenVPN
curl -fL --connect-timeout 30 https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --yes --dearmor -o /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.7 $CODENAME main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

# Р”РѕР±Р°РІРёРј СЂРµРїРѕР·РёС‚РѕСЂРёР№ Debian Backports
if [[ "$OS" == 'debian' ]]; then
	echo "deb http://deb.debian.org/debian $CODENAME-backports main" > /etc/apt/sources.list.d/backports.list
fi

# РЎС‚Р°РІРёРј РЅРµРѕР±С…РѕРґРёРјРѕРµ СЏРґСЂРѕ Рё РїР°РєРµС‚С‹
apt-get update
INSTALL=
# РћР±РЅРѕРІР»СЏРµРј СЏРґСЂРѕ С‚РѕР»СЊРєРѕ РЅР° Ubuntu РЅРёР¶Рµ 26 Рё Debian РЅРёР¶Рµ 14
if [[ "$OS" == 'ubuntu' ]] && (( VERSION < 26 )); then
	INSTALL="linux-generic-hwe-${VERSION}.04"
elif [[ "$OS" == 'debian' ]] && (( VERSION < 14 )); then
	INSTALL="-t $CODENAME-backports linux-image-$ARCH linux-headers-$ARCH"
fi
apt-get install -y $INSTALL git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils socat lua-cqueues ipset irqbalance unattended-upgrades jq ethtool iproute2
apt-get autoremove --purge -y
apt-get clean
dpkg-reconfigure -f noninteractive unattended-upgrades

# РљР»РѕРЅРёСЂСѓРµРј СЂРµРїРѕР·РёС‚РѕСЂРёР№ Рё СѓСЃС‚Р°РЅР°РІР»РёРІР°РµРј dnslib
rm -rf /tmp/dnslib
git clone https://github.com/paulc/dnslib.git /tmp/dnslib
PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --force-reinstall --user /tmp/dnslib

# РљР»РѕРЅРёСЂСѓРµРј СЂРµРїРѕР·РёС‚РѕСЂРёР№ antizapret
rm -rf /tmp/antizapret
git clone https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

# РЎРѕС…СЂР°РЅСЏРµРј РїРѕР»СЊР·РѕРІР°С‚РµР»СЊСЃРєРёРµ РЅР°СЃС‚СЂРѕР№РєРё Рё РѕР±СЂР°Р±РѕС‚С‡РёРєРё custom*.sh
cp /root/antizapret/config/*.txt /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret/ || true
cp /etc/knot-resolver/*.lua /tmp/antizapret/setup/etc/knot-resolver/ || true

# Р’РѕСЃСЃС‚Р°РЅР°РІР»РёРІР°РµРј РёР· Р±СЌРєР°РїР° РїРѕР»СЊР·РѕРІР°С‚РµР»СЊСЃРєРёРµ РЅР°СЃС‚СЂРѕР№РєРё Рё РѕР±СЂР°Р±РѕС‚С‡РёРєРё custom*.sh, РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ OpenVPN Рё WireGuard
tar -xzf /root/backup*.tar.gz || true
rm -f /root/backup*.tar.gz || true

cp -r /root/easyrsa3/* /tmp/antizapret/setup/etc/openvpn/easyrsa3/ || true
cp /root/wireguard/* /tmp/antizapret/setup/etc/wireguard/ || true
cp /root/config/* /tmp/antizapret/setup/root/antizapret/config/ || true
cp /root/knot-resolver/* /tmp/antizapret/setup/etc/knot-resolver/ || true
cp /root/custom/* /tmp/antizapret/setup/root/antizapret/ || true

rm -rf /root/easyrsa3
rm -rf /root/wireguard
rm -rf /root/config
rm -rf /root/knot-resolver
rm -rf /root/custom

# РЎРѕС…СЂР°РЅСЏРµРј РЅР°СЃС‚СЂРѕР№РєРё
echo "SETUP_DATE=$(date --iso-8601=seconds)
OPENVPN_UDP_ENABLE=$OPENVPN_UDP_ENABLE
OPENVPN_TCP_ENABLE=$OPENVPN_TCP_ENABLE
WIREGUARD_ENABLE=$WIREGUARD_ENABLE
OPENVPN_PATCH=$OPENVPN_PATCH
OPENVPN_DCO=$OPENVPN_DCO
ANTIZAPRET_WARP=$ANTIZAPRET_WARP
VPN_WARP=$VPN_WARP
ANTIZAPRET_DNS=$ANTIZAPRET_DNS
VPN_DNS=$VPN_DNS
BLOCK_ADS=$BLOCK_ADS
ALTERNATIVE_CLIENT_IP=$ALTERNATIVE_CLIENT_IP
ALTERNATIVE_FAKE_IP=$ALTERNATIVE_FAKE_IP
OPENVPN_BACKUP_TCP=$OPENVPN_BACKUP_TCP
OPENVPN_BACKUP_UDP=$OPENVPN_BACKUP_UDP
WIREGUARD_BACKUP=$WIREGUARD_BACKUP
OPENVPN_DUPLICATE=$OPENVPN_DUPLICATE
OPENVPN_LOG=$OPENVPN_LOG
SSH_PROTECTION=$SSH_PROTECTION
ATTACK_PROTECTION=$ATTACK_PROTECTION
SCAN_PROTECTION=$SCAN_PROTECTION
TORRENT_GUARD=$TORRENT_GUARD
RESTRICT_FORWARD=$RESTRICT_FORWARD
CLIENT_ISOLATION=$CLIENT_ISOLATION
OPENVPN_HOST=$OPENVPN_HOST
WIREGUARD_HOST=$WIREGUARD_HOST
ROUTE_ALL=$ROUTE_ALL
DISCORD_INCLUDE=$DISCORD_INCLUDE
CLOUDFLARE_INCLUDE=$CLOUDFLARE_INCLUDE
TELEGRAM_INCLUDE=$TELEGRAM_INCLUDE
WHATSAPP_INCLUDE=$WHATSAPP_INCLUDE
ROBLOX_INCLUDE=$ROBLOX_INCLUDE
AMAZON_INCLUDE=$AMAZON_INCLUDE
HETZNER_INCLUDE=$HETZNER_INCLUDE
DIGITALOCEAN_INCLUDE=$DIGITALOCEAN_INCLUDE
OVH_INCLUDE=$OVH_INCLUDE
GOOGLE_INCLUDE=$GOOGLE_INCLUDE
AKAMAI_INCLUDE=$AKAMAI_INCLUDE
CLEAR_HOSTS=y
TXQUEUELEN=1000
MTU=$MTU
SEGMENTATION_OFFLOAD=off
DEFAULT_INTERFACE=
DEFAULT_IP=
ANTIZAPRET_OUT_INTERFACE=
ANTIZAPRET_OUT_IP=
VPN_OUT_INTERFACE=
VPN_OUT_IP=
CLIENT_IP=
FAKE_IP=" > /tmp/antizapret/setup/root/antizapret/setup

# РЎРѕР·РґР°РµРј РїР°РїРєРё РґР»СЏ РєСЌС€Р° Knot Resolver
mkdir -p /var/cache/knot-resolver
mkdir -p /var/cache/knot-resolver2
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver
chown -R knot-resolver:knot-resolver /var/cache/knot-resolver2

# Р’С‹СЃС‚Р°РІР»СЏРµРј СЂР°Р·СЂРµС€РµРЅРёСЏ
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret/setup/root/antizapret -type f -exec chmod +x {} +
find /tmp/antizapret/setup/etc/openvpn/server/scripts -type f -exec chmod +x {} +

# РљРѕРїРёСЂСѓРµРј РЅСѓР¶РЅРѕРµ, СѓРґР°Р»СЏРµРј РЅРµ РЅСѓР¶РЅРѕРµ
find /tmp/antizapret -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/dnslib
rm -rf /tmp/antizapret

# РќР°СЃС‚СЂР°РёРІР°РµРј DNS РІ AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" == '2' ]]; then
	# Cloudflare+Quad9+SkyDNS
	sed -i "s/{'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'}/'193.58.251.251'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '3' ]]; then
	# Cloudflare+Quad9
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '4' ]]; then
	# Comss
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'83.220.169.155', '212.109.195.93', '195.133.25.16'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'83.220.169.155', '212.109.195.93', '195.133.25.16'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '5' ]]; then
	# XBox
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'111.88.96.50', '111.88.96.51'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'111.88.96.50', '111.88.96.51'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == '6' ]]; then
	# Malw
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'84.21.189.133', '193.23.209.189'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'84.21.189.133', '193.23.209.189'/" /etc/knot-resolver/kresd.conf
fi

# РќР°СЃС‚СЂР°РёРІР°РµРј DNS РІ full VPN
if [[ "$VPN_DNS" == '3' ]]; then
	# Quad9
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 9.9.9.10"\npush "dhcp-option DNS 149.112.112.10"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/9.9.9.10, 149.112.112.10/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '4' ]]; then
	# Google
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 8.8.8.8"\npush "dhcp-option DNS 8.8.4.4"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/8.8.8.8, 8.8.4.4/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '5' ]]; then
	# AdGuard
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/94.140.14.14, 94.140.15.15/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '6' ]]; then
	# Comss
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 83.220.169.155"\npush "dhcp-option DNS 212.109.195.93"\npush "dhcp-option DNS 195.133.25.16"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/83.220.169.155, 212.109.195.93, 195.133.25.16/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '7' ]]; then
	# XBox
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 111.88.96.50"\npush "dhcp-option DNS 111.88.96.51"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/111.88.96.50, 111.88.96.51/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == '8' ]]; then
	# Malw
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 84.21.189.133"\npush "dhcp-option DNS 193.23.209.189"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/84.21.189.133, 193.23.209.189/' /etc/wireguard/templates/vpn-client*.conf
fi

# РСЃРїРѕР»СЊР·СѓРµРј Р°Р»СЊС‚РµСЂРЅР°С‚РёРІРЅС‹Р№ РґРёР°РїР°Р·РѕРЅ РїРѕРґРјРµРЅРЅС‹С… IPv4-Р°РґСЂРµСЃРѕРІ
# 10(172).28.0.0/15 => 198.18.0.0/15
if [[ "$ALTERNATIVE_FAKE_IP" == 'y' ]]; then
	sed -i 's/10\.30\./198\.18\./g' /root/antizapret/proxy.py
fi

# РСЃРїРѕР»СЊР·СѓРµРј Р°Р»СЊС‚РµСЂРЅР°С‚РёРІРЅС‹Р№ РґРёР°РїР°Р·РѕРЅ РєР»РёРµРЅС‚СЃРєРёС… IPv4-Р°РґСЂРµСЃРѕРІ
# 10.28.0.0/15 => 172.28.0.0/15
if [[ "$ALTERNATIVE_CLIENT_IP" == 'y' ]]; then
	sed -i 's/10\./172\./g' /root/antizapret/proxy.py
	sed -i 's/10\./172\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

# Р—Р°РїСЂРµС‰Р°РµРј РЅРµСЃРєРѕР»СЊРєРѕ РѕРґРЅРѕРІСЂРµРјРµРЅРЅС‹С… РїРѕРґРєР»СЋС‡РµРЅРёР№ Рє OpenVPN РґР»СЏ РѕРґРЅРѕРіРѕ РєР»РёРµРЅС‚Р°
if [[ "$OPENVPN_DUPLICATE" == 'n' ]]; then
	sed -i '/duplicate-cn/s/^/#/' /etc/openvpn/server/*.conf
fi

# Р’РєР»СЋС‡РёРј РїРѕРґСЂРѕР±РЅС‹Рµ Р»РѕРіРё РІ OpenVPN
if [[ "$OPENVPN_LOG" == 'y' ]]; then
	sed -i '/^#\(verb\|log\)/s/^#//' /etc/openvpn/server/*.conf
fi

# РР·РјРµРЅСЏРµРј MTU РІ РєРѕРЅС„РёРіСѓСЂР°С†РёСЏС… WireGuard Рё OpenVPN
if [[ "$MTU" != '1420' ]]; then
	# РЎРµСЂРІРµСЂРЅС‹Рµ Рё РєР»РёРµРЅС‚СЃРєРёРµ С„Р°Р№Р»С‹ WireGuard
	sed -i "s/1420/$MTU/g" /etc/wireguard/*.conf /etc/wireguard/templates/*.conf /root/*.conf /root/*.ovpn 2>/dev/null || true
	
	# Р”РѕР±Р°РІР»СЏРµРј MTU РІ С€Р°Р±Р»РѕРЅС‹ РєР»РёРµРЅС‚СЃРєРёС… РєРѕРЅС„РёРіРѕРІ WireGuard
	for file in /etc/wireguard/templates/*client*.conf; do
		if grep -q "MTU" "$file"; then
			sed -i "s/MTU.*/MTU = $MTU/g" "$file"
		else
			sed -i "/Address =/a MTU = $MTU" "$file"
		fi
	done

	# РЎРµСЂРІРµСЂРЅС‹Рµ РєРѕРЅС„РёРіРё OpenVPN
	for file in /etc/openvpn/server/*.conf; do
		if grep -q "tun-mtu" "$file"; then
			sed -i "s/tun-mtu.*/tun-mtu $MTU/g" "$file"
		else
			echo "tun-mtu $MTU" >> "$file"
		fi
	done

	# РЁР°Р±Р»РѕРЅС‹ РєР»РёРµРЅС‚СЃРєРёС… РєРѕРЅС„РёРіРѕРІ OpenVPN
	for file in /etc/openvpn/client/templates/*.conf; do
		if grep -q "tun-mtu" "$file"; then
			sed -i "s/tun-mtu.*/tun-mtu $MTU/g" "$file"
		else
			echo "tun-mtu $MTU" >> "$file"
		fi
	done
fi

# РР·РјРµРЅСЏРµРј РїРѕРІРµРґРµРЅРёРµ policy.PASS РІ Knot Resolver
sed -i '/function policy\.PASS(state, _)/,/^end$/s/return state/return nil/' /usr/lib/knot-resolver/kres_modules/policy.lua

# Р—Р°РіСЂСѓР¶Р°РµРј Рё СЃРѕР·РґР°РµРј СЃРїРёСЃРєРё РёСЃРєР»СЋС‡РµРЅРёР№
/root/antizapret/doall.sh noclear

# РќР°СЃС‚СЂР°РёРІР°РµРј СЃРµСЂРІРµСЂР° OpenVPN Рё WireGuard/AmneziaWG РґР»СЏ РїРµСЂРІРѕРіРѕ Р·Р°РїСѓСЃРєР°
# РџРµСЂРµСЃРѕР·РґР°РµРј РґР»СЏ РІСЃРµС… СЃСѓС‰РµСЃС‚РІСѓСЋС‰РёС… РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ С„Р°Р№Р»С‹ РїРѕРґРєР»СЋС‡РµРЅРёР№
# Р•СЃР»Рё РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ РЅРµС‚, С‚Рѕ СЃРѕР·РґР°РµРј РЅРѕРІС‹С… РїРѕР»СЊР·РѕРІР°С‚РµР»РµР№ 'antizapret-client' РґР»СЏ OpenVPN Рё WireGuard/AmneziaWG
/root/antizapret/client.sh 7

# Р’РєР»СЋС‡РёРј РѕР±РЅРѕРІР»СЏРµРјС‹Рµ СЃР»СѓР¶Р±С‹
systemctl enable kresd@1
systemctl enable kresd@2
systemctl enable antizapret
systemctl enable antizapret-update.timer
systemctl enable antizapret-update
if [[ "$OPENVPN_UDP_ENABLE" == 'y' ]]; then
	systemctl enable openvpn-server@antizapret-udp
	systemctl enable openvpn-server@vpn-udp
fi
if [[ "$OPENVPN_TCP_ENABLE" == 'y' ]]; then
	systemctl enable openvpn-server@antizapret-tcp
	systemctl enable openvpn-server@vpn-tcp
fi
if [[ "$WIREGUARD_ENABLE" == 'y' ]]; then
	systemctl enable wg-quick@antizapret
	systemctl enable wg-quick@vpn
fi

ERRORS=

if [[ "$OPENVPN_PATCH" != '0' ]]; then
	if ! /root/antizapret/patch-openvpn.sh "$OPENVPN_PATCH"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run '/root/antizapret/patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$OPENVPN_DCO" == 'y' ]]; then
	if ! /root/antizapret/openvpn-dco.sh y; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh y' after rebooting\n"
	fi
fi

# Р•СЃР»Рё РµСЃС‚СЊ РѕС€РёР±РєРё, РІС‹РІРѕРґРёРј РёС…
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

# РЎРѕР·РґР°РґРёРј С„Р°Р№Р» РїРѕРґРєР°С‡РєРё СЂР°Р·РјРµСЂРѕРј 1 Р“Р± РµСЃР»Рё РµРіРѕ РЅРµС‚
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE=/swapfile
	SWAPSIZE=1024
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 $SWAPFILE
	mkswap $SWAPFILE
	swapon $SWAPFILE
	echo $SWAPFILE none swap sw 0 0 >> /etc/fstab
fi

# РџРµСЂРµР·Р°РіСЂСѓР¶Р°РµРј
echo
echo -e '\e[1;32mAntiZapret VPN + full VPN installed successfully!\e[0m'
echo 'Rebooting...'

reboot