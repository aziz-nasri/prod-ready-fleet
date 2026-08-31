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
    done
    sudo touch /var/log/system-updates.log > /dev/null
    sudo cp "$(dirname "$0")/common/system_update.sh" /usr/bin/ > /dev/null
}

# installing the netplan package for network configurations
log_info "Installing netplan.io package..."
pkg_install netplan.io

# hostname resolution locally
HOSTNAME=$(hostname)
if grep -q "127.0.1.1[[:space:]]*${HOSTNAME}" /etc/hosts 2>/dev/null; then
  log_info "Hostname entry for $HOSTNAME already present, skipping"
else
  log_info "Adding hostname resolution for $HOSTNAME"
  echo "127.0.1.1 ${HOSTNAME}" | sudo tee -a /etc/hosts > /dev/null
fi

# Disabling existing resolvers
log_info "Disabling existing resolvers..."
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/no-stub.conf << EOF
[Resolve]
DNSStubListener=no
DNS=127.0.0.1
EOF
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo rm -f /etc/resolv.conf
sudo bash -c 'echo "nameserver 10.0.20.1" > /etc/resolv.conf'
log_info "resolver disabled."

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