#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source proxy.conf
require_root
require_cmd netplan
trap trap_cleanup EXIT

# Network configuration
[[ -f /etc/netplan/01-netcfg.yaml ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

[[ ${#INTERFACES[@]} -gt 0 ]] || die "No interfaces defined in proxy.conf"

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
chmod 600 "$NETPLAN_FILE" > /dev/null

 # appling changes
log_info "Applying netplan configuration..."
netplan apply
log_info "netpaln configuration applied."

 # closing unecessary listening ports
log_info "closing Ports..."
close_ports $TO_BE_ClOSED_PORTS

# installing nginx
pkg_install nginx
sudo systemctl enable --now nginx > /dev/null
sudo systemctl start nginx > /dev/null


# configuring nginx
log_info "Adding nginx configurations..."
if [[ -f /etc/nginx/sites-available/myapp ]]; then
    log_warn "Application nginx config file already exsit."
else
sudo tee /etc/nginx/sites-available/myapp << EFO
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${PROXY_IP}; 

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${PROXY_IP};

    # ----- SSL (lab can use self-signed) -----
    ssl_certificate     /etc/nginx/ssl/proxy.crt;
    ssl_certificate_key /etc/nginx/ssl/proxy.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # ----- Security headers -----
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;

    # ----- Reverse proxy to App server -----
    location / {
        proxy_pass http://${APP_IP}:${APP_PORT};
        proxy_http_version 1.1;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    # health check endpoint (if your app has /health)
    location /health {
        proxy_pass http://${APP_IP}:${APP_PORT}/health;
        access_log off;
    }
}

server {
    listen 443 ssl default_server;
    server_name _;
    return 444;   # drop connections with no matching/unexpected Host header
}
EFO

sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/ > /dev/null
sudo rm -f /etc/nginx/sites-enabled/default > /dev/null
fi

# adding the server tokens off and the rate limiter in nginx.conf
if [[ ! -f "$NGINX_CONF" ]]; then
   die "nginx.conf file dosen't exist."
fi

backup_file $NGINX_CONF


TOKENS_DIRECTIVE="    server_tokens off;"
LIMIT_ZONE_DIRECTIVE="    limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;"
TOKENS_EXISTS=false
LIMIT_EXISTS=false

grep -qE '^\s*server_tokens\s+off\s*;' "$NGINX_CONF" && TOKENS_EXISTS=true
grep -qE '^\s*limit_req_zone\s+' "$NGINX_CONF" && LIMIT_EXISTS=true

if [[ "$TOKENS_EXISTS" == true && "$LIMIT_EXISTS" == true ]]; then
    log_info "Both directives already present."
else
  TMP_FILE=$(mktemp)

awk -v tokens="$TOKENS_DIRECTIVE" \
    -v limit="$LIMIT_ZONE_DIRECTIVE" \
    -v tokens_exists="$TOKENS_EXISTS" \
    -v limit_exists="$LIMIT_EXISTS" '
BEGIN {
    in_http = 0
    added = 0
}
{
    # Detect the start of the http block
    if ($0 ~ /^http\s*\{/) {
        in_http = 1
        print $0
        next
    }

    # We are inside http block and haven'\''t added the directives yet
    if (in_http == 1 && added == 0) {
        # Add after the opening brace (skip empty lines and comments right after {)
        if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) {
            print $0
            next
        }

        # Insert the directives here
        if (tokens_exists == "false") {
            print tokens
        }
        if (limit_exists == "false") {
            print limit
        }
        print ""          # blank line for readability
        added = 1
        print $0
        next
    }

    # Detect end of http block (very simple check)
    if (in_http == 1 && $0 ~ /^\}/) {
        in_http = 0
    }

    print $0
}
' "$NGINX_CONF" > "$TMP_FILE"

cp "$TMP_FILE" "$NGINX_CONF"
fi

sudo nginx -t || die "Wrong nginx syntax please recheck." > /dev/null
sudo systemctl restart nginx > /dev/null
log_info "nginx configured successfully"

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