#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/tteck/Proxmox/main/misc/build.func)
# Copyright (c) 2024 YourName
# License: MIT

function header_info {
  clear
  cat <<"EOF"
   ____             _____ __    
  / __/__ ___ _____/ __(_) /____
 _\ \/ -_) _ `/ __/ _// / / -_) 
/___/\__/\_,_/\__/_/ /_/_/\__/  
                                
EOF
}
header_info
echo -e "Loading..."
APP="Seafile"
var_disk="10"
var_cpu="2"
var_ram="4096"
var_os="alpine"
var_version="3.18"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
  header_info
  if [[ ! -f /opt/seafile/seafile-server-latest/seafile.sh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  CURRENT_VERSION=$(cat /opt/seafile/seafile-server-latest/seafile/version)
  LATEST_VERSION=$(curl -s https://download.seadrive.org/ | grep -oP 'seafile-server_\K[0-9.]+(?=_x86-64.tar.gz)' | sort -V | tail -n1)
  if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    msg_info "${APP} is already up to date (${CURRENT_VERSION})"
    exit
  fi
  msg_info "Updating $APP to ${LATEST_VERSION}"
  wget -q https://download.seadrive.org/seafile-server_${LATEST_VERSION}_x86-64.tar.gz
  tar xzf seafile-server_${LATEST_VERSION}_x86-64.tar.gz
  mv seafile-server-${LATEST_VERSION} /opt/seafile/
  cd /opt/seafile/seafile-server-${LATEST_VERSION}
  $STD ./upgrade/upgrade_ <old_version >_ <new_version >.sh
  rm -f seafile-server_${LATEST_VERSION}_x86-64.tar.gz
  msg_ok "Updated $APP Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}https://${IP}${CL} \n"
