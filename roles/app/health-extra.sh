#!/usr/bin/env bash

set -euo pipefail
source ./health.conf

echo "Data tier reachability:"
if timeout 3 bash -c "</dev/tcp/$DATA_IP/$DATA_PORT" &>/dev/null; then
    echo "OK: Database server is reachable through port ${DATA_PORT}"
else
     echo "ERROR: Database server is not reachable through port ${DATA_PORT}."
fi

if timeout 3 bash -c "</dev/tcp/$DNS_IP/$DNS_PORT" &>/dev/null; then
    echo "OK: DNS is reachable through port ${DNS_PORT}."
else
    echo "ERROR: DNS is not reachable through port ${DNS_PORT}."
fi
echo ""

echo "Check Database accepts app role connection:"
PGPASSWORD="$PG_PASSWORD" psql -h $DATA_IP -U appuser -d appdb -c 'SELECT 1' > /dev/null
if [[ $? == 0 ]]; then
    echo "OK: Database accepts app role connections and credential path works."
else
    echo "ERROR: Database does not accept app role connections or credentials failed."
fi
echo ""

echo "Checking DNS forwarding:"
if dig +time=2 +tries=1 +short example.com >/dev/null 2>&1; then
  echo "OK: External resolution succeeded."
else
  echo "ERROR: External resolution failed, forwarding appears disabled"
fi
echo ""

# Get values
current=$(systemctl show -p MemoryCurrent --value "$SERVICE")
max=$(systemctl show -p MemoryMax --value "$SERVICE")
# Handle unlimited (infinity)
if [[ "$max" == "infinity" || "$max" == 0 ]]; then
    echo "No MemoryMax limit set"
fi
# Calculate percentage
percent=$(( current * 100 / max ))
echo "Memory usage: $percent% ($current / $max bytes)"
if (( percent >= THRESHOLD )); then
    echo "WARNING: $SERVICE is at ${percent}% of MemoryMax!"
else
    echo "OK: ${SERVICE} Memory usage is under the Threshold."
fi

echo -e "\n======================================================"
echo "==================LOGS AND ERORRS===================="
echo -e "======================================================\n"
# app.service recent logs
echo "Recent myapp service logs:"
echo "--------------------------------------------------------------"
sudo journalctl -u $SERVICE | head -n 30
echo -e "--------------------------------------------------------------\n"