#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.zabbix.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing prerequisites (Apache, PHP, MariaDB, plugins)"
DEBIAN_FRONTEND=noninteractive \
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release apt-transport-https \
  apache2 php php-cli php-gd php-xml php-intl php-ldap php-mysql php-curl \
  mariadb-server monitoring-plugins-basic
systemctl enable --now apache2 mariadb >/dev/null 2>&1 || true
msg_ok "Prerequisites installed"

msg_info "Installing Icinga components"
apt-get install -y --no-install-recommends \
  icinga2 icinga2-ido-mysql icingaweb2 icingacli icingaweb2-module-monitoring
systemctl enable --now icinga2 >/dev/null 2>&1 || true
msg_ok "Icinga installed"

msg_info "Configuring MariaDB (bind to localhost)"
sed -i 's/^#*bind-address.*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf || true
systemctl restart mariadb >/dev/null 2>&1 || true
msg_ok "MariaDB configured"

msg_info "Preparing Icinga IDO database"
DBPW="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
mysql -uroot -e "CREATE DATABASE IF NOT EXISTS icinga;"
mysql -uroot -e "CREATE USER IF NOT EXISTS 'icinga'@'localhost' IDENTIFIED BY '${DBPW}';"
mysql -uroot -e "GRANT ALL ON icinga.* TO 'icinga'@'localhost'; FLUSH PRIVILEGES;"
mysql -uroot -e "USE icinga; SHOW TABLES LIKE 'icinga_dbversion';" | grep -q icinga_dbversion || \
  mysql -uroot icinga < /usr/share/icinga2-ido-mysql/schema/mysql.sql
msg_ok "IDO database ready"

msg_info "Enabling Icinga features (api, ido-mysql)"
icinga2 feature enable api ido-mysql >/dev/null 2>&1 || true
cat > /etc/icinga2/features-available/ido-mysql.conf <<EOF
library "db_ido_mysql"
object IdoMysqlConnection "ido-mysql" {
  user = "icinga"
  password = "${DBPW}"
  host = "localhost"
  database = "icinga"
}
EOF
icinga2 daemon -C >/dev/null 2>&1 || true
systemctl restart icinga2 >/dev/null 2>&1 || true
msg_ok "Icinga features enabled"

msg_info "Configuring Apache for Icinga Web 2"
a2enmod rewrite >/dev/null 2>&1 || true
systemctl reload apache2 >/dev/null 2>&1 || true
msg_ok "Apache configured"

msg_info "Creating Icinga Web 2 setup token"
icingacli setup token create >/dev/null 2>&1 || true
SETUP_TOKEN="$(icingacli setup token show | tail -n1 | tr -d '\r' || true)"
msg_ok "Setup token: ${SETUP_TOKEN}"

echo "DBPW=${DBPW}" > /root/icinga-installer.env
echo "SETUP_TOKEN=${SETUP_TOKEN}" >> /root/icinga-installer.env

apt-get clean
rm -rf /var/lib/apt/lists/*

IP=$(hostname -I | awk '{print $1}')
cat <<EOT

===============================================================================
 ${APP} installed inside this container
-------------------------------------------------------------------------------
 Web UI:      http://${IP}/icingaweb2
 Setup token: ${SETUP_TOKEN}
 DB:          icinga (user: icinga / pw: ${DBPW})
===============================================================================
EOT

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /tmp/zabbix-release_latest+debian12_all.deb
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
