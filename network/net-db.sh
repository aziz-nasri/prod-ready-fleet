#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/net-db.conf"
require_root
trap trap_cleanup EXIT


# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in db-sever.conf"

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
chmod 600 "$NETPLAN_FILE"

 # appling changes
log_info "Applying netplan configuration..."
netplan apply &> /dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."


log_info "Setting up DNS..."
# installing dnsmasq
pkg_install dnsmasq

log_info "Configuring DNS (dnsmasq)..."

# Make sure the main config reads the directory
log_info "Ensuring dnsmasq reads additional config files..."
DNSMASQ_CONF="/etc/dnsmasq.conf"
CONF_DIR_LINE='conf-dir=/etc/dnsmasq.d/,*.conf'

#Line already exists and is active → do nothing
if grep -qE '^\s*conf-dir=' "$DNSMASQ_CONF"; then
    echo "conf-dir is already enabled"
elif grep -qE '^\s*#\s*conf-dir=' "$DNSMASQ_CONF"; then
    sed -i -E 's|^\s*#\s*conf-dir=.*|'"$CONF_DIR_LINE"'|' "$DNSMASQ_CONF"
    echo "Uncommented/updated conf-dir line"
else
    echo "Adding conf-dir line..."
    echo "" >> "$DNSMASQ_CONF"
    echo "# Include extra config files" >> "$DNSMASQ_CONF"
    echo "$CONF_DIR_LINE" >> "$DNSMASQ_CONF"
fi
# Create custom config
log_info "Creating custom dnsmasq config for lab.internal..."
sudo tee /etc/dnsmasq.d/lab.conf > /dev/null <<EOF
interface=${INTERFACES[0]}
listen-address=${LISTEN_IP}
bind-interfaces

no-resolv

domain=lab.internal
expand-hosts
local=/lab.internal/

address=/proxy.lab.internal/10.0.20.1
address=/app.lab.internal/10.0.20.65
address=/db.lab.internal/10.0.20.129
address=/dns.lab.internal/10.0.20.129

cache-size=1000
domain-needed
bogus-priv
log-queries
log-facility=/var/log/dnsmasq.log
EOF

log_info "DNS configured."
sudo systemctl enable --now dnsmasq > /dev/null
sudo systemctl restart dnsmasq > /dev/null