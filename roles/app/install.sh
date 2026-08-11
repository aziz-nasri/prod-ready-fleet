#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source ./app.conf
require_root
check_connectivity
require_cmd netplan
trap trap_cleanup EXIT


# Network configuration

NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in app.conf"

 # generating the netplan file
generate_netplan_yaml() {
  echo "network:"
  echo "  version: 2"
  echo "  ethernets:"
  for i in "${!INTERFACES[@]}"; do
    iface="${INTERFACES[$i]}"
    mode="${MODES[$i]}"
    echo "    $iface:"
    if [[ "$mode" == "dhcp" ]]; then
      echo "      dhcp4: yes"
    else
      echo "      dhcp4: no"
      echo "      addresses:"
      echo "        - ${ADDRESSES[$i]}"
      if [[ -n "${DEFAULT_ROUTE_VIA:-}" && "$iface" == "${DEFAULT_ROUTE_IFACE:-}" ]]; then
        echo "      routes:"
        echo "        - to: default"
        echo "          via: $DEFAULT_ROUTE_VIA"
      fi
      if [[ ${#DNS_SERVERS[@]:-0} -gt 0 ]]; then
        echo "      nameservers:"
        echo "        addresses: [$(IFS=,; echo "${DNS_SERVERS[*]}")]"
      fi
    fi
  done
}

 # moving it to destanation
backup_file "$NETPLAN_FILE"

log_info "Writing new netplan config to $NETPLAN_FILE"
generate_netplan_yaml | tee "$NETPLAN_FILE" > /dev/null
chmod 600 "$NETPLAN_FILE"

 # appling changes
log_info "Applying netplan configuration"
netplan apply

 # closing unecessary listening ports 
close_ports $TO_BE_ClOSED_PORTS

# Runtime & process management

 # creating the application user.
../../common/user_provi.sh appuser.conf
log_info "Appuser created."

 # creating the app.service
 if [[ ! -f $SERVICE_FILE ]]; then
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=${APP_NAME} application server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_EXEC} --bind ${SERVER_ADDR}:8080
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl deamon-reload &> /dev/null
sudo systemctl enable --now $SERVICE_FILE &> /dev/null
sudo systemctl start $SERVICE_FILE &> /dev/null
log_info "application service file created and running."

sudo chown $APP_USER:$APP_USER $APP_DIR/.env &> /dev/null
sudo chmod 600 $APP_DIR/.env &> /dev/null
fi

# logging 
sudo journalclt -u $SERVICE_FILE &> /dev/null

# adding health check script
sudo mkdir ~/health-check > /dev/null
sudo chown admin:admin ~/health-check > /dev/null
sudo chmod 550 ~/health-check > /dev/null
cp ../../common/health-check.sh ~/health-check > /dev/null
cp health-extra.sh ~/health-check > /dev/null
cp health.conf ~/health-check > /dev/null