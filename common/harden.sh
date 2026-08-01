#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_root
check_connectivity
trap trap_cleanup EXIT

# System upadte
sudo apt upadate &> /dev/null
pkg_install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

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


# Network hardening / firewall.


# Logging and Time.


# File Permissions


