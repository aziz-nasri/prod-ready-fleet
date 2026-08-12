#!/usr/bin/env bash

set -euo pipefail

echo "Checking nginx (https respond locally)"
HTTP_CODE=curl -sk -o /dev/null -w '%{http_code}' https://localhost
echo "Returned HTTP status: ${HTTP_CODE}."
if [[ $HTTP_CODE == 200 ]]; then
    echo "OK: nginx is up."
else
    echo "ERROR: nginx is down."
fi 

echo -e "Cert TLS check:\n"
if openssl x509 -checkend $((DAYS * 86400)) -noout -in "$CERT"; then
    echo "Certificate is valid for at least $DAYS more days"
else
    echo "WARNING: Certificate expires in less than $DAYS days!"
fi

echo "Check backend is reachable:"
ping -c 3 $APP_IP &> /dev/null
if [[ $? == 0 ]]; then
    echo "OK: Backend is reachable."
else
    echo "ERROR: Backend is unreachable."
fi 

echo -e "check NAT/forwarding still enabled:\n"
sysctl net.ipv4.ip_forward | grep 1 &> /dev/null
if [[ $? == 0 ]]; then
    echo "OK: IP forwarding is enable (net.ipv4.ip_forward=1)."
else
    echo "ERROR: IP forwarding is disable (net.ipv4.ip_forward=0)."
fi 
nft list ruleset | grep -i masquerade &> /dev/null
if [[ $? == 0 ]]; then
    echo "OK: masquerade rule is present in the firewall."
else
    echo "ERROR: masquerade rule is not present in the firewall.."
fi 

echo -e "\n======================================================"
echo "==================LOGS AND ERORRS===================="
echo -e "======================================================\n"
# nginx recent logs
echo -e "\nRecent nginx service logs:"
echo "--------------------------------------------------------------"
sudo jornalctl nginx | head -n 30
echo -e "--------------------------------------------------------------\n"