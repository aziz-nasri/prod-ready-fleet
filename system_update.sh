#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_root
check_connectivity
trap trap_cleanup EXIT

# adding this script in a cron job
[[ sudo grep system_update /etc/crontab ]] || sudo echo "0 2 * * 0 admin /usr/bin/system_update.sh" >> /etc/crontab

# system update
sudo apt update &> /dev/null
sudo apt upgrade &> /dev/null
log_info "System updated"


