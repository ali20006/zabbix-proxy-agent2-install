#!/bin/bash

set -e

PROXY_CONF="/etc/zabbix/zabbix_proxy.conf"
AGENT_CONF="/etc/zabbix/zabbix_agent2.conf"
DB="/var/lib/zabbix/zabbix_proxy.db"
SCHEMA="/usr/share/zabbix/sql-scripts/sqlite3/proxy.sql"

echo
echo "=========================================="
echo " Zabbix Proxy + Agent 2 Installer"
echo "=========================================="
echo

# ------------------------------------------
# 1. Check root
# ------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: این اسکریپت باید با root اجرا شود."
    echo "اجرا کنید:"
    echo "sudo ./install-zabbix.sh"
    exit 1
fi

# ------------------------------------------
# 2. Get configuration
# ------------------------------------------

read -rp "Hostname را وارد کنید: " HOSTNAME_NEW

if [[ -z "$HOSTNAME_NEW" ]]; then
    echo "ERROR: Hostname نمی‌تواند خالی باشد."
    exit 1
fi

read -rp "IP آدرس Zabbix Server را وارد کنید: " ZABBIX_SERVER

if [[ -z "$ZABBIX_SERVER" ]]; then
    echo "ERROR: IP آدرس Zabbix Server نمی‌تواند خالی باشد."
    exit 1
fi

echo
echo "------------------------------------------"
echo "Hostname      : $HOSTNAME_NEW"
echo "Zabbix Server : $ZABBIX_SERVER"
echo
echo "Proxy Server  : $ZABBIX_SERVER"
echo "Agent Server  : 127.0.0.1"
echo "Agent Active  : $ZABBIX_SERVER"
echo "------------------------------------------"
echo

read -rp "ادامه می‌دهید؟ [y/N]: " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "لغو شد."
    exit 0
fi

# ------------------------------------------
# 3. Detect Ubuntu version
# ------------------------------------------

echo
echo "[1/9] بررسی نسخه Ubuntu..."

. /etc/os-release

if [[ "$ID" != "ubuntu" ]]; then
    echo "ERROR: این اسکریپت فقط برای Ubuntu است."
    exit 1
fi

case "$VERSION_ID" in
    "22.04")
        ZABBIX_REPO="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu22.04_all.deb"
        ;;
    "24.04")
        ZABBIX_REPO="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu24.04_all.deb"
        ;;
    *)
        echo "ERROR: Ubuntu $VERSION_ID در این اسکریپت پشتیبانی نمی‌شود."
        echo "Supported: Ubuntu 22.04 / 24.04"
        exit 1
        ;;
esac

echo "Ubuntu $VERSION_ID detected."

# ------------------------------------------
# 4. Set Linux hostname
# ------------------------------------------

echo
echo "[2/9] تنظیم hostname سیستم..."

hostnamectl set-hostname "$HOSTNAME_NEW"

# ------------------------------------------
# 5. Install Zabbix repository
# ------------------------------------------

echo
echo "[3/9] نصب Repository رسمی Zabbix 7.4..."

apt update
apt install -y wget

TMP_REPO="/tmp/zabbix-release.deb"

wget -q "$ZABBIX_REPO" -O "$TMP_REPO"

dpkg -i "$TMP_REPO"

rm -f "$TMP_REPO"

apt update

# ------------------------------------------
# 6. Install packages
# ------------------------------------------

echo
echo "[4/9] نصب Zabbix Proxy + Agent 2..."

apt install -y \
    zabbix-proxy-sqlite3 \
    zabbix-agent2 \
    zabbix-sql-scripts \
    sqlite3

# ------------------------------------------
# 7. Configure Zabbix Proxy
# ------------------------------------------

echo
echo "[5/9] تنظیم Zabbix Proxy..."

if grep -qE '^Server=' "$PROXY_CONF"; then
    sed -i \
        -E "s/^Server=.*/Server=$ZABBIX_SERVER/" \
        "$PROXY_CONF"
else
    echo "Server=$ZABBIX_SERVER" >> "$PROXY_CONF"
