#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
source "$(dirname "$0")/firewall.conf"
require_root
trap trap_cleanup EXIT

# Proxy server Firewall configurations
proxy_fw(){
log_info "Adding firewall rules to the proxy server..."
nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' > /dev/null
nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null

nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
nft add rule inet filter output oifname "$NAT_IF" udp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output oifname "$NAT_IF" tcp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output oifname "$INT_IF" udp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output oifname "$INT_IF" tcp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output oifname "$INT_IF" tcp dport "$APP_PORT" accept > /dev/null

nft add rule inet filter input iifname "$INT_IF" ip saddr "$MGMT_NET" tcp dport "$SSH_PORT" accept
nft add rule inet filter input iifname "$NAT_IF" tcp dport { "$HTTP_PORT", "$HTTPS_PORT" } accept > /dev/null
nft add rule inet filter input iifname "$INT_IF" ip saddr "$INT_NET" udp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter input iifname "$INT_IF" ip saddr "$INT_NET" tcp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter input iifname "$INT_IF" ip saddr "$APP_TIER" tcp dport  { "$HTTP_PORT", "$HTTPS_PORT" } accept > /dev/null

nft add rule inet filter forward ct state established,related accept > /dev/null
nft add rule inet filter forward iifname "$INT_IF" oifname "$NAT_IF" ip saddr "$INT_NET" tcp dport { "$HTTP_PORT", "$HTTPS_PORT" } accept > /dev/null

nft add table inet nat > /dev/null
nft add chain inet nat postrouting '{ type nat hook postrouting priority 100; }' > /dev/null
nft add rule inet nat postrouting oifname "$NAT_IF" masquerade > /dev/null
}

# Application server Firewall configurations
app_fw(){
log_info "Adding firewall rules to the Application server..."
nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null

nft add rule inet filter input iifname "$APP_INT_IF" ip saddr "$MGMT_NET" tcp dport "$SSH_PORT" accept > /dev/null
nft add rule inet filter input ip saddr "$PROXY_IP" tcp dport "$APP_PORT" accept > /dev/null


nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
nft add rule inet filter output ip daddr "$DATA_TIER" tcp dport "$DATABASE_PORT" accept > /dev/null
nft add rule inet filter output ip daddr "$PROXY_IP" udp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output ip daddr "$PROXY_IP" tcp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output ip daddr "$PROXY_IP" tcp dport { "$HTTP_PORT", "$HTTPS_PORT" } accept > /dev/null
}

# Database + DNS server Firewall configurations
db_fw(){
log_info "Adding firewall rules to the database server..."
nft add rule inet filter input ct state invalid drop > /dev/null
nft add rule inet filter input iifname "$DB_INT_IF" ip saddr "$MGMT_NET" tcp dport "$SSH_PORT" accept > /dev/null
nft add rule inet filter input ip saddr "$APP_TIER" tcp dport "$DATABASE_PORT" accept > /dev/null
nft add rule inet filter input ip saddr "$PROXY_IP" tcp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter input ip saddr "$PROXY_IP" udp dport "$DNS_PORT" accept > /dev/null

nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null
nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
nft add rule inet filter output ip daddr "$PROXY_IP" udp dport "$DNS_PORT" accept > /dev/null
nft add rule inet filter output ip daddr "$PROXY_IP" tcp dport "$DNS_PORT" accept > /dev/null
}
mgmt_fw(){
log_info "Adding firewall rules to the management bastion..."
nft add chain inet filter output '{ type filter hook output priority 0; policy drop; }' > /dev/null

nft add rule inet filter input iifname "$HOST_IF" tcp dport "$SSH_PORT" accept
nft add rule inet filter output oif lo accept
nft add rule inet filter output ct state established,related accept
nft add rule inet filter output oifname "$FLEET_IF" tcp dport "$SSH_PORT" accept
nft add rule inet filter output oifname "$HOST_IF" tcp dport "$SSH_PORT" accept
nft add rule inet filter output oifname "$HOST_IF" tcp dport { "$HTTP_PORT", "$HTTPS_PORT" } accept
nft add rule inet filter output oifname "$HOST_IF" udp dport "$DNS_PORT" accept
}

# Firewall rules applied to all servers
log_info "Applying common firewall rules..."
sudo nft flush ruleset > /dev/null
nft add table inet filter > /dev/null
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; } > /dev/null
nft add rule inet filter input ct state established,related accept > /dev/null
nft add rule inet filter input iif "lo" accept > /dev/null
nft add rule inet filter input ip protocol icmp accept > /dev/null
nft add rule inet filter input ip6 nexthdr icmpv6 accept > /dev/null


if [[ $(hostname | grep -i "proxy") ]]; then
    proxy_fw
elif [[ $(hostname | grep -i "app") ]]; then
    app_fw
elif [[ $(hostname | grep -i "database") ]]; then
    db_fw
elif [[ $(hostname | grep -i "mgmt") ]]; then
    mgmt_fw
else
    sudo nft flush ruleset  > /dev/null
    log_warn "no server detected. no firewall rules applied."
fi
echo "Saving firewall rules to /etc/nftables.conf..."
sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null

echo "Restarting nftables service..."
sudo systemctl restart nftables 2>/dev/null
log_info "finised adding firewall rules."