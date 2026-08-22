#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
source firewall.conf
require_root
check_connectivity
trap trap_cleanup EXIT

# Proxy server Firewall configurations
proxy_fw(){
nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' > /dev/null

nft add rule inet filter input iifname "$NAT_IF" tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null
nft add rule inet filter input iifname "$INT_IF" ip saddr $MGMT_NET tcp dport $SSH_PORT accept > /dev/null

nft add rule inet filter forward ct state established,related accept > /dev/null
nft add rule inet filter forward iifname "$INT_IF" oifname "$NAT_IF" ip saddr $INT_NET tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null

nft add table inet nat > /dev/null
nft add chain inet nat postrouting '{ type nat hook postrouting priority 100; }' > /dev/null
nft add rule inet nat postrouting oifname $NAT_IF masquerade > /dev/null

sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-fleet-forwarding.conf > /dev/null
sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
}

# Application server Firewall configurations
app_fw(){
nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null

nft add rule inet filter input ip saddr $PROXY_IP tcp dport $APP_PORT accept > /dev/null
nft add rule inet filter input tcp dport $APP_PORT drop > /dev/null
nft add rule inet filter input ip saddr $MGMT_NET tcp dport $SSH_PORT accept > /dev/null

nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER tcp dport $DATABASE_PORT accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER udp dport $DNS_PORT accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER tcp dport $DNS_PORT accept > /dev/null
nft add rule inet filter output tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null
sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
}

# Database + DNS server Firewall configurations
db_fw(){
nft add rule inet filter input ct state invalid drop > /dev/null
nft add rule inet filter input ip saddr $MGMT_NET tcp dport $SSH_PORT accept > /dev/null
nft add rule inet filter input ip saddr $APP_TIER tcp dport $DATABASE_PORT accept > /dev/null
nft add rule inet filter input ip saddr $APP_TIER udp dport $DNS_PORT accept > /dev/null
nft add rule inet filter input ip saddr $APP_TIER tcp dport $DNS_PORT accept > /dev/null
nft add rule inet filter input ip saddr $PROXY_IP udp dport $DNS_PORT  accept
nft add rule inet filter input ip saddr $PROXY_IP tcp dport $DNS_PORT  accept

nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null
nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
}
mgmt_fw(){
nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null

nft add rule inet filter input iifname $HOST_IF tcp dport $SSH_PORT accept
nft add rule inet filter output oif lo accept
nft add rule inet filter output ct state established,related accept
nft add rule inet filter output oifname $FLEET_IF tcp dport $SSH_PORT accept
nft add rule inet filter output oifname $HOST_IF tcp dport { $HTTP_PORT, $HTTPS_PORT } accept
nft add rule inet filter output oifname $HOST_IF udp dport $DNS_PORT accept
}

if [[ $(hostname | grep -i "proxy") ]]; then
    log_info "Adding firewall rules to the proxy server."
    proxy_fw
elif [[ $(hostname | grep -i "app") ]]; then
    log_info "Adding firewall rules to the Application server."
    app_fw
elif [[ $(hostname | grep -i "database") ]]; then
    log_info "Adding firewall rules to the database server."
    db_fw
elif [[ $(hostname | grep -i "mgmt") ]]; then
    log_info "Adding firewall rules to the management bastion."
    mgmt_fw
else
    log_warn "no server detected. no firewall rules applied."
fi

log_info "finised adding firewall rules."
sudo systemctl reload nftables 2>/dev/null