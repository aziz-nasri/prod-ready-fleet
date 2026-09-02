#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/mgmt.conf"
require_root
trap trap_cleanup EXIT

 # closing unecessary listening ports
log_info "Closing ports..."
if [[ $(( ${#TO_CLOSE_PORTS[@]} + 0 )) -gt 0 ]]; then
    log_info "closing Ports..."
    close_ports $TO_CLOSE_PORTS
fi

[[ -f ~/.ssh/config ]] || die "~/.ssh/config file was not found"
SSH_CONFIG="~/.ssh/config"

sudo tee ~/.ssh/config << EOF
Host proxy srv1
    HostName $PROXY_IP
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress $MNG_IP

Host app srv2
    HostName $APP_IP
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress $MNG_IP

Host db srv3
    HostName $DB_IP
    User admin
    IdentityFile ~/.ssh/lab-fleet
    BindAddress $MNG_IP
EOF

chmod 600 ~/.ssh/config ~/.ssh/lab-fleet > /dev/null