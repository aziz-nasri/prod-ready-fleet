#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
require_cmd nft
trap trap_cleanup EXIT

ask_add_job(){
    local ANS="."
    while [[ ${ANS^^} -ne "Y" || ${ANS^^} -ne "N" ]]; do 
        echo "Do you want to add a cron job to update the system every week [y/n]?"
        read ANS
        if [[ ${ANS^^} -eq "Y" ]]; then
            if [[ -n $(sudo grep -q system_update /etc/crontab) ]]; then
                sudo echo "0 2 * * 0 admin /usr/bin/system_update.sh" >> /etc/crontab;
            fi
        fi
    done
    sudo touch var/log/system-updates.log > /dev/null
    sudo mv system_update.sh /usr/bin/ > /dev/null
}

# System upadte
log_info "Setting up automatic system update..."
pkg_install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades > /dev/null
 # adding cron job for automatic system unpdate
ask_add_job
 # keeping time accurate
pkg_install chrony
sudo systemctl enable --now chrony > /dev/null
log_info "Automatic system update is set up."

# Minimazing the attack surface.
 # remove unused packages
log_info "Removing unused packages..."
sudo apt autoremove --purge > /dev/null
sudo apt clean > /dev/null
log_info "removed unused packages."

# SSH hardening.
log_info "Hardenig SSH..."
pkg_install ssh
 # creating a backup to rollback if somthing goes wrong.
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s) > /dev/null
 # disabling password authentication
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config > /dev/null
 # disabling root login
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config > /dev/null
 # changing to non-standard port
sudo sed -i 's/^#\?Port 22.*/Port 2307/' /etc/ssh/sshd_config > /dev/null

sudo systemctl enable --now ssh > /dev/null
sudo systemctl start ssh > /dev/null
sudo systemctl restart sshd > /dev/null
log_info "SSH hardening applied."


# Firewall.
log_info "Adding firewall (default deny all)..."
pkg_install nftables
pkg_install netplan.io

sudo systemctl enable --now nftables > /dev/null

if [[ -n $(sudo grep "table inet filter" etc/nftables.conf) ]]; then
    sudo nft add table inet filter > /dev/null
    sudo nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; } > /dev/null
    sudo nft add rule inet filter input iif "lo" accept > /dev/null
    sudo nft add rule inet filter input ct state established,related accept > /dev/null
    sudo nft add rule inet filter input ip protocol icmp accept > /dev/null
    sudo nft add rule inet filter input ip6 nexthdr icmpv6 accept > /dev/null

    sudo nft -f /etc/nftables.conf > /dev/null
fi
log_info "Firewall added."