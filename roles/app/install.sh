#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source ./app.env
require_root
check_connectivity
trap trap_cleanup EXIT


# Runtime & process management

 # creating the application user.
../../common/user_provi.sh appuser.conf

 # crating the app.service
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=${APP_NAME} application server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${APP_EXEC}
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl deamon-reload &> /dev/null
sudo systemctl enable --now app.service
sudo systemctl start app.service

sudo chmod 600 $APP_USER app.env

# logging 
sudo journalclt -u app.sevice