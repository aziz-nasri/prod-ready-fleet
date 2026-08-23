#!/usr/bin/env bash

set -euo pipefail

# system update
sudo apt update > /dev/null 2>> system-updates.log
sudo apt upgrade -y > /dev/null 2>> system-updates.log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: System updated successfuly" | tee -a /var/log/system-updates.log


