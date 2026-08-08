#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../common/lib.sh"
source firewall.conf
require_root
check_connectivity
trap trap_cleanup EXIT

# Proxy server Firewall configurations
proxy_fw(){
nft add chain inet filter forward { type filter hook forward priority 0; policy drop; } > /dev/null
nft add chain inet filter output { type filter hook output priority 0; policy accept; } > /dev/null

nft add rule inet filter input iifname "$NAT_IF" tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null
nft add rule inet filter input iifname "$INT_IF" ip saddr $MGMT_NET tcp dport $SSH_PORT accept > /dev/null

nft add rule inet filter forward ct state established,related accept > /dev/null
nft add rule inet filter forward iifname "$INT_IF" oifname "$NAT_IF" ip saddr $INT_NET tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null

nft add chain inet filter output { type filter hook output priority 0; policy accept; } > /dev/null

sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
sudo systemctl reload nftables 2>/dev/null || true
}

# Application server Firewall configurations
app_fw(){
nft add chain inet filter output { type filter hook output priority 0; policy accept; } > /dev/null

nft add rule inet filter input ip saddr $PROXY_IP tcp dport $APP_PORT accept > /dev/null
nft add rule inet filter input tcp dport $APP_PORT drop > /dev/null
nft add rule inet filter input ip saddr $MGMT_NET tcp dport $SSH_PORT accept > /dev/null

nft add rule inet filter output oif lo accept > /dev/null
nft add rule inet filter output ct state established,related accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER tcp dport $DATABASE_PORT accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER udp dport $DNS_PORT accept > /dev/null
nft add rule inet filter output ip daddr $DATA_TIER tcp dport $DNS_PORT accept > /dev/null
nft add rule inet filter output tcp dport { $HTTP_PORT, $HTTPS_PORT } accept > /dev/null
}
