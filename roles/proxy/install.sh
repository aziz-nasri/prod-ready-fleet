#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/proxy.conf"
require_root
require_cmd netplan
trap trap_cleanup EXIT

# installing required packages
pkg_install curl openssl

# Network configuration
[[ -f "/etc/netplan/${NET_FILE}" ]] || die "Netplan file was not found"
NETPLAN_FILE="/etc/netplan/${NET_FILE}"

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
chmod 600 "$NETPLAN_FILE" > /dev/null

 # appling changes
log_info "Applying netplan configuration..."
netplan apply &> /dev/null || die "Failed to apply netplan configuration"
log_info "netpaln configuration applied."

# adding port forwarding
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-fleet-forwarding.conf > /dev/null

# Adding DNS forwarding
log_info "Adding DNS forwarding..."
log_info "installing dnsmasq..."
pkg_install dnsmasq
if [[ ! -f "/etc/dnsmasq.conf" ]]; then
    die "dnsmasq config file does not exist."
fi
sudo tee -a /etc/dnsmasq.conf > /dev/null << EOF
# DNS forwarding for the fleet
interface=enp0s9
bind-interfaces
listen-address=10.0.20.1

# Forward internal lab.internal queries to srv3, the authoritative internal resolver
server=/lab.internal/10.0.20.129
address=/ReverseProxy/127.0.0.1

# Forward everything else upstream, to a real resolver
server=1.1.1.1
server=8.8.8.8

no-resolv
EOF

sudo systemctl restart dnsmasq > /dev/null
sudo systemctl enable dnsmasq --now > /dev/null


 # closing unecessary listening ports
if [[ $(( ${#TO_CLOSE_PORTS[@]} + 0 )) -gt 0 ]]; then
    log_info "closing Ports..."
    close_ports $TO_CLOSE_PORTS
fi


# installing nginx
pkg_install nginx
sudo systemctl enable --now nginx > /dev/null
sudo systemctl start nginx > /dev/null

# configuring nginx
log_info "Adding nginx configurations..."
if [[ -f "/etc/nginx/sites-enabled/myapp" ]]; then
    log_warn "Application nginx config file already exsit."
else

# Create directories for SSL certificates
sudo mkdir -p /etc/nginx/ssl/private /etc/nginx/ssl/certs

# Generate self-signed certificate (valid 1 year)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/private/myapp.key \
  -out /etc/nginx/ssl/certs/myapp.crt \
  -subj "/CN=${PROXY_IP}" \
  -addext "subjectAltName=IP:${PROXY_IP}"

# Secure the private key
sudo chmod 600 /etc/nginx/ssl/private/myapp.key
sudo chmod 644 /etc/nginx/ssl/certs/myapp.crt
sudo chown admin:admin /etc/nginx/ssl/private/myapp.key /etc/nginx/ssl/certs/myapp.crt


sudo tee /etc/nginx/sites-available/myapp << EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${PROXY_IP}; 
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${PROXY_IP};
    ssl_certificate     /etc/nginx/ssl/certs/myapp.crt;
    ssl_certificate_key /etc/nginx/ssl/private/myapp.key;
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
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
    ssl_certificate     /etc/nginx/ssl/certs/myapp.crt;
    ssl_certificate_key /etc/nginx/ssl/private/myapp.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    return 444;   # drop connections with no matching/unexpected Host header
}
EOF

sudo ln -sf /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp > /dev/null
sudo nginx -t || { sudo rm -f "/etc/nginx/sites-available/myapp" "/etc/nginx/sites-enabled/myapp" > /dev/null; die "nginx syntax test failed.configuration: (/etc/nginx/sites-enabled/myapp)"; }
sudo rm -f /etc/nginx/sites-enabled/default > /dev/null
fi

# adding the server tokens off and the rate limiter in nginx.conf
log_info "Configuring nginx.conf (server tokens off and the rate limiter)..."
if [[ -f "/etc/nginx/conf.d/security.conf" ]]; then
    log_warn "nginx security config file already exsit."
else
sudo tee /etc/nginx/conf.d/security.conf << EOF
# Hide Nginx version
server_tokens off;
# Rate limiting zones (http context)
# 10 requests/second average, burst handled later
limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;
EOF
fi
sudo nginx -t || { sudo rm -f "/etc/nginx/conf.d/security.conf" > /dev/null; die "nginx syntax test failed. configuration: (/etc/nginx/conf.d/security.conf)"; }
log_info "nginx.conf configured successfully."

sudo systemctl restart nginx > /dev/null
log_info "nginx configured successfully"


# adding health check script
log_info "adding health check scripts and cron job..."
if [[ -d "/home/"$SUDO_USER"/health-check" && -f "/home/"$SUDO_USER"/health-check/health-check.sh" && -f "/home/"$SUDO_USER"/health-check/health-extra.sh" ]]; then
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
log_info "Health check scripts and cron job added successfully."
fi