#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
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