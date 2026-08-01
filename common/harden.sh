#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_root
check_connectivity
trap trap_cleanup EXIT

# System upadte
sudo apt upadate &> /dev/null
pkg_install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades &> /dev/null
 # keeping time accurate
pkg_install chrony
sudo systemctl enable --now chrony &> /dev/null

# Minimazing the attack surface.
 # remove unused packages

sudo apt autoremove --purge &> /dev/null
sudo apt clean &> /dev/null
log_info "removed unused packages."

# SSH hardening.
 # creating a backup to rollback if somthing goes wrong.
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s) &> /dev/null
 # disabling password authentication
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config &> /dev/null
 # disabling root login
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config &> /dev/null
 # changing to non-standard port
sudo sed -i 's/^#\?Port 22.*/Port 2307/' /etc/ssh/sshd_config &> /dev/null

sudo systemctl restart sshd &> /dev/null


# Firewall.

pkg_install nftables

sudo systemctl enable --now nftables &> /dev/null

if [[ ! sudo grep "table inet filter" etc/nftables.conf ]]; then
    sudo nft add table inet filter &> /dev/null
    sudo nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; } &> /dev/null
    sudo nft add rule inet filter input iif "lo" accept &> /dev/null
    sudo nft add rule inet filter input ct state established,related accept &> /dev/null
    sudo nft add rule inet filter input tcp dport 2307 accept &> /dev/null
    sudo nft add rule inet filter input ip protocol icmp accept &> /dev/null
    sudo nft add rule inet filter input ip6 nexthdr icmpv6 accept &> /dev/null

    sudo nft -f /etc/nftables.conf &> /dev/null
fi
