#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/net-mgmt.conf"
require_root
trap trap_cleanup EXIT


# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

backup_file "$NETPLAN_FILE"

log_info "Writing new netplan config to ${NETPLAN_FILE}..."
sudo tee "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $NATINT:                    # Adapter 1 - NAT/host-reachable
      dhcp4: yes
    $INTINT:                    # Adapter 2 - internal, fleet-facing
      dhcp4: no
      addresses:
        - $ADDRESSES
      routes:
        - to: $DMZ_SUB
          via: $MNG_IP
          scope: link
        - to: $INT_SUB
          via: $MNG_IP
          scope: link
EOF > /dev/null
chmod 600 "$NETPLAN_FILE" > /dev/null > /dev/null

 # appling changes
log_info "Applying netplan configuration..."
netplan apply > /dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."