#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
require_root
check_connectivity
require_cmd netplan
trap trap_cleanup EXIT


# Network configuration

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

log_info "Writing new netplan config to $NETPLAN_FILE"
generate_netplan_yaml | tee "$NETPLAN_FILE" > /dev/null
chmod 600 "$NETPLAN_FILE"

 # appling changes
log_info "Applying netplan configuration"
netplan apply

 # closing unecessary listening ports 
close_ports $TO_BE_ClOSED_PORTS

# setting up Postgresql
 # installig the package
sudo apt update &> /dev/null
pkg_install postgresql
pkg_install postgresql-contrib
log_info "postgresql installed."

 # creating the database
sudo -u postgres -c << EOF
CREATE USER appuser WITH PASSWORD '${APPUSER_PASSWD}';
CREATE DATABASE appdb OWNER appuser;
REVOKE ALL ON DATABASE appdb FROM PUBLIC;
GRANT CONNECT ON DATABASE appdb TO appuser;
EOF
# Finding PostgreSQL config directory
if [[ -d /etc/postgresql ]]; then
    PG_VERSION=$(ls /etc/postgresql/ | sort -V | tail -n1)
    PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
else
    die "Could not find PostgreSQL configuration directory."
fi
POSTGRESQL_CONF="${PG_CONF_DIR}/postgresql.conf"
PG_HBA_CONF="${PG_CONF_DIR}/pg_hba.conf"

 # Safety checks
if [[ ! -f "$POSTGRESQL_CONF" ]]; then
    die "$POSTGRESQL_CONF not found."
fi
if [[ ! -f "$PG_HBA_CONF" ]]; then
    die "$PG_HBA_CONF not found."
fi

# editing configuration
 # backing up files
backup_file $POSTGRESQL_CONF
backup_file $PG_HBA_CONF

 # the set config function
set_config() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -qE "^[#\s]*${key}\s*=" "$file"; then
        sudo sed -i -E "s|^[#\s]*${key}\s*=.*|${key} = ${value}|" "$file"
    else
        echo "${key} = ${value}" | sudo tee -a "$file" > /dev/null
    fi
}
 # configuring postgresql.conf
set_config "listen_addresses" "'${LISTEN_IP}'" "$POSTGRESQL_CONF"
set_config "port" "${PORT}" "$POSTGRESQL_CONF"

set_config "shared_buffers" "${SHARED_BUFFERS}" "$POSTGRESQL_CONF"
set_config "effective_cache_size" "${EFFECTIVE_CACHE_SIZE}" "$POSTGRESQL_CONF"
set_config "work_mem" "${WORK_MEM}" "$POSTGRESQL_CONF"
set_config "maintenance_work_mem" "${MAINTENANCE_WORK_MEM}" "$POSTGRESQL_CONF"

set_config "logging_collector" "on" "$POSTGRESQL_CONF"
set_config "log_directory" "'log'" "$POSTGRESQL_CONF"
set_config "log_filename" "'postgresql-%Y-%m-%d.log'" "$POSTGRESQL_CONF"
set_config "log_min_duration_statement" "500" "$POSTGRESQL_CONF"
set_config "log_connections" "on" "$POSTGRESQL_CONF"
set_config "log_disconnections" "on" "$POSTGRESQL_CONF"
set_config "log_lock_waits" "on" "$POSTGRESQL_CONF"

set_config "password_encryption" "'scram-sha-256'" "$POSTGRESQL_CONF"

 # configuring pg_hba.conf
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


# enabling postgresql
sudo systemctl enable --now postgresql &> /dev/null
sudo systemctl start postgresql

# installing dnsmasq
pkg_install dnsmasq

# disabling existing resolvers
sudo systemctl stop systemd-resolved &> /dev/null
sudo systemctl disable systemd-resolved &> /dev/null
sudo rm -f /etc/resolv.conf &> /dev/null
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf  &> /dev/null

# Make sure the main config reads the directory
grep -q 'conf-dir=/etc/dnsmasq.d' /etc/dnsmasq.conf || \
  echo 'conf-dir=/etc/dnsmasq.d/,*.conf' | sudo tee -a /etc/dnsmasq.conf

# Create custom config
sudo tee /etc/dnsmasq.d/lab.conf > /dev/null <<EOF
interface=${INTERFACES[0]}
listen-address=${LISTEN_IP}
bind-interfaces

no-hosts
no-resolv

domain=lab.internal
expand-hosts
local=/lab.internal/

address=/proxy.lab.internal/10.0.20.10
address=/app.lab.internal/10.0.20.21
address=/db.lab.internal/10.0.20.20
address=/dns.lab.internal/10.0.20.20

cache-size=1000
domain-needed
bogus-priv
log-queries
log-facility=/var/log/dnsmasq.log
EOF

# backup script
 # creating the backup user
"$(dirname "$0")/../../common/user_provi.sh" backupuser.conf

pkg_install rsync
 # adding the source directory to the service file
sudo sed -i "s/SOURCE_FILE_PLACEHOLDER/${PG_CONF_DIR}/" backup.service &> /dev/null

# Copy the script
sudo cp backup.sh /usr/local/bin/
suod chown backup /usr/local/bin/backup.sh
sudo chmod 500 /usr/local/bin/backup.sh

# Copy the units
sudo cp backup.service backup.timer /etc/systemd/system/

# Create directories
sudo mkdir -p /var/backups/myapp
sudo chown backup /var/backups/myapp
sudo chmod 700 /var/backups/myapp

# Enable and start the timer
sudo systemctl daemon-reload
sudo systemctl enable --now backup.timer



