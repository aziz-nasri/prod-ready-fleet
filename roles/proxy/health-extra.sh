#!/usr/bin/env bash

set -euo pipefail

echo "Checking nginx (https respond locally)"
HTTP_CODE=curl -sk -o /dev/null -w '%{http_code}' https://localhost
echo "Returned HTTP status: ${HTTP_CODE}."
if [[ $HTTP_CODE -ep 200 ]]; then
    echo "nginx is up."
else
    echo "ERROR: nginx is down."
fi 

echo "TLS cert: $(openssl x509 -enddate -noout)"

ping -c 3 10.0.20.65 &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "Backend is reachable."
else
    echo "ERROR: Backend is unreachable."
fi 

echo -e "check NAT/forwarding still enabled:\n"
sysctl net.ipv4.ip_forward | grep 1 &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "IP forwarding is enable (net.ipv4.ip_forward=1)."
else
    echo "ERROR: IP forwarding is disable (net.ipv4.ip_forward=0)."
fi 
nft list ruleset | grep -i masquerade &> /dev/null
if [[ $? -ep 0 ]]; then
    echo "masquerade rule is present in the firewall."
else
    echo "ERROR: masquerade rule is not present in the firewall.."
fi 
