```bash
#!/bin/bash

set -e

# ==========================================
# Zabbix Proxy + Agent 2 Installer
# ==========================================

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
# 1. Get configuration from user
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
echo "Agent Server  : 127.0.0.1"
echo "------------------------------------------"
echo

read -rp "ادامه می‌دهید؟ [y/N]: " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "لغو شد."
    exit 0
fi

# ------------------------------------------
# 2. Check root
# ------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: این اسکریپت باید با root اجرا شود."
    echo "اجرا کنید:"
    echo "sudo ./install-zabbix.sh"
    exit 1
fi

# ------------------------------------------
# 3. Set Linux hostname
# ------------------------------------------

echo
echo "[1/8] تنظیم hostname سیستم..."

hostnamectl set-hostname "$HOSTNAME_NEW"

# ------------------------------------------
# 4. Install required packages
# ------------------------------------------

echo
echo "[2/8] نصب/بررسی پکیج‌های مورد نیاز..."

apt update

apt install -y \
    zabbix-proxy-sqlite3 \
    zabbix-agent2 \
    zabbix-sql-scripts \
    sqlite3

# ------------------------------------------
# 5. Configure Zabbix Proxy
# ------------------------------------------

echo
echo "[3/8] تنظیم Zabbix Proxy..."

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
# 6. Initialize SQLite database
# ------------------------------------------

echo
echo "[4/8] بررسی دیتابیس Zabbix Proxy..."

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

fi

chown zabbix:zabbix "$DB"
chmod 640 "$DB"

# ------------------------------------------
# 7. Configure Zabbix Agent 2
# ------------------------------------------

echo
echo "[5/8] تنظیم Zabbix Agent 2..."

# Agent passive checks فقط از localhost
if grep -qE '^Server=' "$AGENT_CONF"; then
    sed -i \
        -E 's/^Server=.*/Server=127.0.0.1/' \
        "$AGENT_CONF"
else
    echo "Server=127.0.0.1" >> "$AGENT_CONF"
fi

# Agent active checks به Proxy روی همین سرور
if grep -qE '^ServerActive=' "$AGENT_CONF"; then
    sed -i \
        -E 's/^ServerActive=.*/ServerActive=127.0.0.1/' \
        "$AGENT_CONF"
else
    echo "ServerActive=127.0.0.1" >> "$AGENT_CONF"
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
# 8. Enable and restart services
# ------------------------------------------

echo
echo "[6/8] فعال‌سازی سرویس‌ها..."

systemctl daemon-reload

systemctl enable zabbix-proxy
systemctl enable zabbix-agent2

systemctl restart zabbix-proxy
systemctl restart zabbix-agent2

sleep 2

# ------------------------------------------
# Service status
# ------------------------------------------

echo
echo "[7/8] بررسی وضعیت سرویس‌ها..."
echo

echo "Zabbix Proxy:"
systemctl is-active zabbix-proxy

echo
echo "Zabbix Agent 2:"
systemctl is-active zabbix-agent2

# ------------------------------------------
# Final configuration
# ------------------------------------------

echo
echo "[8/8] تنظیمات نهایی"
echo
echo "=========================================="

echo
echo "Linux Hostname:"
hostname

echo
echo "Zabbix Proxy configuration:"
grep -E '^(Server|Hostname|DBName)=' "$PROXY_CONF"

echo
echo "Zabbix Agent 2 configuration:"
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
echo "Agent         : 127.0.0.1"
echo
```
