#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/net-proxy.conf"
require_root
trap trap_cleanup EXIT

# install required packages
pkg_install netplan.io

# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in proxy.conf"

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
      if [[ $(( ${#DNS_SERVERS[@]} + 0 )) -gt 0 ]]; then
        echo "      nameservers:"
        echo "        addresses: [$(IFS=,; echo "${DNS_SERVERS[*]}")]"
      fi
    fi
  done
}

 # moving it to destanation
backup_file "$NETPLAN_FILE"

log_info "Writing new netplan config to ${NETPLAN_FILE}..."
generate_netplan_yaml | tee "$NETPLAN_FILE" > /dev/null
chmod 600 "$NETPLAN_FILE" > /dev/null

 # appling changes
log_info "Applying netplan configuration..."
netplan apply &> /dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."

# adding port forwarding
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-fleet-forwarding.conf > /dev/null

# Adding DNS forwarding
log_info "Adding DNS forwarding..."
log_info "installing dnsmasq..."
pkg_install dnsmasq
if [[ ! -f "/etc/dnsmasq.conf" ]]; then
    die "dnsmasq config file does not exist."
fi
sudo tee -a /etc/dnsmasq.conf > /dev/null << EOF
# DNS forwarding for the fleet
interface=$DNS_INT
bind-interfaces
listen-address=$LISTEN_ADD

# Forward internal lab.internal queries to srv3, the authoritative internal resolver
server=/lab.internal/$INT_RES_SRV
address=/ReverseProxy/127.0.0.1

# Forward everything else upstream, to a real resolver
server=1.1.1.1
server=8.8.8.8

no-resolv
EOF

sudo systemctl restart dnsmasq > /dev/null
sudo systemctl enable dnsmasq --now > /dev/null