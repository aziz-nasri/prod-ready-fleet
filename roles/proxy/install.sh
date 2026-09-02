#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/../../common/lib.sh"
source "$(dirname "$0")/proxy.conf"
require_root
require_cmd netplan
trap trap_cleanup EXIT


# installing required packages
pkg_install openssl
pkg_install curl

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

# making the cert and the key reachable for the working process
sudo chown root:www-data /etc/nginx/ssl/certs/myapp.crt
sudo chmod 644 /etc/nginx/ssl/certs/myapp.crt
sudo chown root:www-data /etc/nginx/ssl/private/myapp.key
sudo chmod 640 /etc/nginx/ssl/private/myapp.key
sudo chmod 750 /etc/nginx/ssl/private/
sudo chown root:www-data /etc/nginx/ssl/private/

sudo tee /etc/nginx/sites-available/myapp << EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name ${PROXY_DMZ_IP} proxy.lab.internal localhost 127.0.0.1 _;

    ssl_certificate     /etc/nginx/ssl/certs/myapp.crt;
    ssl_certificate_key /etc/nginx/ssl/private/myapp.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy strict-origin-when-cross-origin;

    location / {
        proxy_pass http://${APP_DOMAIN}:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection        "";
        proxy_connect_timeout 60s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;
    }

    location /health {
        proxy_pass http://${APP_DOMAIN}:${APP_PORT}/health;
        access_log off;
    }
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

sudo systemctl daemon-reload > /dev/null
sudo systemctl restart nginx > /dev/null
log_info "nginx configured successfully"


# adding health check script
log_info "adding health check scripts and cron job..."
if [[ -d "/home/"$SUDO_USER"/health-check" && -f "/home/"$SUDO_USER"/health-check/health-check.sh" && -f "/home/"$SUDO_USER"/health-check/health-extra.sh" ]]; then
    log_warn "Health checks already exsit."
else
    mkdir /home/"$SUDO_USER"/health-check > /dev/null
    sudo chown $SUDO_USER:$SUDO_USER  /home/"$SUDO_USER"/health-check > /dev/null
    sudo chmod 550 /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/../../common/health-check.sh" /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/health-extra.sh" /home/"$SUDO_USER"/health-check > /dev/null
    cp "$(dirname "$0")/health.conf" /home/"$SUDO_USER"/health-check > /dev/null
    # adding a cron job
    if [[ ! -f "/etc/cron.d/health-check" ]]; then
        CRON_FILE="/etc/cron.d/health-check"
        sudo touch "$CRON_FILE" > /dev/null
        sudo chmod 644 "$CRON_FILE"
        sudo chown $SUDO_USER:$SUDO_USER "$CRON_FILE"
        cat > "$CRON_FILE" << EOF
30 9 * * * ${SUDO_USER} /home/${SUDO_USER}/health-check/health-check.sh &> /var/log/health-check_$(date +%Y-%m-%d).log
EOF
    fi
log_info "Health check scripts and cron job added successfully."
fi