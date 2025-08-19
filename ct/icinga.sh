#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: <your-github-handle>
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://icinga.com/

APP="Icinga"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/icinga2/icinga2.conf ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi
  msg_info "Updating ${APP} components"
  $STD apt-get update
  $STD apt-get -y --only-upgrade install \
      icinga2 icinga2-ido-mysql icingaweb2 icingacli icingaweb2-module-monitoring || true
  systemctl restart icinga2 || true
  systemctl reload apache2 || true
  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
