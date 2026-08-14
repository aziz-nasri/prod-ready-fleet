#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source ./app.conf
require_root
require_cmd netplan
trap trap_cleanup EXIT


# Network configuration
[[ -f /etc/netplan/01-netcfg.yaml ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

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
      if [[ ${#DNS_SERVERS[@]:-0} -gt 0 ]]; then
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
netplan apply
log_info "netpaln configuration applied."
 # closing unecessary listening ports 
log_info "Closing ports..."
close_ports $TO_BE_ClOSED_PORTS

# deploying the application.
log_info "Deploying the application..."
# Step 1: system packages
log_info "Installing required packages..."
apt-get update -qq > /dev/null
pkg_install python3 python3-venv python3-pip > /dev/null

# Step 2: creating the application user.
if id "$APP_USER" &>/dev/null; then
  log_info "User $APP_USER already exists, skipping"
else
log_info "Creating app user..."
../../common/user_provi.sh appuser.conf
mkdir -p "$APP_DIR"  > /dev/null
chown "$APP_USER:$APP_USER" "$APP_DIR" > /dev/null
log_info "Appuser created."
fi

#Step 3: app code.
log_info "Deploying application code..."
cp "$SCRIPT_DIR/app.py" "$APP_DIR/app.py" > /dev/null
cp "$SCRIPT_DIR/requirements.txt" "$APP_DIR/requirements.txt" > /dev/null
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
  log_info ".env already present, leaving existing values in place"
else
  log_info "Writing default .env"
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
log_info "creating the application service..."
if [[ ! -f $SERVICE_FILE ]]; then
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
ExecStart=${APP_EXEC} --bind ${SERVER_ADDR}:8080
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

sudo systemctl deamon-reload > /dev/null
sudo systemctl enable --now $SERVICE_FILE > /dev/null
sudo systemctl start $SERVICE_FILE > /dev/null
log_info "application service file created and running."

sudo chown $APP_USER:$APP_USER $APP_DIR/.env > /dev/null
sudo chmod 600 $APP_DIR/.env > /dev/null
log_info "Application service created."
else
  log_warn "Application service already exsit."
fi

# logging 
sudo journalclt -u $SERVICE_FILE > /dev/null

# adding health check script
log_info "adding health check scripts and cron job..."
if [[ -d ~/health-check && -f ~/health-check/health-check.sh && -f ~/health-check/health-extra.sh  ]]; then
    log_warn "Health checks already exsit."
else
sudo mkdir ~/health-check > /dev/null
sudo chown admin:admin ~/health-check > /dev/null
sudo chmod 550 ~/health-check > /dev/null
cp ../../common/health-check.sh ~/health-check > /dev/null
cp health-extra.sh ~/health-check > /dev/null
cp health.conf ~/health-check > /dev/null
# adding a cron job
(crontab -l 2>/dev/null; echo "30 9 * * * admin ~/health-check/health-check.sh > var/log/health-check<$(date)>.log") | sudo crontab -
log_info "health check added successfully."
fi