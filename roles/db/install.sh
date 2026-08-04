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



sudo systemctl enable --now postgresql &> /dev/null
sudo systemctl start postgresql

