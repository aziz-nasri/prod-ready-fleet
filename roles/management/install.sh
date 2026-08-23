#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "./mgmt.conf"
require_root
require_cmd netplan
trap trap_cleanup EXIT

# Network configuration

[[ -f /etc/netplan/01-netcfg.yaml ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

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
          via: $MNG_ADD
          scope: link
        - to: $INT_SUB
          via: $MNG_ADD
          scope: link
EOF
chmod 600 "$NETPLAN_FILE" > /dev/null > /dev/null

 # appling changes
log_info "Applying netplan configuration..."
netplan apply
log_info "netpaln configuration applied."

 # closing unecessary listening ports
log_info "closing Ports..."
close_ports $TO_BE_ClOSED_PORTS

# SSH set up
ssh-keygen -t ed25519 -f ~/.ssh/lab-fleet -C "admin@lab-fleet" -N "" > /dev/null

[[ -f ~/.ssh/config ]] || die "~/.ssh/config file was not found"
SSH_CONFIG="~/.ssh/config"

sudo tee ~/.ssh/config << EOF
Host proxy srv1
    HostName 10.0.10.10
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress 10.0.0.2

Host app srv2
    HostName 10.0.20.65
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress 10.0.0.2

Host db srv3
    HostName 10.0.20.130
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress 10.0.0.2
EOF

chmod 600 ~/.ssh/config ~/.ssh/lab-fleet > /dev/null

# ssh hardening 
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config > /dev/null
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config > /dev/null
sudo sed -i 's/^#\?Port 22.*/Port 2307/' /etc/ssh/sshd_config > /dev/null
sudo systemctl restart sshd > /dev/null