fi

if grep -qE '^Hostname=' "$PROXY_CONF"; then
    sed -i \
        -E "s/^Hostname=.*/Hostname=$HOSTNAME_NEW/" \
        "$PROXY_CONF"
else
    echo "Hostname=$HOSTNAME_NEW" >> "$PROXY_CONF"
fi

if grep -qE '^DBName=' "$PROXY_CONF"; then
    sed -i \
        -E "s|^DBName=.*|DBName=$DB|" \
        "$PROXY_CONF"
else
    echo "DBName=$DB" >> "$PROXY_CONF"
fi

# ------------------------------------------
# 8. Initialize SQLite database
# ------------------------------------------

echo
echo "[6/9] بررسی دیتابیس Zabbix Proxy..."

mkdir -p /var/lib/zabbix

if [[ ! -s "$DB" ]]; then

    echo "دیتابیس وجود ندارد یا خالی است."
    echo "در حال ایجاد SQLite database..."

    rm -f "$DB"

    if [[ ! -f "$SCHEMA" ]]; then
        echo "ERROR: فایل Schema پیدا نشد:"
        echo "$SCHEMA"
        exit 1
    fi

    sqlite3 "$DB" < "$SCHEMA"

else
    echo "دیتابیس موجود است؛ بدون تغییر باقی می‌ماند."
fi

chown zabbix:zabbix "$DB"
chmod 640 "$DB"

# ------------------------------------------
# 9. Configure Zabbix Agent 2
# ------------------------------------------

echo
echo "[7/9] تنظیم Zabbix Agent 2..."

# Passive checks فقط از localhost
if grep -qE '^Server=' "$AGENT_CONF"; then
    sed -i \
        -E 's/^Server=.*/Server=127.0.0.1/' \
        "$AGENT_CONF"
else
    echo "Server=127.0.0.1" >> "$AGENT_CONF"
fi

# Active checks مستقیماً به Zabbix Server
if grep -qE '^ServerActive=' "$AGENT_CONF"; then
    sed -i \
        -E "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER/" \
        "$AGENT_CONF"
else
    echo "ServerActive=$ZABBIX_SERVER" >> "$AGENT_CONF"
fi

# Hostname
if grep -qE '^Hostname=' "$AGENT_CONF"; then
    sed -i \
        -E "s/^Hostname=.*/Hostname=$HOSTNAME_NEW/" \
        "$AGENT_CONF"
else
    echo "Hostname=$HOSTNAME_NEW" >> "$AGENT_CONF"
fi

# ------------------------------------------
# Enable and restart services
# ------------------------------------------

echo
echo "[8/9] فعال‌سازی سرویس‌ها..."

systemctl daemon-reload

systemctl enable zabbix-proxy
systemctl enable zabbix-agent2

systemctl restart zabbix-proxy
systemctl restart zabbix-agent2

sleep 2

# ------------------------------------------
# Final status
# ------------------------------------------

echo
echo "[9/9] بررسی نهایی..."
echo

echo "Zabbix Proxy:"
systemctl is-active zabbix-proxy

echo
echo "Zabbix Agent 2:"
systemctl is-active zabbix-agent2

echo
echo "=========================================="
echo " Configuration"
echo "=========================================="

echo
echo "Linux Hostname:"
hostname

echo
echo "Zabbix Proxy:"
grep -E '^(Server|Hostname|DBName)=' "$PROXY_CONF"

echo
echo "Zabbix Agent 2:"
grep -E '^(Server|ServerActive|Hostname)=' "$AGENT_CONF"

echo
echo "Versions:"
zabbix_proxy --version | head -1
zabbix_agent2 --version | head -1

echo
echo "Agent 2 port:"
ss -lntp | grep ':10050' || true

echo
echo "=========================================="
echo " Installation completed"
echo "=========================================="
echo
echo "Zabbix Server : $ZABBIX_SERVER"
echo "Proxy Name    : $HOSTNAME_NEW"
echo "Agent Passive : 127.0.0.1"
echo "Agent Active  : $ZABBIX_SERVER"
echo
