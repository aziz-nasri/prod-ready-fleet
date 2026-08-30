#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/db-server.conf"
require_root
require_cmd netplan
trap trap_cleanup EXIT

:<<'COMMENT'
# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in db-sever.conf"

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
netplan apply &> /dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."

 # closing unecessary listening ports
if [[ $(( ${#TO_CLOSE_PORTS[@]} + 0 )) -gt 0 ]]; then
    log_info "closing Ports..."
    close_ports $TO_CLOSE_PORTS
fi


# setting up Postgresql
 # installig the package
sudo apt-get update > /dev/null
pkg_install postgresql
pkg_install postgresql-contrib
log_info "postgresql installed."

log_info "Creating the database..."
 # creating the database
sudo -u postgres psql << EOF
CREATE USER appuser WITH PASSWORD '${APPUSER_PASSWD}';
CREATE DATABASE appdb OWNER appuser;
REVOKE ALL ON DATABASE appdb FROM PUBLIC;
GRANT CONNECT ON DATABASE appdb TO appuser;
EOF
log_info "database created."


log_info "configuring postgresql..."
if [[ -d /etc/postgresql ]]; then
  PG_VERSION=$(ls /etc/postgresql/)
  PG_MAIN_DIR="/etc/postgresql/${PG_VERSION}/main"
  PG_CONF_D="${PG_MAIN_DIR}/conf.d"
  LAB_CONF="${PG_CONF_D}/lab.conf"
  PG_HBA_CONF="${PG_MAIN_DIR}/pg_hba.conf"
else
    die "Could not find PostgreSQL configuration directory."
fi
echo "$PG_VERSION"
echo "$PG_MAIN_DIR"
echo "$PG_CONF_D"
echo "$LAB_CONF"
 # Safety checks
if [[ ! -d "$PG_CONF_D" ]]; then
    die "$PG_CONF_D not found."
fi
if [[ ! -f "$PG_HBA_CONF" ]]; then
    die "$PG_HBA_CONF not found."
fi

#PostgreSQL configuration: lab.conf in conf.d
log_info "Configuring PostgreSQL (writing ${LAB_CONF})..."

# Confirm conf.d is actually included by the main config
if ! grep -q "^include_dir = 'conf.d'" "${PG_MAIN_DIR}/postgresql.conf"; then
  log_info "conf.d not included by postgresql.conf — adding include directive"
  backup_file "${PG_MAIN_DIR}/postgresql.conf"
  echo "include_dir = 'conf.d'" | tee -a "${PG_MAIN_DIR}/postgresql.conf" > /dev/null
fi

cat > "$LAB_CONF" <<'EOF'
# lab.conf — project-specific PostgreSQL configuration
# Managed by lab-fleet-automation. Do not edit postgresql.conf directly for
# these settings — edit this file instead, so distro defaults stay untouched.

# Bind to the internal-zone interface only — never 0.0.0.0
listen_addresses = '10.0.20.130'
port = 5432

# Connection ceiling, sized for a small lab fleet
max_connections = 40

# Logging — enough to debug without excessive noise
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_min_duration_statement = 1000
log_connections = on
log_disconnections = on

# Reasonable small-instance memory settings for a lab VM
shared_buffers = 128MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Password auth requires SCRAM, not older/weaker methods
password_encryption = scram-sha-256
EOF

chown postgres:postgres "$LAB_CONF"
chmod 644 "$LAB_CONF"

 # configuring pg_hba.conf
if grep -qE "${DB_NAME}|${DB_USER}|${APP_IP}" "$PG_HBA_CONF"; then
log_info "pg_hba.conf file is already configured."
else
log_info "Configuring pg_hba.conf..."
backup_file $PG_HBA_CONF
sudo tee "$PG_HBA_CONF" > /dev/null <<EOF

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local Unix socket connections (admin)
local   all             postgres                                peer
local   all             all                                     peer

# IPv4 local connections (localhost)
host    all             all             127.0.0.1/32            scram-sha-256

# Allow the App server to connect to the application database
host    ${DB_NAME}      ${DB_USER}      ${APP_IP}/32            scram-sha-256

# Reject everything else
host    all             all             0.0.0.0/0               reject
host    all             all             ::/0                    reject
EOF
fi

# enabling postgresql
sudo systemctl enable --now postgresql > /dev/null
systemctl restart postgresql > /dev/null
log_info "postgresql configured."


log_info "Setting up DNS..."
# installing dnsmasq
pkg_install dnsmasq

log_info "Disabling existing resolvers..."

# Disable the stub listener of systemd-resolved
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

log_info "Configuring DNS (dnsmasq)..."

# Make sure the main config reads the directory
log_info "Ensuring dnsmasq reads additional config files..."
DNSMASQ_CONF="/etc/dnsmasq.conf"
CONF_DIR_LINE='conf-dir=/etc/dnsmasq.d/,*.conf'

#Line already exists and is active → do nothing
if grep -qE '^\s*conf-dir=' "$DNSMASQ_CONF"; then
    echo "conf-dir is already enabled"
elif grep -qE '^\s*#\s*conf-dir=' "$DNSMASQ_CONF"; then
    sed -i -E 's|^\s*#\s*conf-dir=.*|'"$CONF_DIR_LINE"'|' "$DNSMASQ_CONF"
    echo "Uncommented/updated conf-dir line"
else
    echo "Adding conf-dir line..."
    echo "" >> "$DNSMASQ_CONF"
    echo "# Include extra config files" >> "$DNSMASQ_CONF"
    echo "$CONF_DIR_LINE" >> "$DNSMASQ_CONF"
fi
# Create custom config
log_info "Creating custom dnsmasq config for lab.internal..."
sudo tee /etc/dnsmasq.d/lab.conf > /dev/null <<EOF
interface=${INTERFACES[0]}
listen-address=${LISTEN_IP}
bind-interfaces

no-resolv

domain=lab.internal
expand-hosts
local=/lab.internal/

address=/proxy.lab.internal/10.0.20.1
address=/app.lab.internal/10.0.20.65
address=/db.lab.internal/10.0.20.129
address=/dns.lab.internal/10.0.20.129

cache-size=1000
domain-needed
bogus-priv
log-queries
log-facility=/var/log/dnsmasq.log
EOF

log_info "DNS configured."
sudo systemctl enable --now dnsmasq > /dev/null
sudo systemctl restart dnsmasq > /dev/null
COMMENT


log_info "Setting up database backup..."
pkg_install rsync
# backup script
 # creating the backup user
"$(dirname "$0")/../../common/user_provi.sh" "$(dirname "$0")/backupuser.conf"

 # adding the source directory to the service file
sudo sed -i "s/SOURCE_FILE_PLACEHOLDER/${PG_CONF_DIR}/" backup.service &> /dev/null

# Copy the script
sudo cp "$(dirname "$0")/backup.sh" /usr/local/bin/ > /dev/null
sudo chown backup:backup /usr/local/bin/backup.sh > /dev/null
sudo chmod 500 /usr/local/bin/backup.sh > /dev/null

# Copy the units
sudo cp "$(dirname "$0")/backup.service" "$(dirname "$0")/backup.timer" /etc/systemd/system/ > /dev/null

# Create directories
sudo mkdir -p /var/backups/myapp > /dev/null
sudo chown backup:backup /var/backups/myapp > /dev/null
sudo chmod 700 /var/backups/myapp > /dev/null

# Enable and start the timer
sudo systemctl daemon-reload > /dev/null
sudo systemctl enable --now backup.timer > /dev/null
log_info "database backup is set."
::<<'COMMENT2'
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
COMMENT2