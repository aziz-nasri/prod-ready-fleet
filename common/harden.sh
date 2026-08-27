#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_root
trap trap_cleanup EXIT

ask_add_job(){
    local ANS=""
    while [[ "${ANS^^}" != "Y" && "${ANS^^}" != "N" ]]; do
        echo "Add automatic system update once week? Please enter Y or N:"
        read ANS
        if [[ "${ANS^^}" == "Y" && ! -f "/etc/cron.d/system-update" ]]; then
            CRON_FILE="/etc/cron.d/system-update"
            sudo touch "$CRON_FILE" > /dev/null
            sudo chmod 644 "$CRON_FILE"
            sudo chown admin:admin "$CRON_FILE"
            cat > "$CRON_FILE" << EOF
0 2 * * 0 admin /usr/bin/system_update.sh
EOF
            fi
        fi
    done
    sudo touch /var/log/system-updates.log > /dev/null
    sudo cp common/system_update.sh /usr/bin/ > /dev/null
}

# installing the netplan package for network configurations
log_info "Installing netplan.io package..."
pkg_install netplan.io

# System upadte
log_info "Setting up automatic system update..."
pkg_install unattended-upgrades
sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades > /dev/null
 # adding cron job for automatic system unpdate
ask_add_job
 # keeping time accurate
 log_info "Setting up chrony for time synchronization..."
pkg_install chrony
sudo systemctl enable --now chrony > /dev/null
log_info "Chrony is set up and running."
log_info "Automatic system update is set up."

# Minimizing the attack surface.
 # remove unused packages
log_info "Removing unused packages..."
sudo apt-get autoremove --purge > /dev/null
sudo apt-get clean > /dev/null
log_info "removed unused packages."

# SSH hardening.
log_info "Hardenig SSH..."
pkg_install ssh
 # creating a backup to rollback if somthing goes wrong.
backup_file /etc/ssh/sshd_config
 # disabling password authentication
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config > /dev/null
 # disabling root login
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config > /dev/null

sudo systemctl enable --now ssh > /dev/null
sudo systemctl start ssh > /dev/null
sudo systemctl restart sshd > /dev/null
log_info "SSH hardening applied."


# Firewall.
log_info "Installing firewall (nftables package)..."
pkg_install nftables

sudo systemctl enable --now nftables > /dev/null
sudo systemctl start nftables > /dev/null
log_info "Firewall (nftables) is installed and running."