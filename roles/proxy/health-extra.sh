#!/usr/bin/env bash

set -euo pipefail
source ./health.conf


echo "Checking nginx backend reachability:"
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "http://${APP_DOMAIN}:${APP_PORT}/health" 2>/dev/null || true)

# Check if curl failed
if [ "$HTTP_CODE" = "000" ]; then
    echo "ERROR: Network failure. Proxy cannot reach the app server at all."
# Evaluate the HTTP response code if network succeeded
elif [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 600 ]; then
    echo "SUCCESS: Proxy reached the app server! (HTTP Status: $HTTP_CODE)"
else
    echo "WARNING: Received unexpected status code: $HTTP_CODE"
fi
echo "" 

echo "Cert TLS check:"
if openssl x509 -checkend $(($DAYS * 86400)) -noout -in "$CERT"; then
    echo "Certificate is valid for at least $DAYS more days"
else
    echo "WARNING: Certificate expires in less than $DAYS days!"
fi
echo ""


echo -e "check NAT/forwarding still enabled:"
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
sudo journalctl -u nginx | head -n 30
echo -e "--------------------------------------------------------------\n"