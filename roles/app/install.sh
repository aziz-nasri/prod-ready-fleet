#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/app.conf"
require_root
require_cmd netplan
trap trap_cleanup EXIT


# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in app.conf"

 # generating the netplan file
generate_netplan_yaml() {
  echo "network:"
  echo "  version: 2"
  echo "  ethernets:"
  for i in "${!INTERFACES[@]}"; do
    iface="${INTERFACES[$i]}"
    mode="${MODES[$i]}"
    echo "    $iface:"
    if [[ "$mode" == "dhcp" ]]; then
      echo "      dhcp4: yes"
    else
      echo "      dhcp4: no"
      echo "      addresses:"
      echo "        - ${ADDRESSES[$i]}"
      if [[ -n "${DEFAULT_ROUTE_VIA:-}" && "$iface" == "${DEFAULT_ROUTE_IFACE:-}" ]]; then
        echo "      routes:"
        echo "        - to: default"
        echo "          via: $DEFAULT_ROUTE_VIA"
      fi
      if [[ $(( ${#DNS_SERVERS[@]} + 0 )) -gt 0 ]]; then
        echo "      nameservers:"
        echo "        addresses: [$(IFS=,; echo "${DNS_SERVERS[*]}")]"
      fi
    fi
  done
}

 # moving it to destanation
backup_file "$NETPLAN_FILE"

log_info "Writing new netplan config to ${NETPLAN_FILE}..."
generate_netplan_yaml | tee "$NETPLAN_FILE" > /dev/null
chmod 600 "$NETPLAN_FILE"

 # appling changes
log_info "Applying netplan configuration..."
netplan apply &>/dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."
 # closing unecessary listening ports 
log_info "Closing ports..."
if [[ $(( ${#TO_CLOSE_PORTS[@]} + 0 )) -gt 0 ]]; then
    log_info "closing Ports..."
    close_ports $TO_CLOSE_PORTS
fi

# deploying the application.
log_info "Deploying the application..."
# Step 1: system packages
log_info "Installing required packages..."
apt-get update -qq > /dev/null
pkg_install python3 > /dev/null
pkg_install python3-venv > /dev/null
pkg_install python3-pip > /dev/null
pkg_install postgresql-client > /dev/null

# Step 2: creating the application user.
if id "$APP_USER" &>/dev/null; then
  log_info "User $APP_USER already exists, skipping"
else
log_info "Creating app user..."
"$(dirname "$0")/../../common/user_provi.sh" "$(dirname "$0")/appuser.conf"
fi
mkdir -p "$APP_DIR"  > /dev/null
chown "$APP_USER:$APP_USER" "$APP_DIR" > /dev/null
log_info "Appuser is set up."
#Step 3: app code.
log_info "Deploying application code..."
cp "$(dirname "$0")/app.py" "$APP_DIR" > /dev/null
cp "$(dirname "$0")/requirements.txt" "$APP_DIR" > /dev/null
chown "$APP_USER:$APP_USER" "$APP_DIR/app.py" "$APP_DIR/requirements.txt" > /dev/null
log_info "Finished deploying app code."

# Step 4: virtualenv + dependencies
log_info "setting up virtualenv and dependecies..."
if [[ -x "$VENV_DIR/bin/python" ]]; then
  log_info "Virtualenv already exists, skipping creation"
else
  log_info "Creating virtualenv"
  python3 -m venv "$VENV_DIR" > /dev/null
  chown -R "$APP_USER:$APP_USER" "$VENV_DIR" > /dev/null
fi
log_info "Installing Python dependencies"
sudo -u "$APP_USER" "$VENV_DIR/bin/pip" install --quiet --upgrade pip > /dev/null
sudo -u "$APP_USER" "$VENV_DIR/bin/pip" install --quiet -r "$APP_DIR/requirements.txt" > /dev/null
log_info "Finished setting up."

# Step 5: environment file
log_info "setting up environment file..."
if [[ -f "$ENV_FILE" ]]; then
  log_info "app.env already present, leaving existing values in place"
else
  log_info "Writing default app.env"
  cat > "$ENV_FILE" <<EOF
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF
fi
chown "$APP_USER:$APP_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"
log_info "Finished setting up."

# Step 6: database schema
log_info "Ensuring notes table exists..."
source "$ENV_FILE"
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'EOF'
CREATE TABLE IF NOT EXISTS notes (
    id SERIAL PRIMARY KEY,
    text TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
EOF
log_info "notes table exists."

# Step 3: creating the app.service
log_info "Writing systemd unit"
if [[ ! -f $SERVICE_FILE ]]; then
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Application server (Flask + gunicorn)
After=network.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$VENV_DIR/bin/gunicorn -w 2 -b ${SERVER_ADDR}:${APP_PORT} app:app
Restart=on-failure
RestartSec=3
MemoryMax=512M
TasksMax=100

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${APP_DIR}

[Install]
WantedBy=multi-user.target
EOF

log_info "systemd unit created."
else
  log_warn "systemd unit already exsit."
fi
sudo systemctl daemon-reload > /dev/null
sudo systemctl enable --now $SERVICE_FILE > /dev/null
sudo systemctl start "${SERVICE_FILE##*/}" > /dev/null
log_info "Application deployment finished."

# logging 
sudo journalctl -u $SERVICE_FILE > /dev/null

:<<'COMMENT'
# adding health check script
log_info "adding health check scripts and cron job..."
if [[ -d ~/health-check && -f ~/health-check/health-check.sh && -f ~/health-check/health-extra.sh  ]]; then
    log_warn "Health checks already exsit."
else
    mkdir /home/"$SUDO_USER"/health-check > /dev/null
    sudo chown admin:admin  /home/"$SUDO_USER"/health-check > /dev/null
    sudo chmod 550 /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/../../common/health-check.sh" /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/health-extra.sh" /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/health.conf" /home/"$SUDO_USER"/health-check > /dev/null
    # adding a cron job
    if [[ ! -f "/etc/cron.d/health-check" ]]; then
        CRON_FILE="/etc/cron.d/health-check"
        sudo touch "$CRON_FILE" > /dev/null
        sudo chmod 644 "$CRON_FILE"
        sudo chown admin:admin "$CRON_FILE"
        cat > "$CRON_FILE" << EOF
30 9 * * * admin /home/${SUDO_USER}/health-check/health-check.sh &> /var/log/health-check_$(date +%Y-%m-%d).log
EOF
    fi
fi
log_info "Health check scripts and cron job added successfully."
COMMENT