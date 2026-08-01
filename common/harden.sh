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


# SSH hardening.


# Network hardening / firewall.


# Logging and Time.


# File Permissions


